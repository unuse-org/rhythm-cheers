class_name RhythmChart
extends RefCounted

const EVENT_TYPE_NAMES: Dictionary = {
	"PREPARE": RhythmTypes.EventType.PREPARE,
	"EXPECT_CHEERS": RhythmTypes.EventType.EXPECT_CHEERS,
	"SHOW_CHEERS": RhythmTypes.EventType.SHOW_CHEERS,
	"RETURN_NORMAL": RhythmTypes.EventType.RETURN_NORMAL,
}
const NORMAL_PATTERN: String = "NORMAL"
const DOUBLE_PATTERN: String = "DOUBLE"

# bpmは旧形式との互換用。可変BPM譜面では先頭BPMを保持する。
var bpm: float
var offset: float
var beats_per_measure: int = 4
var end_measure: int = 1
var end_beat: float = 0.0
var lead_in_beats: float = 0.0
var audio_path: String = ""
var section_audio_paths: Dictionary = {}
var tempo_changes: Array[Dictionary] = []
var sections: Dictionary = {}
var events: Array[Dictionary] = []
var cues: Array[Dictionary] = []
var cue_sets: Dictionary = {}
var default_pattern: String = NORMAL_PATTERN


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
	if typeof(data) != TYPE_DICTIONARY:
		return report_error(source_name, "ルートはObject")

	var source: Dictionary = data
	if not is_number(source.get("offset")):
		return report_error(source_name, "offsetは数値にして")

	if source.has("tempo_changes"):
		return parse_measure_chart(source, source_name)

	return parse_legacy_chart(source, source_name)


# 既存のbpm + events形式を単一要素のtempo mapへ変換する。
static func parse_legacy_chart(
	source: Dictionary,
	source_name: String
) -> RhythmChart:
	if not is_number(source.get("bpm")):
		return report_error(source_name, "bpmは数値にして")
	if float(source["bpm"]) <= 0.0:
		return report_error(source_name, "bpmは0より大きくして")
	if typeof(source.get("events")) != TYPE_ARRAY:
		return report_error(source_name, "eventsにはArrayが必要")

	var chart := RhythmChart.new()
	chart.bpm = float(source["bpm"])
	chart.offset = float(source["offset"])
	chart.tempo_changes.append({"beat": 0.0, "bpm": chart.bpm})
	if not parse_explicit_events(source["events"], chart, source_name):
		return null
	if not chart.events.is_empty():
		chart.end_beat = float(chart.events.back()["beat"])
	return chart


# 小節ベース譜面を検証し、実行時に使う拍イベントへ展開する。
static func parse_measure_chart(
	source: Dictionary,
	source_name: String
) -> RhythmChart:
	if not is_positive_integer(source.get("beats_per_measure")):
		return report_error(source_name, "beats_per_measureは正の整数にして")
	if not is_positive_integer(source.get("end_measure")):
		return report_error(source_name, "end_measureは正の整数にして")
	if int(source["end_measure"]) <= 1:
		return report_error(source_name, "end_measureは1より大きくして")
	if (
		typeof(source.get("audio")) != TYPE_STRING
		and typeof(source.get("audio")) != TYPE_DICTIONARY
	):
		return report_error(source_name, "audioは文字列またはObjectにして")
	if typeof(source.get("tempo_changes")) != TYPE_ARRAY:
		return report_error(source_name, "tempo_changesにはArrayが必要")
	if typeof(source.get("sections")) != TYPE_DICTIONARY:
		return report_error(source_name, "sectionsにはObjectが必要")
	if typeof(source.get("cue_sets")) != TYPE_DICTIONARY:
		return report_error(source_name, "cue_setsにはObjectが必要")

	var chart := RhythmChart.new()
	chart.offset = float(source["offset"])
	chart.beats_per_measure = int(source["beats_per_measure"])
	chart.end_measure = int(source["end_measure"])
	chart.end_beat = float(
		(chart.end_measure - 1) * chart.beats_per_measure
	)
	if typeof(source["audio"]) == TYPE_STRING:
		chart.audio_path = String(source["audio"])
	else:
		chart.section_audio_paths = (
			(source["audio"] as Dictionary).duplicate(true)
		)
	chart.cue_sets = (source["cue_sets"] as Dictionary).duplicate(true)
	chart.default_pattern = String(source.get("default_pattern", NORMAL_PATTERN))
	if chart.default_pattern not in [NORMAL_PATTERN, DOUBLE_PATTERN]:
		return report_error(source_name, "default_patternが不明です")

	if not parse_tempo_changes(source["tempo_changes"], chart, source_name):
		return null
	if not parse_sections(source["sections"], chart, source_name):
		return null
	if not validate_section_audio_paths(chart, source_name):
		return null

	var parsed_double_measures: Variant = parse_measure_list(
		source.get("double_cheers_measures", []),
		"double_cheers_measures",
		chart,
		source_name
	)
	if parsed_double_measures == null:
		return null
	var double_measures: Array[int] = parsed_double_measures
	var parsed_no_input_measures: Variant = parse_measure_list(
		source.get("no_input_measures", []),
		"no_input_measures",
		chart,
		source_name
	)
	if parsed_no_input_measures == null:
		return null
	var no_input_measures: Array[int] = parsed_no_input_measures

	if not expand_measure_events(
		chart,
		double_measures,
		no_input_measures,
		source_name
	):
		return null
	return chart


static func parse_tempo_changes(
	raw_changes: Variant,
	chart: RhythmChart,
	source_name: String
) -> bool:
	var changes: Array = raw_changes
	var previous_measure: int = 0
	for index: int in changes.size():
		if typeof(changes[index]) != TYPE_DICTIONARY:
			report_error(source_name, "tempo_changes[%d]はObjectにして" % index)
			return false
		var change: Dictionary = changes[index]
		if not is_positive_integer(change.get("measure")):
			report_error(source_name, "tempo_changes[%d].measureが不正" % index)
			return false
		if not is_number(change.get("bpm")) or float(change["bpm"]) <= 0.0:
			report_error(source_name, "tempo_changes[%d].bpmが不正" % index)
			return false

		var measure := int(change["measure"])
		if measure <= previous_measure or measure >= chart.end_measure:
			report_error(source_name, "tempo_changesのmeasureは昇順かつ曲中にして")
			return false
		if index == 0 and measure != 1:
			report_error(source_name, "最初のtempo changeは1小節目にして")
			return false

		chart.tempo_changes.append({
			"beat": float((measure - 1) * chart.beats_per_measure),
			"bpm": float(change["bpm"]),
			"measure": measure,
		})
		previous_measure = measure

	if chart.tempo_changes.is_empty():
		report_error(source_name, "tempo_changesを1件以上設定して")
		return false
	chart.bpm = float(chart.tempo_changes[0]["bpm"])
	return true


static func validate_section_audio_paths(
	chart: RhythmChart,
	source_name: String
) -> bool:
	for section_name: String in chart.sections:
		var section_path: Variant = chart.section_audio_paths.get(
			section_name,
			chart.audio_path
		)
		if typeof(section_path) != TYPE_STRING or String(section_path).is_empty():
			report_error(
				source_name,
				"sections.%sのaudioがありません" % section_name
			)
			return false
	return true


static func parse_sections(
	raw_sections: Variant,
	chart: RhythmChart,
	source_name: String
) -> bool:
	var section_source: Dictionary = raw_sections
	for section_name: Variant in section_source:
		if typeof(section_name) != TYPE_STRING:
			report_error(source_name, "section名は文字列にして")
			return false
		var raw_section: Variant = section_source[section_name]
		if typeof(raw_section) != TYPE_DICTIONARY:
			report_error(source_name, "sections.%sはObjectにして" % section_name)
			return false

		var section: Dictionary = raw_section
		if (
			not is_positive_integer(section.get("start_measure"))
			or not is_positive_integer(section.get("end_measure"))
		):
			report_error(source_name, "sections.%sの小節範囲が不正" % section_name)
			return false

		var start_measure := int(section["start_measure"])
		var section_end_measure := int(section["end_measure"])
		var section_lead_in: Variant = section.get("lead_in_beats", 0.0)
		if not is_number(section_lead_in) or float(section_lead_in) < 0.0:
			report_error(
				source_name,
				"sections.%s.lead_in_beatsが不正" % section_name
			)
			return false
		if start_measure >= section_end_measure or section_end_measure > chart.end_measure:
			report_error(source_name, "sections.%sは開始以上終了未満にして" % section_name)
			return false

		chart.sections[String(section_name)] = {
			"start_measure": start_measure,
			"end_measure": section_end_measure,
			"start_beat": float((start_measure - 1) * chart.beats_per_measure),
			"end_beat": float((section_end_measure - 1) * chart.beats_per_measure),
			"lead_in_beats": float(section_lead_in),
		}
	return true


static func parse_measure_list(
	raw_value: Variant,
	property_name: String,
	chart: RhythmChart,
	source_name: String
) -> Variant:
	if typeof(raw_value) != TYPE_ARRAY:
		report_error(source_name, "%sにはArrayが必要" % property_name)
		return null

	var result: Array[int] = []
	for index: int in (raw_value as Array).size():
		var value: Variant = (raw_value as Array)[index]
		if not is_positive_integer(value):
			report_error(source_name, "%s[%d]が不正" % [property_name, index])
			return null
		var measure := int(value)
		if measure >= chart.end_measure or result.has(measure):
			report_error(source_name, "%sの小節が範囲外または重複" % property_name)
			return null
		result.append(measure)
	return result


static func expand_measure_events(
	chart: RhythmChart,
	double_measures: Array[int],
	no_input_measures: Array[int],
	source_name: String
) -> bool:
	for measure: int in range(1, chart.end_measure):
		if no_input_measures.has(measure):
			continue

		var measure_beat := float((measure - 1) * chart.beats_per_measure)
		var current_bpm := get_bpm_for_beat(chart.tempo_changes, measure_beat)
		var pattern := (
			DOUBLE_PATTERN if double_measures.has(measure) else chart.default_pattern
		)

		if pattern == DOUBLE_PATTERN:
			append_cheers_sequence(
				chart, measure_beat, measure, pattern, 2.0, 2.5, true
			)
			append_cheers_sequence(
				chart, measure_beat, measure, pattern, 3.0, 3.5, false
			)
		else:
			append_cheers_sequence(
				chart, measure_beat, measure, pattern, 2.0, 3.0, true
			)
		chart.events.append(create_measure_event(
			measure_beat + 4.0,
			RhythmTypes.EventType.RETURN_NORMAL,
			measure,
			pattern
		))

		if not append_measure_cues(
			chart, measure_beat, measure, current_bpm, pattern, source_name
		):
			return false
	return true


# 「乾」でPREPARE、「杯」で表示と判定を進めるイベント列を作る。
static func append_cheers_sequence(
	chart: RhythmChart,
	measure_beat: float,
	measure: int,
	pattern: String,
	prepare_offset: float,
	target_offset: float,
	starts_opponent: bool
) -> void:
	var prepare_event := create_measure_event(
		measure_beat + prepare_offset,
		RhythmTypes.EventType.PREPARE,
		measure,
		pattern
	)
	prepare_event["starts_opponent"] = starts_opponent
	chart.events.append(prepare_event)

	var expect_event := create_measure_event(
		measure_beat + target_offset,
		RhythmTypes.EventType.EXPECT_CHEERS,
		measure,
		pattern
	)
	# 入力窓は先に開くが、人物画像はSHOW_CHEERSまでPREPAREを維持する。
	expect_event["show_state"] = false
	chart.events.append(expect_event)
	chart.events.append(create_measure_event(
		measure_beat + target_offset,
		RhythmTypes.EventType.SHOW_CHEERS,
		measure,
		pattern
	))


static func create_measure_event(
	beat: float,
	event_type: RhythmTypes.EventType,
	measure: int,
	pattern: String
) -> Dictionary:
	return {
		"beat": beat,
		"type": event_type,
		"measure": measure,
		"pattern": pattern,
	}


static func append_measure_cues(
	chart: RhythmChart,
	measure_beat: float,
	measure: int,
	current_bpm: float,
	pattern: String,
	source_name: String
) -> bool:
	var bpm_key := str(int(round(current_bpm)))
	if typeof(chart.cue_sets.get(bpm_key)) != TYPE_DICTIONARY:
		report_error(source_name, "BPM%sのcue setがありません" % bpm_key)
		return false

	var cue_set: Dictionary = chart.cue_sets[bpm_key]
	var cue_definitions: Array[Dictionary]
	if pattern == DOUBLE_PATTERN:
		cue_definitions = [
			{"beat_offset": 0.0, "key": "count_double"},
			{"beat_offset": 2.0, "key": "cheers_double"},
		]
	else:
		cue_definitions = [
			{"beat_offset": 0.0, "key": "count_1"},
			{"beat_offset": 1.0, "key": "count_2"},
			{"beat_offset": 2.0, "key": "cheers"},
		]

	for definition: Dictionary in cue_definitions:
		var cue_key: String = definition["key"]
		if typeof(cue_set.get(cue_key)) != TYPE_STRING:
			report_error(
				source_name,
				"BPM%s.%sの音源がありません" % [bpm_key, cue_key]
			)
			return false
		chart.cues.append({
			"beat": measure_beat + float(definition["beat_offset"]),
			"path": String(cue_set[cue_key]),
			"cue_key": cue_key,
			"measure": measure,
			"bpm": current_bpm,
			"pattern": pattern,
		})
	return true


static func parse_explicit_events(
	raw_events: Array,
	chart: RhythmChart,
	source_name: String
) -> bool:
	var previous_beat: float = -INF
	for index: int in raw_events.size():
		var parsed_event := parse_event(raw_events[index], index, source_name)
		if parsed_event.is_empty():
			return false
		var beat: float = parsed_event["beat"]
		if beat < previous_beat:
			report_error(source_name, "events[%d]のbeatは昇順にして" % index)
			return false
		chart.events.append(parsed_event)
		previous_beat = beat
	return true


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
	return {
		"beat": float(source["beat"]),
		"type": EVENT_TYPE_NAMES[event_type_name],
	}


# 指定画面のイベントだけを返す。local_timelineでは区間先頭を0拍にする。
func create_section(
	section_name: String,
	local_timeline: bool = false
) -> RhythmChart:
	if not sections.has(section_name):
		push_error("譜面sectionがありません: %s" % section_name)
		return null

	var section: Dictionary = sections[section_name]
	var start_beat: float = section["start_beat"]
	var section_end_beat: float = section["end_beat"]
	var section_lead_in := float(section.get("lead_in_beats", 0.0))
	var result := RhythmChart.new()
	result.bpm = bpm
	result.offset = offset
	result.beats_per_measure = beats_per_measure
	result.end_measure = end_measure
	result.lead_in_beats = section_lead_in if local_timeline else 0.0
	result.end_beat = (
		section_end_beat - start_beat + section_lead_in
		if local_timeline
		else section_end_beat
	)
	result.audio_path = String(
		section_audio_paths.get(section_name, audio_path)
	)
	result.section_audio_paths = section_audio_paths.duplicate(true)
	if local_timeline:
		result.tempo_changes = create_local_tempo_changes(
			start_beat,
			section_end_beat,
			section_lead_in
		)
		result.sections = {
			section_name: {
				"start_measure": section["start_measure"],
				"end_measure": section["end_measure"],
				"start_beat": section_lead_in,
				"end_beat": result.end_beat,
				"lead_in_beats": section_lead_in,
			}
		}
	else:
		result.tempo_changes = tempo_changes.duplicate(true)
		result.sections = sections.duplicate(true)
	result.bpm = float(result.tempo_changes[0]["bpm"])
	result.cue_sets = cue_sets.duplicate(true)
	result.default_pattern = default_pattern
	for event: Dictionary in events:
		var beat: float = event["beat"]
		var event_is_in_section := (
			int(event["measure"]) >= int(section["start_measure"])
			and int(event["measure"]) < int(section["end_measure"])
			if event.has("measure")
			else beat >= start_beat and beat < section_end_beat
		)
		if event_is_in_section:
			var section_event := event.duplicate(true)
			if local_timeline:
				section_event["beat"] = (
					beat - start_beat + section_lead_in
				)
			result.events.append(section_event)
	for cue: Dictionary in cues:
		var beat: float = cue["beat"]
		var cue_is_in_section := (
			int(cue["measure"]) >= int(section["start_measure"])
			and int(cue["measure"]) < int(section["end_measure"])
			if cue.has("measure")
			else beat >= start_beat and beat < section_end_beat
		)
		if cue_is_in_section:
			var section_cue := cue.duplicate(true)
			if local_timeline:
				section_cue["beat"] = (
					beat - start_beat + section_lead_in
				)
			result.cues.append(section_cue)
	return result


func create_local_tempo_changes(
	start_beat: float,
	section_end_beat: float,
	section_lead_in: float = 0.0
) -> Array[Dictionary]:
	var result: Array[Dictionary] = [{
		"beat": 0.0,
		"bpm": get_bpm_for_beat(tempo_changes, start_beat),
	}]
	for change: Dictionary in tempo_changes:
		var change_beat := float(change["beat"])
		if change_beat <= start_beat or change_beat >= section_end_beat:
			continue
		var local_change := change.duplicate(true)
		local_change["beat"] = (
			change_beat - start_beat + section_lead_in
		)
		result.append(local_change)
	return result


func get_section_start_beat(section_name: String) -> float:
	if not sections.has(section_name):
		return 0.0
	return float(sections[section_name]["start_beat"])


func get_section_end_beat(section_name: String) -> float:
	if not sections.has(section_name):
		return end_beat
	return float(sections[section_name]["end_beat"])


static func get_bpm_for_beat(
	changes: Array[Dictionary], beat: float
) -> float:
	var result := float(changes[0]["bpm"])
	for change: Dictionary in changes:
		if beat < float(change["beat"]):
			break
		result = float(change["bpm"])
	return result


static func is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func is_positive_integer(value: Variant) -> bool:
	return (
		is_number(value)
		and float(value) > 0.0
		and is_equal_approx(float(value), roundf(float(value)))
	)


static func report_error(
	source_name: String, message: String
) -> RhythmChart:
	push_error("なんやその譜面: %s: %s" % [source_name, message])
	push_error("お前のせいで譜面読み込み失敗したにょん。船降りろ。")
	return null
