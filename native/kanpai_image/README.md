# Kanpai Image

撮影画像から5状態のキャラクター画像を生成するC++ライブラリとGodot向けGDExtensionです。

## 開発ビルド

対象環境はApple Silicon Macです。必要なものはCMake 3.21以降、Ninja、OpenCV 4.14.x、`third_party/godot-cpp`です。動作確認済みの構成はGodot 4.6.x、godot-cpp 4.5、OpenCV 4.14.0です。

開発ツールはリポジトリ直下の`Brewfile`で管理します。

```sh
brew bundle
git submodule update --init --recursive
```

`brew bundle`の完了後、ネイティブ拡張をビルドしてテストします。

```sh
cd native/kanpai_image
cmake --preset macos-arm64-debug
cmake --build --preset macos-arm64-debug
ctest --preset macos-arm64-debug
```

`CMakePresets.json`はApple Silicon Homebrewの`/opt/homebrew/opt/opencv@4`を参照します。CMakeはOpenCV 4.14.xだけを受け付け、構成時に検出したバージョンを表示します。

この構成で生成したGDExtensionはHomebrewのOpenCVを動的に読み込みます。ゲームを実行するApple Silicon Macにも、事前に`brew bundle`で依存関係を導入してください。将来`.app`だけで配布する場合は、OpenCVの静的リンクまたはdylib同梱へ切り替える必要があります。

CLIだけを確認するときは、GDExtensionを無効にできます。

```sh
cmake -S . -B build/core -G Ninja -DKANPAI_BUILD_GDEXTENSION=OFF
cmake --build build/core
ctest --test-dir build/core --output-on-failure
```

入力写真と生成画像はリポジトリへ追加しないでください。
