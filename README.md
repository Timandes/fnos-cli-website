# fnos-cli-website

fnos-cli 的极简中文门户，采用 Docusaurus Classic、React 与 TypeScript。仅包含首页，使用清爽留白的白蓝配色，支持桌面与手机。

## 本地运行

需要 Node.js 20 或更高版本及 npm。

```bash
npm ci
npm start
```

开发地址默认是 http://localhost:3000，支持修改后自动刷新。端口被占用时可显式指定：

```bash
npm start -- --port 3001
```

## 检查与构建

```bash
npm run typecheck
npm test
npm run build
npm run serve
```

静态产物位于 `build/`，正式站点配置为 `https://fnos.timandes.cn/`。部署时上传整个目录，包括根目录的三个安装脚本；不要把脚本请求重写成首页 HTML。

## 跨平台安装

首页提供 Windows CMD、Windows PowerShell、Linux、macOS 四个 Tab，可复制命令并下载脚本。下方独立提供已有 npm 用户使用的 `npm install -g fnos-cli`。

Linux/macOS 使用管道直接执行在线脚本，命令不会在当前目录生成 `fnos-install.sh`：

```bash
curl -fsSL https://fnos.timandes.cn/install.sh | bash
```

Windows CMD 和 PowerShell 命令下载内容后在内存中执行，同样不保存下载的脚本。安装器用于下载依赖的临时目录会在退出时清理；手动下载脚本的链接仍可按需使用。

| 入口 | 用途 |
| --- | --- |
| `https://fnos.timandes.cn/install.cmd` | Windows CMD，引导至同站 PowerShell 安装器 |
| `https://fnos.timandes.cn/install.ps1` | Windows PowerShell 5.1+，x64 / ARM64 |
| `https://fnos.timandes.cn/install.sh` | Linux / macOS，Bash 3.2+，x64 / ARM64 |

脚本优先复用 Node.js >=18.17、npm >=8，读取当前 `npm prefix --global` 和 `npm root --global`，在当前 npm 环境安装或更新 fnos-cli。nvm 和自定义 npm prefix 均沿用原来的目录，不额外创建独立副本或修改 npm 配置。完成前验证实际启动入口，版本号只显示一次，并显示安装路径。

缺少兼容运行环境时，才从 `nodejs.org` 下载 Node.js 24 LTS（含 npm），通过官方 SHA-256 清单校验后安装到独立用户目录。已有 Node/npm 但全局目录不可写时，仅在未检测到 fnos 的情况下使用独立目录；已安装 fnos 却无法更新时会明确报错，不会静默换目录另装一份。

安装脚本自身的进度、成功、错误和操作指引均使用简体中文。PowerShell 文件保存为 UTF-8 BOM，网页与 CMD 入口按 UTF-8 解码下载内容，兼容 Windows PowerShell 5.1；CMD 使用 UTF-8 显示中文，结束时恢复原控制台代码页。npm、下载器或系统返回的原始技术诊断保持原文。

独立安装不需要管理员权限，也不修改已有 Node.js 和全局 npm 配置：

- Linux/macOS：`~/.local/share/fnos-cli/`；按当前 shell 将 `bin` 加入 `.zshrc`（尊重 `ZDOTDIR`）、Bash 启动文件或 Fish `conf.d`。
- Windows：`%LOCALAPPDATA%\fnos-cli\`；将 `bin` 加入用户 PATH，仅暴露 `fnos.cmd`，避免 npm 生成的 PowerShell 启动脚本受执行策略阻挡。
- 安装完重新打开终端，再运行 `fnos --help`。脚本也会显示当前窗口立即使用的方法。重复运行可更新 CLI，不重复添加 PATH。

已有 npm 原生安装时，只有原生命令目录不在 PATH 中才会补充配置。更新成功并验证入口后，会移除旧安装器写入的独立目录 PATH 优先设置；Unix 仅移除精确匹配的 `# fnos-cli` 配置块，Windows 仅移除该安装器的旧 bin 项，其他用户配置保留。旧独立安装文件不会自动删除。手工设置的旧 PATH 如果仍遮蔽原生命令，脚本会给出切换指引。

Unix 已有 npm 的命令目录位于 PATH 时（例如 nvm 环境），不再提示手动添加 PATH；如果仅清理了旧安装器的路径配置，只提示重新打开终端。

Windows 的 npm 原生安装可能同时生成 `fnos.ps1`，PowerShell 执行策略受限时请使用脚本提示的 `fnos.cmd --help` 或完整 CMD 入口路径，无需修改执行策略。

自动下载依赖可访问 Node.js 官网和 npm registry 的网络，以及受 Node.js 24 官方二进制支持的系统版本。Linux 需要兼容的 glibc；Alpine/musl、旧系统或其他架构请先自行准备符合要求的 Node.js/npm，再安装 CLI。Unix 需要 Bash、curl（直接下载脚本后可用 wget）、tar/gzip，以及 sha256sum 或 shasum。Windows CMD 页面命令直接使用系统自带 PowerShell，无需预装 curl。

`npm test` 在隔离 HOME 下执行 Unix 安装行为测试，不联网、不修改真实用户配置。`.github/workflows/verify.yml` 另外配置 Linux/macOS/Windows 的真实网络安装验证；Windows 测试入口为 `tests/windows-installers.ps1`，应在可丢弃的 CI 环境运行。CI 下载测试会临时修改测试账户的用户 PATH，结束时恢复。

## 文件

- `src/pages/index.tsx`：首页文案、导航、安装 Tab 与独立命令复制反馈。
- `src/pages/index.module.css`：首页布局、响应式样式。
- `src/css/custom.css`：字体、配色与基础样式。
- `docusaurus.config.ts`：站点配置；文档区和博客已关闭。
- `docs/superpowers/`：设计和实施记录，不作为网站页面发布。
- `static/install.*`：发布到站点根目录的安装脚本。
- `tests/`：隔离安装测试和 Windows 集成验证。

安装命令可一键复制；浏览器不支持剪贴板或拒绝权限时，页面会提示手动选择复制。GitHub 与 npm 链接在新标签页打开。

## 项目链接

- [fnos-cli 源仓库](https://github.com/Timandes/fnos-cli)
- [fnos-cli npm](https://www.npmjs.com/package/fnos-cli)

Apache-2.0
