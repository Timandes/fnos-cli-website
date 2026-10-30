@echo off
setlocal
for /f "tokens=2 delims=:" %%a in ('chcp') do set "_fnos_codepage=%%a"
chcp 65001 >nul
where powershell.exe >nul 2>&1
if errorlevel 1 (
  echo 安装失败：需要 Windows PowerShell 5.1 或更高版本。 1>&2
  chcp %_fnos_codepage% >nul
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference = 'Stop'; try { [Text.Encoding]::UTF8.GetString((iwr -UseBasicParsing https://fnos.timandes.cn/install.ps1 -ErrorAction Stop).RawContentStream.ToArray()).TrimStart([char]0xfeff) | iex } catch { [Console]::Error.WriteLine(('安装失败：{0}' -f $_.Exception.Message)); exit 1 }"
set "_fnos_exit=%errorlevel%"
chcp %_fnos_codepage% >nul
exit /b %_fnos_exit%
