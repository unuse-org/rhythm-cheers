class_name TitleScreen
extends FlowScreen

@export var door_open_duration: float = 1.0
@export var door_open_distance_ratio: float = 0.5

@onready var door: TextureRect = %Door
@onready var logo: TextureRect = %Logo
@onready var action_button: TextureButton = %ActionButton
@onready var door_audio_player: AudioStreamPlayer = %DoorAudioPlayer
@onready var music_player: AudioStreamPlayer = %MusicPlayer

var is_opening: bool = false
var door_tween: Tween


func _ready() -> void:
	action_button.pressed.connect(_on_action_button_pressed)

	if music_player.stream != null:
		music_player.play()


func _exit_tree() -> void:
	if door_tween != null and door_tween.is_valid():
		door_tween.kill()

	door_audio_player.stop()
	music_player.stop()


func receive_sensor_input(
	sensor_input_type: RhythmTypes.InputType
) -> void:
	if sensor_input_type == RhythmTypes.InputType.CHEERS:
		start_door_opening()


# 乾杯入力後に店の引き戸を左へ開き、演出終了後に次画面へ進む。
func start_door_opening() -> void:
	door_audio_player.volume_db = 20.0
	if is_completed or is_opening:
		return

	is_opening = true
	action_button.disabled = true
	action_button.visible = false
	logo.visible = false

	# ガラガラ音を鳴らす
	if door_audio_player.stream != null:
		door_audio_player.play()

	# 自動テストでは0秒に設定し、待機せず遷移だけを検証できる。
	if door_open_duration <= 0.0:
		_finish_door_opening()
		return

	# Tweenでドアを左へ開く
	# Tweenの終了をawaitして、ドア開き演出が終わるまで待機する。
	var open_distance := size.x * door_open_distance_ratio
	door_tween = create_tween()
	door_tween.set_trans(Tween.TRANS_QUAD)
	door_tween.set_ease(Tween.EASE_IN_OUT)
	door_tween.tween_property(
		door,
		"position",
		Vector2(-open_distance, door.position.y),
		door_open_duration
	)
	await door_tween.finished

	if is_inside_tree():
		_finish_door_opening()


func _finish_door_opening() -> void:
	complete_screen({"door_opened": true})


func _on_action_button_pressed() -> void:
	start_door_opening()
