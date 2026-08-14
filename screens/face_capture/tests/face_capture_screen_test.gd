extends SceneTree

const FACE_CAPTURE_SCENE_PATH: String = (
	"res://screens/face_capture/face_capture_screen.tscn"
)

var failures: Array[String] = []
var completion_count: int = 0


func _initialize() -> void:
	call_deferred("run_tests")


func run_tests() -> void:
	await test_layout_and_capture_flow()
	finish_tests()


func test_layout_and_capture_flow() -> void:
	var source_image := Image.create(16, 8, false, Image.FORMAT_RGBA8)
	source_image.fill(Color(0.25, 0.55, 0.85, 1.0))
	var context := RunContext.new()
	var packed_scene := load(FACE_CAPTURE_SCENE_PATH) as PackedScene
	var screen := packed_scene.instantiate() as FaceCaptureScreen
	screen.setup(context)
	screen.review_duration = 0.1
	screen.shutter_effect_enabled = false
	screen.set_camera_source(FakeCameraCaptureSource.new(source_image))
	screen.screen_completed.connect(_on_screen_completed)
	root.add_child(screen)
	await process_frame

	var camera_stage := screen.get_node("CameraStage") as Control
	expect_true(camera_stage != null, "カメラ表示をCameraStageへ集約する")
	expect_true(
		screen.preview.get_parent() == camera_stage,
		"プレビューをCameraStage基準で配置する"
	)
	expect_true(
		screen.preview.position.x >= 0.0
		and screen.preview.position.y >= 0.0,
		"プレビューを画面外座標への補正なしで配置する"
	)
	expect_true(
		screen.action_button.get_parent() == screen.preview,
		"透明な撮影領域をプレビューへ重ねる"
	)
	expect_true(
		screen.retry_button.get_parent() == screen.preview,
		"再試行領域をプレビューへ重ねる"
	)
	expect_true(
		screen.shutter_player.get_parent() == screen,
		"シャッター演出は画面全体へ重ねる"
	)
	expect_true(screen.preview.texture != null, "カメラ映像を表示する")
	expect_true(
		screen.shutter_audio_player.stream != null,
		"撮影時のシャッター音を読み込む"
	)
	expect_true(screen.before_message.visible, "撮影前の案内を表示する")
	expect_true(not screen.after_message.visible, "撮影後の案内を隠しておく")
	expect_true(screen.face_guide.visible, "撮影前は顔ガイドを表示する")

	# 1枚目を撮影し、確認中の乾杯入力でライブ映像へ戻す。
	screen.receive_sensor_input(RhythmTypes.InputType.CHEERS)
	expect_equal(
		screen.phase,
		FaceCaptureScreen.Phase.REVIEW,
		"撮影後に確認状態へ進む"
	)
	expect_true(context.captured_face_image != null, "撮影画像を保持する")
	expect_true(screen.shutter_audio_player.playing, "撮影開始時にシャッター音を鳴らす")
	expect_true(not screen.before_message.visible, "撮影後は撮影前案内を隠す")
	expect_true(screen.after_message.visible, "撮影後は入店許可を表示する")
	expect_true(not screen.face_guide.visible, "撮影後は顔ガイドを隠す")
	screen.call("_enable_review_input", screen.review_generation)
	screen.receive_sensor_input(RhythmTypes.InputType.CHEERS)
	expect_equal(
		screen.phase,
		FaceCaptureScreen.Phase.LIVE,
		"確認中の乾杯で再撮影へ戻る"
	)
	expect_true(context.captured_face_image == null, "再撮影時に前の画像を破棄する")
	expect_true(screen.before_message.visible, "再撮影時は撮影前案内へ戻す")
	expect_true(not screen.after_message.visible, "再撮影時は入店許可を隠す")
	expect_true(screen.face_guide.visible, "再撮影時は顔ガイドを戻す")

	# 2枚目は確認時間を0秒にし、画面完了まで進める。
	screen.review_duration = 0.0
	screen.receive_sensor_input(RhythmTypes.InputType.CHEERS)
	expect_equal(completion_count, 1, "撮影確認後に完了通知を1回送る")
	expect_true(context.captured_face_image != null, "確定した撮影画像を保持する")

	await create_timer(0.12).timeout
	screen.free()
	await process_frame
	await create_timer(0.1).timeout


func _on_screen_completed(_payload: Dictionary) -> void:
	completion_count += 1


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
		print("FaceCaptureScreen tests passed.")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)

	quit(1)
