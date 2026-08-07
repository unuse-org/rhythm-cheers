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
	test_cheers_text_transitions(chart)
	test_result_visual_transitions(chart)
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


func test_cheers_text_transitions(chart: RhythmChart) -> void:
	var session := RhythmSession.new()
	root.add_child(session)
	session.configure(chart)

	var visual_scene := load(VISUAL_SCENE_PATH) as PackedScene
	var visual := visual_scene.instantiate() as GameplayVisual
	root.add_child(visual)
	visual.configure(session)

	var first_character := visual.first_cheers_character
	var second_character := visual.second_cheers_character

	expect_true(
		not first_character.visible and not second_character.visible,
		"NORMALでは乾杯文字を表示しない"
	)

	session.change_character_state(RhythmTypes.CharacterState.PREPARE)
	expect_equal(first_character.text, "乾", "PREPAREの1文字目")
	expect_true(first_character.visible, "PREPAREでは乾を表示する")
	expect_true(
		not second_character.visible,
		"PREPAREでは杯を表示しない"
	)

	session.change_character_state(RhythmTypes.CharacterState.JUDGING)
	expect_equal(first_character.text, "乾", "JUDGINGの1文字目")
	expect_equal(second_character.text, "杯", "JUDGINGの2文字目")
	expect_true(
		first_character.visible and second_character.visible,
		"JUDGINGでは乾杯を表示する"
	)

	session.change_character_state(RhythmTypes.CharacterState.SUCCESS)
	expect_equal(first_character.text, "乾", "SUCCESSの1文字目")
	expect_equal(second_character.text, "杯", "SUCCESSの2文字目")
	expect_equal(
		first_character.get_theme_color("font_color"),
		GameplayVisual.SUCCESS_TEXT_COLOR,
		"SUCCESSでは乾杯の色を豪華にする"
	)
	expect_equal(
		second_character.get_theme_constant("outline_size"),
		GameplayVisual.RESULT_OUTLINE_SIZE,
		"SUCCESSでは乾杯の縁取りを強くする"
	)

	session.change_character_state(RhythmTypes.CharacterState.FAILURE)
	expect_equal(first_character.text, "失", "FAILUREの1文字目")
	expect_equal(second_character.text, "杯", "FAILUREの2文字目")
	expect_equal(
		first_character.get_theme_color("font_color"),
		GameplayVisual.FAILURE_TEXT_COLOR,
		"FAILUREでは失の色を変更する"
	)
	expect_equal(
		second_character.get_theme_color("font_color"),
		GameplayVisual.BASE_TEXT_COLOR,
		"FAILUREでも杯は通常色を維持する"
	)

	session.change_character_state(RhythmTypes.CharacterState.NORMAL)
	expect_true(
		not first_character.visible and not second_character.visible,
		"RETURN_NORMALでは乾杯文字を消す"
	)

	visual.free()
	session.free()


func test_result_visual_transitions(chart: RhythmChart) -> void:
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
		visual.player_cheers,
		Vector2(232.0, 890.0),
		Vector2(256.0, 269.0),
		"PlayerCheers"
	)

	expect_texture_name(
		visual.character.texture,
		"character_normal.png",
		"NORMALでは通常の人物画像を表示する"
	)
	expect_true(
		not visual.player_cheers.visible,
		"NORMALではユーザー側ジョッキを表示しない"
	)
	expect_true(
		not visual.cheers_effect.visible,
		"NORMALでは衝突エフェクトを表示しない"
	)

	session.change_character_state(RhythmTypes.CharacterState.PREPARE)
	expect_texture_name(
		visual.character.texture,
		"character_prepare.png",
		"PREPAREでは準備中の人物画像を表示する"
	)
	expect_true(
		not visual.player_cheers.visible,
		"PREPAREではユーザー側ジョッキを表示しない"
	)

	session.change_character_state(RhythmTypes.CharacterState.JUDGING)
	expect_texture_name(
		visual.character.texture,
		"character_cheers.png",
		"JUDGINGでは乾杯中の人物画像を表示する"
	)
	expect_true(
		not visual.player_cheers.visible,
		"JUDGINGではユーザー側ジョッキを表示しない"
	)

	session.change_character_state(RhythmTypes.CharacterState.SUCCESS)
	expect_texture_name(
		visual.player_cheers.texture,
		"player_cheers.png",
		"SUCCESSではユーザー側の手とジョッキ画像を使用する"
	)
	expect_true(visual.player_cheers.visible, "SUCCESSではジョッキを表示する")
	expect_true(
		visual.cheers_effect.visible,
		"SUCCESSでは衝突エフェクトを表示する"
	)
	visual.advance(100.0)
	expect_true(
		visual.player_cheers.visible and visual.cheers_effect.visible,
		"SUCCESSの演出をRETURN_NORMALまで維持する"
	)

	session.change_character_state(RhythmTypes.CharacterState.FAILURE)
	expect_texture_name(
		visual.character.texture,
		"character_normal.png",
		"失敗素材がない間は通常の人物画像を流用する"
	)
	expect_equal(
		visual.character.modulate,
		GameplayVisual.FAILURE_CHARACTER_MODULATE,
		"FAILUREでは人物画像に仮の失敗表現を加える"
	)
	expect_true(
		not visual.player_cheers.visible,
		"FAILUREではユーザー側ジョッキを表示しない"
	)
	expect_true(
		not visual.cheers_effect.visible,
		"FAILUREでは衝突エフェクトを表示しない"
	)

	session.change_character_state(RhythmTypes.CharacterState.NORMAL)
	expect_equal(
		visual.character.modulate,
		Color.WHITE,
		"RETURN_NORMALでは人物画像の色を戻す"
	)
	expect_true(
		not visual.player_cheers.visible,
		"RETURN_NORMALではユーザー側ジョッキを消す"
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
