extends SceneTree

const MAIN_SCENE_PATH: String = "res://main/main.tscn"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_tests")


func run_tests() -> void:
	await test_main_waits_for_start_sequence()
	finish_tests()


func test_main_waits_for_start_sequence() -> void:
	var main_scene := load(MAIN_SCENE_PATH) as PackedScene
	var main := main_scene.instantiate()
	main.set("start_delay_seconds", 0.05)
	main.call("setup", RunContext.new())
	root.add_child(main)
	await process_frame

	var music_player := main.get_node("MusicPlayer") as AudioStreamPlayer
	var rhythm_session := main.get_node("RhythmSession") as RhythmSession
	var start_overlay := main.get_node("StartOverlay") as Control

	expect_true(not main.get("is_game_started"), "開始表示中はゲームを止める")
	expect_true(not music_player.playing, "開始表示中は音楽を止める")
	expect_true(start_overlay.visible, "本番スタート表示を見せる")

	main.call(
		"receive_sensor_input",
		RhythmTypes.InputType.CHEERS
	)
	expect_equal(rhythm_session.last_judgement, "-", "開始前の入力を無視する")

	await create_timer(0.08).timeout
	expect_true(main.get("is_game_started"), "待機後にゲームを開始する")
	expect_true(music_player.playing, "待機後に音楽を開始する")
	expect_true(not start_overlay.visible, "開始時に表示を消す")
	expect_true(main.is_processing(), "開始時に譜面進行を有効化する")

	# 音声スレッドの終了を待ってからテストプロセスを閉じる。
	music_player.stop()
	music_player.stream = null
	await create_timer(0.1).timeout
	main.free()
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
		print("Main start tests passed.")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)

	quit(1)
