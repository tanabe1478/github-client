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
public static class GithubClientInteraction {
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr handle, out RECT rect);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr handle);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr handle, uint message, IntPtr wParam, IntPtr lParam);
}
'@
Add-Type -AssemblyName System.Drawing

function Save-WindowScreenshot($Process, $Rect, [string]$Path) {
  $Bitmap = New-Object System.Drawing.Bitmap ($Rect.Right - $Rect.Left), ($Rect.Bottom - $Rect.Top)
  $Graphics = [System.Drawing.Graphics]::FromImage($Bitmap)
  try {
    $Graphics.CopyFromScreen($Rect.Left, $Rect.Top, 0, 0, $Bitmap.Size)
    $Bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
  } finally {
    $Graphics.Dispose()
    $Bitmap.Dispose()
  }
}

$Process = Start-Process -FilePath $Executable.FullName -PassThru `
  -RedirectStandardOutput $StdoutPath -RedirectStandardError $StderrPath
try {
  for ($Attempt = 0; $Attempt -lt 30; $Attempt++) {
    Start-Sleep -Seconds 1
    $Process.Refresh()
    if ($Process.HasExited) {
      throw "Application exited before interaction with code $($Process.ExitCode)."
    }
    if ($Process.MainWindowHandle -ne [IntPtr]::Zero) {
      break
    }
  }
  if ($Process.MainWindowHandle -eq [IntPtr]::Zero) {
    throw "Application window did not appear within 30 seconds."
  }

  $Rect = New-Object GithubClientInteraction+RECT
  if (-not [GithubClientInteraction]::GetWindowRect($Process.MainWindowHandle, [ref]$Rect)) {
    throw "Could not read the application window bounds."
  }
  Save-WindowScreenshot $Process $Rect (Join-Path $ArtifactPath "before.png")

  # Authentication controls live only on Settings. Verify that the native
  # navigation reaches that page; PAT entry itself remains masked.
  $SettingsPoint = [IntPtr](389 * 65536 + 96)
  $null = [GithubClientInteraction]::PostMessage($Process.MainWindowHandle, 0x0200, [IntPtr]::Zero, $SettingsPoint)
  $null = [GithubClientInteraction]::PostMessage($Process.MainWindowHandle, 0x0201, [IntPtr]1, $SettingsPoint)
  $null = [GithubClientInteraction]::PostMessage($Process.MainWindowHandle, 0x0202, [IntPtr]::Zero, $SettingsPoint)
  Start-Sleep -Seconds 2

  Save-WindowScreenshot $Process $Rect (Join-Path $ArtifactPath "after.png")

  # Close cleanly so redirected MoonBit stdout is flushed before assertion.
  $null = $Process.CloseMainWindow()
  $null = $Process.WaitForExit(3000)
  [string]$OutputText = if (Test-Path $StdoutPath) { Get-Content $StdoutPath -Raw } else { "" }
  if (-not $OutputText.Contains("ui-action: nav.settings")) {
    throw "The expected MoonBit Settings navigation was not observed. See $ArtifactPath."
  }
  Write-Host "Interaction smoke passed. Artifacts: $ArtifactPath"
} finally {
  if (-not $Process.HasExited) {
    $null = $Process.CloseMainWindow()
    Start-Sleep -Seconds 1
  }
  if (-not $Process.HasExited) {
    Stop-Process -Id $Process.Id -Force
  }
}
