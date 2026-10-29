import {useEffect, useState, type ReactNode} from 'react';
import Layout from '@theme/Layout';
import styles from './index.module.css';

const githubUrl = 'https://github.com/Timandes/fnos-cli';
const npmUrl = 'https://www.npmjs.com/package/fnos-cli';
const installCommand = 'npm install -g fnos-cli';

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

export default function Home(): ReactNode {
  const [copyState, setCopyState] = useState<'idle' | 'copied' | 'error'>('idle');

  useEffect(() => {
    if (copyState !== 'copied') return;
    const timeout = window.setTimeout(() => setCopyState('idle'), 2500);
    return () => window.clearTimeout(timeout);
  }, [copyState]);

  async function copyInstallCommand() {
    try {
      await navigator.clipboard.writeText(installCommand);
      setCopyState('copied');
    } catch {
      setCopyState('error');
    }
  }

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
            <div id="install" className={styles.install}>
              <span className={styles.installLabel}>安装</span>
              <code className={styles.installCode}>{installCommand}</code>
              <button type="button" className={`${styles.copyButton} ${copyState === 'copied' ? styles.copied : ''}`} onClick={copyInstallCommand} aria-label={copyState === 'copied' ? '安装命令已复制' : '复制安装命令'} aria-describedby="copy-feedback">
                <CopyIcon copied={copyState === 'copied'} />
              </button>
            </div>
            <p id="copy-feedback" role="status" aria-live="polite" className={copyState === 'error' ? styles.copyError : styles.srOnly}>
              {copyState === 'copied' ? '安装命令已复制。' : copyState === 'error' ? '复制未成功，请选中上方命令手动复制。' : ''}
            </p>
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
