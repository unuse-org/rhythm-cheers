---
id: input
title: 入力
description: SensorProviderとCHEERS入力の現行実装
sidebar_position: 4
---

## 入力種別

`RhythmTypes.InputType` に定義されている入力は `CHEERS` の1種類だけである。PREPARE入力は定義されていない。

## SensorProvider

`sensor/sensor_provider.gd` は `Node` を継承し、次のSignalを定義する。

| Signal | 引数 |
| --- | --- |
| `input_detected` | `input_type: RhythmTypes.InputType` |
| `connection_changed` | `connected: bool` |
| `sensor_error` | `message: String` |

`start()` と `stop()` は空実装で、派生クラスが上書きする。

## KeyboardSensorProvider

| 処理 | 現在の動作 |
| --- | --- |
| `start()` | `connection_changed(true)` をemitする |
| `stop()` | `connection_changed(false)` をemitする |
| `_unhandled_input()` | `cheers_input` のpressedで `input_detected(CHEERS)` をemitする |

`project.godot` では `cheers_input` にSpaceキーが割り当てられている。

## SerialSensorProvider

`sensor/serial_sensor_provider.gd` は `SensorProvider` を継承している。GdSerialManagerで指定ポートを開き、改行区切りJSONのx・y・z加速度を読み取る。起動後はCALIBRATINGで静止時の基準ベクトルと標準偏差を求め、IDLE中に乾杯方向への射影成分が閾値以上になると `input_detected(CHEERS)` をemitする。

CHEERS検出後は初期値0.15秒のCOOLDOWNへ入り、同じ動作による連続検出を抑制する。

## Providerの選択

`RhythmCheersApp.SensorMode` は `KEYBOARD` と `SERIAL` を持つ。export property `sensor_mode` の初期値は `KEYBOARD` である。

Appは起動時に両Providerの `process_mode` をdisabledにし、選択したProviderだけをinheritへ変更してSignalを接続し、`start()` を呼ぶ。実行中にProviderを切り替える処理はない。

## 画面ごとのCHEERS処理

| 画面 | CHEERSの処理 |
| --- | --- |
| Title | ドア開演出を開始する |
| FaceCapture / LIVE | 静止画撮影を要求する |
| FaceCapture / REVIEW | 再撮影へ戻る |
| Tutorial | GameplayVisualへ入力表示を要求し、現在の楽曲時刻で `RhythmSession.receive_input()` を呼ぶ |
| Main | GameplayVisualへ常時入力表示を要求し、ゲーム開始済みの場合だけ現在の楽曲時刻で判定する |
| Result | 表示開始5秒後から画面を完了してTitleへ戻る |

TutorialとMainの入力表示は譜面判定から独立している。CHEERSを受け取ると判定窓外でも `my_hand.png` を0.3秒表示する。判定窓外の入力は成功・失敗件数を変更せず、成功時の衝突Effectも表示しない。
