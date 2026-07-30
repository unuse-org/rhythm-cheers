extends Node2D

@onready var music_player: AudioStreamPlayer = $MusicPlayer
@onready var debug_notes: Node2D = $DebugNotes
@onready var judge_line: ColorRect = $JudgeLine
@onready var debug_label: Label = $DebugLabel

@export var debug_note_scene: PackedScene
@export var show_debug_notes := true

const BPM := 148
# 音源の先頭から、最初の拍が始まるまでの時間
const OFFSET := 0.64

# ノートが出現してから判定位置に到達するまでの時間（秒）
const APPROACH_TIME := 2.0

# 判定のタイミングのウィンドウ
const PERFECT_WINDOW := 0.05
const GOOD_WINDOW := 0.1
const MISS_WINDOW := 0.2

# ノートの出現位置と判定位置
const SPAWN_X := 900.0
const JUDGE_X := 150.0
const NOTE_Y := 300.0

# ノートの速度（ピクセル/秒）
var chart: Array[float] = [
	0.0,
	1.0,
	2.0,
	3.0,
	4.0,
	4.5,
	5.0,
	6.0,
]

# ノートの情報
var active_notes: Array[DebugNote] = []
var next_note_index: int = 0
var current_note_index: int = 0

# 判定結果の表示用変数
var last_judgement := "-"

func _ready() -> void:
	judge_line.visible = show_debug_notes
	debug_notes.visible = show_debug_notes
	set_judge_line_position()

	if debug_note_scene == null and show_debug_notes:
		push_error("debug_note_sceneが設定されていません。")

	# 音楽の再生
	music_player.play()

func _process(_delta: float) -> void:
	var song_time := get_song_time()
	var current_beat := seconds_to_beats(song_time)

	if show_debug_notes:
		spawn_upcoming_notes(song_time)
		update_debug_notes(song_time)

	process_missed_notes(song_time)
	update_debug_label(song_time, current_beat)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("hit"):
		judge_input()


# 曲の現在の再生位置を取得する関数
func get_song_time() -> float:
	return music_player.get_playback_position()

# 曲の再生時間をビートに変換する関数
func beat_to_seconds(beat: float) -> float:
	return OFFSET + beat * 60.0 / BPM

# 曲の再生時間をビートに変換する関数
func seconds_to_beats(seconds: float) -> float:
	return (seconds - OFFSET) * BPM / 60.0

# 画面上に表示するノーツを生成する関数
func spawn_upcoming_notes(song_time: float) -> void:
	if debug_note_scene == null:
		return

	while next_note_index < chart.size():
		var beat := chart[next_note_index]
		var note_time := beat_to_seconds(beat)

		# もしノーツの時間が現在の曲の再生時間よりもAPPROACH_TIME秒以上先であれば、
		# そのノーツはまだ画面上に表示される必要がないため、生成をスキップ
		if song_time < note_time - APPROACH_TIME:
			break

		# ノーツの生成
		var note := debug_note_scene.instantiate() as DebugNote

		if note == null:
			push_error("debug_note_sceneのルートにDebugNoteが設定されていません。")
			return

		note.beat = beat
		note.position = Vector2(SPAWN_X, NOTE_Y)

		debug_notes.add_child(note)
		active_notes.append(note)

		next_note_index += 1

# ノーツの位置を更新する関数
func update_debug_notes(song_time: float) -> void:
	for note in active_notes:
		if not is_instance_valid(note): continue

		var note_time := beat_to_seconds(note.beat)
		# ノーツが判定位置に到達するまでの残り時間を計算
		var time_until_hit := note_time - song_time

		# ノーツの位置を更新
		# ノーツの位置は、出現位置から判定位置までの距離を、残り時間に応じて線形補間することで計算
		# これにより、ノーツは一定の速度で判定位置に向かって移動する
		var progress := 1.0 - (time_until_hit / APPROACH_TIME)
		note.position.x = lerp(SPAWN_X, JUDGE_X, progress)

# プレイヤー入力を次の未判定ノートと比較する
func judge_input() -> void:
	if current_note_index >= chart.size():
		last_judgement = "NO NOTE"
		return

	var song_time := get_song_time()
	var target_beat := chart[current_note_index]
	var target_time := beat_to_seconds(target_beat)
	var difference := song_time - target_time
	var absolute_difference := absf(difference)

	if absolute_difference <= PERFECT_WINDOW:
		complete_current_note("PERFECT")
	elif absolute_difference <= GOOD_WINDOW:
		complete_current_note("GOOD")
	elif difference < -GOOD_WINDOW:
		last_judgement = "TOO EARLY"
	else:
		# GOOD判定より遅いが、まだMISS処理されていない場合
		last_judgement = "TOO LATE"

# 判定済みノートを処理する
func complete_current_note(judgement: String) -> void:
	last_judgement = judgement
	remove_first_debug_note()
	current_note_index += 1


# 判定位置を過ぎたノーツをMISS判定として処理する関数
func process_missed_notes(song_time: float) -> void:
	while current_note_index < chart.size():
		var target_beat := chart[current_note_index]
		var target_time := beat_to_seconds(target_beat)

		if song_time <= target_time + MISS_WINDOW:
			break

		last_judgement = "MISS"
		remove_first_debug_note()
		current_note_index += 1

# ノーツを削除する関数
func remove_first_debug_note() -> void:
	if not show_debug_notes || active_notes.is_empty():
		return

	# ノーツを削除する
	var note := active_notes.pop_front() as DebugNote
	note.queue_free()

# デバッグ用のラベルを更新する関数
func update_debug_label(
	song_time: float,
	current_beat: float
) -> void:
	debug_label.text = (
		"Song Time: %.2f\n" % song_time +
		"Current Beat: %.2f\n" % current_beat +
		"Next Note Index: %d\n" % next_note_index +
		"Current Note Index: %d\n" % current_note_index +
		"Last Judgement: %s" % last_judgement
	)

# 判定ラインの位置を設定する関数
func set_judge_line_position() -> void:
	judge_line.position.x = JUDGE_X
	judge_line.position.y = NOTE_Y
