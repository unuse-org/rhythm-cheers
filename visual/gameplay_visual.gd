class_name GameplayVisual
extends Control

@onready var character: TextureRect = $Character
@onready var player: TextureRect = $Player
@onready var cheers_effect: TextureRect = $CheersEffect
@onready var first_cheers_character: Label = $CheersText/FirstCharacter
@onready var second_cheers_character: Label = $CheersText/SecondCharacter

@export_category("Character")
@export var character_normal_texture: Texture2D
@export var character_prepare_texture: Texture2D
@export var character_cheers_texture: Texture2D

@export_category("Player")
@export var player_normal_texture: Texture2D
@export var player_prepare_texture: Texture2D
@export var player_cheers_texture: Texture2D

const REJECTED_INPUT_DISPLAY_SECONDS: float = 0.5
const BASE_TEXT_COLOR: Color = Color(1.0, 0.91, 0.45)
const BASE_OUTLINE_COLOR: Color = Color(0.95, 0.35, 0.12)
const SUCCESS_TEXT_COLOR: Color = Color(1.0, 0.78, 0.15)
const SUCCESS_OUTLINE_COLOR: Color = Color(0.75, 0.10, 0.50)
const FAILURE_TEXT_COLOR: Color = Color.WHITE
const FAILURE_OUTLINE_COLOR: Color = Color(0.05, 0.25, 0.45)
const BASE_OUTLINE_SIZE: int = 12
const RESULT_OUTLINE_SIZE: int = 18

var rhythm_session: RhythmSession

# Playerの確定状態
var player_state: RhythmTypes.CharacterState = RhythmTypes.CharacterState.NORMAL
var player_state_reset_song_time: float = INF

# 誤入力を一時表示するための状態
var temporary_player_state_active: bool = false
var temporary_player_state_until: float = INF


func configure(new_rhythm_session: RhythmSession) -> void:
	rhythm_session = new_rhythm_session

	if not rhythm_session.character_state_changed.is_connected(
		_on_character_state_changed
	):
		rhythm_session.character_state_changed.connect(
			_on_character_state_changed
		)

	if not rhythm_session.input_resolved.is_connected(_on_input_resolved):
		rhythm_session.input_resolved.connect(_on_input_resolved)

	set_character_state(rhythm_session.character_state)
	reset_player_state()


func advance(song_time: float) -> void:
	if song_time >= player_state_reset_song_time:
		player_state = RhythmTypes.CharacterState.NORMAL
		player_state_reset_song_time = INF
		cheers_effect.visible = false

		if not temporary_player_state_active:
			update_player_texture()

	if song_time >= temporary_player_state_until:
		temporary_player_state_active = false
		temporary_player_state_until = INF
		update_player_texture()


# センサー入力に応じてPlayer画像を更新する
func show_player_input(
	_input_type: RhythmTypes.InputType,
	accepted: bool,
	song_time: float
) -> void:
	if accepted:
		temporary_player_state_active = false
		temporary_player_state_until = INF
		player_state = RhythmTypes.CharacterState.SUCCESS
		player_state_reset_song_time = (
			song_time + 60.0 / rhythm_session.timing.bpm
		)
		cheers_effect.visible = true

		update_player_texture()
		return

	# 誤入力は確定状態を変更せず、入力画像だけを短く表示する
	temporary_player_state_active = true
	temporary_player_state_until = (
		song_time + REJECTED_INPUT_DISPLAY_SECONDS
	)
	player.texture = player_cheers_texture


func _on_character_state_changed(
	state: RhythmTypes.CharacterState
) -> void:
	set_character_state(state)

	if state == RhythmTypes.CharacterState.NORMAL:
		reset_player_state()


func _on_input_resolved(
	_beat: float,
	_input_type: RhythmTypes.InputType,
	judgement: String
) -> void:
	if judgement.begins_with("MISS"):
		reset_player_state()


func set_character_state(state: RhythmTypes.CharacterState) -> void:
	match state:
		RhythmTypes.CharacterState.NORMAL:
			character.texture = character_normal_texture

		RhythmTypes.CharacterState.PREPARE:
			character.texture = character_prepare_texture

		RhythmTypes.CharacterState.JUDGING, \
		RhythmTypes.CharacterState.SUCCESS:
			character.texture = character_cheers_texture

		RhythmTypes.CharacterState.FAILURE:
			character.texture = character_normal_texture

	update_cheers_text(state)


func update_cheers_text(state: RhythmTypes.CharacterState) -> void:
	first_cheers_character.text = "乾"
	second_cheers_character.text = "杯"
	first_cheers_character.visible = false
	second_cheers_character.visible = false
	set_cheers_text_style(
		first_cheers_character,
		BASE_TEXT_COLOR,
		BASE_OUTLINE_COLOR,
		BASE_OUTLINE_SIZE
	)
	set_cheers_text_style(
		second_cheers_character,
		BASE_TEXT_COLOR,
		BASE_OUTLINE_COLOR,
		BASE_OUTLINE_SIZE
	)

	match state:
		RhythmTypes.CharacterState.PREPARE:
			first_cheers_character.visible = true

		RhythmTypes.CharacterState.JUDGING:
			first_cheers_character.visible = true
			second_cheers_character.visible = true

		RhythmTypes.CharacterState.SUCCESS:
			first_cheers_character.visible = true
			second_cheers_character.visible = true
			set_cheers_text_style(
				first_cheers_character,
				SUCCESS_TEXT_COLOR,
				SUCCESS_OUTLINE_COLOR,
				RESULT_OUTLINE_SIZE
			)
			set_cheers_text_style(
				second_cheers_character,
				SUCCESS_TEXT_COLOR,
				SUCCESS_OUTLINE_COLOR,
				RESULT_OUTLINE_SIZE
			)

		RhythmTypes.CharacterState.FAILURE:
			first_cheers_character.text = "失"
			first_cheers_character.visible = true
			second_cheers_character.visible = true
			set_cheers_text_style(
				first_cheers_character,
				FAILURE_TEXT_COLOR,
				FAILURE_OUTLINE_COLOR,
				RESULT_OUTLINE_SIZE
			)


func set_cheers_text_style(
	label: Label,
	font_color: Color,
	outline_color: Color,
	outline_size: int
) -> void:
	label.add_theme_color_override("font_color", font_color)
	label.add_theme_color_override("font_outline_color", outline_color)
	label.add_theme_constant_override("outline_size", outline_size)


func reset_player_state() -> void:
	player_state = RhythmTypes.CharacterState.NORMAL
	player_state_reset_song_time = INF
	temporary_player_state_active = false
	temporary_player_state_until = INF
	cheers_effect.visible = false
	update_player_texture()


func update_player_texture() -> void:
	player.texture = get_player_texture(player_state)


func get_player_texture(
	state: RhythmTypes.CharacterState
) -> Texture2D:
	match state:
		RhythmTypes.CharacterState.JUDGING, \
		RhythmTypes.CharacterState.SUCCESS:
			return player_cheers_texture

		_:
			return player_normal_texture
