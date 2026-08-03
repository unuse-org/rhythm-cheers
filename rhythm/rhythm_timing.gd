class_name RhythmTiming
extends RefCounted

var bpm: float
var offset: float


func _init(new_bpm: float, new_offset: float) -> void:
	bpm = new_bpm
	offset = new_offset


# 拍を再生時間へ変換する
func beat_to_seconds(beat: float) -> float:
	return offset + beat * 60.0 / bpm


# 再生時間を拍へ変換する
func seconds_to_beats(seconds: float) -> float:
	return (seconds - offset) * bpm / 60.0
