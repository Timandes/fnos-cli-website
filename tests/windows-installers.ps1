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

function Invoke-Installer([string]$name, [bool]$expectSuccess = $true, [string]$expectedError = '安装失败：找不到 LOCALAPPDATA 环境变量') {
    Write-Host "Installer case: $name"
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
        if ($process.ExitCode -eq 0) { throw "Installer unexpectedly succeeded: $name." }
        if ($errorOutput -notmatch $expectedError) { throw "Unexpected or corrupted Chinese error output: $errorOutput" }
    }
    return $output
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

function Write-NpmWrapper([string]$target) {
    # Keep EXIT /B outside compound blocks so cmd /c preserves the process exit code.
    $wrapper = @'
@echo off
if "%~1"=="install" >>"%FNOS_TEST_NPM_LOG%" echo %*
if "%~1"=="install" if "%FNOS_TEST_NPM_MODE%"=="fail-install" exit /b 73
if "%~1"=="install" if "%FNOS_TEST_NPM_MODE%"=="skip-install" exit /b 0
if "%FNOS_TEST_NPM_MODE%"=="blocked-prefix" if "%~1"=="prefix" (
  "%FNOS_TEST_NODE%" -e "process.stdout.write(process.env.FNOS_TEST_BLOCKED_PREFIX)"
  exit /b 0
)
call "%FNOS_TEST_REAL_NPM%" %*
exit /b %errorlevel%
'@
    [IO.File]::WriteAllText($target, $wrapper, [Text.Encoding]::ASCII)
}

function Test-NpmFailureFixture {
    $wrapperPath = Join-Path $testRoot 'offline-npm.cmd'
    $realNpm = Join-Path $testRoot 'offline-real-npm.cmd'
    $savedExitCode = $global:LASTEXITCODE
    $savedVariables = @{}
    'FNOS_TEST_NPM_LOG', 'FNOS_TEST_REAL_NPM', 'FNOS_TEST_NPM_MODE' | ForEach-Object {
        $savedVariables[$_] = [Environment]::GetEnvironmentVariable($_)
    }
    try {
        $env:FNOS_TEST_NPM_LOG = Join-Path $testRoot 'offline-npm.log'
        $env:FNOS_TEST_REAL_NPM = $realNpm
        [IO.File]::WriteAllText($realNpm, "@echo off`r`n>>`"%FNOS_TEST_NPM_LOG%`" echo unexpected-real-npm`r`nexit /b 0`r`n", [Text.Encoding]::ASCII)
        Write-NpmWrapper $wrapperPath
        $env:FNOS_TEST_NPM_MODE = 'fail-install'
        & $wrapperPath install --global fnos-cli@latest
        if ($LASTEXITCODE -ne 73) { throw "Offline npm fixture returned $LASTEXITCODE instead of 73." }
        $env:FNOS_TEST_NPM_MODE = 'skip-install'
        & $wrapperPath install --global fnos-cli@latest
        if ($LASTEXITCODE -ne 0) { throw "Skipped npm fixture returned $LASTEXITCODE instead of 0." }
        if ((Get-Content -LiteralPath $env:FNOS_TEST_NPM_LOG -Raw) -match 'unexpected-real-npm') { throw 'Failure fixture unexpectedly delegated to npm.' }
        Write-Host 'Windows npm failure fixture checks passed.'
    } finally {
        foreach ($name in $savedVariables.Keys) { [Environment]::SetEnvironmentVariable($name, $savedVariables[$name]) }
        $global:LASTEXITCODE = $savedExitCode
    }
}

function Test-ExistingNpmInstallation([string]$runtimePath, [string]$privatePrefix) {
    # All npm configuration and packages stay inside this disposable test tree.
    $externalRuntime = Join-Path $testRoot 'external-node'
    Copy-Item -LiteralPath $runtimePath -Destination $externalRuntime -Recurse
    $globalPrefix = Join-Path $testRoot 'custom-global-prefix'
    Copy-Item -LiteralPath $privatePrefix -Destination $globalPrefix -Recurse
    $externalProfile = Join-Path $testRoot 'external-profile'
    $oldBin = Join-Path $externalProfile 'fnos-cli\bin'
    $keepPath = "$oldBin-backup"
    $nativeLauncher = Join-Path $globalPrefix 'fnos.cmd'
    $npmWrapperDir = Join-Path $testRoot 'npm-wrapper'
    New-Item -ItemType Directory -Path $npmWrapperDir | Out-Null
    $npmLog = Join-Path $testRoot 'external-npm-install.log'
    $savedNpmPrefix = $env:NPM_CONFIG_PREFIX
    $savedNpmUserConfig = $env:NPM_CONFIG_USERCONFIG
    try {
        $env:NPM_CONFIG_PREFIX = $globalPrefix
        $env:NPM_CONFIG_USERCONFIG = Join-Path $testRoot 'isolated.npmrc'
        [IO.File]::WriteAllText($env:NPM_CONFIG_USERCONFIG, '', [Text.Encoding]::ASCII)
        $env:LOCALAPPDATA = $externalProfile
        $env:PATH = "$externalRuntime;$globalPrefix;$env:SystemRoot\System32;$env:SystemRoot"
        $env:FNOS_TEST_REAL_NPM = Join-Path $externalRuntime 'npm.cmd'
        $env:FNOS_TEST_NODE = Join-Path $externalRuntime 'node.exe'
        $env:FNOS_TEST_NPM_LOG = $npmLog
        $env:FNOS_TEST_NPM_MODE = ''
        $env:FNOS_TEST_BLOCKED_PREFIX = Join-Path $testRoot 'prefix-is-a-file'
        [IO.File]::WriteAllText($env:FNOS_TEST_BLOCKED_PREFIX, 'not a directory', [Text.Encoding]::ASCII)
        # A CMD wrapper delegates to real npm except for explicit failure cases.
        # Use environment variables so its source remains ASCII under Chinese paths.
        Write-NpmWrapper (Join-Path $npmWrapperDir 'npm.cmd')
        $env:PATH = "$npmWrapperDir;$env:PATH"
        [Environment]::SetEnvironmentVariable('Path', "$globalPrefix;$keepPath", 'User')
        $output = Invoke-Installer 'existing-npm'
        $existingVersion = (& $nativeLauncher --version | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or -not $existingVersion) { throw 'External npm installation path did not run.' }
        if (Test-Path -LiteralPath (Join-Path $externalProfile 'fnos-cli')) { throw 'Existing npm installation created a private copy.' }
        if ((Get-Content -LiteralPath $npmLog -Raw) -match '--prefix') { throw 'Existing npm prefix was overridden.' }
        if ($output -notmatch [regex]::Escape($globalPrefix)) { throw 'Installer did not report the native installation path.' }
        if ([regex]::Matches($output, '(?m)^' + [regex]::Escape($existingVersion) + '\r?$').Count -ne 1) { throw 'CLI version was not printed exactly once.' }
        if ([Environment]::GetEnvironmentVariable('Path', 'User') -ne "$globalPrefix;$keepPath") { throw 'Already available native bin changed the user PATH.' }
        if ($output -notmatch '(?m)^\s+fnos\.cmd --help\r?$') { throw 'PowerShell completion guidance did not prefer the CMD launcher.' }

        # Preserve a hand-managed older CLI that shadows the native npm prefix,
        # but explain which entry wins and show the verified absolute CMD entry.
        $customBin = Join-Path $testRoot 'custom-old-fnos'
        New-Item -ItemType Directory -Path $customBin | Out-Null
        $customLauncher = Join-Path $customBin 'fnos.cmd'
        $customLauncherBody = "@echo off`r`necho old-custom-cli`r`nexit /b 0`r`n"
        [IO.File]::WriteAllText($customLauncher, $customLauncherBody, [Text.Encoding]::ASCII)
        $customUserPath = "$customBin;$globalPrefix;$keepPath"
        [Environment]::SetEnvironmentVariable('Path', $customUserPath, 'User')
        $env:PATH = "$customBin;$npmWrapperDir;$externalRuntime;$globalPrefix;$env:SystemRoot\System32;$env:SystemRoot"
        if ((Get-Command fnos -ErrorAction Stop).Source -ne $customLauncher) { throw 'Custom CLI shadowing fixture did not take precedence.' }
        $shadowedOutput = Invoke-Installer 'existing-npm-custom-cli-shadows'
        if ([Environment]::GetEnvironmentVariable('Path', 'User') -ne $customUserPath) { throw 'Installer reordered a hand-managed CLI PATH entry.' }
        if ((Get-Content -LiteralPath $customLauncher -Raw) -cne $customLauncherBody) { throw 'Installer changed the hand-managed CLI.' }
        if ($shadowedOutput -notmatch '其他目录.*优先' -or $shadowedOutput -notmatch [regex]::Escape($customLauncher)) { throw 'Installer did not explain the actual shadowing command.' }
        $absoluteHelp = '& "' + $nativeLauncher + '" --help'
        if ($shadowedOutput -notmatch [regex]::Escape($absoluteHelp)) { throw 'Shadowed CLI guidance omitted the verified absolute CMD launcher.' }
        if ($shadowedOutput -match '(?m)^\s+fnos(?:\.cmd)? --help\r?$') { throw 'Shadowed CLI guidance still recommends the wrong bare command.' }
        if (Test-Path -LiteralPath (Join-Path $externalProfile 'fnos-cli')) { throw 'Shadowing a custom CLI created a private copy.' }
        & $nativeLauncher --version
        if ($LASTEXITCODE -ne 0) { throw 'Custom CLI shadowing changed the native installation path.' }

        # Add only the native global prefix when it is not yet on PATH.
        $env:PATH = "$npmWrapperDir;$externalRuntime;$env:SystemRoot\System32;$env:SystemRoot"
        [Environment]::SetEnvironmentVariable('Path', $keepPath, 'User')
        Invoke-Installer 'existing-npm-missing-path' | Out-Null
        if ([Environment]::GetEnvironmentVariable('Path', 'User') -ne "$globalPrefix;$keepPath") { throw 'Missing native bin did not add exactly its npm prefix.' }
        # A stale process PATH must not duplicate an already saved native prefix.
        Invoke-Installer 'existing-npm-stale-path' | Out-Null
        if ([Environment]::GetEnvironmentVariable('Path', 'User') -ne "$globalPrefix;$keepPath") { throw 'Native prefix was duplicated in the saved user PATH.' }

        # A launcher left by an older installer must stop shadowing the native bin.
        New-Item -ItemType Directory -Path $oldBin -Force | Out-Null
        $oldLauncher = Join-Path $oldBin 'fnos.cmd'
        [IO.File]::WriteAllText($oldLauncher, "@echo off`r`nexit /b 91`r`n", [Text.Encoding]::ASCII)
        $beforePath = "$oldBin;$globalPrefix;$keepPath"
        [Environment]::SetEnvironmentVariable('Path', $beforePath, 'User')
        $env:PATH = "$oldBin;$npmWrapperDir;$externalRuntime;$globalPrefix;$env:SystemRoot\System32;$env:SystemRoot"
        Invoke-Installer 'replace-old-private-bin' | Out-Null
        if ([Environment]::GetEnvironmentVariable('Path', 'User') -ne "$globalPrefix;$keepPath") { throw 'Old private bin cleanup removed unrelated PATH entries.' }
        if (-not (Test-Path -LiteralPath $oldLauncher)) { throw 'Old private files were deleted.' }
        if (Test-Path -LiteralPath (Join-Path $externalProfile 'fnos-cli\npm')) { throw 'Migration created a private npm installation.' }
        if (@(Get-ChildItem -LiteralPath $oldBin -Filter 'node-*.exe').Count) { throw 'Migration copied a private Node executable.' }
        & $nativeLauncher --version
        if ($LASTEXITCODE -ne 0) { throw 'External installation path changed after migration.' }

        # An update error must not create a fallback copy or clean the user's PATH.
        [Environment]::SetEnvironmentVariable('Path', $beforePath, 'User')
        $env:FNOS_TEST_NPM_MODE = 'fail-install'
        Invoke-Installer 'existing-npm-update-failure' $false 'npm 安装失败' | Out-Null
        if ([Environment]::GetEnvironmentVariable('Path', 'User') -ne $beforePath) { throw 'Failed update changed the user PATH.' }
        if (Test-Path -LiteralPath (Join-Path $externalProfile 'fnos-cli\npm')) { throw 'Failed update silently created a private copy.' }

        # Even a successful npm exit must not clean PATH before the native shim runs.
        $nativeLauncherBytes = [IO.File]::ReadAllBytes($nativeLauncher)
        try {
            [IO.File]::WriteAllText($nativeLauncher, "@echo off`r`nexit /b 92`r`n", [Text.Encoding]::ASCII)
            $env:FNOS_TEST_NPM_MODE = 'skip-install'
            & $nativeLauncher --version
            if ($LASTEXITCODE -ne 92) { throw "Broken launcher fixture returned $LASTEXITCODE instead of 92." }
            Invoke-Installer 'existing-npm-broken-launcher' $false 'fnos-cli 无法运行' | Out-Null
            if ([Environment]::GetEnvironmentVariable('Path', 'User') -ne $beforePath) { throw 'Failed native launcher verification changed the user PATH.' }
            if (Test-Path -LiteralPath (Join-Path $externalProfile 'fnos-cli\npm')) { throw 'Failed native launcher verification created a fallback copy.' }
        } finally { [IO.File]::WriteAllBytes($nativeLauncher, $nativeLauncherBytes) }

        # A non-directory prefix cannot be written. Existing packages forbid fallback.
        $installCalls = @(Get-Content -LiteralPath $npmLog).Count
        $env:FNOS_TEST_NPM_MODE = 'blocked-prefix'
        Invoke-Installer 'existing-npm-unwritable' $false '全局.*不可写' | Out-Null
        if (@(Get-Content -LiteralPath $npmLog).Count -ne $installCalls) { throw 'Unwritable global prefix still attempted installation.' }
        if ([Environment]::GetEnvironmentVariable('Path', 'User') -ne $beforePath) { throw 'Unwritable global environment changed the user PATH.' }
        if (Test-Path -LiteralPath (Join-Path $externalProfile 'fnos-cli\npm')) { throw 'Unwritable existing installation created a fallback copy.' }

        # With no package or external fnos command, an unwritable npm prefix may
        # still use the original private user installation (without changing npmrc).
        $emptyPrefix = Join-Path $testRoot 'empty-global-prefix'
        $env:NPM_CONFIG_PREFIX = $emptyPrefix
        $env:PATH = "$npmWrapperDir;$externalRuntime;$env:SystemRoot\System32;$env:SystemRoot"
        [Environment]::SetEnvironmentVariable('Path', $keepPath, 'User')
        Invoke-Installer 'unwritable-new-installation' | Out-Null
        if (-not (Test-Path -LiteralPath (Join-Path $externalProfile 'fnos-cli\npm\node_modules\fnos-cli\package.json'))) { throw 'Unwritable new installation did not use its private prefix.' }
        if (Test-Path -LiteralPath (Join-Path $emptyPrefix 'node_modules\fnos-cli')) { throw 'Private fallback wrote to the blocked global environment.' }
        if ((Get-Content -LiteralPath $env:NPM_CONFIG_USERCONFIG -Raw)) { throw 'Installer changed the isolated npm user configuration.' }

    } finally {
        $env:NPM_CONFIG_PREFIX = $savedNpmPrefix
        $env:NPM_CONFIG_USERCONFIG = $savedNpmUserConfig
        'FNOS_TEST_REAL_NPM', 'FNOS_TEST_NODE', 'FNOS_TEST_NPM_LOG', 'FNOS_TEST_NPM_MODE', 'FNOS_TEST_BLOCKED_PREFIX' | ForEach-Object { Remove-Item -LiteralPath "Env:$_" -ErrorAction SilentlyContinue }
    }
}

try {
    Test-WebBootstrapEncoding
    Test-NpmFailureFixture
    $env:LOCALAPPDATA = ''
    Invoke-Installer 'chinese-error' $false | Out-Null
    if ($EncodingOnly) { Write-Host 'Windows Chinese encoding checks passed.'; return }
    $env:LOCALAPPDATA = $testRoot
    # Remove preinstalled Node/npm from discovery to exercise first-time bootstrap.
    $env:PATH = "$env:SystemRoot\System32;$env:SystemRoot"
    Invoke-Installer 'bootstrap' | Out-Null
    $installRoot = Join-Path $testRoot 'fnos-cli'
    $launcher = Join-Path $installRoot 'bin\fnos.cmd'
    & $launcher --version
    if ($LASTEXITCODE -ne 0) { throw 'Installed launcher failed.' }
    & $launcher --help
    if ($LASTEXITCODE -ne 0) { throw 'CLI help failed.' }

    # Repeat from a fresh process with no Node on PATH: the saved runtime must be reused.
    $runtime = Get-ChildItem -LiteralPath $installRoot -Directory | Where-Object Name -Like 'node-v24.*' | Select-Object -First 1
    if (-not $runtime) { throw 'Node.js was not provisioned.' }
    Invoke-Installer 'repeat' | Out-Null
    if (@(Get-ChildItem -LiteralPath $installRoot -Directory | Where-Object Name -Like 'node-v24.*').Count -ne 1) { throw 'Repeat installation downloaded another runtime.' }
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (@($userPath -split ';' | Where-Object { $_ -eq (Join-Path $installRoot 'bin') }).Count -ne 1) { throw 'Duplicate or missing PATH entry.' }
    & $launcher --version
    if ($LASTEXITCODE -ne 0) { throw 'Launcher failed after repeated installation.' }
    Test-ExistingNpmInstallation $runtime.FullName (Join-Path $installRoot 'npm')
    # Expected native failures above must not become the Actions step exit code.
    $global:LASTEXITCODE = 0
    Write-Host 'Windows installation integration checks passed.'
} finally {
    [Environment]::SetEnvironmentVariable('Path', $originalUserPath, 'User')
    $env:LOCALAPPDATA = $originalLocalAppData
    $env:PATH = $originalPath
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
