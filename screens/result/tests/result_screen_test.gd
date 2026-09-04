extends SceneTree

const RESULT_SCENE_PATH: String = "res://screens/result/result_screen.tscn"

var failures: Array[String] = []
var completion_count: int = 0


func _initialize() -> void:
	call_deferred("run_tests")


func run_tests() -> void:
	await test_input_is_enabled_after_five_seconds()
	finish_tests()


func test_input_is_enabled_after_five_seconds() -> void:
	var packed_scene := load(RESULT_SCENE_PATH) as PackedScene
	var screen := packed_scene.instantiate() as ResultScreen
	screen.screen_completed.connect(_on_screen_completed)
	root.add_child(screen)
	await process_frame

	expect_equal(screen.input_accept_delay, 5.0, "入力受付まで5秒待つ")
	expect_true(not screen.input_enabled, "表示直後は入力を受け付けない")
	expect_true(screen.action_button.disabled, "待機中はボタンを無効にする")
	expect_true(screen.input_accept_timer.time_left > 0.0, "5秒Timerを開始する")

	screen.receive_sensor_input(RhythmTypes.InputType.CHEERS)
	screen.action_button.pressed.emit()
	expect_equal(completion_count, 0, "5秒未満の入力では画面を完了しない")

	# 実時間を待たず、5秒Timerの完了を再現する。
	screen.input_accept_timer.stop()
	screen.input_accept_timer.timeout.emit()
	expect_true(screen.input_enabled, "5秒後に入力受付を有効にする")
	expect_true(not screen.action_button.disabled, "5秒後にボタンを有効にする")

	screen.receive_sensor_input(RhythmTypes.InputType.CHEERS)
	expect_equal(completion_count, 1, "受付開始後の乾杯で画面を完了する")

	screen.free()
	await process_frame
	screen = null
	packed_scene = null
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
		print("ResultScreen tests passed.")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)

	quit(1)
