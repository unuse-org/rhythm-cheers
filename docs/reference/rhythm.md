---
id: rhythm
title: リズム処理
description: 譜面形式、時刻変換、イベント実行、入力判定の現行仕様
sidebar_position: 5
---

## 型定義

`rhythm/input_types.gd` の `RhythmTypes` は次のenumを持つ。

| Enum | 値 |
| --- | --- |
| `InputType` | `CHEERS` |
| `EventType` | `PREPARE`, `EXPECT_CHEERS`, `RETURN_NORMAL` |
| `CharacterState` | `NORMAL`, `PREPARE`, `JUDGING`, `SUCCESS`, `FAILURE` |

## JSON譜面

譜面は `RhythmChart.load_from_file()` でJSONから読み込む。

```json
{
  "bpm": 148.0,
  "offset": 0.64,
  "events": [
    {"beat": 1.0, "type": "PREPARE"},
    {"beat": 2.0, "type": "EXPECT_CHEERS"},
    {"beat": 3.0, "type": "RETURN_NORMAL"}
  ]
}
```

### 検証内容

`RhythmChart.from_dictionary()` は次を検証する。

- ルートがDictionaryである。
- `bpm` が数値で0より大きい。
- `offset` が数値である。
- `events` がArrayである。
- 各eventがDictionaryである。
- `beat` が数値である。
- `type` がStringで、定義済み3種類のいずれかである。
- eventsのbeatが降順になっていない。

検証成功後、eventのtype文字列は `RhythmTypes.EventType` へ変換される。同じbeatを持つeventは許可される。

### 現在の譜面

| ファイル | BPM | Offset | PREPARE数 | 最後のevent beat |
| --- | --- | --- | --- | --- |
| `rhythm/charts/test_chart.json` | 148.0 | 0.64 | 4 | 14.0 |
| `rhythm/charts/tutorial_chart.json` | 148.0 | 0.64 | 5 | 19.0 |

## 拍と秒の変換

`RhythmTiming` は次の式を使う。

```text
seconds = offset + beat × 60 / bpm
beat = (seconds - offset) × bpm / 60
```

## RhythmSessionの状態

`RhythmSession.configure()` は譜面eventsをdeep duplicateし、`RhythmTiming` を生成する。その後、次の状態を初期化する。

| Property | 初期値 |
| --- | --- |
| `next_event_index` | 0 |
| `character_state` | `NORMAL` |
| `input_expected` | false |
| `current_input_beat` | 0.0 |
| `last_judgement` | `"-"` |
| `cheers_success_count` | 0 |
| `cheers_failure_count` | 0 |

## Event実行

`advance(song_time)` は `process_chart_events()` の後に `process_missed_input()` を呼ぶ。

通常のeventは `beat_to_seconds(event.beat)` に達した時点で実行する。`EXPECT_CHEERS` だけは、その時刻より `MISS_WINDOW` だけ前に実行する。

| Event | 実行内容 |
| --- | --- |
| `PREPARE` | `input_expected = false`、CharacterStateを`PREPARE`へ変更 |
| `EXPECT_CHEERS` | 対象beatを保存、`input_expected = true`、CharacterStateを`JUDGING`へ変更 |
| `RETURN_NORMAL` | `input_expected = false`、CharacterStateを`NORMAL`へ変更 |

CharacterStateが実際に変化した場合だけ `character_state_changed(state)` をemitする。

## 判定窓

| 定数 | 秒 |
| --- | --- |
| `PERFECT_WINDOW` | 0.05 |
| `GOOD_WINDOW` | 0.10 |
| `MISS_WINDOW` | 0.20 |

目標時刻を `target`、入力時刻を `input` とすると、差は `input - target` で計算する。

| 条件 | `last_judgement` | 入力待ち | 件数 |
| --- | --- | --- | --- |
| 絶対差 ≤ 0.05 | `PERFECT` | 終了 | 成功 +1 |
| 絶対差 ≤ 0.10 | `GOOD` | 終了 | 成功 +1 |
| 差 < -0.10 | `TOO EARLY` | 継続 | 変更なし |
| 差 > 0.10 | `TOO LATE` | 継続 | 変更なし |
| 時刻 > target + 0.20 | `MISS: CHEERS` | 終了 | 失敗 +1 |

入力待ちでないときの入力は `NO INPUT EXPECTED`、CHEERS以外の入力は `WRONG INPUT TYPE` を `last_judgement` に設定してfalseを返す。

成功確定時はCharacterStateを `SUCCESS`、MISS確定時は `FAILURE` にして、次のSignalをemitする。

```gdscript
input_resolved(
    beat: float,
    input_type: RhythmTypes.InputType,
    judgement: String
)
```

`last_judgement` を変更するSignalは存在しない。`RhythmDebugDisplay` はframeごとにpropertyを直接読む。

## TutorialとMainからの利用

TutorialとMainはAudioStreamPlayerの `get_playback_position()` を `song_time` として使用する。毎frame `RhythmSession.advance(song_time)` を呼び、CHEERS受信時に同じ再生位置で `receive_input()` を呼ぶ。

Tutorialは `input_resolved` を購読して成功数を数える。Mainは曲終了時に `RhythmSession.cheers_success_count` と `cheers_failure_count` をAppへ返す。
