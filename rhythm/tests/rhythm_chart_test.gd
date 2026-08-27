extends SceneTree

const PRODUCTION_CHART_PATH: String = (
	"res://rhythm/charts/kanpai_chart.json"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_tests")


func run_tests() -> void:
	var chart := RhythmChart.from_dictionary(create_chart_source(), "test")
	expect_true(chart != null, "小節譜面を読み込む")
	if chart != null:
		expect_equal(chart.tempo_changes.size(), 5, "BPM変更数")
		expect_equal(chart.events.size(), 261, "乾・杯表示を含む全イベント数")
		expect_equal(chart.cues.size(), 173, "通常と2連のCue数")
		expect_equal(chart.get_section_start_beat("main"), 60.0, "本編開始拍")
		expect_equal(chart.get_section_end_beat("tutorial"), 60.0, "Tutorial終了拍")

		var tutorial := chart.create_section("tutorial")
		var main := chart.create_section("main")
		var local_main := chart.create_section("main", true)
		expect_equal(tutorial.events.size(), 60, "Tutorialは15小節")
		expect_equal(main.events.size(), 201, "Main区間のイベント数")
		expect_equal(local_main.lead_in_beats, 12.0, "Mainは12拍リードイン")
		expect_equal(local_main.events[0]["beat"], 14.0, "リードイン後の乾")
		expect_equal(local_main.cues[0]["beat"], 12.0, "12拍後にChartを開始")
		expect_equal(local_main.end_beat, 192.0, "Mainはリードインと45小節分")
		expect_equal(
			get_tempo_change_beats(local_main),
			[0.0, 80.0, 96.0, 128.0, 160.0],
			"BPM変更をDAWのMainローカル拍へ移す"
		)
		var local_main_timing := RhythmTiming.new(
			local_main.tempo_changes,
			local_main.offset
		)
		expect_near(
			local_main_timing.beat_to_seconds(12.0),
			5.142857,
			"本番最初のワンをDAW時刻へ合わせる"
		)
		expect_near(
			local_main_timing.beat_to_seconds(15.0),
			6.428571,
			"本番最初の杯をDAW時刻へ合わせる"
		)
		expect_equal(
			local_main.audio_path,
			"res://main.mp3",
			"Main専用音源を選択する"
		)
		expect_equal(count_expect_events(chart, 20), 2, "20小節は2連乾杯")
		expect_equal(count_expect_events(chart, 33), 1, "33小節は通常乾杯")
		expect_equal(count_expect_events(chart, 60), 1, "60小節も通常乾杯")
		expect_equal(
			get_event_beats(chart, 16, RhythmTypes.EventType.PREPARE),
			[62.0],
			"通常は乾でPREPAREへ切り替える"
		)
		expect_equal(
			get_event_beats(chart, 16, RhythmTypes.EventType.EXPECT_CHEERS),
			[63.0],
			"通常は杯を判定拍にする"
		)
		expect_equal(
			get_event_beats(chart, 20, RhythmTypes.EventType.PREPARE),
			[78.0, 79.0],
			"2連は各乾でPREPAREへ切り替える"
		)
		expect_equal(
			get_event_beats(chart, 20, RhythmTypes.EventType.EXPECT_CHEERS),
			[78.5, 79.5],
			"2連は各杯を判定拍にする"
		)
		expect_equal(
			get_event_beats(
				local_main,
				20,
				RhythmTypes.EventType.EXPECT_CHEERS
			),
			[30.5, 31.5],
			"2連乾杯をDAWのMainローカル拍へ移す"
		)
		expect_equal(
			get_event_beats(
				local_main,
				60,
				RhythmTypes.EventType.EXPECT_CHEERS
			),
			[191.0],
			"60小節目の杯をDAWのMainローカル拍へ移す"
		)
		expect_equal(
			count_opponent_starts(chart),
			60,
			"2連でも1小節につき相手は1人"
		)
		expect_equal(get_cue_bpm(chart, 38), 130.0, "38小節はBPM130素材")
		expect_equal(get_cue_bpm(chart, 56), 150.0, "56小節はBPM150素材")

	var production_chart := RhythmChart.load_from_file(PRODUCTION_CHART_PATH)
	expect_true(production_chart != null, "実譜面を読み込む")
	if production_chart != null:
		var production_main := production_chart.create_section("main", true)
		expect_equal(production_chart.offset, 0.0, "実譜面はDAWと同じ0秒開始")
		expect_equal(production_main.lead_in_beats, 12.0, "実譜面は12拍リードイン")
		expect_equal(
			get_tempo_change_beats(production_main),
			[0.0, 80.0, 96.0, 128.0, 160.0],
			"実譜面のBPM変更位置をDAWへ合わせる"
		)
		expect_equal(
			get_event_beats(
				production_main,
				16,
				RhythmTypes.EventType.EXPECT_CHEERS
			),
			[15.0],
			"実譜面の最初の杯をDAWの15拍目へ合わせる"
		)
		expect_equal(
			get_event_beats(
				production_main,
				20,
				RhythmTypes.EventType.EXPECT_CHEERS
			),
			[30.5, 31.5],
			"実譜面の2連乾杯をDAWへ合わせる"
		)
		expect_equal(
			count_expect_events(production_chart, 60),
			1,
			"実譜面に60小節目の乾杯を含める"
		)

	var legacy := RhythmChart.from_dictionary({
		"bpm": 120.0,
		"offset": 0.5,
		"events": [{"beat": 2.0, "type": "EXPECT_CHEERS"}],
	})
	expect_true(legacy != null, "旧形式を引き続き読み込む")
	if legacy != null:
		expect_equal(legacy.tempo_changes.size(), 1, "旧形式のtempo map")
	finish_tests()


func create_chart_source() -> Dictionary:
	var cue_sets := {}
	for bpm: int in [120, 130, 140, 150]:
		cue_sets[str(bpm)] = {
			"count_1": "res://%d/1.mp3" % bpm,
			"count_2": "res://%d/2.mp3" % bpm,
			"cheers": "res://%d/cheers.mp3" % bpm,
			"count_double": "res://%d/count_double.mp3" % bpm,
			"cheers_double": "res://%d/cheers_double.mp3" % bpm,
		}
	return {
		"audio": {
			"tutorial": "res://tutorial.mp3",
			"main": "res://main.mp3",
		},
		"offset": 0.0,
		"beats_per_measure": 4,
		"end_measure": 61,
		"sections": {
			"tutorial": {"start_measure": 1, "end_measure": 16},
			"main": {
				"start_measure": 16,
				"end_measure": 61,
				"lead_in_beats": 12,
			},
		},
		"tempo_changes": [
			{"measure": 1, "bpm": 140},
			{"measure": 33, "bpm": 120},
			{"measure": 37, "bpm": 130},
			{"measure": 45, "bpm": 140},
			{"measure": 53, "bpm": 150},
		],
		"default_pattern": "NORMAL",
		"double_cheers_measures": [20, 26, 27, 38, 44, 48, 56],
		"no_input_measures": [],
		"cue_sets": cue_sets,
	}


func count_expect_events(chart: RhythmChart, measure: int) -> int:
	var count := 0
	for event: Dictionary in chart.events:
		if (
			int(event.get("measure", 0)) == measure
			and event["type"] == RhythmTypes.EventType.EXPECT_CHEERS
		):
			count += 1
	return count


func get_cue_bpm(chart: RhythmChart, measure: int) -> float:
	for cue: Dictionary in chart.cues:
		if int(cue["measure"]) == measure:
			return float(cue["bpm"])
	return 0.0


func get_tempo_change_beats(chart: RhythmChart) -> Array[float]:
	var beats: Array[float] = []
	for change: Dictionary in chart.tempo_changes:
		beats.append(float(change["beat"]))
	return beats


func get_event_beats(
	chart: RhythmChart,
	measure: int,
	event_type: RhythmTypes.EventType
) -> Array[float]:
	var beats: Array[float] = []
	for event: Dictionary in chart.events:
		if (
			int(event.get("measure", 0)) == measure
			and event["type"] == event_type
		):
			beats.append(float(event["beat"]))
	return beats


func count_opponent_starts(chart: RhythmChart) -> int:
	var count := 0
	for event: Dictionary in chart.events:
		if (
			event["type"] == RhythmTypes.EventType.PREPARE
			and event.get("starts_opponent", true)
		):
			count += 1
	return count


func expect_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s: expected=%s actual=%s" % [message, expected, actual])


func expect_near(actual: float, expected: float, message: String) -> void:
	if absf(actual - expected) > 0.001:
		failures.append(
			"%s: expected=%.6f actual=%.6f" % [message, expected, actual]
		)


func finish_tests() -> void:
	if failures.is_empty():
		print("RhythmChart tests passed.")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
