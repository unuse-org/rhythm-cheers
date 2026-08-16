/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
const sidebars = {
  referenceSidebar: [
    {
      type: 'doc',
      id: 'overview',
      label: '実装概要',
    },
    {
      type: 'category',
      label: 'アプリケーション',
      collapsible: false,
      items: ['application-flow', 'screens', 'input'],
    },
    {
      type: 'category',
      label: 'ゲーム処理',
      collapsible: false,
      items: ['rhythm', 'gameplay-visual'],
    },
    {
      type: 'category',
      label: '撮影と画像生成',
      collapsible: false,
      items: ['camera', 'character-generation'],
    },
    'build-and-tests',
  ],
};

export default sidebars;
