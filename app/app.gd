class_name RhythmCheersApp
extends Node

# 画面をまたいで利用するセンサーの切り替え方法。
enum SensorMode {
	KEYBOARD,
	SERIAL,
}

@onready var screen_container: Node = $ScreenContainer
@onready var rhythm_audio_controller: RhythmAudioController = (
	$RhythmAudioController
)
@onready var keyboard_sensor_provider: SensorProvider = (
	$KeyboardSensorProvider
)
@onready var serial_sensor_provider: SensorProvider = (
	$SerialSensorProvider
)

@export var sensor_mode: SensorMode = SensorMode.KEYBOARD
@export_file("*.json") var song_chart_path: String = (
	"res://rhythm/charts/kanpai_chart.json"
)

# Appが現在表示している画面と、1プレイ分の共有データを保持する。
var active_sensor_provider: SensorProvider
var current_screen_id: SceneFlow.ScreenId = SceneFlow.ScreenId.TITLE
var current_screen: Node
var run_context: RunContext
# テストでは保存先を汚さないFakeへ差し替えられる。
var player_count_store: PlayerCountStore
var rhythm_audio_ready: bool = false
var song_chart: RhythmChart

# 同じ乾杯入力で複数画面進まないよう、差し替え中は入力を止める。
var transition_locked: bool = false


func _ready() -> void:
	# タイトルからリザルトまで同じRunContextを引き回す。
	run_context = RunContext.new()
	if player_count_store == null:
		player_count_store = PlayerCountStore.new()
	song_chart = RhythmChart.load_from_file(song_chart_path)
	rhythm_audio_ready = song_chart != null
	if not rhythm_audio_ready:
		push_error("全曲譜面を初期化できませんでした。")
	show_screen(SceneFlow.get_initial_screen())
	initialize_sensor_provider()


func _exit_tree() -> void:
	# 画面ではなくAppが所有者なので、アプリ終了時にだけ停止する。
	if active_sensor_provider != null:
		active_sensor_provider.stop()


# SceneFlowが定義するシーンへ現在画面を差し替える。
func show_screen(screen_id: SceneFlow.ScreenId) -> void:
	transition_locked = true

	if current_screen != null:
		current_screen.queue_free()
		current_screen = null

	# 画面IDからシーンパスを取得し、PackedSceneとして読み込む。
	var scene_path := SceneFlow.get_scene_path(screen_id)
	var packed_scene := load(scene_path) as PackedScene

	if packed_scene == null:
		push_error("画面シーンを読み込めませんでした: %s" % scene_path)
		transition_locked = false
		return

	current_screen = packed_scene.instantiate()
	current_screen_id = screen_id
	var screen_audio_ready := configure_rhythm_audio_for_screen(screen_id)

	# 各画面は必要なメソッドとシグナルだけを共通契約として実装する。
	# MainはFlowScreenを継承しないため、継承型ではなく存在確認で扱う。
	# 画面の初期化は、RunContextを引数にsetup()で行う。
	if current_screen.has_method("setup"):
		current_screen.call("setup", run_context)
	if screen_audio_ready and current_screen.has_method("set_audio_controller"):
		current_screen.call("set_audio_controller", rhythm_audio_controller)

	# 画面が完了したらAppへ通知するため、シグナルを接続する。
	if current_screen.has_signal("screen_completed"):
		current_screen.connect("screen_completed", _on_screen_completed)

	# 画面を表示するため、画面コンテナへ追加する。
	screen_container.add_child(current_screen)
	# 新しい画面へ遷移元の入力が届かないよう、次の処理単位で解除する。
	call_deferred("_unlock_transition")


# TutorialとMainでは、それぞれのローカル譜面と専用音源へ切り替える。
func configure_rhythm_audio_for_screen(
	screen_id: SceneFlow.ScreenId
) -> bool:
	if not rhythm_audio_ready:
		return false

	var section_name := ""
	match screen_id:
		SceneFlow.ScreenId.TUTORIAL:
			section_name = "tutorial"
		SceneFlow.ScreenId.MAIN:
			section_name = "main"
		_:
			return false

	var section_chart := song_chart.create_section(section_name, true)
	if section_chart == null:
		return false
	if not rhythm_audio_controller.configure(section_chart):
		push_error("%s音声を初期化できませんでした。" % section_name)
		return false
	return true


# 選択したSensorProviderだけを起動し、入力をAppへ集約する。
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
	active_sensor_provider.sensor_error.connect(_on_sensor_error)
	active_sensor_provider.connection_changed.connect(
		_on_sensor_connection_changed
	)
	active_sensor_provider.start()


# Appが受け取ったセンサー入力を、現在表示中の画面へ転送する。
func receive_sensor_input(
	sensor_input_type: RhythmTypes.InputType
) -> void:
	# Appは入力内容を解釈せず、表示中の画面だけへ転送する。
	if transition_locked or current_screen == null:
		return

	# 画面が入力を受け付けるメソッドを持っていれば、入力を転送する。
	if current_screen.has_method("receive_sensor_input"):
		current_screen.call("receive_sensor_input", sensor_input_type)


# 画面が完了したら、Appが次の画面へ遷移する。
func _on_screen_completed(payload: Dictionary) -> void:
	# 完了通知が重複しても、遷移開始後の通知は無視する。
	if transition_locked:
		return

	apply_screen_payload(payload)

	# Mainを完走した時点で現在の体験者を累計へ一度だけ記録する。
	# transition_lockedにより、Mainからの重複完了通知では再加算されない。
	if current_screen_id == SceneFlow.ScreenId.MAIN:
		run_context.player_number = player_count_store.record_player()

	var next_screen_id := SceneFlow.get_next_screen(current_screen_id)

	# RESULTからTITLEへ戻る時点で前回プレイの画像・結果を破棄する。
	if next_screen_id == SceneFlow.ScreenId.TITLE:
		rhythm_audio_controller.stop()
		run_context.clear()
		run_context = RunContext.new()

	show_screen(next_screen_id)


# 画面固有の完了データを、画面間で共有するRunContextへ反映する。
func apply_screen_payload(payload: Dictionary) -> void:
	if payload.get("tutorial_completed", false):
		run_context.tutorial_completed = true

	if payload.has("cheers_success_count"):
		run_context.cheers_success_count = payload["cheers_success_count"]

	if payload.has("cheers_failure_count"):
		run_context.cheers_failure_count = payload["cheers_failure_count"]


func _unlock_transition() -> void:
	transition_locked = false


func _on_sensor_error(message: String) -> void:
	push_error(message)


func _on_sensor_connection_changed(connected: bool) -> void:
	print("Sensor connected: ", connected)
