extends SceneTree

const EPSILON: float = 0.0001
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_tests")


func run_tests() -> void:
	var timing := RhythmTiming.new(
		[
			{"beat": 0.0, "bpm": 140.0},
			{"beat": 128.0, "bpm": 120.0},
			{"beat": 144.0, "bpm": 130.0},
			{"beat": 176.0, "bpm": 140.0},
			{"beat": 208.0, "bpm": 150.0},
		],
		0.0
	)
	expect_near(timing.beat_to_seconds(0.0), 0.0, "1小節目")
	expect_near(timing.beat_to_seconds(60.0), 25.7142857, "16小節目")
	expect_near(timing.beat_to_seconds(128.0), 54.8571429, "33小節目")
	expect_near(timing.beat_to_seconds(144.0), 62.8571429, "37小節目")
	expect_near(timing.beat_to_seconds(176.0), 77.6263736, "45小節目")
	expect_near(timing.beat_to_seconds(208.0), 91.3406593, "53小節目")
	expect_near(timing.beat_to_seconds(240.0), 104.1406593, "曲終了")

	for beat: float in [0.0, 60.0, 127.5, 128.0, 143.5, 144.0, 240.0]:
		expect_near(
			timing.seconds_to_beats(timing.beat_to_seconds(beat)),
			beat,
			"拍と秒を往復する: %.1f" % beat
		)
	expect_near(timing.get_bpm_at_beat(143.0), 120.0, "BPM120区間")
	expect_near(timing.get_bpm_at_beat(144.0), 130.0, "BPM130境界")
	finish_tests()


func expect_near(actual: float, expected: float, message: String) -> void:
	if absf(actual - expected) > EPSILON:
		failures.append(
			"%s: expected=%.6f actual=%.6f" % [message, expected, actual]
		)


func finish_tests() -> void:
	if failures.is_empty():
		print("RhythmTiming tests passed.")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
