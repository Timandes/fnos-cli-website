# 跨平台安装与首页 Tab

用户已选择自动补齐 Node.js/npm，面向初学者；熟悉 npm 的用户在 Tab 下方直接复制 `npm install -g fnos-cli`。

## 方案

已考虑只检查依赖及自动补齐两种方案，用户选择自动补齐。保留现有 Docusaurus 页面和视觉风格，四个 Tab 分别为 Windows CMD、Windows PowerShell、Linux、macOS，显示对应命令、终端说明、复制按钮和脚本链接。

## 安装行为

- `static/install.sh` 服务 Linux/macOS；`static/install.ps1` 服务 Windows；`static/install.cmd` 调用同一 PowerShell 安装器。
- 复用 Node.js >=18.17、npm >=8；缺失、不完整或过旧时下载 Node.js 24 LTS 官方预编译包，核对 SHA-256 后安装到用户目录。
- 自动下载支持 Linux/macOS x64、ARM64，Windows x64、ARM64；不支持的平台/架构或系统库条件不满足时清楚报错。
- 使用用户目录下的独立 npm prefix 和启动入口，避免管理员权限、全局 npm 配置和原有 Node.js 安装的变更。仅将 fnos 入口加入用户 PATH，Unix 按 shell 写入启动文件，Windows 更新用户 PATH。
- 完成前执行已安装的 CLI `--version`，失败返回非零并给出提示；重复运行不会重复写 PATH。新终端可直接运行 `fnos --help`。
- 正式站点和全部远程脚本地址使用 `https://fnos.timandes.cn/`；不包含部署和远程 Git 推送。

## 验证

先为 shell 安装器写隔离 HOME、受控外部命令的行为测试，覆盖已有依赖、缺失依赖、旧版依赖、下载失败、校验失败、npm 失败、重复执行和含空格路径。Windows 添加可在 Windows PowerShell 5.1 运行的隔离测试；本机若无 Windows 环境，明确记录验证边界。页面验证四个 Tab、复制、键盘切换、窄屏和生产构建。
