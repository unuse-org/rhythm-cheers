---
id: build-and-tests
title: ビルドとテスト
description: Godot、GDExtension、OpenCV、テストの現行構成
sidebar_position: 9
---

## Godot

`project.godot` のfeatureはGodot 4.6、rendererはForward Plusである。起動シーンは `res://app/app.tscn`。

`export_presets.cfg` にはmacOS用Presetが1件ある。出力先は `rhythm-cheers.dmg`、binary architectureはarm64で、camera entitlementを有効にしている。生成したDMGはGit管理外である。

## ネイティブ依存関係

ルートの `Brewfile` は次のFormulaを定義する。

```ruby
brew "cmake"
brew "ninja"
brew "opencv@4"
```

`native/kanpai_image/CMakeLists.txt` の現在値:

| 項目 | 値 |
| --- | --- |
| CMake minimum | 3.21 |
| C++ standard | C++17 |
| OpenCV | 4.14.xのみ |
| OpenCV component | core, dnn, imgproc, objdetect |
| CLI追加component | imgcodecs |
| Core target | `kanpai_image_core` static library |
| CLI target | `kanpai_image_cli` |
| Test target | `kanpai_image_tests` |
| Extension target | `kanpai_image_gdextension` shared library |

CMakeはOpenCV 4.14以上を要求し、4.15以上を検出した場合はconfigure errorにする。

`native/kanpai_image/third_party/godot-cpp` はGit submoduleで、`.gitmodules` のbranchは4.5である。

## CMake Preset

`native/kanpai_image/CMakePresets.json` は次を定義する。

| Preset | Build type | Architecture | CLI | Tests | godot-cpp target |
| --- | --- | --- | --- | --- | --- |
| `macos-arm64-debug` | Debug | arm64 | ON | ON | default |
| `macos-arm64-release` | Release | arm64 | OFF | OFF | `template_release` |

両Presetの `OpenCV_DIR` は `/opt/homebrew/opt/opencv@4/lib/cmake/opencv4` である。

Debug buildとCTestの実行手順は次のとおり。

```bash
brew bundle
git submodule update --init --recursive
cd native/kanpai_image
cmake --preset macos-arm64-debug
cmake --build --preset macos-arm64-debug
ctest --preset macos-arm64-debug
```

## GDExtension成果物

ビルド出力先は `addons/kanpai_image/bin/macos-arm64/` である。現在、次の2ファイルが存在する。

- `libkanpai_image.macos.template_debug.arm64.dylib`
- `libkanpai_image.macos.template_release.arm64.dylib`

どちらもMach-O arm64 shared libraryである。現在のバイナリは `/opt/homebrew/opt/opencv@4/lib/` 以下のOpenCV 4.14 dylibへ動的リンクしている。

`addons/kanpai_image/kanpai_image.gdextension` のentry symbolは `kanpai_image_library_init`、minimum compatibilityはGodot 4.5である。

## C++テスト

`native/kanpai_image/tests/character_generator_test.cpp` は独自の小さいtest runnerで、次を検証する。

- 半透明RGBA画像のsource-over alpha合成
- 負座標に置いたOverlayのclip
- 空入力が `GenerationError::EmptyInput` を返すこと
- 髪とひげを全状態へ合成すること
- ほっぺと失敗マークを対象状態だけへ合成すること
- 装飾素材の透明余白が合成位置へ影響しないこと

CTestには `kanpai_image_tests` という名前で1件登録される。

## Godot自動テスト

各test scriptは `SceneTree` を継承し、失敗がなければexit code 0、失敗時は1で終了する。

```bash
godot --headless --path . --script path/to/test.gd
```

| Test script | 主な検証対象 |
| --- | --- |
| `app/tests/app_test.gd` | 画面遷移、Payload、Provider所有 |
| `app/tests/player_count_store_test.gd` | 累計人数の初期値、保存、加算、再読込 |
| `app/tests/scene_flow_test.gd` | 画面順序、path、RunContext、Scene load |
| `camera/tests/camera_capture_source_test.gd` | Fake撮影、format選択 |
| `image_processing/tests/character_generation_service_test.gd` | cancel、pending、古い結果の破棄 |
| `image_processing/tests/kanpai_image_extension_test.gd` | ClassDB登録、configure、空入力、任意の実画像生成 |
| `main/tests/main_start_test.gd` | 音源先行再生、12拍リードイン、開始Overlay、入力抑止 |
| `rhythm/tests/rhythm_audio_controller_test.gd` | 画面別音源、Cue時刻、遅延offset |
| `rhythm/tests/rhythm_chart_test.gd` | 小節譜面の展開、ローカルSection、2連乾杯、旧形式互換 |
| `rhythm/tests/rhythm_session_test.gd` | 2連乾杯の成功、MISS、frame skip |
| `rhythm/tests/rhythm_timing_test.gd` | 可変BPMの拍・秒変換と全曲終了時刻 |
| `screens/face_capture/tests/face_capture_screen_test.gd` | 撮影、生成待ち、顔未検出からの復帰 |
| `screens/title/tests/title_screen_test.gd` | ドア演出後の完了 |
| `screens/tutorial/tests/tutorial_screen_test.gd` | 曲全体、再挑戦、Clear遷移 |
| `visual/tests/gameplay_visual_test.gd` | 状態表示、MISS、生成画像、上下動、横移動 |

`kanpai_image_extension_test.gd` は環境変数 `KANPAI_TEST_FACE` が設定されている場合だけ、指定されたGit管理外の顔写真でsync/async成功経路を追加検証する。未設定の場合もClassDB登録、素材configure、空Image拒否は実行する。

## 手動テスト

| Scene / Script | 動作 |
| --- | --- |
| `camera/tests/manual_web_camera_test.tscn` | 実カメラPreview、静止画の色・向き、再起動 |
| `sensor/tests/serial_connection_test.tscn` | port一覧、指定portを115200 baudでopen、1行read、close |

Serial connection testは `SerialSensorProvider` を通さず、`GdSerial` を直接使用する。

## Referenceサイト

このReferenceは `docs-site/` のDocusaurus 3.10.2でHTML化する。本文の読込元は `docs/reference/`、生成先は `docs-site/build/` で、生成先と `node_modules` は `docs-site/.gitignore` で除外される。

```bash
cd docs-site
npm ci
npm run build
```
