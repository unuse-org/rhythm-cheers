class_name GameplayVisual
extends Control

@onready var character: TextureRect = $Character
@onready var player_cheers: TextureRect = $PlayerCheers
@onready var cheers_effect: TextureRect = $CheersEffect
@onready var first_cheers_character: Label = $CheersText/FirstCharacter
@onready var second_cheers_character: Label = $CheersText/SecondCharacter

@export_category("Character")
@export var character_normal_texture: Texture2D
@export var character_prepare_texture: Texture2D
@export var character_cheers_texture: Texture2D
@export var character_failure_texture: Texture2D

const BASE_TEXT_COLOR: Color = Color(1.0, 0.91, 0.45)
const BASE_OUTLINE_COLOR: Color = Color(0.95, 0.35, 0.12)
const SUCCESS_TEXT_COLOR: Color = Color(1.0, 0.78, 0.15)
const SUCCESS_OUTLINE_COLOR: Color = Color(0.75, 0.10, 0.50)
const FAILURE_TEXT_COLOR: Color = Color.WHITE
const FAILURE_OUTLINE_COLOR: Color = Color(0.05, 0.25, 0.45)
const FAILURE_CHARACTER_MODULATE: Color = Color(0.55, 0.65, 0.75)
const BASE_OUTLINE_SIZE: int = 12
const RESULT_OUTLINE_SIZE: int = 18

var rhythm_session: RhythmSession


func configure(new_rhythm_session: RhythmSession) -> void:
	rhythm_session = new_rhythm_session

	if not rhythm_session.character_state_changed.is_connected(
		_on_character_state_changed
	):
		rhythm_session.character_state_changed.connect(
			_on_character_state_changed
		)

	set_character_state(rhythm_session.character_state)


func advance(_song_time: float) -> void:
	pass


func _on_character_state_changed(
	state: RhythmTypes.CharacterState
) -> void:
	set_character_state(state)


func set_character_state(state: RhythmTypes.CharacterState) -> void:
	character.modulate = Color.WHITE

	match state:
		RhythmTypes.CharacterState.NORMAL:
			character.texture = character_normal_texture

		RhythmTypes.CharacterState.PREPARE:
			character.texture = character_prepare_texture

		RhythmTypes.CharacterState.JUDGING, \
		RhythmTypes.CharacterState.SUCCESS:
			character.texture = character_cheers_texture

		RhythmTypes.CharacterState.FAILURE:
			if character_failure_texture != null:
				character.texture = character_failure_texture
			else:
				character.texture = character_normal_texture
				character.modulate = FAILURE_CHARACTER_MODULATE

	update_cheers_text(state)
	update_result_visuals(state)


func update_result_visuals(state: RhythmTypes.CharacterState) -> void:
	var succeeded := state == RhythmTypes.CharacterState.SUCCESS
	player_cheers.visible = succeeded
	cheers_effect.visible = succeeded


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
