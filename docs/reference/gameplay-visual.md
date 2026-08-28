---
id: gameplay-visual
title: ゲーム画面の描画
description: GameplayVisualとRhythmDebugDisplayの現行動作
sidebar_position: 6
---

## GameplayVisualのScene構成

`visual/gameplay_visual.tscn` の基準サイズは720 × 1280である。

| Node | z_index | 内容 |
| --- | ---: | --- |
| `World/Opponent0/Background` | 0 | 相手ごとに複製される背景 |
| `World/Opponent0/Character` | 1 | 乾杯相手 |
| `World/Opponent0/Table` | 2 | テーブル |
| `PlayerCheers` | 3 | 成功時のユーザー側ジョッキ |
| `CheersEffect` | 4 | 成功時の衝突Effect |
| `CheersText` | 5 | 「乾」「杯」、成功、失敗表示 |

CharacterのRectはx=46〜674、y=0〜1800で、幅628・高さ1800である。Tableは位置 `(721.05054, 1181)`、サイズ約720.36 × 350.65、回転角180度で配置される。PlayerCheersは位置 `(-3, 283)`、サイズ723 × 997である。

Characterの表示倍率は `character_scale_multiplier` で指定し、初期値は1.3である。拡大基準はRectの下辺中央なので、倍率を変更しても足元とTableの位置関係は変わらない。この倍率は横スクロール用に複製したすべてのCharacterへ適用する。

## 固定Texture

シーンは次の固定Textureを初期値として持つ。

| 状態・用途 | Asset |
| --- | --- |
| NORMAL | `assets/images/character_normal.png` |
| PREPARE | `assets/images/character_prepare.png` |
| JUDGING | `assets/images/character_cheers.png` |
| 背景 | `assets/images/background.png` |
| テーブル | `assets/images/table.png` |
| ユーザー側の手とジョッキ | `assets/images/my_hand.png` |
| 成功Effect | `assets/images/cheers_effect.png` |
| 「乾」 | `assets/images/cheers_text_kan.png` |
| 「杯」 | `assets/images/cheers_text_pai.png` |
| 失敗Overlay | `assets/images/cheers_failure_overlay.png` |
| 成功表示 | `assets/images/cheers_success.png` |

SUCCESSとFAILUREの専用Character Textureはexport propertyとして存在する。nullの場合、SUCCESSはJUDGING Texture、FAILUREはNORMAL Textureを使う。FAILUREの代替表示ではCharacterへ `Color(0.55, 0.65, 0.75)` をmodulateする。

## 生成画像の適用

`apply_character_images(images)` はResourceから次の5 propertyを `Image` として取得する。

- `normal`
- `prepare`
- `judging`
- `success`
- `failure`

1枚でもnullまたは空の場合はfalseを返し、既存Textureを変更しない。5枚揃っている場合は各ImageをImageTextureへ変換し、状態別Textureを置き換える。

既に横スクロール用のOpponentが複製されている場合、全StationのCharacterへ新しいNORMAL Textureを設定する。現在Characterには現在Stateを再適用する。

## CharacterState別表示

| State | Character | 文字 | PlayerCheers / Effect |
| --- | --- | --- | --- |
| `NORMAL` | NORMAL | すべて非表示 | 非表示 |
| `PREPARE` | PREPARE | 「乾」 | 非表示 |
| `JUDGING` | JUDGING | 「乾」「杯」 | 非表示 |
| `SUCCESS` | SUCCESS、なければJUDGING | 成功画像 | 表示 |
| `FAILURE` | FAILURE、なければ色変更NORMAL | 「乾」「杯」と「乾」上の失敗Overlay | 非表示 |

`RhythmSession.character_state_changed` を購読し、状態が変わったときだけ表示を更新する。

## 通常時の上下動

`character_bob_amplitude` の初期値は12pxである。CharacterStateがNORMALのとき、現在beatの小数部に対して次を計算する。

```text
vertical_offset = -sin(beat_progress × PI) × 12
```

各拍の開始と終了で基準位置、拍の中央で12px上になる。NORMAL以外のStateでは基準位置へ戻す。

## 乾杯相手の生成

`configure()` 時に譜面内のPREPAREのうち `starts_opponent` がtrueのeventを数える。2連乾杯の2回目のPREPAREは同じ相手へ適用するため数えない。0件の場合もOpponent数は1になる。`Opponent0` をtemplateとして、2人目以降をduplicateし、x方向へ `opponent_spacing` ずつ配置する。初期値は720pxである。

各StationにはBackground、Character、Tableが含まれる。

## 横スクロール区間

RETURN_NORMALから、次に `starts_opponent` がtrueとなるPREPAREまでを1つの移動区間として記録する。

```text
start_beat = RETURN_NORMAL.beat
end_beat   = 次のPREPARE.beat
from_index = 現在の相手番号
to_index   = 次の相手番号
```

現在beatが区間内の場合、0〜1のprogressを求めて `smoothstep(0, 1, progress)` を適用する。Worldのx座標は次で計算する。

```text
world.x = world_base_x - station_position × opponent_spacing
```

完了済み区間では移動先indexを使用する。計算は前frameとの差分ではなく、現在beatから絶対位置を求める。

## RhythmDebugDisplay

Mainシーンの `RhythmDebugDisplay` は `z_index = 100` である。`show_debug_notes` の初期値はtrue。

譜面内のEXPECT_CHEERSだけをDebug Noteとして抽出し、目標時刻の2秒前に生成する。Noteは画面右外の `viewport_width + 60` から、画面幅の18%にあるJudgeLineへ線形移動する。y座標は画面高さの72%である。

DebugLabelは次を表示する。

- Song Time
- Current Beat
- Sensor Mode
- Next Event Index
- Next Debug Note Index
- Character State
- Input Expected
- Expected Input Type
- Last Judgement

`input_resolved` を受信すると、最も古いDebug Noteを1つ削除する。
