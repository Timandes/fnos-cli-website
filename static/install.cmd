@echo off
setlocal
where powershell.exe >nul 2>&1
if errorlevel 1 (
  echo Installation failed: Windows PowerShell 5.1 is required. 1>&2
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference = 'Stop'; try { $script = Invoke-RestMethod -Uri 'https://fnos.timandes.cn/install.ps1' -TimeoutSec 60; Invoke-Expression $script } catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }"
exit /b %errorlevel%
