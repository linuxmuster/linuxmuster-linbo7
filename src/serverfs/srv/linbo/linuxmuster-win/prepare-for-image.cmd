@echo off
:: =============================================
::  Windows Imaging Preparation Script (modern)
:: =============================================
::
:: contributed by Blair 20251013
:: (see https://ask.linuxmuster.net/t/skript-zur-vorbereitung-des-images/11874)

:: Check admin rights
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Please run this script with administrator privileges!
    pause
    exit /b
)

echo ================================
echo   Checking Windows Update Activity...
echo ================================

:checkUpdates
tasklist | findstr /I "TiWorker.exe" >nul
if %errorlevel%==0 (
    echo [*] Windows Update is still processing...
    timeout /t 30 >nul
    goto checkUpdates
)
echo [*] No active update processing detected.

:: Check if a reboot is required after update
echo [*] Checking if a reboot is required...
PowerShell -NoProfile -Command "if ((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired' -ErrorAction SilentlyContinue)) { exit 1 }"
if %errorlevel% neq 0 (
    echo.
    echo ========================================
    echo [WARNING] Windows Update requires a reboot!
    echo The reboot will now be performed automatically.
    echo ========================================
    timeout /t 10 >nul
    shutdown /r /t 60 /c "System is rebooting to complete updates"
    exit /b
)

echo ================================
echo   Checking Fast Boot...
echo ================================

PowerShell -NoProfile -Command "if ((Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power').HiberbootEnabled -eq 1) { exit 1 }"
if %errorlevel% neq 0 (
    echo.
    echo ========================================
    echo [NOTE] Fast Boot is still enabled.
    echo The registry value will now be disabled.
    echo A reboot is required for the change to take effect.
    echo ========================================
    timeout /t 5 >nul
    PowerShell -NoProfile -Command "Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -Value 0"
    shutdown /r /t 60 /c "System is rebooting to apply Fast Boot change"
    exit /b
)

echo ================================
echo   Checking System Integrity...
echo ================================

PowerShell -NoProfile -Command "if ((Get-Volume | Where-Object { $_.DriveLetter -ne $null -and $_.HealthStatus -ne 'Healthy' }).Count -gt 0) { Write-Host '[ERROR] At least one volume is not healthy!'; exit 1 }"
if %errorlevel% neq 0 (
    echo.
    echo ========================================
    echo [WARNING] At least one volume is not healthy.
    echo CHKDSK will be scheduled automatically and run on reboot.
    echo ========================================
    timeout /t 5 >nul
    chkntfs /d
    echo y | chkdsk C: /F /R
    echo.
    echo [NOTE] Rebooting in 60 seconds for filesystem check...
    shutdown /r /t 60 /c "System is rebooting for filesystem check"
    exit /b
)

echo [*] Starting SFC system file check...
sfc /scannow

echo [*] Starting DISM Health Check...
DISM /Online /Cleanup-Image /ScanHealth

echo ================================
echo   Starting System Cleanup...
echo ================================

echo [*] Deleting temporary files...
del /f /s /q "%TEMP%\*" >nul 2>&1
del /f /s /q "C:\Windows\Temp\*" >nul 2>&1

echo [*] Deleting prefetch data...
del /f /q "C:\Windows\Prefetch\*" >nul 2>&1

echo [*] Emptying recycle bin for all users...
PowerShell -NoProfile -Command "Get-CimInstance Win32_UserProfile | Where-Object { $_.Loaded -eq $false -and $_.LocalPath -like 'C:\\Users\\*' } | ForEach-Object { $recyclePath = Join-Path $_.LocalPath 'Recycle.Bin'; if (Test-Path $recyclePath) { Remove-Item -Path $recyclePath -Recurse -Force -ErrorAction SilentlyContinue } }; try {Clear-RecycleBin -Force -ErrorAction SilentlyContinue} catch {}"

echo [*] Cleaning Windows Update cache...
net stop wuauserv >nul 2>&1
rd /s /q "C:\Windows\SoftwareDistribution\Download" >nul 2>&1
net start wuauserv >nul 2>&1

echo [*] Starting DISM component cleanup...
DISM /Online /Cleanup-Image /StartComponentCleanup

echo [*] Starting Storage Sense manually...
PowerShell -NoProfile -Command "Start-StorageSense -Verbose" >nul 2>&1

echo [*] Cleaning user profiles...
for /d %%i in (C:\Users\*) do (
    del /f /s /q "%%i\AppData\Local\Temp\*" >nul 2>&1
    del /f /s /q "%%i\AppData\Local\Microsoft\Windows\INetCache\*" >nul 2>&1
    del /f /s /q "%%i\AppData\Roaming\Microsoft\Windows\Recent\*" >nul 2>&1
)

echo [*] Deleting Event Logs...
for /f %%x in ('wevtutil el') do (
    echo Deleting %%x...
    wevtutil cl "%%x" 2>nul
)

echo [*] Removing old Windows installation remnants...
rd /s /q "C:\$WINDOWS.~BT" >nul 2>&1
rd /s /q "C:\$WINDOWS.~WS" >nul 2>&1
rd /s /q "C:\$GetCurrent" >nul 2>&1

echo [*] Forcing filesystem flush...
PowerShell -NoProfile -Command "Get-Volume | ForEach-Object { if ($_.DriveLetter) { try { $path = $_.DriveLetter + ':\flush.tmp'; [System.IO.File]::WriteAllText($path, 'flush'); Remove-Item $path -Force } catch {} } }"

echo.
echo ================================
echo   Cleanup completed
echo   System will shutdown
echo ================================
timeout /t 5 >nul
shutdown /s /t 0 /f