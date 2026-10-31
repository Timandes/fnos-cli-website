# 首页交付验证

## 2026-10-30 恢复 Windows 一键复制

- 撤回 Windows 手动选择命令的交互，恢复全部安装 Tab 的一键复制；保留原有中文解码兼容、内存执行及安装器行为。
- 使用下载的上游现行过滤列表验证：本站和 uv 的 Windows 安装命令均匹配通用 ClickFix 规则，但 `astral.sh` 有网页域名例外，`fnos.timandes.cn` 没有。恢复复制交互不等同于消除了 uBlock 误报，后者仍需上游例外处理。
- 独立只读复核确认撤回完整，页面及安装器与引入手动选择前完全一致；`npm test` 25/25、`npm run typecheck`、`npm run build`、差异检查通过。

## 2026-10-30 安装器 CI 回归修复

- 初始核实 main `8f51a2a` 与 develop `6284597` 文件树一致，两者 CI 仍有相同 fish 和 Windows 失败；任务期间又更新为 main `471c6d2`、develop `7d1c2fc`，文件树仍一致。本地 hotfix 已同步最新 main，保留并行的管道安装命令更新。
- fish 测试继承了外部 `XDG_CONFIG_HOME`，安装器实际读写路径与断言路径不一致。设置外部配置目录后复现原两项失败；测试夹具现显式隔离 `XDG_CONFIG_HOME` 和 `ZDOTDIR`，新增回归验证外部 fish/zsh 配置逐字节不变。
- Windows CI 的直接夹具自检证实，模拟失败的 npm CMD 返回 0 而非 73。其括号块内 `exit /b 73` 后还有命令，与 [PowerShell #17936 的 CMD 行为](https://github.com/PowerShell/PowerShell/issues/17936) 相符；改用顶层条件退出，生产安装器不变。离线步骤复用同一夹具验证失败 73、跳过 0 且不调用真实 npm，集成测试仍验证失败后 PATH/原安装不变。
- 预期失败的原生命令会留下全局退出码；测试成功路径明确清零，避免 GitHub Actions 将夹具的预期失败当作整步失败。
- 本机默认及外部 XDG/ZDOTDIR 环境完整离线测试均为 26/26；typecheck、build、Bash/Node 语法、差异检查通过。仓库没有 lint 脚本。已推送 `1507063` 和 `c20bb6c` 的 website 与 Linux/macOS 真实安装验证通过；Windows 夹具最终修复尚待 CI 确认。
- 此前 hotfix 推送被 SSH 认证拒绝（`Permission denied (publickey)`，agent 无身份），远程仍为 `c20bb6c`；草稿 PR 创建被 GitHub 集成 403 拒绝。后续用户授权直接提交、合并 main 并正常推送，替代草稿 PR 交付；重新核对远程 main `86aa5b7`、develop `4ea7235`，相较 `471c6d2` 仅增加上述一键复制验证记录，合并时保留双方文档。SSH agent 仍无身份，未盲目重试；本地 main 整合后仍待恢复现有认证才能推送并验证最终 Windows CI。未部署、发版、强推或更改权限/凭据。

## 2026-10-30 管道安装命令

- Linux/macOS 的显示与复制命令改为 `curl -fsSL https://fnos.timandes.cn/install.sh | bash`，不再先保存 `fnos-install.sh`；保留 Bash 兼容要求及可选的手动下载链接。
- Windows CMD/PowerShell 原本已按 UTF-8 解码后在内存执行，无需保存下载脚本，保持原有兼容处理。
- 浏览器实测 Linux、macOS Tab 的显示、复制反馈和实际剪贴板内容；生产 HTML 不再包含旧的保存文件命令。
- 本地 HTTP 管道在隔离 HOME、npm 命令替身环境下验证成功和失败两条路径：当前工作目录均无脚本残留，TMPDIR 均已清空；未修改实际 nvm 环境。
- `npm test` 25/25、`npm run typecheck`、`npm run build`、`git diff --check` 通过。

## 2026-10-30 nvm 安装完成提示

- 修复清理旧安装器配置后仍提示手动添加 nvm 版本目录到 PATH 的问题；已有 npm 命令目录位于 PATH 时不显示手动添加指引，仅按需提示重新打开终端。
- 扩展现有回归检查，覆盖 macOS nvm 安装后的旧配置清理、无配置变更及旧命令遮蔽场景；自定义 npm 命令目录确实不在 PATH 时仍有手动指引。
- 修复前已复现错误输出；修复后 `npm test` 25/25、`bash -n static/install.sh`、`git diff --check` 通过。

## 2026-10-30 复用已有 npm 安装

- 修复已有 nvm/npm 环境仍被强制安装到独立用户 prefix 的问题：优先使用当前 npm 的全局目录和原生启动入口，版本只显示一次，报告实际命令路径。
- 仅缺兼容运行环境，或全局目录不可写且没有已有 fnos 时使用独立目录；已有安装更新失败时不回落，不创建第二份安装。
- 验证入口成功后才清理旧安装器的精确 PATH 项/标记块；不删除旧文件，不改动其他用户配置。失败路径保持原有 CLI 和 PATH 配置。
- Windows CMD 委托同一 PowerShell 安装器，因此同步使用新选择逻辑；保留 Windows 编码策略。
- macOS 已用真实 npm 在隔离 HOME/prefix 中预装再更新，确认使用原生全局目录、不生成私有副本、不生成 `.zshrc`；未修改真实用户的 nvm 安装。
- 独立只读审阅发现的 fish 自定义配置覆盖和末尾换行问题已补回归并修复，复核通过；Windows 仍仅完成静态审阅，运行验证留待 Windows CI。
- 最终 `npm test` 25/25 通过；`npm run typecheck`、`npm run build`、`bash -n static/install.sh`、`git diff --check` 通过。

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
