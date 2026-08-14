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
	test_character_bobs_on_beat(chart)
	test_opponent_scroll_transitions(chart)
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
	expect_equal(session.cheers_success_count, 1, "成功回数を記録する")
	expect_equal(session.cheers_failure_count, 0, "成功時は失敗回数を増やさない")

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
	expect_equal(session.cheers_success_count, 0, "MISS時は成功回数を増やさない")
	expect_equal(session.cheers_failure_count, 1, "MISS回数を記録する")

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

	var kan_image := visual.cheers_kan
	var pai_image := visual.cheers_pai
	var success_image := visual.cheers_success
	var failure_overlay := visual.cheers_failure_overlay

	expect_true(
		not kan_image.visible
		and not pai_image.visible
		and not success_image.visible
		and not failure_overlay.visible,
		"NORMALでは乾杯文字を表示しない"
	)

	session.change_character_state(RhythmTypes.CharacterState.PREPARE)
	expect_texture_name(
		kan_image.texture,
		"cheers_text_kan.png",
		"乾の画像素材を使用する"
	)
	expect_true(kan_image.visible, "PREPAREでは乾を表示する")
	expect_true(
		not pai_image.visible,
		"PREPAREでは杯を表示しない"
	)

	session.change_character_state(RhythmTypes.CharacterState.JUDGING)
	expect_texture_name(
		pai_image.texture,
		"cheers_text_pai.png",
		"杯の画像素材を使用する"
	)
	expect_true(
		kan_image.visible and pai_image.visible,
		"JUDGINGでは乾杯を表示する"
	)
	expect_true(
		not failure_overlay.visible,
		"JUDGINGでは失敗印を表示しない"
	)

	session.change_character_state(RhythmTypes.CharacterState.SUCCESS)
	expect_texture_name(
		success_image.texture,
		"cheers_success.png",
		"成功専用の乾杯画像を使用する"
	)
	expect_true(
		not kan_image.visible
		and not pai_image.visible
		and success_image.visible
		and not failure_overlay.visible,
		"SUCCESSでは成功専用の乾杯画像へ切り替える"
	)

	session.change_character_state(RhythmTypes.CharacterState.FAILURE)
	expect_texture_name(
		failure_overlay.texture,
		"cheers_failure_overlay.png",
		"失敗印の画像素材を使用する"
	)
	expect_true(
		kan_image.visible
		and pai_image.visible
		and not success_image.visible
		and failure_overlay.visible,
		"FAILUREでは乾杯の上に失敗印を表示する"
	)
	expect_equal(
		failure_overlay.get_parent(),
		kan_image,
		"失敗印を乾の子として重ねる"
	)

	session.change_character_state(RhythmTypes.CharacterState.NORMAL)
	expect_true(
		not kan_image.visible
		and not pai_image.visible
		and not success_image.visible
		and not failure_overlay.visible,
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
		visual.character,
		Vector2(150.5, 96.0),
		Vector2(419.0, 744.0),
		"Character"
	)
	expect_control_rect(
		visual.opponent_stations[0].get_node("Table") as Control,
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


func test_character_bobs_on_beat(chart: RhythmChart) -> void:
	var session := RhythmSession.new()
	root.add_child(session)
	session.configure(chart)

	var visual_scene := load(VISUAL_SCENE_PATH) as PackedScene
	var visual := visual_scene.instantiate() as GameplayVisual
	root.add_child(visual)
	visual.configure(session)

	var base_position := visual.character.position
	var half_beat_time := session.timing.beat_to_seconds(0.5)
	var expected_peak := (
		base_position + Vector2(0.0, -visual.character_bob_amplitude)
	)

	visual.advance(half_beat_time)
	expect_vector_approx(
		visual.character.position,
		expected_peak,
		"NORMALでは拍に合わせて人物が上へ動く"
	)

	visual.advance(half_beat_time)
	expect_vector_approx(
		visual.character.position,
		expected_peak,
		"同じ曲時刻では人物位置が変化しない"
	)

	var static_states: Array[RhythmTypes.CharacterState] = [
		RhythmTypes.CharacterState.PREPARE,
		RhythmTypes.CharacterState.JUDGING,
		RhythmTypes.CharacterState.SUCCESS,
		RhythmTypes.CharacterState.FAILURE,
	]

	for state: RhythmTypes.CharacterState in static_states:
		session.change_character_state(state)
		visual.advance(half_beat_time)
		expect_vector_approx(
			visual.character.position,
			base_position,
			"%sでは人物を基準位置に固定する"
			% RhythmTypes.CharacterState.keys()[state]
		)

	session.change_character_state(RhythmTypes.CharacterState.NORMAL)
	visual.advance(half_beat_time)
	expect_vector_approx(
		visual.character.position,
		expected_peak,
		"NORMALへ戻ると人物の上下動を再開する"
	)

	visual.free()
	session.free()


func test_opponent_scroll_transitions(chart: RhythmChart) -> void:
	var session := RhythmSession.new()
	root.add_child(session)
	session.configure(chart)

	var visual_scene := load(VISUAL_SCENE_PATH) as PackedScene
	var visual := visual_scene.instantiate() as GameplayVisual
	root.add_child(visual)
	visual.configure(session)

	expect_equal(visual.opponent_count, 4, "PREPAREの数だけ乾杯相手を作る")
	expect_equal(
		visual.opponent_stations.size(),
		4,
		"乾杯相手のノード数"
	)
	expect_equal(
		visual.movement_segments.size(),
		3,
		"乾杯相手間の移動区間数"
	)

	for index: int in visual.opponent_stations.size():
		var station := visual.opponent_stations[index]
		expect_vector_approx(
			station.position,
			Vector2(visual.opponent_spacing * index, 0.0),
			"乾杯相手%dの配置" % index
		)

	var first_character := visual.character
	var prepare_time := session.timing.beat_to_seconds(1.0)
	var cheers_time := session.timing.beat_to_seconds(2.0)
	var return_time := session.timing.beat_to_seconds(3.0)

	session.advance(prepare_time)
	session.advance(cheers_time - RhythmSession.MISS_WINDOW + 0.001)
	session.receive_input(RhythmTypes.InputType.CHEERS, cheers_time)
	session.advance(return_time)
	visual.advance(return_time)

	expect_equal(
		visual.active_opponent_index,
		1,
		"乾杯終了後に次の相手を操作対象にする"
	)
	expect_true(
		first_character != visual.character,
		"乾杯ごとに別の人物ノードへ切り替える"
	)
	expect_vector_approx(
		visual.world.position,
		visual.world_base_position,
		"RETURN_NORMALの時点では元の相手の位置にいる"
	)

	var movement_middle_time := session.timing.beat_to_seconds(4.0)
	var expected_middle := (
		visual.world_base_position
		+ Vector2(-visual.opponent_spacing * 0.5, 0.0)
	)
	visual.advance(movement_middle_time)
	expect_vector_approx(
		visual.world.position,
		expected_middle,
		"次のPREPAREまでの中間で相手間の中央へ移動する"
	)
	visual.advance(movement_middle_time)
	expect_vector_approx(
		visual.world.position,
		expected_middle,
		"同じ曲時刻ではスクロール位置が変化しない"
	)

	var next_prepare_time := session.timing.beat_to_seconds(5.0)
	session.advance(next_prepare_time)
	visual.advance(next_prepare_time)
	var next_opponent_position := (
		visual.world_base_position
		+ Vector2(-visual.opponent_spacing, 0.0)
	)
	expect_vector_approx(
		visual.world.position,
		next_opponent_position,
		"次のPREPAREで次の相手を中央に配置する"
	)

	visual.advance(session.timing.beat_to_seconds(5.5))
	expect_vector_approx(
		visual.world.position,
		next_opponent_position,
		"PREPARE中は横移動を停止する"
	)

	var last_prepare_time := session.timing.beat_to_seconds(12.0)
	session.advance(last_prepare_time)
	visual.advance(last_prepare_time)
	expect_equal(
		visual.active_opponent_index,
		3,
		"曲時刻を進めても譜面から正しい相手を復元する"
	)
	expect_vector_approx(
		visual.world.position,
		visual.world_base_position
		+ Vector2(-visual.opponent_spacing * 3.0, 0.0),
		"終盤では最後の相手を中央に配置する"
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


func expect_vector_approx(
	actual: Vector2,
	expected: Vector2,
	message: String
) -> void:
	if not actual.is_equal_approx(expected):
		failures.append(
			"%s: expected=%s actual=%s" % [message, expected, actual]
		)


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
