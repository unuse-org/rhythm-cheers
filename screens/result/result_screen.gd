class_name ResultScreen
extends FlowScreen

@onready var action_button: Button = %ActionButton
@onready var score_label: Label = %ScoreLabel
@onready var face_preview: TextureRect = %FacePreview
@onready var face_status_label: Label = %FaceStatusLabel


func _ready() -> void:
	action_button.pressed.connect(_on_action_button_pressed)
	update_result_display()


func setup(context: RunContext) -> void:
	super.setup(context)

	if is_node_ready():
		update_result_display()


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


func update_result_face() -> void:
	if (
		run_context == null
		or run_context.captured_face_image == null
		or run_context.captured_face_image.is_empty()
	):
		face_preview.texture = null
		face_status_label.text = "顔写真なし"
		face_status_label.visible = true
		return

	face_preview.texture = ImageTexture.create_from_image(
		run_context.captured_face_image
	)
	face_status_label.visible = false


func update_result_display() -> void:
	update_result_text()
	update_result_face()


func _on_action_button_pressed() -> void:
	complete_screen()
