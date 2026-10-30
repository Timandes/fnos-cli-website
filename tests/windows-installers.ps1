# Integration test for a disposable Windows CI runner. Downloads real Node/npm.
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

function Invoke-Installer([string]$name) {
    $stdout = Join-Path $testRoot "$name.stdout"
    $stderr = Join-Path $testRoot "$name.stderr"
    $process = Start-Process -FilePath $powershellExe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $installer + '"')) -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $output = Get-Content -LiteralPath $stdout -Raw
    Write-Host $output
    if ($process.ExitCode -ne 0) { throw "Installer failed ($($process.ExitCode)): $(Get-Content -LiteralPath $stderr -Raw)" }
    if ($output -notmatch 'Installation complete') { throw 'Missing completion message.' }
}

try {
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
