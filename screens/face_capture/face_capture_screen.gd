class_name FaceCaptureScreen
extends FlowScreen

# 顔撮影画面内の入力可否を、カメラ状態とは別に管理する。
enum Phase {
	LIVE,
	CAPTURING,
	SHUTTER,
	REVIEW,
	COMPLETED,
}

@export var review_duration: float = 5.0
@export var shutter_effect_enabled: bool = true

@onready var preview: TextureRect = %Preview
@onready var face_guide: TextureRect = %FaceGuide
@onready var before_message: TextureRect = %BeforeMessage
@onready var after_message: TextureRect = %AfterMessage
@onready var shutter_player: VideoStreamPlayer = %ShutterPlayer
@onready var status_label: Label = %StatusLabel
@onready var action_button: Button = %ActionButton
@onready var retry_button: Button = %RetryButton

var camera_source: CameraCaptureSource
var phase: Phase = Phase.LIVE
var capture_in_progress: bool = false
var review_generation: int = 0
var review_input_enabled: bool = false


func _ready() -> void:
	action_button.pressed.connect(_on_action_button_pressed)
	retry_button.pressed.connect(_retry_camera)
	shutter_player.finished.connect(_on_shutter_finished)
	shutter_player.resized.connect(_update_shutter_aspect)

	if camera_source == null:
		camera_source = _create_default_camera_source()

	_show_capture_message(false)
	_attach_camera_source()
	_update_shutter_aspect()


func _exit_tree() -> void:
	# 待機中の確認タイマーと動画を無効化し、カメラも確実に解放する。
	review_generation += 1
	shutter_player.stop()

	if camera_source != null:
		camera_source.stop()


# テストではシーンツリーへ追加する前にFake撮影元を注入する。
func set_camera_source(source: CameraCaptureSource) -> void:
	if is_node_ready():
		push_error("CameraCaptureSourceは_ready()より前に設定してください。")
		return

	camera_source = source


func receive_sensor_input(
	sensor_input_type: RhythmTypes.InputType
) -> void:
	if sensor_input_type == RhythmTypes.InputType.CHEERS:
		_handle_cheers_input()


func _create_default_camera_source() -> CameraCaptureSource:
	# 自動テストでは物理カメラを要求せず、通常実行では実機を使う。
	if DisplayServer.get_name() == "headless":
		return FakeCameraCaptureSource.new()

	return WebCameraCaptureSource.new()


func _attach_camera_source() -> void:
	if camera_source.get_parent() == null:
		add_child(camera_source)

	camera_source.preview_ready.connect(_on_preview_ready)
	camera_source.state_changed.connect(_on_camera_state_changed)
	camera_source.capture_succeeded.connect(_on_capture_succeeded)
	camera_source.capture_failed.connect(_on_capture_failed)

	action_button.disabled = true
	retry_button.visible = false
	status_label.text = "Webカメラを起動しています。"
	camera_source.start()


func _handle_cheers_input() -> void:
	match phase:
		Phase.LIVE:
			_request_capture()

		Phase.REVIEW:
			if review_input_enabled:
				_start_retake()


func _request_capture() -> void:
	if is_completed or capture_in_progress or camera_source == null:
		return

	if camera_source.state != CameraCaptureSource.State.READY:
		return

	# センサーの連続入力が同じフレームに届いても撮影は1回に限定する。
	phase = Phase.CAPTURING
	capture_in_progress = true
	status_label.text = "撮影しています。"
	_update_action_visibility()
	camera_source.capture_frame()


func _start_retake() -> void:
	if phase != Phase.REVIEW or camera_source == null:
		return

	# 進行待ちタイマーを無効化してからライブ映像へ戻す。
	review_generation += 1
	phase = Phase.LIVE
	capture_in_progress = false
	review_input_enabled = false
	shutter_player.stop()
	shutter_player.visible = false
	_show_capture_message(false)
	status_label.text = "カメラを再起動しています。"

	if run_context != null:
		run_context.captured_face_image = null

	camera_source.stop()
	camera_source.start()
	_update_action_visibility()


func _retry_camera() -> void:
	if phase != Phase.LIVE or capture_in_progress or camera_source == null:
		return

	preview.texture = null
	_show_capture_message(false)
	status_label.text = "カメラを再起動しています。"
	camera_source.stop()
	camera_source.start()


func _on_preview_ready(texture: Texture2D) -> void:
	if phase == Phase.LIVE:
		preview.texture = texture


func _on_camera_state_changed(
	next_state: CameraCaptureSource.State,
	message: String
) -> void:
	if phase in [Phase.LIVE, Phase.CAPTURING]:
		match next_state:
			CameraCaptureSource.State.READY:
				status_label.text = "乾杯して撮影"

			CameraCaptureSource.State.UNAVAILABLE, CameraCaptureSource.State.ERROR:
				status_label.text = "%s\n画面をタップして再試行" % message

			_:
				if not message.is_empty():
					status_label.text = message

	_update_action_visibility(next_state)


func _on_capture_succeeded(image: Image) -> void:
	if is_completed or phase != Phase.CAPTURING or not capture_in_progress:
		return

	if image == null or image.is_empty():
		_on_capture_failed("撮影画像が空でした。もう一度お試しください。")
		return

	if run_context == null:
		_on_capture_failed("撮影画像の保存先を初期化できませんでした。")
		return

	# CameraTexture由来の画像参照を画面終了後も安全に保持できるよう複製する。
	var stored_image := image.duplicate() as Image
	run_context.captured_face_image = stored_image

	# 撮影画像を動画の背面へ固定し、シャッター越しにも写真を見せる。
	preview.texture = ImageTexture.create_from_image(stored_image)
	_show_capture_message(true)
	camera_source.stop()
	capture_in_progress = false
	_play_shutter_effect()


func _play_shutter_effect() -> void:
	phase = Phase.SHUTTER
	status_label.text = "撮影しました。"
	_update_action_visibility()

	if not shutter_effect_enabled or shutter_player.stream == null:
		_start_review()
		return

	_update_shutter_aspect()
	shutter_player.visible = true
	shutter_player.stop()
	shutter_player.play()


func _on_shutter_finished() -> void:
	if phase != Phase.SHUTTER:
		return

	shutter_player.visible = false
	_start_review()


func _start_review() -> void:
	if phase != Phase.SHUTTER:
		return

	phase = Phase.REVIEW
	review_input_enabled = false
	shutter_player.visible = false
	_update_action_visibility()

	review_generation += 1
	var current_generation := review_generation
	call_deferred("_enable_review_input", current_generation)

	if review_duration <= 0.0:
		complete_review()
		return

	_run_review_countdown(current_generation)


func _enable_review_input(generation: int) -> void:
	if phase != Phase.REVIEW or generation != review_generation:
		return

	review_input_enabled = true
	_update_action_visibility()


# 撮影確認中に入力がなければ、指定秒数後にチュートリアルへ進む。
func _run_review_countdown(generation: int) -> void:
	var remaining := review_duration

	while remaining > 0.0:
		status_label.text = (
			"この写真で進みます（%d秒）\n乾杯して再撮影"
			% ceili(remaining)
		)
		var wait_time: float = minf(1.0, remaining)
		await get_tree().create_timer(wait_time).timeout

		if (
			not is_inside_tree()
			or phase != Phase.REVIEW
			or generation != review_generation
		):
			return

		remaining -= wait_time

	complete_review()


func complete_review() -> void:
	if phase != Phase.REVIEW or is_completed:
		return

	review_generation += 1
	phase = Phase.COMPLETED
	review_input_enabled = false
	status_label.text = "チュートリアルへ進みます。"
	_update_action_visibility()
	complete_screen({"capture_completed": true})


func _on_capture_failed(message: String) -> void:
	if is_completed:
		return

	phase = Phase.LIVE
	capture_in_progress = false
	review_input_enabled = false
	_show_capture_message(false)
	status_label.text = message
	_update_action_visibility()


func _update_action_visibility(
	current_state: CameraCaptureSource.State = CameraCaptureSource.State.IDLE
) -> void:
	if camera_source != null and current_state == CameraCaptureSource.State.IDLE:
		current_state = camera_source.state

	match phase:
		Phase.LIVE:
			action_button.disabled = (
				capture_in_progress
				or current_state != CameraCaptureSource.State.READY
			)

		Phase.REVIEW:
			action_button.disabled = not review_input_enabled

		_:
			action_button.disabled = true

	retry_button.visible = (
		phase == Phase.LIVE
		and not capture_in_progress
		and current_state in [
			CameraCaptureSource.State.UNAVAILABLE,
			CameraCaptureSource.State.ERROR,
		]
	)


func _on_action_button_pressed() -> void:
	_handle_cheers_input()


# 撮影前後の案内画像と、顔合わせガイドを同じ状態から切り替える。
func _show_capture_message(captured: bool) -> void:
	before_message.visible = not captured
	after_message.visible = captured
	face_guide.visible = not captured


func _update_shutter_aspect() -> void:
	var shutter_material := shutter_player.material as ShaderMaterial

	if shutter_material == null or shutter_player.size.y <= 0.0:
		return

	shutter_material.set_shader_parameter(
		"target_aspect",
		shutter_player.size.x / shutter_player.size.y
	)
