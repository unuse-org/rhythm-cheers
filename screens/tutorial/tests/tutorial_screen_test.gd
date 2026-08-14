extends SceneTree

const TUTORIAL_SCENE_PATH: String = (
	"res://screens/tutorial/tutorial_screen.tscn"
)
const SUCCESS_BEATS: Array[float] = [2.0, 6.0, 10.0]

var failures: Array[String] = []
var completion_count: int = 0
var completion_payload: Dictionary = {}


func _initialize() -> void:
	call_deferred("run_tests")


func run_tests() -> void:
	await test_tutorial_uses_full_track_and_clear_sequence()
	finish_tests()


func test_tutorial_uses_full_track_and_clear_sequence() -> void:
	var tutorial_scene := load(TUTORIAL_SCENE_PATH) as PackedScene
	var tutorial := tutorial_scene.instantiate() as TutorialScreen
	var context := RunContext.new()
	context.cheers_success_count = 7
	context.cheers_failure_count = 2
	tutorial.setup(context)
	tutorial.music_enabled = false
	tutorial.clear_display_duration = 0.0
	tutorial.screen_completed.connect(_on_screen_completed)
	root.add_child(tutorial)
	tutorial.set_process(false)

	expect_true(
		not tutorial.intro_overlay.visible,
		"テスト時は開始案内を待たずに練習を開始する"
	)
	expect_true(tutorial.progress_panel.visible, "プレイ中は進捗を表示する")
	expect_equal(tutorial.progress_label.text, "0 / 3", "初期進捗の表示")

	var first_target_time := tutorial.rhythm_session.timing.beat_to_seconds(
		SUCCESS_BEATS[0]
	)
	var first_miss_time := (
		first_target_time + RhythmSession.MISS_WINDOW + 0.001
	)
	var tutorial_end_time := tutorial.rhythm_session.timing.beat_to_seconds(
		tutorial.tutorial_end_beat
	)

	# 成功数が足りない場合は短区間ではなく、曲全体を最初からやり直す。
	tutorial.advance_tutorial(first_miss_time)
	expect_equal(
		tutorial.rhythm_session.cheers_failure_count,
		1,
		"入力がなければ練習を失敗として判定する"
	)
	expect_equal(
		tutorial.notice_label.visible,
		false,
		"通常の失敗時は文章を表示しない"
	)
	tutorial.advance_tutorial(tutorial_end_time)
	expect_equal(tutorial.tutorial_run_count, 1, "曲全体の再挑戦回数")
	expect_equal(tutorial.tutorial_success_count, 0, "再挑戦時に成功数を戻す")
	expect_equal(
		tutorial.notice_label.text,
		"もう一度練習しよう",
		"再挑戦時の案内"
	)
	expect_true(tutorial.notice_label.visible, "再挑戦時だけ案内を表示する")
	tutorial.hide_notice()
	expect_true(not tutorial.is_completed, "成功数不足では完了しない")

	# 再挑戦した曲の中で3回成功しても、曲の区切りまでは継続する。
	for expected_success_count: int in range(1, SUCCESS_BEATS.size() + 1):
		var target_time := tutorial.rhythm_session.timing.beat_to_seconds(
			SUCCESS_BEATS[expected_success_count - 1]
		)
		var input_open_time := (
			target_time - RhythmSession.MISS_WINDOW + 0.001
		)

		tutorial.advance_tutorial(input_open_time)
		tutorial.receive_sensor_input_at(
			RhythmTypes.InputType.CHEERS,
			target_time
		)
		expect_equal(
			tutorial.tutorial_success_count,
			expected_success_count,
			"一曲内の成功回数を記録する"
		)
		expect_equal(
			tutorial.progress_label.text,
			"%d / 3" % expected_success_count,
			"成功回数を進捗へ反映する"
		)

		expect_true(
			not tutorial.notice_label.visible,
			"成功時は文章を表示しない"
		)

	expect_true(
		not tutorial.is_completed,
		"3回成功しても曲の終了前には遷移しない"
	)
	tutorial.advance_tutorial(tutorial_end_time)

	expect_true(tutorial.clear_overlay.visible, "完了前にクリア表示を出す")
	expect_equal(
		(tutorial.get_node("ClearOverlay/ClearMessage") as Label).text,
		"3回成功！\n本番へ",
		"クリア時に本番への遷移を伝える"
	)
	expect_true(tutorial.is_completed, "クリア表示後にチュートリアルを完了する")
	expect_equal(completion_count, 1, "完了通知を1回だけ送る")
	expect_equal(
		completion_payload.get("tutorial_completed"),
		true,
		"完了データにチュートリアル結果を含める"
	)

	# 練習結果は本番リザルト用の値へ混ぜない。
	expect_equal(context.cheers_success_count, 7, "本番成功数を変更しない")
	expect_equal(context.cheers_failure_count, 2, "本番失敗数を変更しない")

	tutorial.finish_tutorial_track()
	expect_equal(completion_count, 1, "完了後に通知を重複させない")
	tutorial.free()
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
		print("TutorialScreen tests passed.")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)

	quit(1)
