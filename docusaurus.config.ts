import type {Config} from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';

const config: Config = {
  title: 'fnos-cli',
  tagline: '飞牛 fnOS 的命令行客户端。',
  favicon: 'img/favicon.svg',
  url: 'https://fnos.timandes.net',
  baseUrl: '/',
  organizationName: 'Timandes',
  projectName: 'fnos-cli-website',
  onBrokenLinks: 'throw',
  i18n: {
    defaultLocale: 'zh-Hans',
    locales: ['zh-Hans'],
  },
  presets: [
    [
      'classic',
      {
        docs: false,
        blog: false,
        theme: {customCss: './src/css/custom.css'},
      } satisfies Preset.Options,
    ],
  ],
  themeConfig: {
    colorMode: {
      defaultMode: 'light',
      disableSwitch: true,
      respectPrefersColorScheme: false,
    },
    metadata: [
      {name: 'keywords', content: 'fnos-cli, fnOS, 飞牛, NAS, 命令行'},
      {name: 'theme-color', content: '#ffffff'},
    ],
  } satisfies Preset.ThemeConfig,
};

export default config;
