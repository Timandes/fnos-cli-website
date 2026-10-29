# fnos-cli 极简门户设计

## 目标与范围

在 `/Users/timandes/Projects/fnos/fnos-cli-website` 创建独立 Docusaurus 项目，仅实现中文首页。访客能够了解 fnos-cli、复制安装命令、查看命令示例，并进入 GitHub 或 npm。此阶段交付本地项目和预览。

## 方案选择

用户通过回复批注「采纳这个」选择第一轮「清爽留白：白底蓝色，简洁耐看」及其效果图。该方案采用居中标题、白色背景、蓝色强调、浅灰代码区、开放式三列功能介绍。已展示的黑绿终端、米白暖橙、黑白瑞士排版、手册侧栏和薄荷工具面板均未采用。

## 首页结构

- 顶栏：fnos-cli 字标、首页、GitHub、npm。
- 首屏：小字 `fnOS × Command Line`，标题「用命令行，连接你的 fnOS。」，副标题「飞牛 fnOS 的命令行客户端。」，以及「查询系统状态，管理多台设备，让日常操作融入脚本。」。
- 操作：「快速开始」滚动到安装位置；「查看 GitHub」跳转源仓库。
- 安装：`npm install -g fnos-cli`，可复制，显示成功或失败反馈。
- 示例：`fnos --help`、`fnos resmon cpu`、`fnos docker listContainers --all true`。
- 功能：多设备连接、脚本友好、安全认证。文案依据现有 CLI README，不引入未实现能力。
- 页脚：Apache-2.0、GitHub 与 npm 入口。

## 实现约束与自主选择

- Docusaurus Classic，关闭 docs 和 blog，只保留首页；设计与计划目录不作为网站文档发布。
- 默认固定浅色，蓝色采用 `#2563eb`，强调留白；具体字距、间距由实施者按选定效果图调整。
- 适配桌面和 360px 手机宽度，窄屏重排；按钮有键盘焦点，反馈使用 `aria-live`，尊重减少动态效果偏好。
- 复制功能失败时显示清楚提示，不显示虚假成功；禁用 JavaScript 时安装命令和链接仍可阅读使用。
- 链接使用 `https://github.com/Timandes/fnos-cli` 和 `https://www.npmjs.com/package/fnos-cli`；不创建未实现的站内页面或无效导航。
- 本地 Node.js 为 22.23.3，npm 为 10.9.9；安装时核对 Docusaurus 当前稳定版本并锁定依赖。
- 不增加后台、账户、搜索、统计、发布或远程仓库。
- 当前源项目保持不变。新项目如需初始化 Git，使用 git flow 分支命名；提交采用英文 Conventional Commits，禁止 Co-Authored-By。

## 验证

运行生产构建，启动本地预览，检查桌面与手机排版、复制交互、首页锚点及外链。此低风险展示页不额外引入单元测试框架，以真实构建与浏览器验收为准。
