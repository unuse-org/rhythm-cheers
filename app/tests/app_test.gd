extends SceneTree

const APP_SCENE_PATH: String = "res://app/app.tscn"
const MAIN_SCENE_PATH: String = "res://main/main.tscn"

class FakeCharacterImageSet:
	extends Resource

	var normal: Image


class FakePlayerCountStore:
	extends PlayerCountStore

	var total_count: int = 40
	var record_call_count: int = 0


	func record_player() -> int:
		record_call_count += 1
		total_count += 1
		return total_count


var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_tests")


func run_tests() -> void:
	await test_app_flow()
	test_sensor_provider_ownership()
	await test_escape_returns_to_title()
	finish_tests()


func test_app_flow() -> void:
	var app_scene := load(APP_SCENE_PATH) as PackedScene
	var app := app_scene.instantiate() as RhythmCheersApp
	# 実機用Sceneの既定値に依存せず、テスト入力を直接送れるProviderを使う。
	app.sensor_mode = RhythmCheersApp.SensorMode.KEYBOARD
	var player_count_store := FakePlayerCountStore.new()
	app.player_count_store = player_count_store
	root.add_child(app)
	await process_frame
	# 共通音楽は疑似時刻で進め、実音声と実時間へ依存させない。
	app.rhythm_audio_controller.playback_enabled = false

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
	var tutorial_success_beats: Array[float] = [3.0, 7.0, 11.0]

	for success_beat: float in tutorial_success_beats:
		var target_time := tutorial.rhythm_session.timing.beat_to_seconds(
			success_beat
		)
		var input_open_time := (
			target_time - RhythmSession.EARLY_SUCCESS_WINDOW + 0.001
		)

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
	# Tutorial完了後は本番音源を開始し、リードイン中は開始表示を維持する。
	expect_true(
		not main_screen.get("is_game_started"),
		"Main遷移直後はゲーム入力を開始しない"
	)
	expect_true(
		app.rhythm_audio_controller.running,
		"Main専用音源を開始する"
	)
	expect_true(
		app.rhythm_audio_controller.chart.audio_path.ends_with(
			"OffVocal_本番.mp3"
		),
		"Main用Controllerへ本番音源を設定する"
	)
	expect_true(
		(main_screen.get_node("StartOverlay") as Control).visible,
		"リードイン中は本番スタートを表示する"
	)
	var gameplay_start_time: float = main_screen.get("gameplay_start_time")
	main_screen.call("advance_main", gameplay_start_time - 0.001)
	expect_true(
		not main_screen.get("is_game_started"),
		"規定拍より前は入力を開始しない"
	)
	main_screen.call("advance_main", gameplay_start_time)
	expect_true(
		main_screen.get("is_game_started"),
		"規定拍でMainのゲーム進行を開始する"
	)
	rhythm_session.cheers_success_count = 3
	rhythm_session.cheers_failure_count = 1
	var result_character_image := Image.create(
		2,
		2,
		false,
		Image.FORMAT_RGBA8
	)
	result_character_image.fill(Color.RED)
	var generated_images := FakeCharacterImageSet.new()
	generated_images.normal = result_character_image
	app.run_context.generated_character_images = generated_images
	app.run_context.character_generation_succeeded = true
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
	expect_equal(app.run_context.player_number, 41, "累計41人目を割り当てる")
	expect_equal(
		player_count_store.record_call_count,
		1,
		"Mainの重複完了通知でも人数を一度だけ加算する"
	)
	expect_equal(app.run_context.calculate_success_amount(), 1500, "成功金額")
	expect_equal(app.run_context.calculate_failure_amount(), -50, "失敗金額")
	expect_equal(app.run_context.calculate_total_amount(), 1450, "合計金額")
	expect_true(
		not is_instance_valid(main_screen),
		"メイン画面を遷移後に破棄する"
	)

	var result_screen := app.current_screen as ResultScreen
	expect_true(
		result_screen.result_audio_player.playing,
		"レシート表示時に会計の効果音を再生する"
	)
	expect_true(
		not result_screen.music_player.playing,
		"会計の効果音が鳴っている間はリザルトBGMを再生しない"
	)
	result_screen.result_audio_player.stop()
	result_screen.result_audio_player.finished.emit()
	expect_true(
		result_screen.music_player.playing,
		"会計の効果音が終了した後にリザルトBGMを再生する"
	)
	expect_equal(
		result_screen.success_count_label.text,
		"3",
		"リザルト画面に乾杯数を表示する"
	)
	expect_equal(
		result_screen.success_amount_label.text,
		"1500円",
		"リザルト画面に乾杯金額を表示する"
	)
	expect_equal(
		result_screen.failure_count_label.text,
		"1",
		"リザルト画面に失杯数を表示する"
	)
	expect_equal(
		result_screen.failure_amount_label.text,
		"-50円",
		"リザルト画面に失杯金額を表示する"
	)
	expect_equal(
		result_screen.total_amount_label.text,
		"1450円",
		"リザルト画面に合計金額を表示する"
	)
	expect_equal(
		result_screen.player_count_label.text,
		"No 041",
		"リザルト画面に累計人数を表示する"
	)
	expect_true(
		result_screen.face_preview.texture != null,
		"リザルト画面にNORMAL生成画像を表示する"
	)
	expect_equal(
		result_screen.face_preview.texture.get_image().get_pixel(0, 0),
		Color.RED,
		"撮影画像ではなくNORMAL生成画像を利用する"
	)

	# 実時間を待たず、Resultの5秒入力待機完了を再現する。
	result_screen.input_accept_timer.stop()
	result_screen.input_accept_timer.timeout.emit()
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
	expect_equal(app.run_context.player_number, 0, "累計人数の表示値を初期化する")
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


func test_escape_returns_to_title() -> void:
	var app_scene := load(APP_SCENE_PATH) as PackedScene
	var app := app_scene.instantiate() as RhythmCheersApp
	app.sensor_mode = RhythmCheersApp.SensorMode.KEYBOARD
	root.add_child(app)
	await process_frame
	app.rhythm_audio_controller.playback_enabled = false

	# 実行中の本番画面からEscを押した状態を作る。
	app.show_screen(SceneFlow.ScreenId.MAIN)
	await process_frame
	app.run_context.cheers_success_count = 4
	app.run_context.tutorial_completed = true
	var previous_context := app.run_context

	var escape_event := InputEventKey.new()
	escape_event.keycode = KEY_ESCAPE
	escape_event.pressed = true
	# Appの_inputまで実際の入力配信経路で届くことを確認する。
	Input.parse_input_event(escape_event)
	await process_frame

	expect_equal(
		app.current_screen_id,
		SceneFlow.ScreenId.TITLE,
		"Escapeでタイトルへ強制帰還する"
	)
	expect_true(
		not app.rhythm_audio_controller.running,
		"強制帰還時にリズム音源を停止する"
	)
	expect_true(
		app.run_context != previous_context,
		"強制帰還時にRunContextを作り直す"
	)
	expect_equal(
		app.run_context.cheers_success_count,
		0,
		"強制帰還時にプレイ結果を破棄する"
	)
	expect_true(
		not app.run_context.tutorial_completed,
		"強制帰還時にチュートリアル状態を破棄する"
	)

	app.free()
	await process_frame


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
