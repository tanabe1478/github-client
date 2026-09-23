param(
  [string]$Output = "artifacts\imgui-smoke.png",
  [int]$StartupSeconds = 30,
  [ValidateSet("Inbox", "ForYou", "Repositories", "PullRequests", "Issues", "Settings")]
  [string]$Page = "Inbox"
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$Executable = Get-ChildItem (Join-Path $RepoRoot "_build") -Filter "github_client.exe" -Recurse |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1
if (-not $Executable) {
  throw "github_client.exe was not found. Run scripts/windows/run.ps1 -BuildOnly first."
}

$OutputPath = Join-Path $RepoRoot $Output
New-Item -ItemType Directory -Force (Split-Path $OutputPath) | Out-Null
$StdoutPath = "$OutputPath.stdout.log"
$StderrPath = "$OutputPath.stderr.log"
Remove-Item $StdoutPath, $StderrPath -Force -ErrorAction SilentlyContinue

Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class GithubClientCapture {
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)]
  public struct POINT { public int X, Y; }
  private delegate bool EnumWindowsProc(IntPtr handle, IntPtr parameter);
  [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr parameter);
  [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr handle, out uint processId);
  [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr handle);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(IntPtr handle, StringBuilder text, int count);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr handle, out RECT rect);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr handle);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr handle, IntPtr insertAfter, int x, int y, int width, int height, uint flags);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr handle, IntPtr deviceContext, uint flags);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr handle, ref POINT point);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  public static IntPtr FindAppWindow(int processId) {
    IntPtr found = IntPtr.Zero;
    EnumWindows((handle, parameter) => {
      uint candidateProcessId;
      GetWindowThreadProcessId(handle, out candidateProcessId);
      if (candidateProcessId != (uint)processId || !IsWindowVisible(handle)) return true;
      var title = new StringBuilder(256);
      GetWindowText(handle, title, title.Capacity);
      if (title.ToString().StartsWith("MoonBit GitHub Client")) {
        found = handle;
        return false;
      }
      return true;
    }, IntPtr.Zero);
    return found;
  }
}
'@
Add-Type -AssemblyName System.Drawing

$Process = Start-Process -FilePath $Executable.FullName -PassThru `
  -RedirectStandardOutput $StdoutPath -RedirectStandardError $StderrPath
try {
  $WindowHandle = [IntPtr]::Zero
  for ($Attempt = 0; $Attempt -lt $StartupSeconds; $Attempt++) {
    Start-Sleep -Seconds 1
    $Process.Refresh()
    if ($Process.HasExited) {
      throw "Application exited before capture with code $($Process.ExitCode)."
    }
    $WindowHandle = [GithubClientCapture]::FindAppWindow($Process.Id)
    if ($WindowHandle -ne [IntPtr]::Zero) { break }
  }
  if ($WindowHandle -eq [IntPtr]::Zero) {
    throw "Application window did not appear within $StartupSeconds seconds."
  }

  $null = [GithubClientCapture]::SetWindowPos(
    $WindowHandle, [IntPtr](-1), 0, 0, 0, 0, 0x0001 -bor 0x0002 -bor 0x0040
  )
  $null = [GithubClientCapture]::SetForegroundWindow($WindowHandle)
  Start-Sleep -Milliseconds 200
  $Rect = New-Object GithubClientCapture+RECT
  if (-not [GithubClientCapture]::GetWindowRect($WindowHandle, [ref]$Rect)) {
    throw "Could not read the application window bounds."
  }
  $NavigationY = @{
    Inbox = 165
    ForYou = 219
    PullRequests = 273
    Issues = 327
    Repositories = 404
    Settings = 458
  }
  if ($Page -ne "Inbox") {
    $null = [GithubClientCapture]::SetCursorPos(
      $Rect.Left + 96,
      $Rect.Top + $NavigationY[$Page]
    )
    [GithubClientCapture]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
    [GithubClientCapture]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 500
  }
  Start-Sleep -Milliseconds 500

  $Bitmap = New-Object System.Drawing.Bitmap ($Rect.Right - $Rect.Left), ($Rect.Bottom - $Rect.Top)
  $Graphics = [System.Drawing.Graphics]::FromImage($Bitmap)
  try {
    $DeviceContext = $Graphics.GetHdc()
    try {
      $Printed = [GithubClientCapture]::PrintWindow($WindowHandle, $DeviceContext, 2)
    } finally {
      $Graphics.ReleaseHdc($DeviceContext)
    }
    if (-not $Printed) {
      $Graphics.CopyFromScreen($Rect.Left, $Rect.Top, 0, 0, $Bitmap.Size)
    }
    $Bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
  } finally {
    $Graphics.Dispose()
    $Bitmap.Dispose()
  }
  Write-Host "Captured $OutputPath"
} finally {
  if (-not $Process.HasExited) {
    $null = $Process.CloseMainWindow()
    Start-Sleep -Seconds 1
  }
  if (-not $Process.HasExited) {
    Stop-Process -Id $Process.Id -Force
  }
}
