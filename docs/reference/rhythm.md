---
id: rhythm
title: リズム処理
description: 譜面形式、可変BPM、音声Cue、イベント実行、入力判定の現行仕様
sidebar_position: 5
---

## 型定義

`rhythm/input_types.gd` の `RhythmTypes` は次のenumを持つ。

| Enum | 値 |
| --- | --- |
| `InputType` | `CHEERS` |
| `EventType` | `PREPARE`, `EXPECT_CHEERS`, `SHOW_CHEERS`, `RETURN_NORMAL` |
| `CharacterState` | `NORMAL`, `PREPARE`, `JUDGING`, `SUCCESS`, `FAILURE` |

## JSON譜面

全曲譜面は `rhythm/charts/kanpai_chart.json` にある。`RhythmChart.load_from_file()` がJSONを読み込み、小節指定から実行用の拍イベントと掛け声Cueを生成する。

| Key | 用途 |
| --- | --- |
| `audio` | Section名ごとのOffVocal音源 |
| `offset` | 0拍目に対応する曲先頭からの秒数 |
| `beats_per_measure` | 1小節の拍数。現在は4 |
| `end_measure` | 曲終了境界の小節番号。範囲はこの値を含まない |
| `sections` | 画面ごとの開始小節・終了小節・リードイン拍数 |
| `tempo_changes` | BPMが切り替わる小節とBPM |
| `default_pattern` | 通常小節のパターン。現在は `NORMAL` |
| `double_cheers_measures` | 2連乾杯に置き換える小節番号 |
| `no_input_measures` | 入力イベントと掛け声Cueを生成しない小節番号 |
| `cue_sets` | BPM・Cue種別ごとの音源パス |

小節範囲は `start_measure <= measure < end_measure` で扱う。`create_section(name)` は全曲と同じ拍番号・BPMマップを維持する。`create_section(name, true)` は指定区間内のevent、Cue、BPM変更をローカルタイムラインへ変換し、そのSectionの音源パスを設定する。

`lead_in_beats` が設定されたSectionでは、ローカル変換したevent、Cue、BPM変更を指定拍数だけ後ろへ移す。現在のMainは12拍、Tutorialは未指定のため0拍である。

旧形式の `bpm`、`offset`、`events` を直接指定するJSONも読み込める。旧形式は先頭0拍のtempo change 1件へ変換される。

## 現在の全曲譜面

offsetは0秒、拍子は4/4である。各Section音源の先頭を0拍目として扱う。

| Section | ベース音源 |
| --- | --- |
| Tutorial | `assets/audio/OffVocal_チュートリアル.mp3` |
| Main | `assets/audio/OffVocal_本番.mp3` |

Main Sectionの `lead_in_beats` は12である。本番音源は全曲タイムラインの13小節目から始まり、最初のCueと16小節目の譜面は12拍後から始まる。Mainローカル時刻では最初の「ワン」が5.143秒、「乾」が6.000秒、「杯」と判定対象が6.429秒である。

| 小節範囲 | Section | BPM |
| --- | --- | --- |
| 1以上16未満 | Tutorial | 140 |
| 16以上33未満 | Main | 140 |
| 33以上37未満 | Main | 120 |
| 37以上45未満 | Main | 130 |
| 45以上53未満 | Main | 140 |
| 53以上61未満 | Main | 150 |

2連乾杯は20、26、27、38、44、48、56小節目である。60小節目は通常乾杯で、61小節目の先頭を曲終了境界とする。現在 `no_input_measures` は空である。

### 小節から生成するevent

小節先頭の拍を0とした相対位置は次のとおり。

| Pattern | 相対拍 | Event |
| --- | --- | --- |
| NORMAL | 2 | `PREPARE` |
| NORMAL | 3 | `EXPECT_CHEERS`、`SHOW_CHEERS` |
| NORMAL | 4 | `RETURN_NORMAL` |
| DOUBLE | 2、3 | `PREPARE` |
| DOUBLE | 2.5、3.5 | `EXPECT_CHEERS`、`SHOW_CHEERS` |
| DOUBLE | 4 | `RETURN_NORMAL` |

掛け声の「1」「2」ではCharacterStateをNORMALに保つ。「乾」で `PREPARE` によりPREPARE画像と「乾」を表示し、「杯」で `SHOW_CHEERS` によりJUDGING画像と「乾杯」を表示する。2連乾杯の2回目の `PREPARE` は同じ相手に適用する。

### 小節から生成する掛け声Cue

| Pattern | 相対拍 | Cue key |
| --- | --- | --- |
| NORMAL | 0 | `count_1` |
| NORMAL | 1 | `count_2` |
| NORMAL | 2 | `cheers` |
| DOUBLE | 0 | `count_double` |
| DOUBLE | 2 | `cheers_double` |

各Cueはその小節のBPMに対応する `cue_sets` の音源を使用する。現在の譜面ではBPM120区間に2連乾杯がないため、BPM120のCue setは通常用3音源だけを持つ。

## 拍と秒の変換

`RhythmTiming` はtempo changeごとに開始拍、開始秒、BPMを積算して保持する。指定した拍または秒を含む区間を選び、区間内では次の式を使う。

```text
seconds = segment_start_seconds
        + (beat - segment_start_beat) × 60 / segment_bpm

beat = segment_start_beat
     + (seconds - segment_start_seconds) × segment_bpm / 60
```

旧形式向けに単一BPMを渡すこともできる。

## 音声再生

`RhythmAudioController` はApp直下にあり、OffVocal用の `BaseMusicPlayer` と掛け声用の `CuePlayerA`、`CuePlayerB` を所有する。Tutorial表示時はTutorialのローカルChartと音源、Main表示時はMainのローカルChartと音源へ再設定される。

Controllerは画面表示・入力判定用の曲時刻として、再生位置へ `AudioServer.get_time_since_last_mix()` を加え、`AudioServer.get_output_latency()` を引いた値を返す。Cueの開始判定には出力Latencyを引かないMix時刻を使い、新しいCueがBaseMusicと同じ出力Latencyを通った時点で揃うようにする。frame更新がCue時刻より遅れた場合は遅れた秒数を再生開始offsetへ渡す。遅れが音源尺以上の場合は実音声を再生せず、Cueを処理済みにする。

BaseMusicの長さが譜面終了時刻より0.1秒を超えて短い場合、Controllerは不足秒数をwarningへ出す。現在のTutorial音源は譜面より約13.714秒短いため、このwarningの対象である。

ローカルChartには対象SectionのCueだけが含まれる。Main内のCue、event、BPM変更拍はSection先頭からの相対拍へ変換した後、12拍のリードイン分だけ後ろへ移される。

## RhythmSessionの状態

`RhythmSession.configure()` は譜面eventsをdeep duplicateし、譜面のtempo changesとoffsetから `RhythmTiming` を生成する。

| Property | 初期値・用途 |
| --- | --- |
| `next_event_index` | 次に処理するeventのindex。初期値0 |
| `character_state` | 初期値 `NORMAL` |
| `pending_inputs` | 未解決の入力対象を拍順に保持するFIFO |
| `input_expected` | `pending_inputs` が空でない場合true |
| `current_input_beat` | `pending_inputs` 先頭の拍。空なら0 |
| `last_judgement` | 初期値 `"-"` |
| `cheers_success_count` | 成功確定数。初期値0 |
| `cheers_failure_count` | MISS確定数。初期値0 |

`EXPECT_CHEERS` は「杯」の対象時刻より `MISS_WINDOW` 秒前に入力受付を開始し、対象拍を `pending_inputs` へ追加する。受付開始時点ではPREPARE画像を維持し、対象時刻の `SHOW_CHEERS` でJUDGINGへ進む。対象時刻前に成功が確定した場合、`SHOW_CHEERS` はSUCCESS画像を上書きしない。

2連乾杯では2つの対象を順番に保持する。各対象には `SHOW_CHEERS` を通過したかを保持し、先の入力を解決した後も次の「杯」より前ならPREPAREを維持する。frameが複数eventをまたいだ場合は、次のeventを実行する前に期限を過ぎた対象を拍順にMISS確定する。

## 判定窓

| 定数 | 秒 |
| --- | --- |
| `PERFECT_WINDOW` | 0.05 |
| `GOOD_WINDOW` | 0.10 |
| `MISS_WINDOW` | 0.20 |

目標時刻を `target`、入力時刻を `input` とすると、差は `input - target` で計算する。

| 条件 | `last_judgement` | 入力対象 | 件数 |
| --- | --- | --- | --- |
| 絶対差 ≤ 0.05 | `PERFECT` | FIFO先頭を解決 | 成功 +1 |
| 絶対差 ≤ 0.10 | `GOOD` | FIFO先頭を解決 | 成功 +1 |
| 差 < -0.10 | `TOO EARLY` | 維持 | 変更なし |
| 差 > 0.10 | `TOO LATE` | 維持 | 変更なし |
| 時刻 ≥ target + 0.20 | `MISS: CHEERS` | FIFO先頭を解決 | 失敗 +1 |

入力待ちでないときの入力は `NO INPUT EXPECTED`、CHEERS以外の入力は `WRONG INPUT TYPE` を `last_judgement` に設定してfalseを返す。

成功またはMISSの確定ごとに次のSignalをemitする。

```gdscript
input_resolved(
    beat: float,
    input_type: RhythmTypes.InputType,
    judgement: String
)
```

`last_judgement` の変更Signalはない。`RhythmDebugDisplay` はframeごとにpropertyを直接読む。

## TutorialとMainからの利用

Tutorialは1小節目から16小節目直前までを使用する。成功数が3未満ならTutorial音源を0秒へ戻して同区間を再実行する。成功時はClearOverlayを表示して待機せず、Mainへ遷移する。

Mainは画面生成直後に本番音源を0秒から再生し、12拍の間はStartOverlayを表示する。入力、RhythmSession、GameplayVisual、RhythmDebugDisplayはリードイン終了時刻まで進めない。12拍目でOverlayを隠し、最初の掛け声Cueとゲーム進行を開始する。

音源の再生終了時にControllerを停止し、成功数と失敗数をAppへ返す。最後の判定対象は60小節目の通常乾杯である。

TutorialまたはMainを単独実行してControllerが注入されていない場合は、各シーン内のMusicPlayerを代替として使用する。
