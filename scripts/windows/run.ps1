param(
  [switch]$BuildOnly
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$VcpkgRoot = if ($env:VCPKG_ROOT) { $env:VCPKG_ROOT } else { Join-Path $env:USERPROFILE "vcpkg" }
$Triplet = if ($env:VCPKG_DEFAULT_TRIPLET) { $env:VCPKG_DEFAULT_TRIPLET } else { "x64-windows-static" }
$GlfwHeader = Join-Path $VcpkgRoot "installed\$Triplet\include\GLFW\glfw3.h"
$GlfwLibrary = Join-Path $VcpkgRoot "installed\$Triplet\lib\glfw3.lib"

if (-not (Test-Path $GlfwHeader) -or -not (Test-Path $GlfwLibrary)) {
  throw "GLFW was not found. Run: $VcpkgRoot\vcpkg.exe install glfw3:$Triplet"
}

$VsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $VsWhere)) {
  throw "Visual Studio Build Tools were not found."
}
$VsRoot = & $VsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $VsRoot) {
  throw "The Visual C++ build tools were not found."
}

$VcVars = Join-Path $VsRoot "VC\Auxiliary\Build\vcvars64.bat"
cmd /d /s /c "`"$VcVars`" >nul && set" | ForEach-Object {
  if ($_ -match '^([^=]+)=(.*)$') {
    [Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
  }
}

$LlvmBin = Join-Path $env:ProgramFiles "LLVM\bin"
if (-not (Test-Path (Join-Path $LlvmBin "clang.exe"))) {
  throw "LLVM clang was not found. Install LLVM.LLVM with winget."
}
# Moon derives `ar` from the configured clang++ driver name. LLVM ships the
# executable as llvm-ar.exe, so provide the conventional name in a local tool
# directory without modifying the LLVM installation.
$NativeToolDir = Join-Path $RepoRoot ".native-tools\win32"
New-Item -ItemType Directory -Force $NativeToolDir | Out-Null
Copy-Item (Join-Path $LlvmBin "llvm-ar.exe") (Join-Path $NativeToolDir "ar.exe") -Force
$env:Path = "$NativeToolDir;$LlvmBin;$env:Path"
$env:VCPKG_ROOT = $VcpkgRoot
$env:VCPKG_DEFAULT_TRIPLET = $Triplet
$env:CPATH = (Join-Path $VcpkgRoot "installed\$Triplet\include")

# MoonBit currently links -lm on Windows although the UCRT already contains
# the math functions. Supply an empty compatibility library until upstream no
# longer requires this workaround.
$CompatDir = Join-Path $RepoRoot ".native-libs\win32"
New-Item -ItemType Directory -Force $CompatDir | Out-Null
$StubSource = Join-Path $CompatDir "m.c"
$StubObject = Join-Path $CompatDir "m.obj"
$StubLibrary = Join-Path $CompatDir "m.lib"
Set-Content -Encoding Ascii $StubSource "void __moonbit_m_stub(void){}"
& (Join-Path $LlvmBin "clang.exe") -c $StubSource -o $StubObject
& (Join-Path $LlvmBin "llvm-lib.exe") "/out:$StubLibrary" $StubObject /nologo

Push-Location $RepoRoot
try {
  if ($BuildOnly) {
    moon build cmd/github_client --target native
  } else {
    moon run cmd/github_client --target native
  }
} finally {
  Pop-Location
}
