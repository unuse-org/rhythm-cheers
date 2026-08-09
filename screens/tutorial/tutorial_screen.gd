class_name TutorialScreen
extends FlowScreen

@onready var action_button: Button = %ActionButton


func _ready() -> void:
	action_button.pressed.connect(_on_action_button_pressed)


func receive_sensor_input(
	sensor_input_type: RhythmTypes.InputType
) -> void:
	if sensor_input_type == RhythmTypes.InputType.CHEERS:
		complete_tutorial()


func complete_tutorial() -> void:
	complete_screen({"tutorial_completed": true})


func _on_action_button_pressed() -> void:
	complete_tutorial()
