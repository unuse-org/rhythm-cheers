extends Node2D

# Appが他画面と同じ方法で完了を受け取るための共通シグナル。
signal screen_completed(payload: Dictionary)

@onready var music_player: AudioStreamPlayer = $MusicPlayer
@onready var rhythm_session: RhythmSession = $RhythmSession
@onready var gameplay_visual: GameplayVisual = $GameplayVisual
@onready var rhythm_debug_display: RhythmDebugDisplay = $RhythmDebugDisplay
@onready var start_overlay: Control = %StartOverlay

@export_file("*.json") var chart_path: String = (
	"res://rhythm/charts/kanpai_chart.json"
)

var run_context: RunContext
var audio_controller: RhythmAudioController
var chart: RhythmChart
var gameplay_start_time: float = 0.0

# 本番音源のリードイン中はfalseにして、センサー入力を受け付けない。
var is_game_started: bool = false
# finishedの重複通知やテスト操作で結果を複数回送らないためのフラグ。
var is_game_completed: bool = false


# Appから1プレイ分の共有データを受け取る。
func setup(context: RunContext) -> void:
	run_context = context


func set_audio_controller(controller: RhythmAudioController) -> void:
	audio_controller = controller


func _ready() -> void:
	# 初期化完了後、音源のリードインからprocessを開始する。
	set_process(false)
	if audio_controller == null:
		music_player.finished.connect(_on_music_finished)

	var full_chart := RhythmChart.load_from_file(chart_path)
	chart = (
		full_chart.create_section("main", true)
		if full_chart != null and full_chart.sections.has("main")
		else full_chart
	)

	if chart == null:
		# _processを無効化
		set_process(false)
		return
	if audio_controller != null:
		audio_controller.song_finished.connect(_on_music_finished)

	# チャートの読み込み
	rhythm_session.configure(chart)
	gameplay_start_time = rhythm_session.timing.beat_to_seconds(
		chart.lead_in_beats
	)
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
	# App所有の共通Playerはfinish_game()で停止する。
	music_player.stop()
	music_player.stream = null


func _process(_delta: float) -> void:
	advance_main(get_song_time())


# リードイン中は音源だけを進め、規定拍に達したframeから譜面を進める。
func advance_main(song_time: float) -> void:
	if chart == null or is_game_completed:
		return
	if audio_controller != null and not audio_controller.playback_enabled:
		audio_controller.set_simulated_song_time(song_time)

	if not is_game_started:
		if song_time < gameplay_start_time:
			return
		start_game()

	rhythm_session.advance(song_time)
	gameplay_visual.advance(song_time)
	rhythm_debug_display.advance(song_time)


# Appが共有SensorProviderから転送した入力を判定へ渡す。
func receive_sensor_input(sensor_input_type: RhythmTypes.InputType) -> void:
	if not is_game_started or is_game_completed:
		return

	var song_time := get_song_time()
	rhythm_session.receive_input(
		sensor_input_type,
		song_time
	)


func get_song_time() -> float:
	if audio_controller != null:
		return audio_controller.get_song_time()
	return music_player.get_playback_position()


# 「本番スタート！」を表示したまま、本番音源のリードインを再生する。
func begin_start_sequence() -> void:
	start_overlay.visible = true
	set_process(true)
	if audio_controller != null:
		audio_controller.start(0.0)
	else:
		music_player.play(0.0)

	if gameplay_start_time <= 0.0:
		start_game()


# リードイン終了時に表示を消し、譜面進行と入力受付を有効にする。
func start_game() -> void:
	if is_game_started or is_game_completed:
		return

	is_game_started = true
	start_overlay.visible = false


# 曲終了時点の集計値をAppへ返し、リザルト遷移を要求する。
func finish_game() -> void:
	if is_game_completed:
		return

	is_game_completed = true
	set_process(false)
	music_player.stop()
	if audio_controller != null:
		audio_controller.stop()
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
