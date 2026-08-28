class_name RhythmTiming
extends RefCounted

var bpm: float
var offset: float
var tempo_segments: Array[Dictionary] = []


# 旧コードの単一BPMと、新Chartのtempo_changesの両方を受け付ける。
func _init(bpm_or_changes: Variant, new_offset: float) -> void:
	offset = new_offset
	if RhythmChart.is_number(bpm_or_changes):
		bpm = float(bpm_or_changes)
		initialize_segments([{"beat": 0.0, "bpm": bpm}])
		return

	var changes: Array = bpm_or_changes
	bpm = float((changes[0] as Dictionary)["bpm"])
	initialize_segments(changes)


# 各テンポ区間の開始秒を先に積算し、変換時の分岐を単純にする。
func initialize_segments(changes: Array) -> void:
	tempo_segments.clear()
	var start_seconds := offset
	for index: int in changes.size():
		var change: Dictionary = changes[index]
		var start_beat := float(change["beat"])
		var segment_bpm := float(change["bpm"])
		if index > 0:
			var previous: Dictionary = tempo_segments[index - 1]
			start_seconds = (
				float(previous["start_seconds"])
				+ (start_beat - float(previous["start_beat"]))
				* 60.0 / float(previous["bpm"])
			)
		tempo_segments.append({
			"start_beat": start_beat,
			"start_seconds": start_seconds,
			"bpm": segment_bpm,
		})


func beat_to_seconds(beat: float) -> float:
	var segment := get_segment_for_beat(beat)
	return (
		float(segment["start_seconds"])
		+ (beat - float(segment["start_beat"]))
		* 60.0 / float(segment["bpm"])
	)


func seconds_to_beats(seconds: float) -> float:
	var segment := get_segment_for_seconds(seconds)
	return (
		float(segment["start_beat"])
		+ (seconds - float(segment["start_seconds"]))
		* float(segment["bpm"]) / 60.0
	)


func get_bpm_at_beat(beat: float) -> float:
	return float(get_segment_for_beat(beat)["bpm"])


func get_segment_for_beat(beat: float) -> Dictionary:
	var result: Dictionary = tempo_segments[0]
	for segment: Dictionary in tempo_segments:
		if beat < float(segment["start_beat"]):
			break
		result = segment
	return result


func get_segment_for_seconds(seconds: float) -> Dictionary:
	var result: Dictionary = tempo_segments[0]
	for segment: Dictionary in tempo_segments:
		if seconds < float(segment["start_seconds"]):
			break
		result = segment
	return result
