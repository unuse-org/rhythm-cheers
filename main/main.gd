extends Node2D

@onready var music_player: AudioStreamPlayer = $MusicPlayer
@onready var rhythm_session: RhythmSession = $RhythmSession
@onready var gameplay_visual: GameplayVisual = $GameplayVisual
@onready var rhythm_debug_display: RhythmDebugDisplay = $RhythmDebugDisplay

@export_file("*.json") var chart_path: String = (
	"res://rhythm/charts/test_chart.json"
)

var run_context: RunContext


func setup(context: RunContext) -> void:
	run_context = context


func _ready() -> void:
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
	music_player.stop()
	music_player.stream = null


func _process(_delta: float) -> void:
	var song_time: float = music_player.get_playback_position()

	rhythm_session.advance(song_time)
	gameplay_visual.advance(song_time)
	rhythm_debug_display.advance(song_time)


# SensorProviderから入力を受信する
func receive_sensor_input(sensor_input_type: RhythmTypes.InputType) -> void:
	var song_time: float = music_player.get_playback_position()
	rhythm_session.receive_input(
		sensor_input_type,
		song_time
	)
