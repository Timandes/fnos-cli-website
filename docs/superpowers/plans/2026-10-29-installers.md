# Cross-platform Installers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 初学者复制平台命令即可补齐运行环境并安装 fnos-cli，老手可在 Tab 下直接使用 npm。

**Architecture:** 静态脚本随 Docusaurus 构建发布，Windows CMD 委托 PowerShell，Unix 共用 Bash 安装器；首页用 Docusaurus Tabs 展示命令。

**Tech Stack:** Bash、Windows PowerShell 5.1、CMD、React、TypeScript、Node.js 原生测试运行器。

**Spec:** `docs/superpowers/specs/2026-10-29-installers-design.md`

## Global Constraints

- 正式 URL `https://fnos.timandes.net/`，不执行部署或推送。
- 复用 Node.js >=18.17、npm >=8，否则下载 Node.js 24 LTS 并验证 SHA-256。
- 自动下载支持 x64、ARM64，安装至用户目录，不要求 sudo，不变更全局 npm 配置。
- 中文页面，四个 Tab，下方保留 `npm install -g fnos-cli`。

## Review Focus

- 下载中断或校验不符必须在执行解压和 npm 前退出。
- PATH 含空格、已有旧 Node 或 npm 缺失时必须使用正确运行时。
- 失败不能输出成功，重复运行不能重复 PATH 配置。
- Windows npm.cmd 退出码必须检查，不能被 PowerShell 吞掉。
- 复制当前 Tab 命令与 npm 命令分别反馈，窄屏不撑开页面。

### Task 1: 安装器

**Files:** `static/install.sh`、`static/install.ps1`、`static/install.cmd`、`tests/installers.test.mjs`。

- [x] 使用临时 HOME 和外部下载/npm 的替身写行为测试，先运行确认安装器缺失失败。
- [x] 实现用户目录安装、环境检查、官方清单选择、校验、PATH、版本验证和错误处理。
- [x] 运行行为测试和 Bash 语法检查；增加 Windows 隔离集成测试和 Windows CI（本机无 Windows，CI 尚未运行）。

### Task 2: 首页与说明

**Files:** `src/pages/index.tsx`、`src/pages/index.module.css`、`docusaurus.config.ts`、`README.md`、`package.json`。

- [x] 四个 Tab 展示命令、复制、对应脚本链接；下方提供 npm 命令与独立复制反馈。
- [x] 更新正式 URL 与安装说明。
- [x] 运行安装器测试、类型检查和生产构建，检查产物脚本。
- [x] 浏览器验证桌面/手机、四种命令、复制和键盘切换；记录平台验证范围。

## 执行记录

- 基线：工作区干净，`npm run typecheck` 通过。
- 选择：在当前项目的功能分支实施；不创建项目外 worktree。
- 安装器：14 项隔离测试通过，覆盖缺失/旧运行时、平台架构、失败退出、校验、路径空格、ZDOTDIR、重复安装与暂态网络错误。
- 实际 npm 安装：隔离 HOME 中安装 fnos-cli 0.5.1，并成功运行 `--version` 和 `--help`。
- 审阅：独立只读审阅发现 Windows 启动器编码问题；改为 ASCII + `%~dp0` 相对路径，并运行最终入口验证。审阅者复核通过。
- Ruling：私有 Node 持久记录位置并在后续安装复用，避免每次从新终端启动都重新下载。
- Ruling：下载采用 HTTP/1.1、重试和断点续传，应对真实下载遇到的 HTTP/2 协议中断；显示下载进度，便于初学者了解状态。
- 页面：四平台切换、键盘方向键后 Enter 激活、复制内容和失败反馈通过；360px 页面宽度等于 scrollWidth，四个 Tab 以两列全部显示。测试注入通过重载恢复，viewport 已复原。
- 环境边界：沙箱中的预览端口探测导致进程堆内存耗尽；授权后的本地生产预览正常，使用生产构建进行页面验收。
- 真实自动补齐边界：macOS 从无 Node 的隔离 HOME 启动，官方包下载遇 HTTP/2 协议错误；HTTP/1.1 再测在 600 秒内接收 47,095,470 / 53,068,959 字节后超时，停止后续重复下载。官方响应已确认 `Accept-Ranges: bytes`，最终脚本加入断点续传；本轮不宣称完整自动补齐真机验收通过。
- 初次交付：`feature/cross-platform-installers`，当时改动未提交、未推送、未部署；三个构建产物脚本与源文件逐字节一致。预览 `http://127.0.0.1:3002/`。
- 后续集成授权：用户要求「提交主干、推送所有 remote」，按 Git Flow 将功能合入 `develop` 再合入 `main`，同步 `origin` / `codeup` 的两个长期分支，不包含站点部署。
