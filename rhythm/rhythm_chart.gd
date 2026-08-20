class_name RhythmChart
extends RefCounted

# PREPARE：乾杯の準備を開始するイベント
# EXPECT_CHEERS：乾杯入力を期待するイベント
# RETURN_NORMAL：キャラクターの状態をNORMALに戻すイベント
const EVENT_TYPE_NAMES: Dictionary = {
	"PREPARE": RhythmTypes.EventType.PREPARE,
	"EXPECT_CHEERS": RhythmTypes.EventType.EXPECT_CHEERS,
	"RETURN_NORMAL": RhythmTypes.EventType.RETURN_NORMAL,
}

var bpm: float
var offset: float
var events: Array[Dictionary] = []

# RhythmChartをJSONファイルから読み込む
static func load_from_file(path: String) -> RhythmChart:
	var file := FileAccess.open(path, FileAccess.READ)

	if file == null:
		push_error(
			"譜面を開けないにょん: %s (%s)"
			% [path, error_string(FileAccess.get_open_error())]
		)
		return null

	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())

	if parse_error != OK:
		push_error(
			"JSONの解析無理ぽ: %s:%d: %s"
			% [path, json.get_error_line(), json.get_error_message()]
		)
		return null

	return from_dictionary(json.data, path)


static func from_dictionary(
	data: Variant,
	source_name: String = "<memory>"
) -> RhythmChart:
	# 今回はJSONのルートにObjectを期待する
	# https://docs.godotengine.org/en/stable/classes/class_json.html
	if typeof(data) != TYPE_DICTIONARY:
		return report_error(source_name, "ルートはObject")

	var source: Dictionary = data

	if not is_number(source.get("bpm")):
		return report_error(source_name, "bpmは数値にして")

	if float(source["bpm"]) <= 0.0:
		return report_error(source_name, "bpmは0より大きくして")

	if not is_number(source.get("offset")):
		return report_error(source_name, "offsetは数値にして")

	if typeof(source.get("events")) != TYPE_ARRAY:
		return report_error(source_name, "eventsにはArrayが必要")

	var chart := RhythmChart.new()

	# RhythmChartのプロパティに変換
	chart.bpm = float(source["bpm"])
	chart.offset = float(source["offset"])

	var raw_events: Array = source["events"]
	var previous_beat: float = -INF

	# eventsを順番に解析してRhythmChartに追加する
	for index: int in raw_events.size():
		var parsed_event := parse_event(
			raw_events[index],
			index,
			source_name
		)

		if parsed_event.is_empty():
			return null

		var beat: float = parsed_event["beat"]

		if beat < previous_beat:
			return report_error(
				source_name,
				"events[%d]のbeatは昇順にして" % index
			)

		chart.events.append(parsed_event)
		previous_beat = beat

	return chart


# 解析した譜面イベントをRhythmChartに追加する
static func parse_event(
	data: Variant,
	index: int,
	source_name: String
) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY:
		report_error(source_name, "events[%d]はObjectにして" % index)
		return {}

	var source: Dictionary = data

	if not is_number(source.get("beat")):
		report_error(source_name, "events[%d].beatは数値にして" % index)
		return {}

	if typeof(source.get("type")) != TYPE_STRING:
		report_error(source_name, "events[%d].typeは文字列にして" % index)
		return {}

	var event_type_name: String = source["type"]

	if not EVENT_TYPE_NAMES.has(event_type_name):
		report_error(
			source_name,
			"events[%d].typeが不明です: %s" % [index, event_type_name]
		)
		return {}

	var event_type: RhythmTypes.EventType = EVENT_TYPE_NAMES[event_type_name]
	var parsed_event: Dictionary = {
		"beat": float(source["beat"]),
		"type": event_type,
	}
	return parsed_event


static func is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func report_error(
	source_name: String,
	message: String
) -> RhythmChart:
	push_error("なんやその譜面: %s: %s" % [source_name, message])
	push_error("お前のせいで譜面読み込み失敗したにょん。船降りろ。")
	return null
