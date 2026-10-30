# Windows PowerShell 5.1+; installs for the current user without elevation.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$previousConsoleOutputEncoding = [Console]::OutputEncoding
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

function Test-InstallerPath([string]$path) {
    $root = $installRoot.TrimEnd('\')
    return ($path -ieq $root -or $path.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase))
}

function Get-FnosRuntime([switch]$ExternalOnly) {
    $nodes = @(Get-Command node.exe -All -CommandType Application -ErrorAction SilentlyContinue)
    $npms = @(Get-Command npm.cmd -All -CommandType Application -ErrorAction SilentlyContinue)
    foreach ($node in $nodes) {
        if ($ExternalOnly -and (Test-InstallerPath $node.Source)) { continue }
        try {
            $nodeVersion = & $node.Source --version 2>$null
            if ($LASTEXITCODE -ne 0 -or $nodeVersion -notmatch '^v(\d+)\.(\d+)\.') { continue }
            if ([int]$Matches[1] -lt 18 -or ([int]$Matches[1] -eq 18 -and [int]$Matches[2] -lt 17)) { continue }
            $savedPath = $env:PATH
            try {
                $env:PATH = (Split-Path -Parent $node.Source) + ';' + $env:PATH
                foreach ($npm in $npms) {
                    if ($ExternalOnly -and (Test-InstallerPath $npm.Source)) { continue }
                    $npmVersion = & $npm.Source --version 2>$null
                    if ($LASTEXITCODE -eq 0 -and $npmVersion -match '^(\d+)\.' -and [int]$Matches[1] -ge 8) {
                        return [pscustomobject]@{ Node = $node.Source; Npm = $npm.Source }
                    }
                }
            } finally { $env:PATH = $savedPath }
        } catch { continue }
    }
    return $null
}

function Get-NpmGlobalPath([string]$command) {
    $value = (& $npmPath $command --global 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $value -or $value -match '[\r\n]' -or -not [IO.Path]::IsPathRooted($value)) {
        throw '无法读取当前 npm 的全局安装目录，请检查 npm 配置后重试。'
    }
    return [IO.Path]::GetFullPath($value)
}

function Test-DirectoryWritable([string]$path) {
    $probe = $null
    try {
        $parent = $path
        while (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            if (Test-Path -LiteralPath $parent) { return $false }
            $parent = Split-Path -Parent $parent
            if (-not $parent) { return $false }
        }
        $probe = Join-Path $parent ('.fnos-write-' + [Guid]::NewGuid().ToString('N'))
        $stream = [IO.File]::Open($probe, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
        $stream.Dispose()
        return $true
    } catch { return $false }
    finally { if ($probe -and (Test-Path -LiteralPath $probe)) { Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue } }
}

function Test-PathEntry([string]$path, [string]$entry) {
    return (@($path -split ';' | Where-Object { $_.TrimEnd('\') -ieq $entry.TrimEnd('\') }).Count -gt 0)
}

$workDir = $null
try {
    if (-not $env:LOCALAPPDATA) { throw '找不到 LOCALAPPDATA 环境变量，请在 Windows 中运行此安装脚本。' }
    $installRoot = Join-Path $env:LOCALAPPDATA 'fnos-cli'
    $prefix = Join-Path $installRoot 'npm'
    $binDir = Join-Path $installRoot 'bin'
    Write-Host '正在检查 fnos-cli 安装环境……'

    $runtimeRecord = Join-Path $installRoot 'node-path.txt'
    # Prefer the caller's Node/npm, even when an old installer runtime is on PATH.
    $runtime = Get-FnosRuntime -ExternalOnly
    $useExistingNpm = $null -ne $runtime
    if (-not $runtime -and (Test-Path -LiteralPath $runtimeRecord)) {
        $savedRuntime = (Get-Content -LiteralPath $runtimeRecord -Encoding UTF8 -Raw).Trim()
        if (Test-Path -LiteralPath (Join-Path $savedRuntime 'node.exe')) { $env:PATH = "$savedRuntime;$env:PATH" }
    }

    if (-not $runtime) { $runtime = Get-FnosRuntime }
    if (-not $runtime) {
        $osArch = $env:PROCESSOR_ARCHITECTURE
        if ($env:PROCESSOR_ARCHITEW6432) { $osArch = $env:PROCESSOR_ARCHITEW6432 }
        switch ($osArch) {
            'AMD64' { $arch = 'x64' }
            'ARM64' { $arch = 'arm64' }
            default { throw '暂不支持当前处理器架构，自动安装仅支持 x64 和 ARM64。' }
        }
        $workDir = Join-Path ([IO.Path]::GetTempPath()) ('fnos-install-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $workDir -Force | Out-Null
        Write-Host '正在从 nodejs.org 下载 Node.js 24 长期支持版（包含 npm）……'
        $manifest = (Invoke-WebRequest -UseBasicParsing -Uri 'https://nodejs.org/dist/latest-v24.x/SHASUMS256.txt' -TimeoutSec 60).Content
        $pattern = '(?m)^([a-fA-F0-9]{64})\s+(node-(v24\.\d+\.\d+)-win-' + $arch + '\.zip)\r?$'
        $entry = [regex]::Match($manifest, $pattern)
        if (-not $entry.Success) { throw 'Node.js 下载清单无效，请稍后重试。' }
        $expectedHash = $entry.Groups[1].Value
        $archive = $entry.Groups[2].Value
        $version = $entry.Groups[3].Value
        $zipPath = Join-Path $workDir 'node.zip'
        Invoke-WebRequest -UseBasicParsing -Uri "https://nodejs.org/dist/$version/$archive" -OutFile $zipPath -TimeoutSec 600
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $zipPath).Hash -ne $expectedHash) { throw 'Node.js 文件校验失败，请重新下载。' }
        Expand-Archive -LiteralPath $zipPath -DestinationPath $workDir
        $runtimeName = [IO.Path]::GetFileNameWithoutExtension($archive)
        $runtimeDir = Join-Path $installRoot $runtimeName
        New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
        if (Test-Path -LiteralPath $runtimeDir) { $runtimeDir += '-' + [Guid]::NewGuid().ToString('N') }
        Move-Item -LiteralPath (Join-Path $workDir $runtimeName) -Destination $runtimeDir
        $env:PATH = "$runtimeDir;$env:PATH"
        $runtime = Get-FnosRuntime
        if (-not $runtime) { throw 'Node.js 无法运行，请使用受支持的 Windows 10/11 或 Windows Server 版本。' }
        [IO.File]::WriteAllText($runtimeRecord, $runtimeDir, [Text.UTF8Encoding]::new($false))
    }

    $nodePath = $runtime.Node
    $npmPath = $runtime.Npm
    $env:PATH = (Split-Path -Parent $nodePath) + ';' + $env:PATH
    if ($useExistingNpm) {
        $globalPrefix = Get-NpmGlobalPath 'prefix'
        $globalRoot = Get-NpmGlobalPath 'root'
        $existingCommands = @(Get-Command fnos, fnos.cmd, fnos.ps1 -All -CommandType Application, ExternalScript -ErrorAction SilentlyContinue |
            Where-Object { -not (Test-InstallerPath $_.Source) })
        $hasExistingCli = (Test-Path -LiteralPath (Join-Path $globalRoot 'fnos-cli')) -or $existingCommands.Count -gt 0
        if (-not (Test-DirectoryWritable $globalPrefix) -or -not (Test-DirectoryWritable $globalRoot)) {
            if ($hasExistingCli) { throw "当前 npm 全局安装目录不可写（$globalPrefix）。检测到已有 fnos-cli，请修复该环境的目录权限后重试。" }
            Write-Host '当前 npm 全局安装目录不可写，将安装到独立的用户目录。'
            $useExistingNpm = $false
        }
    }

    Write-Host '正在通过 npm 安装最新版本的 fnos-cli……'
    if ($useExistingNpm) {
        # Respect nvm and custom npm prefixes; never write npm's global config.
        & $npmPath install --global fnos-cli@latest
    } else {
        & $npmPath install --global --prefix $prefix fnos-cli@latest
    }
    if ($LASTEXITCODE -ne 0) { throw "npm 安装失败（退出码：$LASTEXITCODE），请检查当前 npm 环境和网络连接后重试。" }

    if ($useExistingNpm) {
        $launcherPath = Join-Path $globalPrefix 'fnos.cmd'
        if (-not (Test-Path -LiteralPath $launcherPath -PathType Leaf)) { throw 'npm 未生成原生 fnos.cmd 启动器，请检查当前 npm 环境。' }
    } else {
        $cliPath = Join-Path $prefix 'node_modules\fnos-cli\bin\fnos'
        if (-not (Test-Path -LiteralPath $cliPath -PathType Leaf)) { throw 'npm 未生成 fnos 可执行文件，请重新安装。' }
        New-Item -ItemType Directory -Path $binDir -Force | Out-Null
        # Keep the private launcher ASCII-only so Unicode user paths work in CMD.
        $runtimeVersion = (& $nodePath --version).Trim()
        if ($LASTEXITCODE -ne 0 -or $runtimeVersion -notmatch '^v\d+\.\d+\.\d+$') { throw '无法识别 Node.js 运行环境。' }
        $launcherNode = 'node-' + $runtimeVersion + '.exe'
        $launcherNodePath = Join-Path $binDir $launcherNode
        if (-not (Test-Path -LiteralPath $launcherNodePath)) { Copy-Item -LiteralPath $nodePath -Destination $launcherNodePath }
        $launcher = "@echo off`r`n`"%~dp0$launcherNode`" `"%~dp0..\npm\node_modules\fnos-cli\bin\fnos`" %*`r`nexit /b %errorlevel%`r`n"
        $launcherPath = Join-Path $binDir 'fnos.cmd'
        [IO.File]::WriteAllText($launcherPath, $launcher, [Text.Encoding]::ASCII)
    }
    # Verify the actual launcher and print the CLI version exactly once.
    & $launcherPath --version
    if ($LASTEXITCODE -ne 0) { throw '安装的 fnos-cli 无法运行，请检查当前安装环境后重试。' }

    # Only change PATH after successful installation and launcher verification.
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $pathParts = @($userPath -split ';' | Where-Object { $_.TrimEnd('\') -ine $binDir.TrimEnd('\') })
    $newPath = $pathParts -join ';'
    $env:PATH = (@($env:PATH -split ';' | Where-Object { $_.TrimEnd('\') -ine $binDir.TrimEnd('\') })) -join ';'
    if ($useExistingNpm) {
        if (-not (Test-PathEntry $env:PATH $globalPrefix)) {
            if (-not (Test-PathEntry $newPath $globalPrefix)) {
                $newPath = if ($newPath) { "$globalPrefix;$newPath" } else { $globalPrefix }
            }
            $env:PATH = "$globalPrefix;$env:PATH"
        }
    } else {
        $newPath = if ($newPath) { "$binDir;$newPath" } else { $binDir }
        $env:PATH = "$binDir;$env:PATH"
    }
    $pathChanged = $newPath -cne $userPath
    if ($pathChanged) { [Environment]::SetEnvironmentVariable('Path', $newPath, 'User') }
    # Notify Explorer so terminals opened after installation inherit the new PATH.
    if ($pathChanged) { try {
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
        Write-Warning 'PATH 已保存。如果新打开的终端仍找不到 fnos，请注销 Windows 后重新登录。'
    } }
    Write-Host "`n安装完成！"
    Write-Host "安装位置：$launcherPath"
    $resolvedFnos = Get-Command fnos -ErrorAction SilentlyContinue
    $resolvedBin = if ($resolvedFnos -and $resolvedFnos.Source -and [IO.Path]::IsPathRooted($resolvedFnos.Source)) {
        Split-Path -Parent $resolvedFnos.Source
    } else { $null }
    $launcherBin = Split-Path -Parent $launcherPath
    if ($resolvedBin -and $resolvedBin.TrimEnd('\') -ieq $launcherBin.TrimEnd('\')) {
        # npm may also create fnos.ps1, which the default execution policy blocks.
        Write-Host "`n请在终端运行：`n`n  fnos.cmd --help`n"
        Write-Host "也可以直接运行： & `"$launcherPath`" --help"
    } else {
        $resolvedDescription = if ($resolvedBin) { $resolvedFnos.Source } else { [string]$resolvedFnos.CommandType }
        Write-Host "当前 fnos 由其他目录或命令优先处理：$resolvedDescription"
        Write-Host "请使用本次安装的 CMD 入口：`n`n  & `"$launcherPath`" --help`n"
    }
} catch {
    [Console]::Error.WriteLine("安装失败：$($_.Exception.Message)")
    exit 1
} finally {
    if ($workDir -and (Test-Path -LiteralPath $workDir)) { Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue }
    [Console]::OutputEncoding = $previousConsoleOutputEncoding
}
