class_name GameplayVisual
extends Control

@onready var world: Control = $World
@onready var opponent_template: Control = $World/Opponent0
@onready var player_cheers: TextureRect = $PlayerCheers
@onready var cheers_effect: TextureRect = $CheersEffect
@onready var first_cheers_character: Label = $CheersText/FirstCharacter
@onready var second_cheers_character: Label = $CheersText/SecondCharacter

var character: TextureRect

@export_category("Character")
@export var character_normal_texture: Texture2D
@export var character_prepare_texture: Texture2D
@export var character_cheers_texture: Texture2D
@export var character_failure_texture: Texture2D
@export_range(0.0, 48.0, 0.5) var character_bob_amplitude: float = 12.0

@export_category("Horizontal Progress")
@export_range(720.0, 1440.0, 1.0) var opponent_spacing: float = 720.0

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
var character_base_position: Vector2
var world_base_position: Vector2
var opponent_stations: Array[Control] = []
var movement_segments: Array[Dictionary] = []
var opponent_count: int = 1
var active_opponent_index: int = 0
var current_character_state: RhythmTypes.CharacterState = (
	RhythmTypes.CharacterState.NORMAL
)


func _ready() -> void:
	world_base_position = world.position


func configure(new_rhythm_session: RhythmSession) -> void:
	rhythm_session = new_rhythm_session
	world.position = world_base_position
	initialize_movement_segments()
	initialize_opponent_stations()
	set_active_opponent(0)

	if not rhythm_session.character_state_changed.is_connected(
		_on_character_state_changed
	):
		rhythm_session.character_state_changed.connect(
			_on_character_state_changed
		)

	current_character_state = rhythm_session.character_state
	set_character_state(current_character_state)


func advance(song_time: float) -> void:
	if rhythm_session == null:
		return

	var current_beat := rhythm_session.timing.seconds_to_beats(song_time)
	update_active_opponent(current_beat)
	update_world_position(current_beat)

	if rhythm_session.character_state != RhythmTypes.CharacterState.NORMAL:
		reset_character_position()
		return

	var beat_progress := fposmod(current_beat, 1.0)
	var vertical_offset := -sin(beat_progress * PI) * character_bob_amplitude

	character.position = (
		character_base_position + Vector2(0.0, vertical_offset)
	)


func _on_character_state_changed(
	state: RhythmTypes.CharacterState
) -> void:
	current_character_state = state
	set_character_state(state)


func initialize_movement_segments() -> void:
	movement_segments.clear()
	opponent_count = 0

	var previous_return_beat: float = NAN

	for chart_event: Dictionary in rhythm_session.chart:
		var event_type: RhythmTypes.EventType = chart_event["type"]
		var event_beat: float = chart_event["beat"]

		match event_type:
			RhythmTypes.EventType.RETURN_NORMAL:
				previous_return_beat = event_beat

			RhythmTypes.EventType.PREPARE:
				if opponent_count > 0 and not is_nan(previous_return_beat):
					movement_segments.append({
						"start_beat": previous_return_beat,
						"end_beat": event_beat,
						"from_index": opponent_count - 1,
						"to_index": opponent_count,
					})

				opponent_count += 1

	opponent_count = maxi(opponent_count, 1)


func initialize_opponent_stations() -> void:
	character = null

	for station: Control in opponent_stations:
		if station != opponent_template and is_instance_valid(station):
			station.free()

	opponent_stations.clear()
	opponent_template.position = Vector2.ZERO
	opponent_template.name = "Opponent0"
	opponent_stations.append(opponent_template)

	for index: int in range(1, opponent_count):
		var station := opponent_template.duplicate() as Control
		station.name = "Opponent%d" % index
		station.position = Vector2(opponent_spacing * index, 0.0)
		world.add_child(station)
		opponent_stations.append(station)

	world.size.x = opponent_spacing * opponent_count


func set_active_opponent(index: int) -> void:
	if opponent_stations.is_empty():
		return

	if character != null:
		character.position = character_base_position
		character.texture = character_normal_texture
		character.modulate = Color.WHITE

	active_opponent_index = clampi(index, 0, opponent_stations.size() - 1)
	var station := opponent_stations[active_opponent_index]
	character = station.get_node("Character") as TextureRect
	character_base_position = character.position


func update_active_opponent(current_beat: float) -> void:
	var target_index: int = 0

	for segment: Dictionary in movement_segments:
		if current_beat < float(segment["start_beat"]):
			break

		target_index = int(segment["to_index"])

	if target_index == active_opponent_index:
		return

	set_active_opponent(target_index)
	set_character_state(current_character_state)


func update_world_position(current_beat: float) -> void:
	var station_position: float = 0.0

	for segment: Dictionary in movement_segments:
		var start_beat: float = segment["start_beat"]
		var end_beat: float = segment["end_beat"]
		var from_index: float = segment["from_index"]
		var to_index: float = segment["to_index"]

		if current_beat < start_beat:
			break

		if current_beat >= end_beat:
			station_position = to_index
			continue

		var duration := end_beat - start_beat
		var progress := 1.0

		if duration > 0.0:
			progress = clampf(
				(current_beat - start_beat) / duration,
				0.0,
				1.0
			)

		var eased_progress := smoothstep(0.0, 1.0, progress)
		station_position = lerpf(from_index, to_index, eased_progress)
		break

	world.position = Vector2(
		world_base_position.x - station_position * opponent_spacing,
		world_base_position.y
	)


func set_character_state(state: RhythmTypes.CharacterState) -> void:
	reset_character_position()
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


func reset_character_position() -> void:
	character.position = character_base_position


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
