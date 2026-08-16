---
id: camera
title: カメラ
description: CameraCaptureSource、WebCameraCaptureSource、FakeCameraCaptureSourceの現行実装
sidebar_position: 7
---

## CameraCaptureSource

`camera/camera_capture_source.gd` はカメラ実装の基底クラスである。

### State

| State | 意味 |
| --- | --- |
| `IDLE` | 停止中 |
| `DISCOVERING` | Feedまたは最初のframeを待機中 |
| `READY` | Previewと撮影が利用可能 |
| `CAPTURING` | 静止画を取得中 |
| `CAPTURED` | 静止画取得済み |
| `UNAVAILABLE` | カメラがない、または切断された |
| `ERROR` | 対応外OS、形式不明などのエラー |

### Signal

| Signal | 引数 |
| --- | --- |
| `preview_ready` | `texture: Texture2D` |
| `state_changed` | `next_state: State`, `message: String` |
| `capture_succeeded` | `image: Image` |
| `capture_failed` | `message: String` |

基底クラスの `start()` と `capture_frame()` は未実装エラーを返す。`stop()` はStateをIDLEにする。

## WebCameraCaptureSource

`camera/web_camera_capture_source.gd` がGodotの `CameraServer` を利用する。

| 設定 | 現在値 |
| --- | --- |
| `SUPPORTED_PLATFORMS` | `macOS`のみ |
| `preferred_size` | 1280 × 720 |

### 起動

`start()` はIDLEでない場合は何もしない。OSがmacOS以外の場合はERRORへ遷移する。

macOSでは次を行う。

1. `CameraServer.camera_feeds_updated` と `camera_feed_removed` を購読する。
2. StateをDISCOVERINGへ変更する。
3. `CameraServer.monitoring_feeds = true` にする。
4. `CameraServer.feeds()` の先頭Feedを選ぶ。

Feedが空の場合はUNAVAILABLEになる。複数Feedからの選択UIはなく、配列先頭を使用する。

### Format選択

Feedが持つformatsから、幅と高さについて次のscoreが最小のformatを選ぶ。

```text
score = abs(width - 1280) + abs(height - 720)
```

有効なformatがない場合は既定形式を使う。`set_format()` がfalseの場合もwarningを出して既定形式を使う。

### FeedDataType

最初の `frame_changed` で実際のdata typeを確認する。

| FeedDataType | Preview処理 |
| --- | --- |
| `FEED_RGB` | `CameraTexture`を直接使用 |
| `FEED_EXTERNAL` | `CameraTexture`を直接使用 |
| `FEED_YCBCR` | 単一TextureをShaderでRGB変換 |
| `FEED_YCBCR_SEP` | Y TextureとCbCr TextureをShaderでRGB変換 |
| その他 | ERROR |

YCbCr変換には `camera/ycbcr_to_rgb.gdshader` を使う。変換係数はBT.709で、結果alphaは1.0固定である。変換用SubViewportはframe Textureの実サイズへ追従する。

Preview準備が完了すると `preview_ready(preview_texture)` をemitし、DISCOVERINGからREADYへ遷移する。

### 静止画取得

`capture_frame()` はREADYかつPreview Textureが存在するときだけ動作する。

1. StateをCAPTURINGにする。
2. `RenderingServer.frame_post_draw` を待つ。
3. `preview_texture.get_image()` でGPUからImageを取得する。
4. ImageをRGBA8へ変換する。
5. StateをCAPTUREDにする。
6. `capture_succeeded(image)` をemitする。

Imageが空の場合はREADYへ戻り、`capture_failed` をemitする。

### 停止と切断

`stop()` はFeedのSignalを解除し、CameraTextureを非activeにし、変換用SubViewportと参照を破棄する。CameraServerのSignalも解除し、`monitoring_feeds = false` としてIDLEへ遷移する。

使用中Feedのremoved Signalを受けた場合はカメラ参照を解放し、UNAVAILABLEへ遷移する。CameraServerの監視とSignal接続は維持されるため、その後のfeeds updatedで再探索する。

## FakeCameraCaptureSource

`camera/fake_camera_capture_source.gd` は自動テスト用である。constructorへImageを渡せる。nullまたは空の場合は64 × 64の青系RGBA8画像を生成する。

`start()` でImageTextureを生成し、Previewを通知してREADYになる。`capture_frame()` は元ImageをduplicateしてCAPTUREDへ遷移し、成功Signalをemitする。

## FaceCaptureScreenでの表示

CameraStage内のPreviewはCameraFrameの内側へ配置され、`stretch_mode = 6` を使用する。Preview上には撮影前だけFaceGuideと `camera_message_1.png`、撮影後は `camera_message_2.png` が表示される。

CameraSourceがUNAVAILABLEまたはERRORの場合、StatusLabelへmessageと再試行案内を表示し、RetryButtonを表示する。RetryButtonはCameraSourceをstopしてからstartする。

ShutterPlayerはCameraStage内ではなくFaceCaptureScreen直下にあり、全画面表示される。動画のgreen部分は `camera/shutter_chroma_key.gdshader` で透過され、表示領域のaspect比に合わせて中央cropされる。
