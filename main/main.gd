extends Node2D

@onready var music_player: AudioStreamPlayer = $MusicPlayer
@onready var rhythm_session: RhythmSession = $RhythmSession
@onready var gameplay_visual: GameplayVisual = $GameplayVisual
@onready var rhythm_debug_display: RhythmDebugDisplay = $RhythmDebugDisplay

@onready var keyboard_sensor_provider: SensorProvider = $KeyboardSensorProvider
@onready var serial_sensor_provider: SensorProvider = $SerialSensorProvider

enum SensorMode {
	KEYBOARD,
	SERIAL,
}

@export var sensor_mode: SensorMode = SensorMode.KEYBOARD
@export_file("*.json") var chart_path: String = (
	"res://rhythm/charts/test_chart.json"
)

# 有効なSensorProvider
var active_sensor_provider: SensorProvider


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
		SensorMode.keys()[sensor_mode]
	)
	initialize_sensor_provider()

	music_player.play()


func _exit_tree() -> void:
	music_player.stop()

	if active_sensor_provider != null:
		active_sensor_provider.stop()


func _process(_delta: float) -> void:
	var song_time: float = music_player.get_playback_position()

	rhythm_session.advance(song_time)
	gameplay_visual.advance(song_time)
	rhythm_debug_display.advance(song_time)


# 使用するSensorProviderを選択して初期化する
func initialize_sensor_provider() -> void:
	keyboard_sensor_provider.process_mode = Node.PROCESS_MODE_DISABLED
	serial_sensor_provider.process_mode = Node.PROCESS_MODE_DISABLED

	match sensor_mode:
		SensorMode.KEYBOARD:
			active_sensor_provider = keyboard_sensor_provider

		SensorMode.SERIAL:
			active_sensor_provider = serial_sensor_provider

	if active_sensor_provider == null:
		push_error("SensorProviderを初期化できませんでした。")
		return

	active_sensor_provider.process_mode = Node.PROCESS_MODE_INHERIT

	active_sensor_provider.input_detected.connect(receive_sensor_input)
	active_sensor_provider.sensor_error.connect(on_sensor_error)
	active_sensor_provider.connection_changed.connect(on_sensor_connection_changed)

	active_sensor_provider.start()


# SensorProviderから入力を受信する
func receive_sensor_input(sensor_input_type: RhythmTypes.InputType) -> void:
	var song_time: float = music_player.get_playback_position()
	rhythm_session.receive_input(
		sensor_input_type,
		song_time
	)


func on_sensor_error(message: String) -> void:
	push_error(message)


func on_sensor_connection_changed(connected: bool) -> void:
	print("Sensor connected: ", connected)
