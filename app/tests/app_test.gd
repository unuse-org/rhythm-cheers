extends SceneTree

const APP_SCENE_PATH: String = "res://app/app.tscn"
const MAIN_SCENE_PATH: String = "res://main/main.tscn"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_tests")


func run_tests() -> void:
	await test_app_flow()
	test_sensor_provider_ownership()
	finish_tests()


func test_app_flow() -> void:
	var app_scene := load(APP_SCENE_PATH) as PackedScene
	var app := app_scene.instantiate() as RhythmCheersApp
	root.add_child(app)
	await process_frame

	expect_equal(
		app.current_screen_id,
		SceneFlow.ScreenId.TITLE,
		"起動時にタイトルを表示する"
	)
	expect_true(
		app.active_sensor_provider is KeyboardSensorProvider,
		"初期状態ではキーボードセンサーを共有する"
	)

	app.active_sensor_provider.input_detected.emit(
		RhythmTypes.InputType.CHEERS
	)
	app.active_sensor_provider.input_detected.emit(
		RhythmTypes.InputType.CHEERS
	)
	await process_frame
	expect_equal(
		app.current_screen_id,
		SceneFlow.ScreenId.FACE_CAPTURE,
		"連続入力でも顔撮影より先へ進まない"
	)

	app.active_sensor_provider.input_detected.emit(
		RhythmTypes.InputType.CHEERS
	)
	await process_frame
	expect_equal(
		app.current_screen_id,
		SceneFlow.ScreenId.TUTORIAL,
		"顔撮影からチュートリアルへ進む"
	)

	app.active_sensor_provider.input_detected.emit(
		RhythmTypes.InputType.CHEERS
	)
	await process_frame
	expect_equal(
		app.current_screen_id,
		SceneFlow.ScreenId.MAIN,
		"チュートリアルからメインへ進む"
	)
	expect_true(
		app.run_context.tutorial_completed,
		"チュートリアル完了状態を引き継ぐ"
	)

	var music_player := app.current_screen.get_node(
		"MusicPlayer"
	) as AudioStreamPlayer
	music_player.stop()
	music_player.stream = null
	await create_timer(0.1).timeout
	app.free()
	await process_frame


func test_sensor_provider_ownership() -> void:
	var main_scene := load(MAIN_SCENE_PATH) as PackedScene
	var main := main_scene.instantiate()

	expect_true(
		not main.has_node("KeyboardSensorProvider"),
		"Mainはキーボードセンサーを所有しない"
	)
	expect_true(
		not main.has_node("SerialSensorProvider"),
		"Mainはシリアルセンサーを所有しない"
	)
	expect_true(
		main.has_method("receive_sensor_input"),
		"MainはAppから入力を受け取れる"
	)

	main.free()


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
		print("App tests passed.")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)

	quit(1)
