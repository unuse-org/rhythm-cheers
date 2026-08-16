import {themes as prismThemes} from 'prism-react-renderer';

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'rhythm-cheers 実装Reference',
  tagline: '現行実装の技術Reference',
  url: 'http://localhost',
  baseUrl: '/',

  onBrokenLinks: 'throw',

  i18n: {
    defaultLocale: 'ja',
    locales: ['ja'],
  },

  markdown: {
    mermaid: true,
    hooks: {
      onBrokenMarkdownLinks: 'throw',
    },
  },
  themes: ['@docusaurus/theme-mermaid'],

  presets: [
    [
      'classic',
      {
        docs: {
          path: '../docs/reference',
          routeBasePath: '/',
          sidebarPath: './sidebars.js',
          showLastUpdateTime: true,
        },
        blog: false,
        theme: {
          customCss: './src/css/custom.css',
        },
      },
    ],
  ],

  themeConfig: {
    navbar: {
      title: 'rhythm-cheers 実装Reference',
      items: [
        {
          to: '/',
          label: '概要',
          position: 'left',
        },
        {
          to: '/application-flow',
          label: 'アプリケーション',
          position: 'left',
        },
        {
          to: '/rhythm',
          label: 'リズム',
          position: 'left',
        },
        {
          to: '/character-generation',
          label: '画像生成',
          position: 'left',
        },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Reference',
          items: [
            {label: '概要', to: '/'},
            {label: '画面', to: '/screens'},
            {label: 'ビルドとテスト', to: '/build-and-tests'},
          ],
        },
      ],
      copyright: 'rhythm-cheers current implementation reference',
    },
    colorMode: {
      defaultMode: 'light',
      respectPrefersColorScheme: true,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
      additionalLanguages: ['bash', 'cpp', 'json'],
    },
    tableOfContents: {
      minHeadingLevel: 2,
      maxHeadingLevel: 4,
    },
  },
};

export default config;
