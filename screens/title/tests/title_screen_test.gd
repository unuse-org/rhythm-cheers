extends SceneTree

const TITLE_SCENE_PATH: String = "res://screens/title/title_screen.tscn"

var failures: Array[String] = []
var completion_count: int = 0
var completion_payload: Dictionary = {}


func _initialize() -> void:
	call_deferred("run_tests")


func run_tests() -> void:
	await test_door_opens_before_completion()
	finish_tests()


func test_door_opens_before_completion() -> void:
	var packed_scene := load(TITLE_SCENE_PATH) as PackedScene
	var screen := packed_scene.instantiate() as TitleScreen
	screen.door_open_duration = 0.5
	screen.screen_completed.connect(_on_screen_completed)
	root.add_child(screen)
	await process_frame

	expect_true(screen.door.texture != null, "居酒屋の扉画像を表示する")
	expect_true(
		screen.action_button.texture_normal != null,
		"Start画像をTextureButtonへ表示する"
	)
	expect_true(
		screen.door_audio_player.stream != null,
		"扉を開く効果音を読み込む"
	)

	screen.receive_sensor_input(RhythmTypes.InputType.CHEERS)
	expect_true(screen.is_opening, "乾杯入力で扉を開き始める")
	expect_true(not screen.action_button.visible, "開始後はStart画像を隠す")
	expect_true(not screen.logo.visible, "開始後はLogo画像を隠す")
	expect_true(screen.door_audio_player.playing, "扉を開く時に効果音を再生する")
	expect_equal(completion_count, 0, "扉の移動中は画面遷移しない")

	# 演出中の連続入力ではTweenや完了通知を増やさない。
	screen.receive_sensor_input(RhythmTypes.InputType.CHEERS)
	screen.door_tween.custom_step(0.6)
	await process_frame

	expect_true(screen.door.position.x < 0.0, "扉を左方向へスライドする")
	expect_equal(completion_count, 1, "扉が開いた後に画面を完了する")
	expect_equal(
		completion_payload.get("door_opened"),
		true,
		"扉が開いたことを完了データへ含める"
	)

	screen.free()
	await process_frame


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
		print("TitleScreen tests passed.")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)

	quit(1)
