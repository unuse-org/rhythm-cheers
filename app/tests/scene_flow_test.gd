extends SceneTree

var failures: Array[String] = []
var completion_count: int = 0
var completion_payload: Dictionary = {}


func _initialize() -> void:
	call_deferred("run_tests")


func run_tests() -> void:
	test_flow_order()
	test_scene_paths()
	test_run_context()
	test_placeholder_screens()
	finish_tests()


func test_flow_order() -> void:
	var expected: Array[SceneFlow.ScreenId] = [
		SceneFlow.ScreenId.TITLE,
		SceneFlow.ScreenId.FACE_CAPTURE,
		SceneFlow.ScreenId.TUTORIAL,
		SceneFlow.ScreenId.MAIN,
		SceneFlow.ScreenId.RESULT,
	]

	expect_equal(
		SceneFlow.get_initial_screen(),
		SceneFlow.ScreenId.TITLE,
		"起動画面はTITLE"
	)
	expect_equal(SceneFlow.FLOW, expected, "画面遷移順")

	for index: int in expected.size():
		var next_index := (index + 1) % expected.size()
		expect_equal(
			SceneFlow.get_next_screen(expected[index]),
			expected[next_index],
			"%sの次画面"
			% SceneFlow.ScreenId.keys()[expected[index]]
		)


func test_scene_paths() -> void:
	for screen_id: SceneFlow.ScreenId in SceneFlow.FLOW:
		var scene_path := SceneFlow.get_scene_path(screen_id)
		expect_true(
			ResourceLoader.exists(scene_path, "PackedScene"),
			"%sのシーンが存在する"
			% SceneFlow.ScreenId.keys()[screen_id]
		)
		var packed_scene := load(scene_path) as PackedScene
		expect_true(
			packed_scene != null,
			"%sのシーンを読み込める"
			% SceneFlow.ScreenId.keys()[screen_id]
		)


func test_run_context() -> void:
	var context := RunContext.new()

	expect_true(context.captured_face_image == null, "撮影画像の初期値")
	expect_true(context.processed_face_image == null, "加工画像の初期値")
	expect_true(not context.tutorial_completed, "チュートリアル状態の初期値")
	expect_equal(context.cheers_success_count, 0, "成功数の初期値")
	expect_equal(context.cheers_failure_count, 0, "失敗数の初期値")
	expect_equal(context.calculate_total_amount(), 0, "合計金額の初期値")

	context.captured_face_image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
	context.processed_face_image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
	context.tutorial_completed = true
	context.cheers_success_count = 3
	context.cheers_failure_count = 1
	expect_equal(context.calculate_success_amount(), 1500, "成功金額を計算する")
	expect_equal(context.calculate_failure_amount(), -50, "失敗金額を計算する")
	expect_equal(context.calculate_total_amount(), 1450, "合計金額を計算する")
	context.clear()

	expect_true(context.captured_face_image == null, "撮影画像を破棄する")
	expect_true(context.processed_face_image == null, "加工画像を破棄する")
	expect_true(not context.tutorial_completed, "チュートリアル状態を戻す")
	expect_equal(context.cheers_success_count, 0, "成功数を戻す")
	expect_equal(context.cheers_failure_count, 0, "失敗数を戻す")
	expect_equal(context.calculate_total_amount(), 0, "合計金額を戻す")


func test_placeholder_screens() -> void:
	var screen_ids: Array[SceneFlow.ScreenId] = [
		SceneFlow.ScreenId.TITLE,
		SceneFlow.ScreenId.FACE_CAPTURE,
		SceneFlow.ScreenId.RESULT,
	]

	for screen_id: SceneFlow.ScreenId in screen_ids:
		completion_count = 0
		completion_payload = {}

		var packed_scene := load(
			SceneFlow.get_scene_path(screen_id)
		) as PackedScene
		var screen := packed_scene.instantiate() as FlowScreen
		expect_true(screen != null, "%sがFlowScreenを実装する" % screen_id)

		if screen == null:
			continue

		screen.setup(RunContext.new())
		screen.screen_completed.connect(_on_screen_completed)

		if screen_id == SceneFlow.ScreenId.FACE_CAPTURE:
			var face_capture := screen as FaceCaptureScreen
			face_capture.review_duration = 0.0
			face_capture.shutter_effect_enabled = false
			face_capture.set_camera_source(
				FakeCameraCaptureSource.new()
			)
		elif screen_id == SceneFlow.ScreenId.TITLE:
			var title := screen as TitleScreen
			title.door_open_duration = 0.0

		root.add_child(screen)
		screen.receive_sensor_input(RhythmTypes.InputType.CHEERS)

		expect_equal(completion_count, 1, "%sが完了通知を出す" % screen_id)
		screen.receive_sensor_input(RhythmTypes.InputType.CHEERS)
		expect_equal(
			completion_count,
			1,
			"%sが完了通知を重複させない" % screen_id
		)

		if screen_id == SceneFlow.ScreenId.FACE_CAPTURE:
			expect_equal(
				completion_payload.get("capture_completed"),
				true,
				"顔撮影画面の完了データ"
			)

		screen.free()


func _on_screen_completed(payload: Dictionary) -> void:
	completion_count += 1
	completion_payload = payload


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
		print("SceneFlow tests passed.")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)

	quit(1)
