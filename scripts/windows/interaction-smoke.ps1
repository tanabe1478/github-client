param(
  [string]$ArtifactDirectory = "artifacts\interaction-smoke"
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$Executable = Get-ChildItem (Join-Path $RepoRoot "_build") -Filter "github_client.exe" -Recurse |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1
if (-not $Executable) {
  throw "github_client.exe was not found. Run scripts/windows/run.ps1 -BuildOnly first."
}

$ArtifactPath = Join-Path $RepoRoot $ArtifactDirectory
New-Item -ItemType Directory -Force $ArtifactPath | Out-Null
$StdoutPath = Join-Path $ArtifactPath "stdout.log"
$StderrPath = Join-Path $ArtifactPath "stderr.log"
Remove-Item $StdoutPath, $StderrPath -Force -ErrorAction SilentlyContinue

Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class GithubClientInteraction {
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left, Top, Right, Bottom; }
  private delegate bool EnumWindowsProc(IntPtr handle, IntPtr parameter);
  [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr parameter);
  [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr handle, out uint processId);
  [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr handle);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(IntPtr handle, StringBuilder text, int count);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr handle, out RECT rect);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr handle);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr handle, IntPtr insertAfter, int x, int y, int width, int height, uint flags);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr handle, IntPtr deviceContext, uint flags);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr handle, uint message, IntPtr wParam, IntPtr lParam);
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

function Save-WindowScreenshot([IntPtr]$WindowHandle, $Rect, [string]$Path) {
  $Bitmap = New-Object System.Drawing.Bitmap ($Rect.Right - $Rect.Left), ($Rect.Bottom - $Rect.Top)
  $Graphics = [System.Drawing.Graphics]::FromImage($Bitmap)
  try {
    $DeviceContext = $Graphics.GetHdc()
    try {
      $Printed = [GithubClientInteraction]::PrintWindow($WindowHandle, $DeviceContext, 2)
    } finally {
      $Graphics.ReleaseHdc($DeviceContext)
    }
    if (-not $Printed) {
      $Graphics.CopyFromScreen($Rect.Left, $Rect.Top, 0, 0, $Bitmap.Size)
    }
    $Bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
  } finally {
    $Graphics.Dispose()
    $Bitmap.Dispose()
  }
}

$Process = Start-Process -FilePath $Executable.FullName -PassThru `
  -RedirectStandardOutput $StdoutPath -RedirectStandardError $StderrPath
$WindowHandle = [IntPtr]::Zero
try {
  for ($Attempt = 0; $Attempt -lt 30; $Attempt++) {
    Start-Sleep -Seconds 1
    $Process.Refresh()
    if ($Process.HasExited) {
      throw "Application exited before interaction with code $($Process.ExitCode)."
    }
    $WindowHandle = [GithubClientInteraction]::FindAppWindow($Process.Id)
    if ($WindowHandle -ne [IntPtr]::Zero) { break }
  }
  if ($WindowHandle -eq [IntPtr]::Zero) {
    throw "Application window did not appear within 30 seconds."
  }

  $null = [GithubClientInteraction]::SetWindowPos(
    $WindowHandle, [IntPtr](-1), 0, 0, 0, 0, 0x0001 -bor 0x0002 -bor 0x0040
  )
  $null = [GithubClientInteraction]::SetForegroundWindow($WindowHandle)
  Start-Sleep -Milliseconds 200
  $Rect = New-Object GithubClientInteraction+RECT
  if (-not [GithubClientInteraction]::GetWindowRect($WindowHandle, [ref]$Rect)) {
    throw "Could not read the application window bounds."
  }
  Save-WindowScreenshot $WindowHandle $Rect (Join-Path $ArtifactPath "before.png")

  $null = [GithubClientInteraction]::SetCursorPos($Rect.Left + 96, $Rect.Top + 458)
  [GithubClientInteraction]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
  [GithubClientInteraction]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Seconds 2

  Save-WindowScreenshot $WindowHandle $Rect (Join-Path $ArtifactPath "after.png")
  $null = [GithubClientInteraction]::PostMessage(
    $WindowHandle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero
  )
  $null = $Process.WaitForExit(3000)
  [string]$OutputText = if (Test-Path $StdoutPath) { Get-Content $StdoutPath -Raw } else { "" }
  if (-not $OutputText.Contains("ui-action: nav.settings")) {
    throw "The expected MoonBit Settings navigation was not observed. See $ArtifactPath."
  }
  Write-Host "Interaction smoke passed. Artifacts: $ArtifactPath"
} finally {
  if (-not $Process.HasExited) {
    if ($WindowHandle -ne [IntPtr]::Zero) {
      $null = [GithubClientInteraction]::PostMessage(
        $WindowHandle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero
      )
      Start-Sleep -Seconds 1
    }
  }
  if (-not $Process.HasExited) {
    Stop-Process -Id $Process.Id -Force
  }
}
