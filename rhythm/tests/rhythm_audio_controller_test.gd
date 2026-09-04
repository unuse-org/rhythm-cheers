extends SceneTree

const CHART_PATH: String = "res://rhythm/charts/kanpai_chart.json"

var failures: Array[String] = []
var played_beats: Array[float] = []
var played_offsets: Array[float] = []


func _initialize() -> void:
	call_deferred("run_tests")


func run_tests() -> void:
	var controller := create_controller()
	expect_equal(
		controller.base_music_player.volume_db,
		6.0,
		"BGMを+6 dBで再生する"
	)
	for cue_player: AudioStreamPlayer in controller.cue_players:
		expect_equal(
			cue_player.volume_db,
			6.0,
			"Cue音を+6 dBで再生する"
		)
	var full_chart := RhythmChart.load_from_file(CHART_PATH)
	var tutorial_chart := full_chart.create_section("tutorial", true)
	expect_true(
		ResourceLoader.exists(tutorial_chart.audio_path),
		"Tutorial専用音源が存在する"
	)
	expect_true(controller.configure(tutorial_chart), "Tutorial Chartを設定する")
	expect_near(
		controller.calculate_audio_shortfall(12.0),
		13.714,
		"短いTutorial音源の不足秒数を検出する"
	)
	controller.cue_played.connect(_on_cue_played)
	controller.start(0.0)

	controller.set_simulated_song_time(0.0)
	expect_equal(played_beats, [0.0], "最初のワンを0拍目で再生する")
	controller.set_simulated_song_time(
		controller.timing.beat_to_seconds(1.0)
	)
	expect_equal(played_beats, [0.0, 1.0], "2拍目のツーを再生する")

	var late_time := controller.timing.beat_to_seconds(2.0) + 0.05
	controller.set_simulated_song_time(late_time)
	expect_equal(played_beats, [0.0, 1.0, 2.0], "3拍目の乾杯を再生する")
	expect_near(played_offsets.back(), 0.05, "遅れたCueを途中から再生する")

	var main_chart := full_chart.create_section("main", true)
	expect_true(
		ResourceLoader.exists(main_chart.audio_path),
		"Main専用音源が存在する"
	)
	expect_true(controller.configure(main_chart), "Main Chartへ切り替える")
	expect_equal(controller.chart.cues[0]["measure"], 16, "Mainは16小節目から")
	expect_equal(controller.chart.cues[0]["beat"], 12.0, "Main先頭Cueは12拍後")
	played_beats.clear()
	played_offsets.clear()
	controller.start(0.0)
	var main_cue_time := controller.timing.beat_to_seconds(12.0)
	expect_near(main_cue_time, 5.143, "本編先頭CueをDAWの12拍目へ合わせる")
	expect_near(
		controller.timing.beat_to_seconds(15.0),
		6.429,
		"本編最初の杯をDAWの15拍目へ合わせる"
	)
	controller.set_simulated_song_time(main_cue_time - 0.001)
	expect_true(played_beats.is_empty(), "リードイン中はCueを再生しない")
	controller.set_simulated_song_time(main_cue_time + 0.05)
	expect_equal(played_beats.back(), 12.0, "12拍後に本番先頭Cueを再生する")
	expect_near(played_offsets.back(), 0.05, "Cueの遅れをoffsetへ反映する")

	controller.free()
	finish_tests()


func create_controller() -> RhythmAudioController:
	var controller := RhythmAudioController.new()
	controller.playback_enabled = false
	var base := AudioStreamPlayer.new()
	base.name = "BaseMusicPlayer"
	controller.add_child(base)
	var cue_a := AudioStreamPlayer.new()
	cue_a.name = "CuePlayerA"
	controller.add_child(cue_a)
	var cue_b := AudioStreamPlayer.new()
	cue_b.name = "CuePlayerB"
	controller.add_child(cue_b)
	root.add_child(controller)
	return controller


func _on_cue_played(beat: float, _path: String, start_offset: float) -> void:
	played_beats.append(beat)
	played_offsets.append(start_offset)


func expect_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s: expected=%s actual=%s" % [message, expected, actual])


func expect_near(actual: float, expected: float, message: String) -> void:
	if absf(actual - expected) > 0.001:
		failures.append("%s: expected=%.3f actual=%.3f" % [message, expected, actual])


func finish_tests() -> void:
	if failures.is_empty():
		print("RhythmAudioController tests passed.")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
