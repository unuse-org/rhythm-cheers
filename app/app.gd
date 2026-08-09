class_name RhythmCheersApp
extends Node

enum SensorMode {
	KEYBOARD,
	SERIAL,
}

@onready var screen_container: Node = $ScreenContainer
@onready var keyboard_sensor_provider: SensorProvider = (
	$KeyboardSensorProvider
)
@onready var serial_sensor_provider: SensorProvider = (
	$SerialSensorProvider
)

@export var sensor_mode: SensorMode = SensorMode.KEYBOARD

var active_sensor_provider: SensorProvider
var current_screen_id: SceneFlow.ScreenId = SceneFlow.ScreenId.TITLE
var current_screen: Node
var run_context: RunContext
var transition_locked: bool = false


func _ready() -> void:
	run_context = RunContext.new()
	show_screen(SceneFlow.get_initial_screen())
	initialize_sensor_provider()


func _exit_tree() -> void:
	if active_sensor_provider != null:
		active_sensor_provider.stop()


func show_screen(screen_id: SceneFlow.ScreenId) -> void:
	transition_locked = true

	if current_screen != null:
		current_screen.queue_free()
		current_screen = null

	var scene_path := SceneFlow.get_scene_path(screen_id)
	var packed_scene := load(scene_path) as PackedScene

	if packed_scene == null:
		push_error("画面シーンを読み込めませんでした: %s" % scene_path)
		transition_locked = false
		return

	current_screen = packed_scene.instantiate()
	current_screen_id = screen_id

	if current_screen.has_method("setup"):
		current_screen.call("setup", run_context)

	if current_screen.has_signal("screen_completed"):
		current_screen.connect("screen_completed", _on_screen_completed)

	screen_container.add_child(current_screen)
	call_deferred("_unlock_transition")


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


func receive_sensor_input(
	sensor_input_type: RhythmTypes.InputType
) -> void:
	if transition_locked or current_screen == null:
		return

	if current_screen.has_method("receive_sensor_input"):
		current_screen.call("receive_sensor_input", sensor_input_type)


func _on_screen_completed(payload: Dictionary) -> void:
	if transition_locked:
		return

	apply_screen_payload(payload)

	var next_screen_id := SceneFlow.get_next_screen(current_screen_id)

	if next_screen_id == SceneFlow.ScreenId.TITLE:
		run_context.clear()
		run_context = RunContext.new()

	show_screen(next_screen_id)


func apply_screen_payload(payload: Dictionary) -> void:
	if payload.get("tutorial_completed", false):
		run_context.tutorial_completed = true


func _unlock_transition() -> void:
	transition_locked = false


func _on_sensor_error(message: String) -> void:
	push_error(message)


func _on_sensor_connection_changed(connected: bool) -> void:
	print("Sensor connected: ", connected)
