# PowerShell Build & Installer Packaging Script for POS Print Agent (Windows x64)
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Resolve-Path (Join-Path $ScriptDir "..\..")
Set-Location $ProjectRoot

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "1. Building POS Print Agent for Windows (x64 Release)..." -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
flutter build windows --release

$ReleaseDir = Join-Path $ProjectRoot "build\windows\x64\runner\Release"
if (-not (Test-Path (Join-Path $ReleaseDir "pos_print_agent.exe"))) {
    throw "Release executable not found at $ReleaseDir\pos_print_agent.exe"
}

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "2. Bundling sqlite3.dll (x64) for offline SQLite FFI..." -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
$SqliteDllPath = Join-Path $ReleaseDir "sqlite3.dll"
if (-not (Test-Path $SqliteDllPath)) {
    $SqliteZipUrl = "https://www.sqlite.org/2024/sqlite-dll-win-x64-3460100.zip"
    $TempZip = Join-Path $env:TEMP "sqlite-dll-win-x64.zip"
    $TempExtract = Join-Path $env:TEMP "sqlite-dll-extract"
    Invoke-WebRequest -Uri $SqliteZipUrl -OutFile $TempZip
    if (Test-Path $TempExtract) { Remove-Item -Recurse -Force $TempExtract }
    Expand-Archive -Path $TempZip -DestinationPath $TempExtract -Force
    Copy-Item (Join-Path $TempExtract "sqlite3.dll") -Destination $SqliteDllPath -Force
    Write-Host "Bundled sqlite3.dll into $ReleaseDir" -ForegroundColor Green
}

# Create one-click self-installer batch file inside the Release bundle
$OneClickSetupBat = @'
@echo off
chcp 65001 >nul
echo ====================================================
echo   Installing POS Print Agent Desktop Service...
echo ====================================================
set "INSTALL_DIR=%LOCALAPPDATA%\Programs\POSPrintAgent"
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
xcopy /E /I /Y "%~dp0*" "%INSTALL_DIR%\" >nul

powershell -NoProfile -Command "$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut([Environment]::GetFolderPath('Desktop') + '\POS Print Agent.lnk'); $s.TargetPath = '%INSTALL_DIR%\pos_print_agent.exe'; $s.WorkingDirectory = '%INSTALL_DIR%'; $s.Save()"
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "POSPrintAgent" /t REG_SZ /d "\"%INSTALL_DIR%\pos_print_agent.exe\"" /f >nul

echo Installation complete! Launching POS Print Agent...
start "" "%INSTALL_DIR%\pos_print_agent.exe"
'@
Set-Content -Path (Join-Path $ReleaseDir "Install-POS-Print-Agent.bat") -Value $OneClickSetupBat -Encoding UTF8

$DistDir = Join-Path $ProjectRoot "dist\windows"
if (-not (Test-Path $DistDir)) { New-Item -ItemType Directory -Path $DistDir | Out-Null }

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "3. Creating Windows Portable & One-Click Installer ZIP..." -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
$ZipOutput = Join-Path $DistDir "POS-Print-Agent-Windows-x64-Installer.zip"
if (Test-Path $ZipOutput) { Remove-Item -Force $ZipOutput }
Compress-Archive -Path "$ReleaseDir\*" -DestinationPath $ZipOutput -Force

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "4. Checking for Inno Setup (ISCC.exe) to build Setup.exe..." -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
$IsccCandidates = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles}\Inno Setup 6\ISCC.exe",
    "${env:LOCALAPPDATA}\Programs\Inno Setup 6\ISCC.exe"
)
$IsccPath = $IsccCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($IsccPath) {
    & $IsccPath (Join-Path $ScriptDir "pos_print_agent_setup.iss")
    Write-Host "Built Windows Setup Wizard: $DistDir\POS-Print-Agent-Windows-Setup.exe" -ForegroundColor Green
} else {
    Write-Host "Inno Setup not found; created ZIP installer with Install-POS-Print-Agent.bat at: $ZipOutput" -ForegroundColor Yellow
}

Write-Host "====================================================" -ForegroundColor Green
Write-Host "Windows Installer packaging complete! Output in: $DistDir" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Green
