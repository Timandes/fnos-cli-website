# Integration test for a disposable Windows CI runner. Downloads real Node/npm.
param([switch]$EncodingOnly)

$ErrorActionPreference = 'Stop'
$installer = (Resolve-Path (Join-Path $PSScriptRoot '..\static\install.ps1')).Path
$tokens = $null
$parseErrors = $null
[Management.Automation.Language.Parser]::ParseFile($installer, [ref]$tokens, [ref]$parseErrors) | Out-Null
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }

$originalLocalAppData = $env:LOCALAPPDATA
$originalPath = $env:PATH
$originalUserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('fnos windows test ' + [char]0x5c0f + [char]0x660e + ' ' + [Guid]::NewGuid().ToString('N'))
$powershellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
New-Item -ItemType Directory -Path $testRoot | Out-Null

function Invoke-Installer([string]$name, [bool]$expectSuccess = $true) {
    $stdout = Join-Path $testRoot "$name.stdout"
    $stderr = Join-Path $testRoot "$name.stderr"
    $process = Start-Process -FilePath $powershellExe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $installer + '"')) -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $output = Get-Content -LiteralPath $stdout -Encoding UTF8 -Raw
    Write-Host $output
    $errorOutput = Get-Content -LiteralPath $stderr -Encoding UTF8 -Raw
    if ($expectSuccess) {
        if ($process.ExitCode -ne 0) { throw "Installer failed ($($process.ExitCode)): $errorOutput" }
        if ($output -notmatch '安装完成') { throw 'Missing Chinese completion message.' }
    } else {
        if ($process.ExitCode -eq 0) { throw 'Installer unexpectedly succeeded without LOCALAPPDATA.' }
        if ($errorOutput -notmatch '安装失败：找不到 LOCALAPPDATA 环境变量') { throw "Chinese error output was corrupted: $errorOutput" }
    }
}

function Test-WebBootstrapEncoding {
    $source = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\src\pages\index.tsx') -Encoding UTF8 -Raw
    $match = [regex]::Match($source, "(?s)value: 'windows-powershell'.*?command: '([^']+)'")
    if (-not $match.Success) { throw 'PowerShell installation command was not found.' }
    # Simulate a response whose decoded Content is wrong while raw UTF-8 bytes
    # contain a BOM and Chinese. Execute the real command published by the page.
    function Invoke-WebRequest {
        [CmdletBinding()]
        param([Parameter(Position = 0)][string]$Uri, [switch]$UseBasicParsing)
        if ($Uri -ne 'https://fnos.timandes.cn/install.ps1') { throw 'Unexpected bootstrap URL.' }
        $utf8 = [Text.UTF8Encoding]::new($true)
        [byte[]]$body = $utf8.GetPreamble() + $utf8.GetBytes("Write-Output '下载脚本中的简体中文提示'")
        return [pscustomobject]@{ RawContentStream = [IO.MemoryStream]::new($body); Content = 'incorrect decoded text' }
    }
    function Invoke-RestMethod { throw 'Bootstrap must decode the raw script bytes explicitly.' }
    $decodedOutput = & ([scriptblock]::Create($match.Groups[1].Value))
    if ($decodedOutput -ne '下载脚本中的简体中文提示') { throw 'Downloaded Chinese script was decoded incorrectly.' }
}

try {
    Test-WebBootstrapEncoding
    $env:LOCALAPPDATA = ''
    Invoke-Installer 'chinese-error' $false
    if ($EncodingOnly) { Write-Host 'Windows Chinese encoding checks passed.'; return }
    $env:LOCALAPPDATA = $testRoot
    # Remove preinstalled Node/npm from discovery to exercise first-time bootstrap.
    $env:PATH = "$env:SystemRoot\System32;$env:SystemRoot"
    Invoke-Installer 'bootstrap'
    $installRoot = Join-Path $testRoot 'fnos-cli'
    $launcher = Join-Path $installRoot 'bin\fnos.cmd'
    & $launcher --version
    if ($LASTEXITCODE -ne 0) { throw 'Installed launcher failed.' }
    & $launcher --help
    if ($LASTEXITCODE -ne 0) { throw 'CLI help failed.' }

    # Repeat from a fresh process with no Node on PATH: the saved runtime must be reused.
    $runtime = Get-ChildItem -LiteralPath $installRoot -Directory | Where-Object Name -Like 'node-v24.*' | Select-Object -First 1
    if (-not $runtime) { throw 'Node.js was not provisioned.' }
    Invoke-Installer 'repeat'
    if (@(Get-ChildItem -LiteralPath $installRoot -Directory | Where-Object Name -Like 'node-v24.*').Count -ne 1) { throw 'Repeat installation downloaded another runtime.' }
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (@($userPath -split ';' | Where-Object { $_ -eq (Join-Path $installRoot 'bin') }).Count -ne 1) { throw 'Duplicate or missing PATH entry.' }
    & $launcher --version
    if ($LASTEXITCODE -ne 0) { throw 'Launcher failed after repeated installation.' }
    Write-Host 'Windows installation integration checks passed.'
} finally {
    [Environment]::SetEnvironmentVariable('Path', $originalUserPath, 'User')
    $env:LOCALAPPDATA = $originalLocalAppData
    $env:PATH = $originalPath
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
