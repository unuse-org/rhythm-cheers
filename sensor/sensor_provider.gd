class_name SensorProvider
extends Node

# unused_signalを無視する
# 抽象クラスなので
@warning_ignore("unused_signal")
signal input_detected(input_type: RhythmTypes.InputType)
@warning_ignore("unused_signal")
signal connection_changed(connected: bool)
@warning_ignore("unused_signal")
signal sensor_error(message: String)

func start() -> void:
	pass

func stop() -> void:
	pass
