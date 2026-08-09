class_name FaceCaptureScreen
extends FlowScreen

@onready var action_button: Button = %ActionButton


func _ready() -> void:
	action_button.pressed.connect(_on_action_button_pressed)


func receive_sensor_input(
	sensor_input_type: RhythmTypes.InputType
) -> void:
	if sensor_input_type == RhythmTypes.InputType.CHEERS:
		complete_capture()


func complete_capture() -> void:
	complete_screen({"capture_completed": true})


func _on_action_button_pressed() -> void:
	complete_capture()
