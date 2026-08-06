class_name RhythmSession
extends Node

signal input_resolved(
	beat: float,
	input_type: RhythmTypes.InputType,
	judgement: String
)
signal character_state_changed(state: RhythmTypes.CharacterState)

# 判定ウィンドウ
const PERFECT_WINDOW: float = 0.05
const GOOD_WINDOW: float = 0.10
const MISS_WINDOW: float = 0.20

# 読み込み済みの譜面イベントと時間情報
var chart: Array[Dictionary] = []
var timing: RhythmTiming

# イベント処理
var next_event_index: int = 0

# キャラクター状態
var character_state: RhythmTypes.CharacterState = RhythmTypes.CharacterState.NORMAL

# 入力判定
var input_expected: bool = false
var current_input_beat: float = 0.0

# 最後の判定結果
var last_judgement: String = "-"

# RhythmChartを読み込む
func configure(new_chart: RhythmChart) -> void:
	# duplicate()でコピーすることで、RhythmChartの内容を変更しても元の譜面に影響しないようにする
	chart = new_chart.events.duplicate(true)
	# インスタンスの生成
	timing = RhythmTiming.new(new_chart.bpm, new_chart.offset)

	# 初期化
	next_event_index = 0
	character_state = RhythmTypes.CharacterState.NORMAL
	input_expected = false
	current_input_beat = 0.0
	last_judgement = "-"


# 再生時刻までに発生した譜面イベントとMISSを処理する
func advance(song_time: float) -> void:
	process_chart_events(song_time)
	process_missed_input(song_time)


# SensorProviderから入力を受信する
func receive_input(
	sensor_input_type: RhythmTypes.InputType,
	song_time: float
) -> bool:
	if not input_expected:
		set_judgement("NO INPUT EXPECTED")
		return false

	if sensor_input_type != RhythmTypes.InputType.CHEERS:
		set_judgement("WRONG INPUT TYPE")
		return false

	return judge_input_timing(song_time)


# 譜面イベントを時刻に従って実行する
func process_chart_events(song_time: float) -> void:
	while next_event_index < chart.size():
		var chart_event: Dictionary = chart[next_event_index]

		var event_type: RhythmTypes.EventType = chart_event["type"]
		var event_beat: float = chart_event["beat"]
		var event_time: float = timing.beat_to_seconds(event_beat)

		var execution_time: float = event_time

		# 判定時刻よりMISS_WINDOW秒前から入力受付を開始する
		if event_type == RhythmTypes.EventType.EXPECT_CHEERS:
			execution_time -= MISS_WINDOW

		if song_time < execution_time:
			break

		execute_chart_event(chart_event)
		next_event_index += 1


# 譜面イベントを実行する
func execute_chart_event(chart_event: Dictionary) -> void:
	var event_type: RhythmTypes.EventType = chart_event["type"]

	# RhythmTypes.EventType.PREPARE: 乾杯の準備を開始する
	# RhythmTypes.EventType.EXPECT_CHEERS: 乾杯入力の受付を開始する
	# RhythmTypes.EventType.RETURN_NORMAL: キャラクター状態を通常に戻す
	match event_type:
		RhythmTypes.EventType.PREPARE:
			input_expected = false
			change_character_state(RhythmTypes.CharacterState.PREPARE)

		RhythmTypes.EventType.EXPECT_CHEERS:
			var event_beat: float = chart_event["beat"]
			start_cheers_window(event_beat)

		RhythmTypes.EventType.RETURN_NORMAL:
			input_expected = false
			change_character_state(RhythmTypes.CharacterState.NORMAL)


# 入力受付を開始する
func start_cheers_window(event_beat: float) -> void:
	# 値を更新して入力受付状態にする
	current_input_beat = event_beat
	input_expected = true
	change_character_state(RhythmTypes.CharacterState.JUDGING)


# 入力タイミングを判定する
func judge_input_timing(song_time: float) -> bool:
	if not input_expected:
		set_judgement("NO INPUT EXPECTED")
		return false

	var target_time: float = timing.beat_to_seconds(current_input_beat)

	# 入力時刻と目標時刻の差を計算する
	var difference: float = song_time - target_time
	var absolute_difference: float = absf(difference)

	if absolute_difference <= PERFECT_WINDOW:
		complete_input("PERFECT")
		return true

	elif absolute_difference <= GOOD_WINDOW:
		complete_input("GOOD")
		return true

	elif difference < -GOOD_WINDOW:
		set_judgement("TOO EARLY")

	else:
		set_judgement("TOO LATE")

	return false


# 入力成功時の処理
func complete_input(judgement: String) -> void:
	set_judgement(judgement)
	input_expected = false
	change_character_state(RhythmTypes.CharacterState.SUCCESS)
	input_resolved.emit(
		current_input_beat,
		RhythmTypes.InputType.CHEERS,
		judgement
	)


# 入力されないまま判定可能時間を過ぎた場合
func process_missed_input(song_time: float) -> void:
	if not input_expected:
		return

	var target_time: float = timing.beat_to_seconds(current_input_beat)

	if song_time <= target_time + MISS_WINDOW:
		return

	var judgement: String = (
		"MISS: %s"
		% RhythmTypes.InputType.keys()[RhythmTypes.InputType.CHEERS]
	)

	set_judgement(judgement)
	input_expected = false
	change_character_state(RhythmTypes.CharacterState.FAILURE)
	input_resolved.emit(
		current_input_beat,
		RhythmTypes.InputType.CHEERS,
		judgement
	)


# キャラクター状態を変更する
func change_character_state(new_state: RhythmTypes.CharacterState) -> void:
	if character_state == new_state:
		return

	character_state = new_state
	character_state_changed.emit(character_state)

	print(
		"Character state: ",
		RhythmTypes.CharacterState.keys()[character_state]
	)


# 最後の判定結果を更新する
func set_judgement(judgement: String) -> void:
	last_judgement = judgement


# 現在期待している入力タイプ名を返す
func get_expected_input_type_string() -> String:
	if not input_expected:
		return "-"

	return RhythmTypes.InputType.keys()[RhythmTypes.InputType.CHEERS]
