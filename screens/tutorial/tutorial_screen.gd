class_name TutorialScreen
extends FlowScreen

@onready var music_player: AudioStreamPlayer = $MusicPlayer
@onready var rhythm_session: RhythmSession = $RhythmSession
@onready var gameplay_visual: GameplayVisual = $GameplayVisual
@onready var progress_label: Label = %ProgressLabel
@onready var status_label: Label = %StatusLabel
@onready var clear_overlay: Control = %ClearOverlay

@export_category("Tutorial Resources")
@export var tutorial_music: AudioStream
@export_file("*.json") var chart_path: String = (
	"res://rhythm/charts/tutorial_chart.json"
)

@export_category("Tutorial Progress")
@export_range(1, 10, 1) var required_success_count: int = 3
@export_range(3.0, 64.0, 0.5) var tutorial_end_beat: float = 20.0
@export_range(0.0, 5.0, 0.1) var clear_display_duration: float = 1.0

# 自動テストでは実時間の再生を止め、曲時刻を直接進める。
@export var music_enabled: bool = true

# 成功回数はチュートリアル内だけで保持し、RunContextへは加算しない。
var tutorial_success_count: int = 0
var tutorial_run_count: int = 0
var chart: RhythmChart
var track_finished: bool = false
var clear_sequence_started: bool = false


func _ready() -> void:
	music_player.stream = tutorial_music
	chart = RhythmChart.load_from_file(chart_path)

	if chart == null:
		set_process(false)
		status_label.text = "チュートリアル譜面を読み込めません"
		return

	if tutorial_music == null:
		set_process(false)
		status_label.text = "チュートリアル音楽が設定されていません"
		return

	rhythm_session.input_resolved.connect(_on_input_resolved)
	music_player.finished.connect(_on_music_finished)
	start_tutorial_track()


func _exit_tree() -> void:
	# 次の画面へ音声再生とストリーム参照を残さない。
	music_player.stop()
	music_player.stream = null


func _process(_delta: float) -> void:
	advance_tutorial(music_player.get_playback_position())


func receive_sensor_input(
	sensor_input_type: RhythmTypes.InputType
) -> void:
	receive_sensor_input_at(
		sensor_input_type,
		music_player.get_playback_position()
	)


# 専用曲と譜面を先頭へ戻し、チュートリアル全体を開始する。
func start_tutorial_track() -> void:
	track_finished = false
	clear_sequence_started = false
	tutorial_success_count = 0
	rhythm_session.configure(chart)
	gameplay_visual.configure(rhythm_session)
	clear_overlay.visible = false
	update_progress_label()

	if tutorial_run_count == 0:
		status_label.text = "曲に合わせて3回成功しよう"
	else:
		status_label.text = "もう一度、曲の最初から挑戦しよう"

	music_player.stop()

	if music_enabled:
		music_player.play(0.0)


# 曲時刻を明示的に受け取れる形にし、自動テストでも同じ進行を使う。
func advance_tutorial(song_time: float) -> void:
	if chart == null or track_finished or is_completed:
		return

	rhythm_session.advance(song_time)
	gameplay_visual.advance(song_time)

	var tutorial_end_time := rhythm_session.timing.beat_to_seconds(
		tutorial_end_beat
	)

	if song_time >= tutorial_end_time:
		finish_tutorial_track()


# Appからの入力とテスト入力を同じ判定経路へ流す。
func receive_sensor_input_at(
	sensor_input_type: RhythmTypes.InputType,
	song_time: float
) -> void:
	if chart == null or track_finished or is_completed:
		return

	rhythm_session.receive_input(sensor_input_type, song_time)


# 曲全体の終了時に成功数を評価し、不足時は曲の先頭から再挑戦する。
func finish_tutorial_track() -> void:
	if track_finished or is_completed:
		return

	track_finished = true
	music_player.stop()

	if tutorial_success_count >= required_success_count:
		start_clear_sequence()
		return

	tutorial_run_count += 1
	start_tutorial_track()


# クリア表示を挟み、チュートリアルとメインが直結して見えないようにする。
func start_clear_sequence() -> void:
	if clear_sequence_started:
		return

	clear_sequence_started = true
	set_process(false)
	clear_overlay.visible = true
	status_label.text = "チュートリアルクリア！"

	if clear_display_duration <= 0.0:
		complete_tutorial()
		return

	get_tree().create_timer(clear_display_duration).timeout.connect(
		complete_tutorial,
		CONNECT_ONE_SHOT
	)


func complete_tutorial() -> void:
	set_process(false)
	music_player.stop()
	complete_screen({"tutorial_completed": true})


# 成功時だけ規定回数まで加算し、残りの練習機会では表示を維持する。
func _on_input_resolved(
	_beat: float,
	_input_type: RhythmTypes.InputType,
	judgement: String
) -> void:
	if judgement == "PERFECT" or judgement == "GOOD":
		if tutorial_success_count < required_success_count:
			tutorial_success_count += 1

		status_label.text = "成功！"
		update_progress_label()
		return

	status_label.text = "次のタイミングでもう一度"


func _on_music_finished() -> void:
	finish_tutorial_track()


func update_progress_label() -> void:
	progress_label.text = (
		"成功 %d / %d"
		% [tutorial_success_count, required_success_count]
	)
