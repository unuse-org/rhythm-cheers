class_name ResultScreen
extends FlowScreen

@onready var action_button: Button = %ActionButton
@onready var score_label: Label = %ScoreLabel


func _ready() -> void:
	action_button.pressed.connect(_on_action_button_pressed)
	update_result_text()


func setup(context: RunContext) -> void:
	super.setup(context)

	if is_node_ready():
		update_result_text()


func receive_sensor_input(
	sensor_input_type: RhythmTypes.InputType
) -> void:
	if sensor_input_type == RhythmTypes.InputType.CHEERS:
		complete_screen()


func update_result_text() -> void:
	if run_context == null:
		score_label.text = "成功: --\n失敗: --\n結果: --"
		return

	score_label.text = (
		"成功: %d\n失敗: %d\n結果: %d"
		% [
			run_context.cheers_success_count,
			run_context.cheers_failure_count,
			run_context.result_value,
		]
	)


func _on_action_button_pressed() -> void:
	complete_screen()
