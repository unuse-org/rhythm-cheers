class_name KeyboardSensorProvider
extends SensorProvider


func start() -> void:
	connection_changed.emit(true)
	
func stop() -> void:
	connection_changed.emit(false)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cheers_input"):
		input_detected.emit(RhythmTypes.InputType.CHEERS)
