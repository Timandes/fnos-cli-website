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
npm run build
npm run serve
```

静态产物位于 `build/`。当前只配置本地预览；部署前请按实际域名及子路径调整 `docusaurus.config.ts` 中的 `url` 和 `baseUrl`。

## 文件

- `src/pages/index.tsx`：首页文案、导航与安装命令复制。
- `src/pages/index.module.css`：首页布局、响应式样式。
- `src/css/custom.css`：字体、配色与基础样式。
- `docusaurus.config.ts`：站点配置；文档区和博客已关闭。
- `docs/superpowers/`：设计和实施记录，不作为网站页面发布。

安装命令可一键复制；浏览器不支持剪贴板或拒绝权限时，页面会提示手动选择复制。GitHub 与 npm 链接在新标签页打开。

## 项目链接

- [fnos-cli 源仓库](https://github.com/Timandes/fnos-cli)
- [fnos-cli npm](https://www.npmjs.com/package/fnos-cli)

Apache-2.0
