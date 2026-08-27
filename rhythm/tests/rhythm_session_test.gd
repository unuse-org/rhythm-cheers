extends SceneTree

var failures: Array[String] = []
var resolved_beats: Array[float] = []
var judgements: Array[String] = []


func _initialize() -> void:
	call_deferred("run_tests")


func run_tests() -> void:
	test_prepare_image_follows_kan_syllable()
	test_asymmetric_success_window()
	test_double_cheers_success()
	test_double_cheers_overlap_selects_nearest_target()
	test_double_cheers_accepts_late_boundary()
	test_first_miss_does_not_overwrite_second_target()
	test_frame_skip_resolves_both_misses()
	finish_tests()


func test_prepare_image_follows_kan_syllable() -> void:
	var chart := RhythmChart.new()
	chart.offset = 0.0
	chart.tempo_changes = [{"beat": 0.0, "bpm": 120.0}]
	chart.events = [
		{"beat": 2.0, "type": RhythmTypes.EventType.PREPARE},
		{
			"beat": 3.0,
			"type": RhythmTypes.EventType.EXPECT_CHEERS,
			"show_state": false,
		},
		{"beat": 3.0, "type": RhythmTypes.EventType.SHOW_CHEERS},
		{"beat": 4.0, "type": RhythmTypes.EventType.RETURN_NORMAL},
	]
	var session := RhythmSession.new()
	session.configure(chart)

	var prepare_time := session.timing.beat_to_seconds(2.0)
	var target_time := session.timing.beat_to_seconds(3.0)
	session.advance(prepare_time)
	expect_equal(
		session.character_state,
		RhythmTypes.CharacterState.PREPARE,
		"乾でPREPARE画像へ切り替える"
	)
	session.advance(target_time - RhythmSession.EARLY_SUCCESS_WINDOW)
	expect_equal(session.input_expected, true, "杯の前から入力窓を開く")
	expect_equal(
		session.character_state,
		RhythmTypes.CharacterState.PREPARE,
		"入力窓が開いても杯まではPREPAREを維持する"
	)
	session.advance(target_time)
	expect_equal(
		session.character_state,
		RhythmTypes.CharacterState.JUDGING,
		"杯でJUDGING画像へ切り替える"
	)

	session.configure(chart)
	var early_input_time := (
		target_time - RhythmSession.EARLY_SUCCESS_WINDOW + 0.001
	)
	session.advance(early_input_time)
	session.receive_input(
		RhythmTypes.InputType.CHEERS,
		early_input_time
	)
	session.advance(target_time)
	expect_equal(
		session.character_state,
		RhythmTypes.CharacterState.SUCCESS,
		"早めの成功画像を杯イベントで上書きしない"
	)
	session.free()


func test_asymmetric_success_window() -> void:
	var early_session := create_single_session()
	var target_time := early_session.timing.beat_to_seconds(2.0)
	early_session.receive_input(
		RhythmTypes.InputType.CHEERS,
		target_time - RhythmSession.EARLY_SUCCESS_WINDOW
	)
	expect_equal(early_session.cheers_success_count, 1, "早い側-0.20秒を成功にする")
	early_session.free()

	var late_session := create_single_session()
	target_time = late_session.timing.beat_to_seconds(2.0)
	late_session.receive_input(
		RhythmTypes.InputType.CHEERS,
		target_time + RhythmSession.LATE_SUCCESS_WINDOW
	)
	expect_equal(late_session.cheers_success_count, 1, "遅い側+0.30秒を成功にする")
	late_session.free()

	var missed_session := create_single_session()
	target_time = missed_session.timing.beat_to_seconds(2.0)
	missed_session.advance(
		target_time + RhythmSession.LATE_SUCCESS_WINDOW + 0.001
	)
	expect_equal(missed_session.cheers_failure_count, 1, "+0.30秒経過後はMISSにする")
	missed_session.free()


func test_double_cheers_success() -> void:
	var session := create_double_session()
	var first_target := session.timing.beat_to_seconds(2.0)
	var second_target := session.timing.beat_to_seconds(3.0)

	session.advance(first_target - RhythmSession.EARLY_SUCCESS_WINDOW)
	expect_equal(session.pending_inputs.size(), 1, "1回目の受付を開く")
	session.receive_input(RhythmTypes.InputType.CHEERS, first_target)
	session.advance(second_target - RhythmSession.EARLY_SUCCESS_WINDOW)
	session.receive_input(RhythmTypes.InputType.CHEERS, second_target)

	expect_equal(session.cheers_success_count, 2, "2連乾杯を2成功として数える")
	expect_equal(session.cheers_failure_count, 0, "成功時は失敗を増やさない")
	expect_equal(resolved_beats, [2.0, 3.0], "入力を拍順に解決する")
	session.free()


func test_double_cheers_overlap_selects_nearest_target() -> void:
	var session := create_double_session()
	var first_target := session.timing.beat_to_seconds(2.0)
	var second_target := session.timing.beat_to_seconds(3.0)
	# BPM150では2つの成功範囲が0.10秒重なる。第2対象に近い時刻を使う。
	var overlap_input_time := second_target - 0.15
	session.receive_input(RhythmTypes.InputType.CHEERS, overlap_input_time)

	expect_equal(session.cheers_failure_count, 1, "近い第2対象を選ぶ前に第1対象をMISSにする")
	expect_equal(session.cheers_success_count, 1, "重複窓では近い第2対象を成功にする")
	expect_equal(resolved_beats, [2.0, 3.0], "重複窓でも拍順に結果を通知する")
	expect_equal(session.pending_inputs.size(), 0, "重複窓の対象を両方解決する")
	expect_equal(
		session.character_state,
		RhythmTypes.CharacterState.SUCCESS,
		"先のMISS後も選択した第2対象の成功表示を残す"
	)
	session.free()


func test_double_cheers_accepts_late_boundary() -> void:
	var session := create_double_session()
	var second_target := session.timing.beat_to_seconds(3.0)
	# 2回目の+0.30秒はRETURN_NORMALと同時刻でも成功範囲に含める。
	session.receive_input(
		RhythmTypes.InputType.CHEERS,
		second_target + RhythmSession.LATE_SUCCESS_WINDOW
	)

	expect_equal(session.cheers_failure_count, 1, "未入力の1回目だけをMISSにする")
	expect_equal(session.cheers_success_count, 1, "2回目の+0.30秒を成功にする")
	expect_equal(resolved_beats, [2.0, 3.0], "境界入力でも拍順に結果を通知する")
	expect_equal(
		session.character_state,
		RhythmTypes.CharacterState.SUCCESS,
		"RETURN_NORMALと同時刻でも成功表示を残す"
	)
	session.free()


func test_first_miss_does_not_overwrite_second_target() -> void:
	reset_results()
	var session := create_double_session()
	var first_target := session.timing.beat_to_seconds(2.0)
	var second_target := session.timing.beat_to_seconds(3.0)

	session.advance(first_target - RhythmSession.EARLY_SUCCESS_WINDOW)
	# 第1対象の遅い側の成功範囲を過ぎると、第2対象だけが残る。
	session.advance(first_target + RhythmSession.MISS_WINDOW + 0.001)
	expect_equal(session.cheers_failure_count, 1, "1回目を先にMISS確定する")
	expect_equal(session.current_input_beat, 3.0, "2回目の対象を保持する")
	session.receive_input(RhythmTypes.InputType.CHEERS, second_target)
	expect_equal(session.cheers_success_count, 1, "2回目は成功できる")
	expect_equal(resolved_beats, [2.0, 3.0], "MISSと成功を拍順に通知する")
	session.free()


func test_frame_skip_resolves_both_misses() -> void:
	reset_results()
	var session := create_double_session()
	session.advance(session.timing.beat_to_seconds(4.0))
	expect_equal(session.cheers_failure_count, 2, "フレームを飛ばしても2失敗を数える")
	expect_equal(resolved_beats, [2.0, 3.0], "飛ばした入力も拍順に通知する")
	expect_equal(
		session.character_state,
		RhythmTypes.CharacterState.NORMAL,
		"RETURN_NORMALまで時刻順に実行する"
	)
	session.free()


func create_double_session() -> RhythmSession:
	reset_results()
	var chart := RhythmChart.from_dictionary({
		"bpm": 150.0,
		"offset": 0.0,
		"events": [
			{"beat": 0.0, "type": "PREPARE"},
			{"beat": 2.0, "type": "EXPECT_CHEERS"},
			{"beat": 3.0, "type": "EXPECT_CHEERS"},
			{"beat": 3.75, "type": "RETURN_NORMAL"},
		],
	})
	var session := RhythmSession.new()
	session.configure(chart)
	session.input_resolved.connect(_on_input_resolved)
	return session


func create_single_session() -> RhythmSession:
	reset_results()
	var chart := RhythmChart.from_dictionary({
		"bpm": 120.0,
		"offset": 0.0,
		"events": [
			{"beat": 2.0, "type": "EXPECT_CHEERS"},
			{"beat": 3.0, "type": "RETURN_NORMAL"},
		],
	})
	var session := RhythmSession.new()
	session.configure(chart)
	session.input_resolved.connect(_on_input_resolved)
	return session


func reset_results() -> void:
	resolved_beats.clear()
	judgements.clear()


func _on_input_resolved(
	beat: float,
	_input_type: RhythmTypes.InputType,
	judgement: String
) -> void:
	resolved_beats.append(beat)
	judgements.append(judgement)


func expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s: expected=%s actual=%s" % [message, expected, actual])


func finish_tests() -> void:
	if failures.is_empty():
		print("RhythmSession tests passed.")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
