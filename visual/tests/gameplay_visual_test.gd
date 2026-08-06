extends SceneTree

const CHART_PATH: String = "res://rhythm/charts/test_chart.json"
const VISUAL_SCENE_PATH: String = "res://visual/gameplay_visual.tscn"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_tests")


func run_tests() -> void:
	var chart := RhythmChart.load_from_file(CHART_PATH)

	if chart == null:
		failures.append("Chartを読み込める")
		finish_tests()
		return

	test_character_follows_chart(chart)
	test_missed_cheers(chart)
	test_player_state_transitions(chart)
	finish_tests()


func test_character_follows_chart(chart: RhythmChart) -> void:
	var session := RhythmSession.new()
	root.add_child(session)
	session.configure(chart)

	var prepare_time: float = session.timing.beat_to_seconds(1.0)
	session.advance(prepare_time - 0.001)
	expect_equal(
		session.character_state,
		RhythmTypes.CharacterState.NORMAL,
		"PREPAREイベントの直前はNORMALを維持する"
	)
	session.advance(prepare_time)
	expect_equal(
		session.character_state,
		RhythmTypes.CharacterState.PREPARE,
		"PREPAREイベントでCharacterがPREPAREになる"
	)
	expect_true(
		not session.input_expected,
		"PREPAREイベントでは入力受付を開始しない"
	)

	var accepted := session.receive_input(
		RhythmTypes.InputType.CHEERS,
		prepare_time
	)
	expect_true(not accepted, "PREPARE中のCHEERS入力を受理しない")
	expect_equal(
		session.character_state,
		RhythmTypes.CharacterState.PREPARE,
		"PREPARE中の入力でCharacter状態を変更しない"
	)

	var cheers_time: float = session.timing.beat_to_seconds(2.0)
	session.advance(cheers_time - RhythmSession.MISS_WINDOW + 0.001)
	expect_equal(
		session.character_state,
		RhythmTypes.CharacterState.JUDGING,
		"EXPECT_CHEERSイベントでCharacterがJUDGINGになる"
	)
	expect_true(session.input_expected, "EXPECT_CHEERSで入力受付を開始する")

	accepted = session.receive_input(
		RhythmTypes.InputType.CHEERS,
		cheers_time
	)
	expect_true(accepted, "判定時間内のCHEERS入力を受理する")
	expect_equal(
		session.character_state,
		RhythmTypes.CharacterState.SUCCESS,
		"CHEERS入力成功時にCharacterがSUCCESSになる"
	)

	session.advance(session.timing.beat_to_seconds(3.0))
	expect_equal(
		session.character_state,
		RhythmTypes.CharacterState.NORMAL,
		"RETURN_NORMALイベントでCharacterがNORMALになる"
	)
	session.free()


func test_missed_cheers(chart: RhythmChart) -> void:
	var session := RhythmSession.new()
	root.add_child(session)
	session.configure(chart)

	var prepare_time: float = session.timing.beat_to_seconds(1.0)
	var cheers_time: float = session.timing.beat_to_seconds(2.0)

	session.advance(prepare_time)
	session.advance(cheers_time - RhythmSession.MISS_WINDOW + 0.001)
	session.advance(cheers_time + RhythmSession.MISS_WINDOW + 0.001)

	expect_equal(
		session.character_state,
		RhythmTypes.CharacterState.FAILURE,
		"CHEERS入力がなければCharacterがFAILUREになる"
	)
	expect_true(
		session.last_judgement.begins_with("MISS"),
		"CHEERS入力がなければMISSを記録する"
	)

	session.advance(session.timing.beat_to_seconds(3.0))
	expect_equal(
		session.character_state,
		RhythmTypes.CharacterState.NORMAL,
		"MISS後もRETURN_NORMALでCharacterがNORMALになる"
	)
	session.free()


func test_player_state_transitions(chart: RhythmChart) -> void:
	var session := RhythmSession.new()
	root.add_child(session)
	session.configure(chart)

	var visual_scene := load(VISUAL_SCENE_PATH) as PackedScene
	var visual := visual_scene.instantiate() as GameplayVisual
	root.add_child(visual)
	visual.configure(session)

	expect_equal(
		visual.size,
		Vector2(720.0, 1280.0),
		"GameplayVisualが基準解像度と一致する"
	)
	expect_control_rect(
		visual.get_node("Character") as Control,
		Vector2(150.5, 96.0),
		Vector2(419.0, 744.0),
		"Character"
	)
	expect_control_rect(
		visual.get_node("Table") as Control,
		Vector2(0.0, 680.0),
		Vector2(720.0, 429.0),
		"Table"
	)
	expect_control_rect(
		visual.get_node("Player") as Control,
		Vector2(232.0, 890.0),
		Vector2(256.0, 269.0),
		"Player"
	)

	expect_texture_name(
		visual.player.texture,
		"player_normal.png",
		"Playerの初期画像がNORMALになる"
	)

	visual.show_player_input(
		RhythmTypes.InputType.CHEERS,
		false,
		10.0
	)
	expect_texture_name(
		visual.player.texture,
		"player_cheers.png",
		"誤入力画像を一時表示する"
	)
	visual.advance(
		10.0 + GameplayVisual.REJECTED_INPUT_DISPLAY_SECONDS + 0.01
	)
	expect_texture_name(
		visual.player.texture,
		"player_normal.png",
		"誤入力後に直前の状態へ戻る"
	)

	visual.show_player_input(
		RhythmTypes.InputType.CHEERS,
		true,
		20.0
	)
	expect_true(visual.cheers_effect.visible, "CHEERS成功時にEffectを表示する")
	visual.advance(20.0 + 60.0 / chart.bpm + 0.001)
	expect_texture_name(
		visual.player.texture,
		"player_normal.png",
		"CHEERS成功から1拍後にNORMALへ戻る"
	)
	expect_true(
		not visual.cheers_effect.visible,
		"CHEERS成功から1拍後にEffectを非表示にする"
	)

	session.start_cheers_window(1.0)
	session.process_missed_input(
		session.timing.beat_to_seconds(1.0)
		+ RhythmSession.MISS_WINDOW
		+ 0.001
	)
	expect_texture_name(
		visual.player.texture,
		"player_normal.png",
		"MISS時にPlayerをNORMALへ戻す"
	)

	visual.show_player_input(
		RhythmTypes.InputType.CHEERS,
		true,
		40.0
	)
	session.change_character_state(RhythmTypes.CharacterState.PREPARE)
	session.change_character_state(RhythmTypes.CharacterState.NORMAL)
	expect_texture_name(
		visual.player.texture,
		"player_normal.png",
		"RETURN_NORMAL時にPlayerもNORMALへ戻す"
	)

	visual.free()
	session.free()


func expect_texture_name(
	texture: Texture2D,
	expected_name: String,
	message: String
) -> void:
	if texture == null or texture.resource_path.get_file() != expected_name:
		var actual_name := "<null>"

		if texture != null:
			actual_name = texture.resource_path.get_file()

		failures.append(
			"%s: expected=%s actual=%s"
			% [message, expected_name, actual_name]
		)


func expect_control_rect(
	control: Control,
	expected_position: Vector2,
	expected_size: Vector2,
	label: String
) -> void:
	expect_equal(control.position, expected_position, "%sの位置" % label)
	expect_equal(control.size, expected_size, "%sのサイズ" % label)


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
		print("GameplayVisual tests passed.")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)

	quit(1)
