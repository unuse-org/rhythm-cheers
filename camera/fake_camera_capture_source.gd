class_name FakeCameraCaptureSource
extends CameraCaptureSource

var capture_image: Image
var preview_texture: ImageTexture


func _init(image: Image = null) -> void:
	capture_image = image


# 物理カメラを使えない自動テスト用に、固定画像をライブ映像として扱う。
func start() -> void:
	if state != State.IDLE:
		return

	_set_state(State.DISCOVERING, "テスト画像を準備しています。")

	if capture_image == null or capture_image.is_empty():
		capture_image = _create_default_image()

	preview_texture = ImageTexture.create_from_image(capture_image)
	preview_ready.emit(preview_texture)
	_set_state(State.READY, "テスト用カメラの準備ができました。")


func stop() -> void:
	preview_texture = null
	_set_state(State.IDLE)


func capture_frame() -> void:
	if state != State.READY:
		capture_failed.emit("カメラの準備ができていません。")
		return

	_set_state(State.CAPTURING, "撮影しています。")

	if capture_image == null or capture_image.is_empty():
		_set_state(State.READY, "撮影に失敗しました。もう一度お試しください。")
		capture_failed.emit(state_message)
		return

	var captured_image := capture_image.duplicate() as Image
	_set_state(State.CAPTURED, "撮影しました。")
	capture_succeeded.emit(captured_image)


func _create_default_image() -> Image:
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.55, 0.8, 1.0))
	return image
