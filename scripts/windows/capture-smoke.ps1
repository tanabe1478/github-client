param(
  [string]$Output = "artifacts\imgui-smoke.png",
  [int]$StartupSeconds = 3
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
$Process = Start-Process -FilePath $Executable.FullName -PassThru
try {
  Start-Sleep -Seconds $StartupSeconds
  $Process.Refresh()
  if ($Process.HasExited) {
    throw "Application exited before capture with code $($Process.ExitCode)."
  }

  Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class GithubClientCapture {
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll")]
  public static extern bool GetWindowRect(IntPtr handle, out RECT rect);
}
'@
  $Rect = New-Object GithubClientCapture+RECT
  if (-not [GithubClientCapture]::GetWindowRect($Process.MainWindowHandle, [ref]$Rect)) {
    throw "Could not read the application window bounds."
  }

  Add-Type -AssemblyName System.Drawing
  $Bitmap = New-Object System.Drawing.Bitmap ($Rect.Right - $Rect.Left), ($Rect.Bottom - $Rect.Top)
  $Graphics = [System.Drawing.Graphics]::FromImage($Bitmap)
  try {
    $Graphics.CopyFromScreen($Rect.Left, $Rect.Top, 0, 0, $Bitmap.Size)
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
