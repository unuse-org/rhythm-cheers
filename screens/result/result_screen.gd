class_name ResultScreen
extends FlowScreen

@onready var result_audio_player: AudioStreamPlayer = %ResultAudioPlayer
@onready var action_button: Button = %ActionButton
@onready var success_count_label: Label = %SuccessCountLabel
@onready var now_label: Label = %NowLabel
@onready var player_count_label: Label = %PlayerCountLabel
@onready var success_amount_label: Label = %SuccessAmountLabel
@onready var failure_count_label: Label = %FailureCountLabel
@onready var failure_amount_label: Label = %FailureAmountLabel
@onready var total_amount_label: Label = %TotalAmountLabel
@onready var face_preview: TextureRect = %FacePreview
@onready var face_status_label: Label = %FaceStatusLabel
@onready var music_player: AudioStreamPlayer = %MusicPlayer


func _ready() -> void:
	action_button.pressed.connect(_on_action_button_pressed)
	result_audio_player.finished.connect(_on_result_audio_finished)
	update_result_display()

	# レシートが現れるタイミングに合わせ、会計の効果音を一度だけ鳴らす。
	if result_audio_player.stream != null:
		result_audio_player.play()
	else:
		play_music()


# 会計音とBGMが重ならないよう、効果音の再生終了後にBGMを開始する。
func _on_result_audio_finished() -> void:
	play_music()


func play_music() -> void:
	if music_player.stream != null and not music_player.playing:
		music_player.play()


func _exit_tree() -> void:
	result_audio_player.stop()
	result_audio_player.stream = null

	music_player.stop()
	music_player.stream = null


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
	var normal_image: Image
	if (
		run_context != null
		and run_context.character_generation_succeeded
		and run_context.generated_character_images != null
	):
		normal_image = (
			run_context.generated_character_images.get("normal") as Image
		)

	if normal_image == null or normal_image.is_empty():
		face_preview.texture = null
		face_status_label.text = "キャラクター画像なし"
		face_status_label.visible = true
		return

	face_preview.texture = ImageTexture.create_from_image(normal_image)
	face_status_label.visible = false


func update_now_label() -> void:
	var now = Time.get_datetime_dict_from_system()

	now_label.text = "%02d年%02d月%02d日" % [
		now.year,
		now.month,
		now.day,
	]


func update_player_count_label() -> void:
	if run_context == null or run_context.player_number <= 0:
		player_count_label.text = "No ---"
		return

	player_count_label.text = (
		"No %03d" % run_context.player_number
	)


func update_result_display() -> void:
	update_result_amounts()
	update_now_label()
	update_player_count_label()
	update_result_face()


func _format_amount(amount: int) -> String:
	return "¥%d" % amount


func _on_action_button_pressed() -> void:
	complete_screen()
