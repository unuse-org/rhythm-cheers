# rhythm-cheers Reference Site

`../docs/reference`にある、現行コードの実装事実だけを閲覧するDocusaurusサイトです。

## ローカルで閲覧する

```bash
cd docs-site
npm install
npm run start
```

ブラウザで `http://localhost:3000` を開きます。Markdownの変更は開発サーバーへ自動反映されます。

## 静的HTMLを生成する

```bash
cd docs-site
npm ci
npm run build
```

生成結果は `docs-site/build/` に出力されます。

本文には計画、改善案、将来仕様を含めません。Docusaurusの構成は`docs-site/`、本文は`docs/reference/`で管理します。
