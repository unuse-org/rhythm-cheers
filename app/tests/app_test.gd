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

	# 1周目: TITLEからMAINまで、共有センサーで順番に進む。
	expect_equal(
		app.current_screen_id,
		SceneFlow.ScreenId.TITLE,
		"起動時にタイトルを表示する"
	)
	expect_true(
		app.active_sensor_provider is KeyboardSensorProvider,
		"初期状態ではキーボードセンサーを共有する"
	)
	var title := app.current_screen as TitleScreen
	title.door_open_duration = 0.0

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

	var face_capture := app.current_screen as FaceCaptureScreen
	face_capture.review_duration = 0.0
	face_capture.shutter_effect_enabled = false
	expect_true(
		face_capture.camera_source is FakeCameraCaptureSource,
		"ヘッドレステストではFakeカメラを利用する"
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
	expect_true(
		app.run_context.captured_face_image != null,
		"撮影画像をRunContextへ引き継ぐ"
	)

	var tutorial := app.current_screen as TutorialScreen
	tutorial.set_process(false)
	tutorial.music_enabled = false
	tutorial.clear_display_duration = 0.0
	tutorial.start_tutorial_track()

	# 一曲内で3回成功させ、曲の区切りからMAINへ進む。
	var tutorial_success_beats: Array[float] = [2.0, 6.0, 10.0]

	for success_beat: float in tutorial_success_beats:
		var target_time := tutorial.rhythm_session.timing.beat_to_seconds(
			success_beat
		)
		var input_open_time := target_time - RhythmSession.MISS_WINDOW + 0.001

		tutorial.advance_tutorial(input_open_time)
		tutorial.receive_sensor_input_at(
			RhythmTypes.InputType.CHEERS,
			target_time
		)

	var tutorial_end_time := tutorial.rhythm_session.timing.beat_to_seconds(
		tutorial.tutorial_end_beat
	)
	tutorial.advance_tutorial(tutorial_end_time)

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

	var main_screen := app.current_screen
	var rhythm_session := main_screen.get_node(
		"RhythmSession"
	) as RhythmSession
	var main_music_player := main_screen.get_node(
		"MusicPlayer"
	) as AudioStreamPlayer

	# Mainは開始表示中に音楽・入力を開始しない。
	expect_true(
		not main_screen.get("is_game_started"),
		"開始表示中はゲームを停止する"
	)
	expect_true(not main_music_player.playing, "開始表示中は音楽を再生しない")
	app.active_sensor_provider.input_detected.emit(
		RhythmTypes.InputType.CHEERS
	)
	expect_equal(rhythm_session.last_judgement, "-", "開始前の入力を無視する")

	main_screen.call("start_game")
	expect_true(main_screen.get("is_game_started"), "開始表示後にゲームを始める")
	expect_true(main_music_player.playing, "ゲーム開始と同時に音楽を再生する")
	rhythm_session.cheers_success_count = 3
	rhythm_session.cheers_failure_count = 1
	var completed_context := app.run_context

	# 曲終了を再現し、重複通知されてもRESULTを越えないことを確認する。
	main_screen.call("finish_game")
	main_screen.call("finish_game")
	await process_frame
	expect_equal(
		app.current_screen_id,
		SceneFlow.ScreenId.RESULT,
		"メイン終了後にリザルトへ進む"
	)
	expect_equal(app.run_context.cheers_success_count, 3, "成功数を引き継ぐ")
	expect_equal(app.run_context.cheers_failure_count, 1, "失敗数を引き継ぐ")
	expect_equal(app.run_context.calculate_success_amount(), 1500, "成功金額")
	expect_equal(app.run_context.calculate_failure_amount(), -50, "失敗金額")
	expect_equal(app.run_context.calculate_total_amount(), 1450, "合計金額")
	expect_true(
		not is_instance_valid(main_screen),
		"メイン画面を遷移後に破棄する"
	)

	var result_screen := app.current_screen as ResultScreen
	expect_equal(
		result_screen.success_count_label.text,
		"3",
		"リザルト画面に乾杯数を表示する"
	)
	expect_equal(
		result_screen.success_amount_label.text,
		"¥1500",
		"リザルト画面に乾杯金額を表示する"
	)
	expect_equal(
		result_screen.failure_count_label.text,
		"1",
		"リザルト画面に失杯数を表示する"
	)
	expect_equal(
		result_screen.failure_amount_label.text,
		"¥-50",
		"リザルト画面に失杯金額を表示する"
	)
	expect_equal(
		result_screen.total_amount_label.text,
		"¥1450",
		"リザルト画面に合計金額を表示する"
	)
	expect_true(
		result_screen.face_preview.texture != null,
		"リザルト画面に撮影画像を表示する"
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
		SceneFlow.ScreenId.TITLE,
		"リザルトからタイトルへ戻る"
	)
	expect_true(
		app.run_context != completed_context,
		"タイトルへ戻る際にRunContextを作り直す"
	)
	expect_equal(app.run_context.cheers_success_count, 0, "成功数を初期化する")
	expect_equal(app.run_context.cheers_failure_count, 0, "失敗数を初期化する")
	expect_true(
		not app.run_context.tutorial_completed,
		"チュートリアル状態を初期化する"
	)
	expect_true(
		app.run_context.captured_face_image == null,
		"撮影画像を初期化する"
	)

	# 2周目: 新しいRunContextで再びゲームを始められる。
	var replay_title := app.current_screen as TitleScreen
	replay_title.door_open_duration = 0.0
	app.active_sensor_provider.input_detected.emit(
		RhythmTypes.InputType.CHEERS
	)
	await process_frame
	expect_equal(
		app.current_screen_id,
		SceneFlow.ScreenId.FACE_CAPTURE,
		"2周目もタイトルから開始できる"
	)

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
