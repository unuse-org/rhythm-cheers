class_name FlowScreen
extends Control

signal screen_completed(payload: Dictionary)

var run_context: RunContext
var is_completed: bool = false


func setup(context: RunContext) -> void:
	run_context = context


func receive_sensor_input(
	_sensor_input_type: RhythmTypes.InputType
) -> void:
	pass


func complete_screen(payload: Dictionary = {}) -> void:
	if is_completed:
		return

	is_completed = true
	screen_completed.emit(payload)
