extends Node2D

@onready var music_player: AudioStreamPlayer = $MusicPlayer
@onready var debug_notes: Node2D = $DebugNotes
@onready var judge_line: ColorRect = $JudgeLine
@onready var debug_label: Label = $DebugLabel

@export var debug_note_scene: PackedScene
@export var show_debug_notes: bool = true

const BPM: float = 148.0

# 音源の先頭から、最初の拍が始まるまでの時間
const OFFSET: float = 0.64

# ノートが出現してから判定位置に到達するまでの時間
const APPROACH_TIME: float = 2.0

# 判定ウィンドウ
const PERFECT_WINDOW: float = 0.05
const GOOD_WINDOW: float = 0.1
const MISS_WINDOW: float = 0.2

# デバッグノートの表示位置
var spawn_x: float = 0.0
var judge_x: float = 0.0
var note_y: float = 0.0


enum EventType {
	PREPARE,
	JUDGE,
	RETURN_NORMAL,
}


enum CharacterState {
	NORMAL,
	PREPARE,
	WAIT_INPUT,
	CHEERS,
}


# イベント情報を持つ譜面
var chart: Array[Dictionary] = [
	{
		"beat": 1.0,
		"type": EventType.PREPARE,
	},
	{
		"beat": 2.0,
		"type": EventType.JUDGE,
	},
	{
		"beat": 5.0,
		"type": EventType.PREPARE,
	},
	{
		"beat": 6.0,
		"type": EventType.JUDGE,
	},
]


# デバッグノート
var active_notes: Array[DebugNote] = []
var debug_judge_events: Array[Dictionary] = []
var next_debug_note_index: int = 0

# イベント処理
var next_event_index: int = 0

# キャラクター状態
var character_state: CharacterState = CharacterState.NORMAL
var state_change_generation: int = 0

# 入力判定
var input_expected: bool = false
var current_judge_beat: float = 0.0

# 最後の判定結果
var last_judgement: String = "-"


func _ready() -> void:
	set_debug_layout()

	judge_line.visible = show_debug_notes
	debug_notes.visible = show_debug_notes

	set_judge_line_position()
	initialize_debug_judge_events()

	if debug_note_scene == null and show_debug_notes:
		push_error("debug_note_sceneが設定されていません。")

	music_player.play()


func _process(_delta: float) -> void:
	var song_time: float = get_song_time()
	var current_beat: float = seconds_to_beats(song_time)

	process_chart_events(song_time)
	process_missed_input(song_time)

	if show_debug_notes:
		spawn_upcoming_debug_notes(song_time)
		update_debug_notes(song_time)

	update_debug_label(song_time, current_beat)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("hit"):
		judge_input()


# 曲の現在の再生位置を取得する
func get_song_time() -> float:
	return music_player.get_playback_position()


# 拍を再生時間へ変換する
func beat_to_seconds(beat: float) -> float:
	return OFFSET + beat * 60.0 / BPM


# 再生時間を拍へ変換する
func seconds_to_beats(seconds: float) -> float:
	return (seconds - OFFSET) * BPM / 60.0


# JUDGEイベントをデバッグノート用の配列へ抽出する
func initialize_debug_judge_events() -> void:
	debug_judge_events.clear()

	for chart_event: Dictionary in chart:
		var event_type: EventType = chart_event["type"]

		if event_type == EventType.JUDGE:
			debug_judge_events.append(chart_event)


# 譜面イベントを時刻に従って実行する
func process_chart_events(song_time: float) -> void:
	while next_event_index < chart.size():
		var chart_event: Dictionary = chart[next_event_index]
		var event_type: EventType = chart_event["type"]
		var event_beat: float = chart_event["beat"]
		var event_time: float = beat_to_seconds(event_beat)

		var execution_time: float = event_time

		# JUDGEイベントは早めの入力も受け付ける必要があるため、
		# 判定時刻よりMISS_WINDOW秒前に入力受付を開始する
		if event_type == EventType.JUDGE:
			execution_time -= MISS_WINDOW

		if song_time < execution_time:
			break

		execute_chart_event(chart_event)
		next_event_index += 1


# 譜面イベントを実行する
func execute_chart_event(chart_event: Dictionary) -> void:
	var event_type: EventType = chart_event["type"]
	var event_beat: float = chart_event["beat"]

	match event_type:
		EventType.PREPARE:
			change_character_state(CharacterState.PREPARE)

		EventType.JUDGE:
			start_input_window(event_beat)

		EventType.RETURN_NORMAL:
			change_character_state(CharacterState.NORMAL)


# 入力受付を開始する
func start_input_window(event_beat: float) -> void:
	current_judge_beat = event_beat
	input_expected = true

	change_character_state(CharacterState.WAIT_INPUT)


# プレイヤー入力を現在のJUDGEイベントと比較する
func judge_input() -> void:
	if not input_expected:
		last_judgement = "NO INPUT EXPECTED"
		return

	var song_time: float = get_song_time()
	var target_time: float = beat_to_seconds(current_judge_beat)

	var difference: float = song_time - target_time
	var absolute_difference: float = absf(difference)

	if absolute_difference <= PERFECT_WINDOW:
		complete_input("PERFECT")

	elif absolute_difference <= GOOD_WINDOW:
		complete_input("GOOD")

	elif difference < -GOOD_WINDOW:
		last_judgement = "TOO EARLY"

	else:
		last_judgement = "TOO LATE"


# 入力成功時の処理
func complete_input(judgement: String) -> void:
	last_judgement = judgement
	input_expected = false

	remove_first_debug_note()
	change_character_state(CharacterState.CHEERS)

	return_to_normal_after_delay()


# 入力されないまま判定可能時間を過ぎた場合の処理
func process_missed_input(song_time: float) -> void:
	if not input_expected:
		return

	var target_time: float = beat_to_seconds(current_judge_beat)

	if song_time <= target_time + MISS_WINDOW:
		return

	last_judgement = "MISS"
	input_expected = false

	remove_first_debug_note()
	change_character_state(CharacterState.NORMAL)


# 一定時間後に通常状態へ戻す
func return_to_normal_after_delay() -> void:
	var generation: int = state_change_generation

	await get_tree().create_timer(0.5).timeout

	# 待機中に別の状態遷移が起きていれば何もしない
	if generation != state_change_generation:
		return

	change_character_state(CharacterState.NORMAL)


# キャラクター状態を変更する
func change_character_state(new_state: CharacterState) -> void:
	if character_state == new_state:
		return

	character_state = new_state
	state_change_generation += 1

	match new_state:
		CharacterState.NORMAL:
			print("NORMAL")

		CharacterState.PREPARE:
			print("PREPARE")

		CharacterState.WAIT_INPUT:
			print("WAIT_INPUT")

		CharacterState.CHEERS:
			print("CHEERS")


# 画面上にデバッグノートを生成する
func spawn_upcoming_debug_notes(song_time: float) -> void:
	if debug_note_scene == null:
		return

	while next_debug_note_index < debug_judge_events.size():
		var chart_event: Dictionary = (
			debug_judge_events[next_debug_note_index]
		)

		var beat: float = chart_event["beat"]
		var note_time: float = beat_to_seconds(beat)

		if song_time < note_time - APPROACH_TIME:
			break

		var note: DebugNote = (
			debug_note_scene.instantiate() as DebugNote
		)

		if note == null:
			push_error(
				"debug_note_sceneのルートにDebugNoteが設定されていません。"
			)
			return

		note.beat = beat
		note.position = Vector2(spawn_x, note_y)

		debug_notes.add_child(note)
		active_notes.append(note)

		next_debug_note_index += 1


# デバッグノートの位置を更新する
func update_debug_notes(song_time: float) -> void:
	for note: DebugNote in active_notes:
		if not is_instance_valid(note):
			continue

		var note_time: float = beat_to_seconds(note.beat)
		var time_until_hit: float = note_time - song_time

		var progress: float = (
			1.0 - time_until_hit / APPROACH_TIME
		)

		note.position.x = lerpf(
			spawn_x,
			judge_x,
			progress
		)


# 最も古いデバッグノートを削除する
func remove_first_debug_note() -> void:
	if active_notes.is_empty():
		return

	var note: DebugNote = active_notes.pop_front()

	if is_instance_valid(note):
		note.queue_free()


# デバッグラベルを更新する
func update_debug_label(
	song_time: float,
	current_beat: float
) -> void:
	debug_label.text = (
		"Song Time: %.2f\n" % song_time
		+ "Current Beat: %.2f\n" % current_beat
		+ "Next Event Index: %d\n" % next_event_index
		+ "Next Debug Note Index: %d\n" % next_debug_note_index
		+ "State: %s\n"
		% CharacterState.keys()[character_state]
		+ "Input Expected: %s\n" % input_expected
		+ "Last Judgement: %s" % last_judgement
	)


# 判定ラインの位置を設定する
func set_judge_line_position() -> void:
		var judge_point := Vector2(judge_x, note_y)

		judge_line.size = Vector2(6.0, 180.0)
		judge_line.position = judge_point - judge_line.size / 2.0

# デバッグ用のレイアウトを設定する
func set_debug_layout() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size

	spawn_x = viewport_size.x + 60.0
	judge_x = viewport_size.x * 0.18
	note_y = viewport_size.y * 0.72

	set_judge_line_position()
