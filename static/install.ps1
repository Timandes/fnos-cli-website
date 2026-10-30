# Windows PowerShell 5.1+; installs for the current user without elevation.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

function Test-FnosRuntime {
    try {
        if (-not (Get-Command node.exe -ErrorAction SilentlyContinue) -or -not (Get-Command npm.cmd -ErrorAction SilentlyContinue)) { return $false }
        $nodeVersion = & node.exe --version 2>$null
        if ($LASTEXITCODE -ne 0 -or $nodeVersion -notmatch '^v(\d+)\.(\d+)\.') { return $false }
        if ([int]$Matches[1] -lt 18 -or ([int]$Matches[1] -eq 18 -and [int]$Matches[2] -lt 17)) { return $false }
        $npmVersion = & npm.cmd --version 2>$null
        return ($LASTEXITCODE -eq 0 -and $npmVersion -match '^(\d+)\.' -and [int]$Matches[1] -ge 8)
    } catch { return $false }
}

$workDir = $null
try {
    if (-not $env:LOCALAPPDATA) { throw 'LOCALAPPDATA is missing. Run this installer in Windows.' }
    $installRoot = Join-Path $env:LOCALAPPDATA 'fnos-cli'
    $prefix = Join-Path $installRoot 'npm'
    $binDir = Join-Path $installRoot 'bin'
    Write-Host 'Installing fnos-cli for the current user...'

    $runtimeRecord = Join-Path $installRoot 'node-path.txt'
    if (-not (Test-FnosRuntime) -and (Test-Path -LiteralPath $runtimeRecord)) {
        $savedRuntime = (Get-Content -LiteralPath $runtimeRecord -Encoding UTF8 -Raw).Trim()
        if (Test-Path -LiteralPath (Join-Path $savedRuntime 'node.exe')) { $env:PATH = "$savedRuntime;$env:PATH" }
    }

    if (-not (Test-FnosRuntime)) {
        $osArch = $env:PROCESSOR_ARCHITECTURE
        if ($env:PROCESSOR_ARCHITEW6432) { $osArch = $env:PROCESSOR_ARCHITEW6432 }
        switch ($osArch) {
            'AMD64' { $arch = 'x64' }
            'ARM64' { $arch = 'arm64' }
            default { throw 'Unsupported architecture. Automatic installation supports x64 and ARM64.' }
        }
        $workDir = Join-Path ([IO.Path]::GetTempPath()) ('fnos-install-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $workDir -Force | Out-Null
        Write-Host 'Downloading Node.js 24 LTS (includes npm) from nodejs.org...'
        $manifest = (Invoke-WebRequest -UseBasicParsing -Uri 'https://nodejs.org/dist/latest-v24.x/SHASUMS256.txt' -TimeoutSec 60).Content
        $pattern = '(?m)^([a-fA-F0-9]{64})\s+(node-(v24\.\d+\.\d+)-win-' + $arch + '\.zip)\r?$'
        $entry = [regex]::Match($manifest, $pattern)
        if (-not $entry.Success) { throw 'Invalid Node.js download manifest.' }
        $expectedHash = $entry.Groups[1].Value
        $archive = $entry.Groups[2].Value
        $version = $entry.Groups[3].Value
        $zipPath = Join-Path $workDir 'node.zip'
        Invoke-WebRequest -UseBasicParsing -Uri "https://nodejs.org/dist/$version/$archive" -OutFile $zipPath -TimeoutSec 600
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $zipPath).Hash -ne $expectedHash) { throw 'Node.js checksum mismatch. Please retry the download.' }
        Expand-Archive -LiteralPath $zipPath -DestinationPath $workDir
        $runtimeName = [IO.Path]::GetFileNameWithoutExtension($archive)
        $runtimeDir = Join-Path $installRoot $runtimeName
        New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
        if (Test-Path -LiteralPath $runtimeDir) { $runtimeDir += '-' + [Guid]::NewGuid().ToString('N') }
        Move-Item -LiteralPath (Join-Path $workDir $runtimeName) -Destination $runtimeDir
        $env:PATH = "$runtimeDir;$env:PATH"
        if (-not (Test-FnosRuntime)) { throw 'Node.js could not run. Use a supported Windows 10/11 or Windows Server version.' }
        [IO.File]::WriteAllText($runtimeRecord, $runtimeDir, [Text.UTF8Encoding]::new($false))
    }

    $nodePath = (Get-Command node.exe -CommandType Application).Source
    $npmPath = (Get-Command npm.cmd -CommandType Application).Source
    Write-Host 'Installing the latest fnos-cli from npm...'
    & $npmPath install --global --prefix $prefix fnos-cli@latest
    if ($LASTEXITCODE -ne 0) { throw "npm installation failed (exit $LASTEXITCODE). Check your network and try again." }
    $cliPath = Join-Path $prefix 'node_modules\fnos-cli\bin\fnos'
    if (-not (Test-Path -LiteralPath $cliPath)) { throw 'npm did not create the fnos executable.' }
    & $nodePath $cliPath --version
    if ($LASTEXITCODE -ne 0) { throw 'The installed fnos-cli could not run.' }

    New-Item -ItemType Directory -Path $binDir -Force | Out-Null
    # Expose only a CMD launcher; npm-generated .ps1 shims may be policy-blocked.
    # Keep the launcher ASCII-only: CMD expands %~dp0 as a Unicode path. A
    # private copy of the standalone Node executable avoids embedding an
    # external runtime path that the console's code page cannot represent.
    $runtimeVersion = (& $nodePath --version).Trim()
    if ($LASTEXITCODE -ne 0 -or $runtimeVersion -notmatch '^v\d+\.\d+\.\d+$') { throw 'Cannot identify the Node.js runtime.' }
    $launcherNode = 'node-' + $runtimeVersion + '.exe'
    $launcherNodePath = Join-Path $binDir $launcherNode
    if (-not (Test-Path -LiteralPath $launcherNodePath)) { Copy-Item -LiteralPath $nodePath -Destination $launcherNodePath }
    $launcher = "@echo off`r`n`"%~dp0$launcherNode`" `"%~dp0..\npm\node_modules\fnos-cli\bin\fnos`" %*`r`nexit /b %errorlevel%`r`n"
    $launcherPath = Join-Path $binDir 'fnos.cmd'
    [IO.File]::WriteAllText($launcherPath, $launcher, [Text.Encoding]::ASCII)
    & $launcherPath --version
    if ($LASTEXITCODE -ne 0) { throw 'The generated fnos launcher could not run.' }
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $pathParts = @($userPath -split ';' | Where-Object { $_ -and $_.TrimEnd('\') -ine $binDir.TrimEnd('\') })
    $newPath = (@($binDir) + $pathParts) -join ';'
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    $env:PATH = "$binDir;$env:PATH"
    # Notify Explorer so terminals opened after installation inherit the new PATH.
    try {
        if (-not ('Fnos.EnvironmentBroadcast' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace Fnos {
    public static class EnvironmentBroadcast {
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern IntPtr SendMessageTimeout(IntPtr hwnd, uint msg, UIntPtr wparam, string lparam, uint flags, uint timeout, out UIntPtr result);
    }
}
'@
        }
        $broadcastResult = [UIntPtr]::Zero
        [Fnos.EnvironmentBroadcast]::SendMessageTimeout([IntPtr]0xffff, 0x1a, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$broadcastResult) | Out-Null
    } catch {
        Write-Warning 'PATH was saved. If a new terminal cannot find fnos, sign out of Windows and sign in again.'
    }
    Write-Host "`nInstallation complete! Close all terminal windows and open a new one, then run:`n`n  fnos --help`n"
    Write-Host "If this terminal has not refreshed PATH, run: & `"$binDir\fnos.cmd`" --help"
} catch {
    [Console]::Error.WriteLine("Installation failed: $($_.Exception.Message)")
    exit 1
} finally {
    if ($workDir -and (Test-Path -LiteralPath $workDir)) { Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue }
}
