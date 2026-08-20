extends Control

@onready var preview: TextureRect = %Preview
@onready var status_label: Label = %StatusLabel
@onready var capture_button: Button = %CaptureButton
@onready var retry_button: Button = %RetryButton

var camera_source: WebCameraCaptureSource


func _ready() -> void:
	camera_source = WebCameraCaptureSource.new()
	add_child(camera_source)

	camera_source.preview_ready.connect(_on_preview_ready)
	camera_source.state_changed.connect(_on_state_changed)
	camera_source.capture_succeeded.connect(_on_capture_succeeded)
	camera_source.capture_failed.connect(_on_capture_failed)
	capture_button.pressed.connect(_on_capture_button_pressed)
	retry_button.pressed.connect(_on_retry_button_pressed)

	capture_button.disabled = true
	retry_button.visible = false
	camera_source.start()


func _exit_tree() -> void:
	if camera_source != null:
		camera_source.stop()


func _on_preview_ready(texture: Texture2D) -> void:
	preview.texture = texture


func _on_state_changed(
	next_state: CameraCaptureSource.State,
	message: String
) -> void:
	status_label.text = message
	capture_button.disabled = next_state != CameraCaptureSource.State.READY
	retry_button.visible = next_state in [
		CameraCaptureSource.State.UNAVAILABLE,
		CameraCaptureSource.State.ERROR,
	]


func _on_capture_succeeded(image: Image) -> void:
	# 取得した静止画へ差し替え、ライブ映像との色・向きを確認する。
	preview.texture = ImageTexture.create_from_image(image)
	status_label.text = "撮影成功: %d × %d / RGBA8" % [
		image.get_width(),
		image.get_height(),
	]
	retry_button.text = "カメラを再開"
	retry_button.visible = true


func _on_capture_failed(message: String) -> void:
	status_label.text = message


func _on_capture_button_pressed() -> void:
	camera_source.capture_frame()


func _on_retry_button_pressed() -> void:
	preview.texture = null
	camera_source.stop()
	camera_source.start()
