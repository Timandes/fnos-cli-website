# 复用已有 npm 安装的修复

## 问题与原因

用户在 macOS 已通过 nvm 安装 Node/npm 和 fnos，安装脚本却始终传入独立 `--prefix`，另建 `.local/share/fnos-cli/bin/fnos` 并追加 PATH。已有运行时检测只决定是否下载 Node，没有决定 CLI 的安装位置。

## 修复约束

- 优先使用外部兼容 Node/npm 的 `prefix --global`、`root --global`，通过原生 npm 安装或原地更新，尊重 nvm 和自定义 prefix，不写全局 npm 配置。
- 缺兼容运行时（含复用安装器私有运行时），或全局目录不可写且没有已有 fnos，使用原独立用户目录方案。
- 已有 fnos 但全局目录不可写，或 npm 更新/启动入口验证失败，中文报错；不另装副本，不清理 PATH。
- 验证最终入口成功后，才删除旧安装器写入的精确 PATH 配置；保留旧文件和其他用户配置。已有原生目录在 PATH 时无需追加。
- 版本号一次，显示实际命令路径；当前 shell 仍被手工旧配置遮蔽时提供切换指引，不覆盖用户自己的配置。
- Bash 服务 macOS/Linux；Windows CMD 仍委托 PowerShell。中文提示、Windows BOM 和控制台编码兼容性保持。

## 验证

隔离测试覆盖已有 nvm 安装、首次安装、自定义 prefix、权限不足、安装失败、旧 PATH 标记迁移、用户配置保持不变，以及原有自动补齐/下载校验路径。Windows 扩展现有可丢弃 CI 集成测试；本机没有 Windows/PowerShell，不能把静态检查当作 Windows 实机通过。
