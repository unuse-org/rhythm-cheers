class_name TutorialScreen
extends FlowScreen

@onready var music_player: AudioStreamPlayer = $MusicPlayer
@onready var rhythm_session: RhythmSession = $RhythmSession
@onready var gameplay_visual: GameplayVisual = $GameplayVisual
@onready var intro_overlay: Control = %IntroOverlay
@onready var intro_timer: Timer = %IntroTimer
@onready var progress_panel: Control = %ProgressPanel
@onready var progress_label: Label = %ProgressLabel
@onready var notice_label: Label = %NoticeLabel
@onready var notice_timer: Timer = %NoticeTimer
@onready var clear_overlay: Control = %ClearOverlay

@export_category("Tutorial Resources")
@export var tutorial_music: AudioStream
@export_file("*.json") var chart_path: String = (
	"res://rhythm/charts/tutorial_chart.json"
)

@export_category("Tutorial Progress")
@export_range(1, 10, 1) var required_success_count: int = 3
@export_range(3.0, 64.0, 0.5) var tutorial_end_beat: float = 20.0
@export_range(0.0, 10.0, 0.1) var intro_display_duration: float = 2.5
@export_range(0.0, 5.0, 0.1) var notice_display_duration: float = 1.5
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
		show_initialization_error("チュートリアル譜面を読み込めません")
		return

	if tutorial_music == null:
		set_process(false)
		show_initialization_error("チュートリアル音楽が設定されていません")
		return

	rhythm_session.input_resolved.connect(_on_input_resolved)
	music_player.finished.connect(_on_music_finished)
	intro_timer.timeout.connect(_on_intro_timer_timeout)
	notice_timer.timeout.connect(hide_notice)

	if music_enabled and intro_display_duration > 0.0:
		# 案内表示中も編集時の表示状態を残さず、人物を通常状態に整える。
		rhythm_session.configure(chart)
		gameplay_visual.configure(rhythm_session)
		show_tutorial_intro()
	else:
		start_tutorial_track()


func _exit_tree() -> void:
	# 次の画面へ音声再生とストリーム参照を残さない。
	music_player.stop()
	music_player.stream = null
	intro_timer.stop()
	notice_timer.stop()


func _process(_delta: float) -> void:
	advance_tutorial(music_player.get_playback_position())


func receive_sensor_input(
	sensor_input_type: RhythmTypes.InputType
) -> void:
	receive_sensor_input_at(
		sensor_input_type,
		music_player.get_playback_position()
	)


# 曲を止めたまま遊び方を提示し、合図を読む準備時間を作る。
func show_tutorial_intro() -> void:
	set_process(false)
	intro_overlay.visible = true
	progress_panel.visible = false
	clear_overlay.visible = false
	hide_notice()
	music_player.stop()

	intro_timer.wait_time = intro_display_duration
	intro_timer.start()


func _on_intro_timer_timeout() -> void:
	set_process(true)
	start_tutorial_track()


# 専用曲と譜面を先頭へ戻し、チュートリアル全体を開始する。
func start_tutorial_track() -> void:
	intro_timer.stop()
	track_finished = false
	clear_sequence_started = false
	tutorial_success_count = 0
	rhythm_session.configure(chart)
	gameplay_visual.configure(rhythm_session)
	intro_overlay.visible = false
	progress_panel.visible = true
	clear_overlay.visible = false
	hide_notice()
	update_progress_label()

	if tutorial_run_count > 0:
		show_notice("もう一度練習しよう")

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
	hide_notice()
	progress_panel.visible = false
	clear_overlay.visible = true

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

		update_progress_label()


func _on_music_finished() -> void:
	finish_tutorial_track()


func update_progress_label() -> void:
	progress_label.text = "%d / %d" % [
		tutorial_success_count,
		required_success_count,
	]


# 曲をやり直すときだけ短い案内を出し、通常の成否は画像演出に任せる。
func show_notice(message: String) -> void:
	notice_label.text = message
	notice_label.visible = true
	notice_timer.stop()

	if notice_display_duration <= 0.0:
		return

	notice_timer.wait_time = notice_display_duration
	notice_timer.start()


func hide_notice() -> void:
	notice_timer.stop()
	notice_label.visible = false


func show_initialization_error(message: String) -> void:
	intro_timer.stop()
	intro_overlay.visible = false
	progress_panel.visible = true
	notice_label.text = message
	notice_label.visible = true
