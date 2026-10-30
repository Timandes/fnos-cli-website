# 首页交付验证

## 2026-10-30 安装提示中文化

- Bash、PowerShell 和 CMD 安装脚本自身的提示统一为简体中文，包括依赖检测、下载、安装、校验、错误和完成后的操作指引。
- PowerShell 源文件使用 UTF-8 BOM，网页和 CMD 下载入口显式按 UTF-8 解码；PowerShell 恢复原输出编码，CMD 恢复原控制台代码页。
- Windows CI 增加下载脚本中文解码及中文错误输出检查，保留真实安装与重复安装检查；本机不具备 Windows 实机执行环境。

## 2026-10-30 域名更正

- 用户更正正式地址为 `https://fnos.timandes.cn/`；首页四种安装命令、CMD 引导器、站点 canonical 配置和项目说明同步改为 `.cn`。

## 2026-10-29 跨平台安装更新

- 四个 Tab：Windows CMD、Windows PowerShell、Linux、macOS；下方独立提供 npm 直装命令及复制反馈。
- 正式站点 URL 已设为 `https://fnos.timandes.cn/`；`install.sh`、`install.ps1`、`install.cmd` 随构建发布到根目录。
- 最终 `npm test` 14/14 通过；`npm run typecheck`、`npm run build`、`bash -n static/install.sh`、`git diff --check` 通过。构建脚本与源文件逐字节一致，CI YAML 可解析。
- 浏览器实测四种安装命令、复制的准确内容、npm 独立复制、拒绝剪贴板后的提示、键盘切换；360px 时页面无横向溢出，四个 Tab 以两列全部展示。测试注入已通过重载恢复，viewport 已复原。
- 独立只读审阅及修复复核通过；Windows 使用 ASCII 相对路径启动器，避免中文用户路径的控制台码页问题。
- macOS 隔离 HOME 复用当前 Node/npm，真实安装 fnos-cli 0.5.1，`--version`、`--help` 成功。未访问 NAS 或读取认证配置。
- 从无 Node 环境启动的真实完整安装因官方下载协议错误和慢速超时未完成；已增加 HTTP/1.1、进度、重试及断点续传。Windows/Linux 的真实执行仍需已配置的 CI 验证，尚未运行 CI。
- 初次交付时位于 `feature/cross-platform-installers`，未提交、推送或部署。本地生产预览为 `http://127.0.0.1:3002/`。
- 后续用户授权提交主干并推送全部 remote；集成顺序为功能分支 → `develop` → `main`，同步 `origin` 和 `codeup` 的 `develop` / `main`。推送会触发仓库配置的 CI，实际安装结果以 CI 为准。

## 初次首页交付记录

- 项目：`/Users/timandes/Projects/fnos/fnos-cli-website`。
- 服务：`http://127.0.0.1:3000/`，已在内置浏览器打开并保留；开发服务保持运行。
- 最终代码的 `npm run typecheck` 和 `npm run build` 均退出 0。
- 本地首页 HTTP 200；生产 HTML 已核对必要文案、安装命令、有效锚点、GitHub/npm 链接和 ID 唯一性。
- 浏览器检查桌面和 360px 手机宽度，均无页面横向溢出；手机标题按完整词组换行。
- 安装命令复制成功提示和模拟剪贴板拒绝后的手动复制提示均已检查。模拟仅作用于测试页面，随后已重载恢复。
- 快速开始正确定位安装区域；键盘导航存在可见焦点。
- 新的只读审阅上下文检查自写源码与约定，未报告阻塞项。构建发现 Layout 不支持 noNavbar，已使用 Navbar 主题覆盖修正，并通过类型检查和构建复验。

## 实施决定及边界

- 初次交付按用户指定的新独立目录直接实现；后续用户已明确要求初始化 Git 并提交代码，沿用 fnos-cli 的提交身份，配置提供的 GitHub 远程地址，并建立 main / develop 分支。
- 展示页通过真实构建和浏览器检查验证，未增加测试框架；以后增加复杂行为时需要相应自动化测试。
- 安装因官方源下载慢，单次使用公共 npm 镜像，未修改全局 npm 配置；原生可选组件安装使用了本机 Node 头文件，未把本机路径写入项目配置。
- 外链地址已核对，远程站点即时可达性受上游服务影响。
- 当前配置用于本地预览；发布时需配置真实域名和 baseUrl。

## Git 首次提交

- 远程：`git@github.com:Timandes/fnos-cli-website.git`，初始化前已确认没有远程分支。
- 首次提交：`feat: initialize Docusaurus homepage`。
- 提交前重新运行 TypeScript 检查和生产构建，均退出 0。
- 依赖、构建产物、运行缓存和执行临时记录通过 .gitignore 排除。
