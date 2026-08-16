extends Node2D

# Appが他画面と同じ方法で完了を受け取るための共通シグナル。
signal screen_completed(payload: Dictionary)

@onready var music_player: AudioStreamPlayer = $MusicPlayer
@onready var rhythm_session: RhythmSession = $RhythmSession
@onready var gameplay_visual: GameplayVisual = $GameplayVisual
@onready var rhythm_debug_display: RhythmDebugDisplay = $RhythmDebugDisplay
@onready var start_overlay: Control = %StartOverlay

@export_file("*.json") var chart_path: String = (
	"res://rhythm/charts/test_chart.json"
)
@export_range(0.0, 5.0, 0.1) var start_delay_seconds: float = 1.5

var run_context: RunContext

# 開始演出中の入力と譜面進行を止めるための状態。
var is_game_started: bool = false
# finishedの重複通知やテスト操作で結果を複数回送らないためのフラグ。
var is_game_completed: bool = false


# Appから1プレイ分の共有データを受け取る。
func setup(context: RunContext) -> void:
	run_context = context


func _ready() -> void:
	# シーン生成直後は停止し、開始演出後にstart_game()から有効化する。
	set_process(false)
	music_player.finished.connect(_on_music_finished)

	var chart := RhythmChart.load_from_file(chart_path)

	if chart == null:
		# _processを無効化
		set_process(false)
		return

	# チャートの読み込み
	rhythm_session.configure(chart)
	# ゲーム画面の初期化
	gameplay_visual.configure(rhythm_session)
	if (
		run_context != null
		and run_context.character_generation_succeeded
	):
		gameplay_visual.apply_character_images(
			run_context.generated_character_images
		)
	# デバッグ表示の初期化
	rhythm_debug_display.configure(
		rhythm_session,
		"SHARED"
	)

	begin_start_sequence()


func _exit_tree() -> void:
	# 遷移後に音声再生とストリーム参照を残さない。
	music_player.stop()
	music_player.stream = null


func _process(_delta: float) -> void:
	var song_time: float = music_player.get_playback_position()

	rhythm_session.advance(song_time)
	gameplay_visual.advance(song_time)
	rhythm_debug_display.advance(song_time)


# Appが共有SensorProviderから転送した入力を判定へ渡す。
func receive_sensor_input(sensor_input_type: RhythmTypes.InputType) -> void:
	if not is_game_started or is_game_completed:
		return

	var song_time: float = music_player.get_playback_position()
	rhythm_session.receive_input(
		sensor_input_type,
		song_time
	)


# 「本番スタート！」を表示し、一定時間後にゲームを開始する。
func begin_start_sequence() -> void:
	start_overlay.visible = true

	if start_delay_seconds <= 0.0:
		start_game()
		return

	# 一定時間後にstart_game()を呼び出す。
	# 1.5秒後にゲームを開始する。
	get_tree().create_timer(start_delay_seconds).timeout.connect(
		start_game,
		CONNECT_ONE_SHOT
	)


# 音楽・譜面進行・入力受付を同じタイミングで開始する。
func start_game() -> void:
	if is_game_started or is_game_completed:
		return

	is_game_started = true
	start_overlay.visible = false
	set_process(true)
	music_player.play(0.0)


# 曲終了時点の集計値をAppへ返し、リザルト遷移を要求する。
func finish_game() -> void:
	if is_game_completed:
		return

	is_game_completed = true
	set_process(false)
	music_player.stop()
	# RhythmSessionの集計値をAppへ返す。
	screen_completed.emit(
		{
			"cheers_success_count": rhythm_session.cheers_success_count,
			"cheers_failure_count": rhythm_session.cheers_failure_count,
		}
	)


# AudioStreamPlayerの終了シグナルを画面共通の完了通知へ変換する。
func _on_music_finished() -> void:
	finish_game()
