class_name ResultScreen
extends FlowScreen

@onready var result_audio_player: AudioStreamPlayer = %ResultAudioPlayer
@onready var action_button: Button = %ActionButton
@onready var success_count_label: Label = %SuccessCountLabel
@onready var success_amount_label: Label = %SuccessAmountLabel
@onready var failure_count_label: Label = %FailureCountLabel
@onready var failure_amount_label: Label = %FailureAmountLabel
@onready var total_amount_label: Label = %TotalAmountLabel
@onready var face_preview: TextureRect = %FacePreview
@onready var face_status_label: Label = %FaceStatusLabel


func _ready() -> void:
	action_button.pressed.connect(_on_action_button_pressed)
	update_result_display()

	# レシートが現れるタイミングに合わせ、会計の効果音を一度だけ鳴らす。
	if result_audio_player.stream != null:
		result_audio_player.play()


func _exit_tree() -> void:
	result_audio_player.stop()
	result_audio_player.stream = null


func setup(context: RunContext) -> void:
	super.setup(context)

	if is_node_ready():
		update_result_display()


func receive_sensor_input(
	sensor_input_type: RhythmTypes.InputType
) -> void:
	if sensor_input_type == RhythmTypes.InputType.CHEERS:
		complete_screen()


func update_result_amounts() -> void:
	if run_context == null:
		success_count_label.text = "--"
		success_amount_label.text = "¥--"
		failure_count_label.text = "--"
		failure_amount_label.text = "¥--"
		total_amount_label.text = "¥--"
		return

	success_count_label.text = str(run_context.cheers_success_count)
	success_amount_label.text = _format_amount(
		run_context.calculate_success_amount()
	)
	failure_count_label.text = str(run_context.cheers_failure_count)
	failure_amount_label.text = _format_amount(
		run_context.calculate_failure_amount()
	)
	total_amount_label.text = _format_amount(
		run_context.calculate_total_amount()
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
	update_result_amounts()
	update_result_face()


func _format_amount(amount: int) -> String:
	return "¥%d" % amount


func _on_action_button_pressed() -> void:
	complete_screen()
