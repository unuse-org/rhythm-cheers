extends SceneTree

var failures: Array[String] = []
var captured_image: Image
var preview_texture: Texture2D


func _initialize() -> void:
	call_deferred("run_tests")


func run_tests() -> void:
	test_fake_camera_capture()
	test_preferred_camera_format()
	test_preferred_camera_feed()
	finish_tests()


func test_fake_camera_capture() -> void:
	var source := FakeCameraCaptureSource.new()
	source.preview_ready.connect(_on_preview_ready)
	source.capture_succeeded.connect(_on_capture_succeeded)
	root.add_child(source)

	source.start()
	expect_equal(
		source.state,
		CameraCaptureSource.State.READY,
		"Fakeカメラが撮影可能になる"
	)
	expect_true(preview_texture != null, "Fakeカメラがプレビューを返す")

	source.capture_frame()
	expect_equal(
		source.state,
		CameraCaptureSource.State.CAPTURED,
		"Fakeカメラが撮影を完了する"
	)
	expect_true(captured_image != null, "Fakeカメラが画像を返す")
	expect_equal(captured_image.get_width(), 64, "撮影画像の幅")
	expect_equal(captured_image.get_height(), 64, "撮影画像の高さ")

	source.stop()
	expect_equal(
		source.state,
		CameraCaptureSource.State.IDLE,
		"停止後はIDLEへ戻る"
	)
	source.free()


func test_preferred_camera_format() -> void:
	var formats: Array = [
		{"width": 640, "height": 480},
		{"width": 1280, "height": 720},
		{"width": 1920, "height": 1080},
	]
	var selected_index := WebCameraCaptureSource.find_preferred_format_index(
		formats,
		Vector2i(1280, 720)
	)
	expect_equal(selected_index, 1, "希望解像度と一致する形式を選ぶ")
	expect_equal(
		WebCameraCaptureSource.find_preferred_format_index([], Vector2i.ZERO),
		-1,
		"有効な形式がない場合は未選択を返す"
	)


func test_preferred_camera_feed() -> void:
	var feed_names: Array[String] = [
		"FaceTime HD Camera",
		"Logi C922 Pro Stream Webcam",
	]
	expect_equal(
		WebCameraCaptureSource.find_preferred_feed_index(feed_names, "logi"),
		1,
		"カメラ名を大文字小文字なしの部分一致で選ぶ"
	)
	expect_equal(
		WebCameraCaptureSource.find_preferred_feed_index(feed_names, ""),
		-1,
		"優先名が空なら指定選択しない"
	)
	expect_equal(
		WebCameraCaptureSource.find_preferred_feed_index(feed_names, "Elgato"),
		-1,
		"一致するカメラがなければ未選択を返す"
	)

func _on_preview_ready(texture: Texture2D) -> void:
	preview_texture = texture


func _on_capture_succeeded(image: Image) -> void:
	captured_image = image


func expect_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append(
			"%s: expected=%s actual=%s" % [message, expected, actual]
		)


func finish_tests() -> void:
	if failures.is_empty():
		print("CameraCaptureSource tests passed.")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)

	quit(1)
