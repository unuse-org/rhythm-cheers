class_name RhythmDebugDisplay
extends Node2D

@onready var debug_notes: Node2D = $DebugNotes
@onready var judge_line: ColorRect = $JudgeLine
@onready var debug_label: Label = $DebugLabel

@export var debug_note_scene: PackedScene
@export var show_debug_notes: bool = true

# ノートが出現してから判定位置へ到達するまでの時間
const APPROACH_TIME: float = 2.0

# デバッグノートの色
const CHEERS_NOTE_COLOR: Color = Color.RED

var rhythm_session: RhythmSession
var sensor_mode_name: String = "-"

var active_notes: Array[DebugNote] = []
var debug_input_events: Array[Dictionary] = []
var next_debug_note_index: int = 0

# デバッグノートの表示位置
var spawn_x: float = 0.0
var judge_x: float = 0.0
var note_y: float = 0.0


func configure(
	new_rhythm_session: RhythmSession,
	new_sensor_mode_name: String
) -> void:
	rhythm_session = new_rhythm_session
	sensor_mode_name = new_sensor_mode_name

	set_debug_layout()

	judge_line.visible = show_debug_notes
	debug_notes.visible = show_debug_notes
	debug_label.visible = show_debug_notes

	initialize_debug_input_events()

	if not rhythm_session.input_resolved.is_connected(_on_input_resolved):
		rhythm_session.input_resolved.connect(_on_input_resolved)

	if debug_note_scene == null and show_debug_notes:
		push_error("debug_note_sceneが設定されていません。")


func advance(song_time: float) -> void:
	if rhythm_session == null:
		return

	if show_debug_notes:
		spawn_upcoming_debug_notes(song_time)
		update_debug_notes(song_time)

	var current_beat: float = (
		rhythm_session.timing.seconds_to_beats(song_time)
	)
	update_debug_label(song_time, current_beat)


# 入力イベントをデバッグノート用の配列へ抽出する
func initialize_debug_input_events() -> void:
	debug_input_events.clear()

	for chart_event: Dictionary in rhythm_session.chart:
		var event_type: RhythmTypes.EventType = chart_event["type"]

		if event_type == RhythmTypes.EventType.EXPECT_CHEERS:
			debug_input_events.append(chart_event)


# 画面上にデバッグノートを生成する
func spawn_upcoming_debug_notes(song_time: float) -> void:
	if debug_note_scene == null:
		return

	while next_debug_note_index < debug_input_events.size():
		var chart_event: Dictionary = (
			debug_input_events[next_debug_note_index]
		)

		var beat: float = chart_event["beat"]
		var note_time: float = rhythm_session.timing.beat_to_seconds(beat)

		if song_time < note_time - APPROACH_TIME:
			break

		var note: DebugNote = debug_note_scene.instantiate() as DebugNote

		if note == null:
			push_error("debug_note_sceneのルートにDebugNoteが設定されていません。")
			return

		note.beat = beat
		note.position = Vector2(spawn_x, note_y)

		# @onreadyを初期化させるため先にツリーへ追加する
		debug_notes.add_child(note)

		note.set_debug_color(CHEERS_NOTE_COLOR)

		active_notes.append(note)
		next_debug_note_index += 1


# デバッグノートの位置を更新する
func update_debug_notes(song_time: float) -> void:
	for note: DebugNote in active_notes:
		if not is_instance_valid(note):
			continue

		var note_time: float = (
			rhythm_session.timing.beat_to_seconds(note.beat)
		)
		var time_until_hit: float = note_time - song_time

		var progress: float = 1.0 - time_until_hit / APPROACH_TIME

		note.position.x = lerpf(
			spawn_x,
			judge_x,
			progress
		)


func _on_input_resolved(
	_beat: float,
	_input_type: RhythmTypes.InputType,
	_judgement: String
) -> void:
	remove_first_debug_note()


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
	if not show_debug_notes:
		return

	debug_label.text = (
		"Song Time: %.2f\n" % song_time
		+ "Current Beat: %.2f\n" % current_beat
		+ "Sensor Mode: %s\n" % sensor_mode_name
		+ "Next Event Index: %d\n" % rhythm_session.next_event_index
		+ "Next Debug Note Index: %d\n" % next_debug_note_index
		+ "State: %s\n"
		% RhythmTypes.CharacterState.keys()[rhythm_session.character_state]
		+ "Input Expected: %s\n" % rhythm_session.input_expected
		+ "Expected Input Type: %s\n"
		% rhythm_session.get_expected_input_type_string()
		+ "Last Judgement: %s" % rhythm_session.last_judgement
	)


# デバッグ用レイアウトを設定する
func set_debug_layout() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size

	spawn_x = viewport_size.x + 60.0
	judge_x = viewport_size.x * 0.18
	note_y = viewport_size.y * 0.72

	set_judge_line_position()


# 判定ラインの位置を設定する
func set_judge_line_position() -> void:
	var judge_point := Vector2(judge_x, note_y)

	judge_line.size = Vector2(6.0, 180.0)
	judge_line.position = judge_point - judge_line.size / 2.0
