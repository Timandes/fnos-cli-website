import {useEffect, useState, type ReactNode} from 'react';
import Layout from '@theme/Layout';
import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';
import styles from './index.module.css';

const githubUrl = 'https://github.com/Timandes/fnos-cli';
const npmUrl = 'https://www.npmjs.com/package/fnos-cli';
const installCommand = 'npm install -g fnos-cli';
const installers = [
  {
    value: 'windows-cmd', label: 'Windows CMD', script: '/install.cmd',
    command: 'powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://fnos.timandes.net/install.ps1 -ErrorAction Stop | iex"',
    help: '打开「命令提示符」，粘贴命令并按回车。适用于 Windows 10 / 11，支持 x64 和 ARM64。',
  },
  {
    value: 'windows-powershell', label: 'Windows PowerShell', script: '/install.ps1',
    command: 'irm https://fnos.timandes.net/install.ps1 -ErrorAction Stop | iex',
    help: '打开 PowerShell，粘贴命令并按回车。适用于 Windows PowerShell 5.1 及以上版本，支持 x64 和 ARM64。',
  },
  {
    value: 'linux', label: 'Linux', script: '/install.sh',
    command: 'curl -fsSL https://fnos.timandes.net/install.sh -o fnos-install.sh && bash fnos-install.sh',
    help: '打开终端，粘贴命令并按回车。需要 Bash 和 curl，支持使用 glibc 的 x64 / ARM64 发行版。',
  },
  {
    value: 'macos', label: 'macOS', script: '/install.sh',
    command: 'curl -fsSL https://fnos.timandes.net/install.sh -o fnos-install.sh && bash fnos-install.sh',
    help: '打开「终端」，粘贴命令并按回车。支持 Apple 芯片和 Intel Mac。',
  },
];

const features = [
  {title: '多设备连接', description: '命名保存不同 server，按需切换。'},
  {title: '脚本友好', description: '支持原始 JSON 与格式化输出。'},
  {title: '安全认证', description: '支持密码、两步验证与 OAuth。'},
];

function ExternalLink({href, children, className}: {
  href: string;
  children: ReactNode;
  className?: string;
}) {
  return <a href={href} className={className} target="_blank" rel="noopener noreferrer">{children}</a>;
}

function CopyIcon({copied}: {copied: boolean}) {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      {copied ? <path d="m5 12 4 4L19 6" /> : <><rect x="8" y="8" width="12" height="13" rx="2" /><path d="M16 8V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v10a2 2 0 0 0 2 2h3" /></>}
    </svg>
  );
}

function CommandBlock({command, label, feedbackId}: {command: string; label: string; feedbackId: string}) {
  const [copyState, setCopyState] = useState<'idle' | 'copied' | 'error'>('idle');

  useEffect(() => {
    if (copyState !== 'copied') return;
    const timeout = window.setTimeout(() => setCopyState('idle'), 2500);
    return () => window.clearTimeout(timeout);
  }, [copyState]);

  async function copyInstallCommand() {
    try {
      await navigator.clipboard.writeText(command);
      setCopyState('copied');
    } catch {
      setCopyState('error');
    }
  }

  return (
    <>
      <div className={styles.install}>
        <code className={styles.installCode}>{command}</code>
        <button type="button" className={`${styles.copyButton} ${copyState === 'copied' ? styles.copied : ''}`} onClick={copyInstallCommand} aria-label={copyState === 'copied' ? `${label}已复制` : `复制${label}`} aria-describedby={feedbackId}>
          <CopyIcon copied={copyState === 'copied'} />
        </button>
      </div>
      <p id={feedbackId} role="status" aria-live="polite" className={copyState === 'error' ? styles.copyError : styles.srOnly}>
        {copyState === 'copied' ? `${label}已复制。` : copyState === 'error' ? '复制未成功，请选中上方命令手动复制。' : ''}
      </p>
    </>
  );
}

export default function Home(): ReactNode {
  return (
    <Layout title="用命令行，连接你的飞牛 fnOS" description="飞牛 fnOS 的命令行客户端。查询系统状态，管理多台设备，让日常操作融入脚本。" noFooter>
      <div className={styles.page}>
        <header className={styles.header}>
          <div className={styles.headerInner}>
            <a href="/" className={styles.wordmark} aria-label="飞牛fnOS CLI 首页">飞牛fnOS CLI</a>
            <nav aria-label="主导航" className={styles.nav}>
              <a href="/" aria-current="page" className={styles.activeLink}>首页</a>
              <ExternalLink href={githubUrl}>GitHub <span aria-hidden="true">↗</span></ExternalLink>
              <ExternalLink href={npmUrl}>npm <span aria-hidden="true">↗</span></ExternalLink>
            </nav>
          </div>
        </header>

        <main id="main-content" className={styles.main}>
          <section className={styles.hero} aria-labelledby="hero-title">
            <p className={styles.eyebrow}>飞牛 fnOS <span aria-hidden="true">×</span> Command Line</p>
            <h1 id="hero-title"><span>用命令行，</span><wbr /><span>连接你的飞牛 fnOS</span></h1>
            <p className={styles.description}>
              <span>飞牛 fnOS 的命令行客户端。</span>
              <span>查询系统状态，管理多台设备，让日常操作融入脚本。</span>
            </p>
            <div className={styles.actions}>
              <a href="#install" className={styles.primaryButton}>快速开始</a>
              <ExternalLink href={githubUrl} className={styles.secondaryButton}>查看 GitHub</ExternalLink>
            </div>
          </section>

          <section className={styles.commands} aria-label="安装与命令示例">
            <div id="install" className={styles.installer}>
              <h2>一键安装</h2>
              <p className={styles.installIntro}>选择你的系统，复制命令到对应终端运行。脚本会自动补齐 Node.js 和 npm，并安装 fnos-cli，无需管理员权限。</p>
              <Tabs defaultValue="windows-cmd">
                {installers.map(installer => (
                  <TabItem key={installer.value} value={installer.value} label={installer.label}>
                    <CommandBlock command={installer.command} label={`${installer.label} 安装命令`} feedbackId={`${installer.value}-feedback`} />
                    <div className={styles.installHelp}>
                      <p>{installer.help}</p>
                      <a href={installer.script} download>下载安装脚本 <span aria-hidden="true">↓</span></a>
                    </div>
                  </TabItem>
                ))}
              </Tabs>
              <p className={styles.installNote}>首次安装需要联网下载依赖，请耐心等待。完成后重新打开终端，运行 <code>fnos --help</code> 即可开始。</p>
            </div>
            <div className={styles.npmInstall}>
              <h2>已经拥有 npm？使用 npm 安装</h2>
              <p>需要 Node.js 18.17 或更高版本、npm 8 或更高版本。</p>
              <CommandBlock command={installCommand} label="npm 安装命令" feedbackId="npm-feedback" />
            </div>
            <div className={styles.examples}>
              <h2>示例命令</h2>
              <div className={styles.codeScroll}>
                <pre><code><span className={styles.codeLine}><span className={styles.lineNumber} aria-hidden="true">1</span><span><span className={styles.commandName}>fnos --help</span></span></span><span className={styles.codeLine}><span className={styles.lineNumber} aria-hidden="true">2</span><span><span className={styles.commandName}>fnos</span> resmon cpu</span></span><span className={styles.codeLine}><span className={styles.lineNumber} aria-hidden="true">3</span><span><span className={styles.commandName}>fnos</span> docker listContainers <span className={styles.commandName}>--all true</span></span></span></code></pre>
              </div>
            </div>
          </section>

          <section className={styles.features} aria-label="主要功能">
            {features.map(feature => (
              <article className={styles.feature} key={feature.title}>
                <h2>{feature.title}</h2>
                <p>{feature.description}</p>
              </article>
            ))}
          </section>
        </main>

        <footer className={styles.footer}>
          <div className={styles.footerInner}>
            <p>fnos-cli <span aria-hidden="true">·</span> Apache-2.0</p>
            <nav aria-label="项目链接">
              <ExternalLink href={githubUrl}>GitHub</ExternalLink>
              <ExternalLink href={npmUrl}>npm</ExternalLink>
            </nav>
          </div>
        </footer>
      </div>
    </Layout>
  );
}
