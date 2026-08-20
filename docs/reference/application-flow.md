---
id: application-flow
title: アプリケーションと画面遷移
description: RhythmCheersApp、SceneFlow、RunContext、FlowScreenの現行動作
sidebar_position: 2
---

## Appシーン

`app/app.tscn` のルートは `RhythmCheersApp` で、直下に次のNodeを持つ。

| Node | 型・Script | 用途 |
| --- | --- | --- |
| `ScreenContainer` | `Node` | 現在画面を1つ配置する |
| `KeyboardSensorProvider` | `KeyboardSensorProvider` | Space入力をCHEERSへ変換する |
| `SerialSensorProvider` | `SerialSensorProvider` | 現在は空実装 |

`RhythmCheersApp._ready()` は `RunContext` を生成し、Titleを表示した後、選択されたSensorProviderを開始する。

## 画面IDとシーン

| `SceneFlow.ScreenId` | Scene |
| --- | --- |
| `TITLE` | `res://screens/title/title_screen.tscn` |
| `FACE_CAPTURE` | `res://screens/face_capture/face_capture_screen.tscn` |
| `TUTORIAL` | `res://screens/tutorial/tutorial_screen.tscn` |
| `MAIN` | `res://main/main.tscn` |
| `RESULT` | `res://screens/result/result_screen.tscn` |

`SceneFlow.get_initial_screen()` は `TITLE` を返す。`get_next_screen()` は `FLOW` 配列内の次要素を返し、最後の `RESULT` の次は `TITLE` になる。不明なIDではエラーを出して `TITLE` を返す。

## 画面生成手順

`RhythmCheersApp.show_screen()` は次の順で処理する。

1. `transition_locked` を `true` にする。
2. 既存の `current_screen` があれば `queue_free()` する。
3. `SceneFlow.get_scene_path()` でシーンパスを取得する。
4. `PackedScene` をloadしてinstantiateする。
5. 画面が `setup` を持つ場合、現在の `RunContext` を渡す。
6. 画面が `screen_completed` Signalを持つ場合、Appの `_on_screen_completed` へ接続する。
7. `ScreenContainer` へ追加する。
8. deferred callで `transition_locked` を解除する。

シーンloadに失敗した場合はエラーを出し、遷移ロックを解除して終了する。

## 画面の共通契約

`FlowScreen` は `Control` を継承し、次を定義する。

```gdscript
signal screen_completed(payload: Dictionary)

func setup(context: RunContext) -> void
func receive_sensor_input(input_type: RhythmTypes.InputType) -> void
func complete_screen(payload: Dictionary = {}) -> void
```

`complete_screen()` は `is_completed` が `true` の場合は何もしない。最初の呼出しだけ `screen_completed` をemitする。

Title、FaceCapture、Tutorial、Resultは `FlowScreen` を継承する。Mainは `Node2D` を継承し、同名のSignal、`setup()`、`receive_sensor_input()` を個別に実装する。Appは継承型ではなく、メソッドとSignalの存在確認で両方を扱う。

## 完了Payload

| 送信画面 | Key | 値 |
| --- | --- | --- |
| Title | `door_opened` | `true` |
| FaceCapture | `capture_completed` | `true` |
| Tutorial | `tutorial_completed` | `true` |
| Main | `cheers_success_count` | `RhythmSession`の成功数 |
| Main | `cheers_failure_count` | `RhythmSession`の失敗数 |
| Result | なし | 空Dictionary |

Appの `apply_screen_payload()` が `RunContext` へ反映するのは `tutorial_completed`、`cheers_success_count`、`cheers_failure_count` だけである。

MainからResultへ遷移する直前に、Appは `PlayerCountStore.record_player()` を1回呼ぶ。保存後の累計人数を `RunContext.player_number` へ設定してからResultを生成する。遷移開始後は `transition_locked` がtrueになるため、Mainが完了通知を重複しても人数は再加算されない。

## PlayerCountStore

`app/player_count_store.gd` は端末内の累計体験者数を `user://player_count.cfg` へConfigFile形式で保存する。

```ini
[players]
total_count=1
```

保存ファイルがない場合の累計人数は0である。`record_player()` は現在値へ1を加えて保存し、保存後の値を返す。読込値が負数の場合は0として扱う。読込に失敗した場合も0から開始し、保存に失敗した場合は0を返す。

## RunContext

`RunContext` は `RefCounted` で、1回のTitleからResultまで同じインスタンスが使われる。

| Property | 型 | 初期値・用途 |
| --- | --- | --- |
| `captured_face_image` | `Image` | FaceCaptureが保存した撮影画像 |
| `processed_face_image` | `Image` | 宣言とclearのみ。現在は読書きされない |
| `generated_character_images` | `Resource` | `KanpaiCharacterImageSet`を保持する |
| `character_generation_succeeded` | `bool` | 生成画像を画面で使用する条件 |
| `tutorial_completed` | `bool` | Tutorial完了Payloadでtrueになる |
| `cheers_success_count` | `int` | Main完了時の成功数 |
| `cheers_failure_count` | `int` | Main完了時の失敗数 |
| `player_number` | `int` | Result遷移時に割り当てられた累計体験者数 |

金額計算は次の定数と関数を使う。

| 定数・関数 | 現在値・計算 |
| --- | --- |
| `AMOUNT_PER_SUCCESS` | `500` |
| `AMOUNT_PER_FAILURE` | `-50` |
| `calculate_success_amount()` | 成功数 × 500 |
| `calculate_failure_amount()` | 失敗数 × -50 |
| `calculate_total_amount()` | 成功金額 + 失敗金額 |

ResultからTitleへ戻るとき、Appは既存Contextへ `clear()` を呼び、その後で新しい `RunContext` を生成する。

## 入力配送

Appはactive Providerの `input_detected` を `receive_sensor_input()` へ接続する。入力内容はAppで解釈せず、遷移中でなく現在画面が存在するときだけ、その画面の `receive_sensor_input()` へ転送する。

`transition_locked` が `true` の間に届いた入力は破棄される。
