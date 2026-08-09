extends Node2D

# Appが他画面と同じ方法で完了を受け取るための共通シグナル。
signal screen_completed(payload: Dictionary)

@onready var music_player: AudioStreamPlayer = $MusicPlayer
@onready var rhythm_session: RhythmSession = $RhythmSession
@onready var gameplay_visual: GameplayVisual = $GameplayVisual
@onready var rhythm_debug_display: RhythmDebugDisplay = $RhythmDebugDisplay

@export_file("*.json") var chart_path: String = (
	"res://rhythm/charts/test_chart.json"
)

# 正式なリザルト計算が決まるまで使用する暫定ポイント。
const POINTS_PER_SUCCESS: int = 100

var run_context: RunContext

# finishedの重複通知やテスト操作で結果を複数回送らないためのフラグ。
var is_game_completed: bool = false


# Appから1プレイ分の共有データを受け取る。
func setup(context: RunContext) -> void:
	run_context = context


func _ready() -> void:
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
	# デバッグ表示の初期化
	rhythm_debug_display.configure(
		rhythm_session,
		"SHARED"
	)

	music_player.play()


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
	var song_time: float = music_player.get_playback_position()
	rhythm_session.receive_input(
		sensor_input_type,
		song_time
	)


# 曲終了時点の集計値をAppへ返し、リザルト遷移を要求する。
func finish_game() -> void:
	if is_game_completed:
		return

	is_game_completed = true
	set_process(false)
	music_player.stop()
	screen_completed.emit(
		{
			"cheers_success_count": rhythm_session.cheers_success_count,
			"cheers_failure_count": rhythm_session.cheers_failure_count,
			"result_value": (
				rhythm_session.cheers_success_count
				* POINTS_PER_SUCCESS
			),
		}
	)


# AudioStreamPlayerの終了シグナルを画面共通の完了通知へ変換する。
func _on_music_finished() -> void:
	finish_game()
