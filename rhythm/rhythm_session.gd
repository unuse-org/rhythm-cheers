class_name RhythmSession
extends Node

signal input_resolved(
	beat: float,
	input_type: RhythmTypes.InputType,
	judgement: String
)
signal character_state_changed(state: RhythmTypes.CharacterState)

# 判定ウィンドウ
const PERFECT_WINDOW: float = 0.30
const GOOD_WINDOW: float = 0.30
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
# 2連乾杯とフレーム落ちを扱うため、未解決の入力対象を時刻順に保持する。
var pending_inputs: Array[Dictionary] = []

# 最後の判定結果
var last_judgement: String = "-"

# 1曲中の乾杯結果。入力確定時だけ更新し、途中入力は数えない。
var cheers_success_count: int = 0
var cheers_failure_count: int = 0

# RhythmChartを読み込む
func configure(new_chart: RhythmChart) -> void:
	# duplicate()でコピーすることで、RhythmChartの内容を変更しても元の譜面に影響しないようにする
	chart = new_chart.events.duplicate(true)
	# インスタンスの生成
	timing = RhythmTiming.new(new_chart.tempo_changes, new_chart.offset)

	# 初期化
	next_event_index = 0
	character_state = RhythmTypes.CharacterState.NORMAL
	input_expected = false
	current_input_beat = 0.0
	pending_inputs.clear()
	last_judgement = "-"
	cheers_success_count = 0
	cheers_failure_count = 0


# 再生時刻までに発生した譜面イベントとMISSを処理する
func advance(song_time: float) -> void:
	process_chart_events(song_time)
	process_missed_inputs(song_time)


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

		# フレームが複数イベントをまたいだ場合も、イベント発生順でMISSを確定する。
		process_missed_inputs(execution_time)
		execute_chart_event(chart_event)
		next_event_index += 1


# 譜面イベントを実行する
func execute_chart_event(chart_event: Dictionary) -> void:
	var event_type: RhythmTypes.EventType = chart_event["type"]

	# RhythmTypes.EventType.PREPARE: 乾杯の準備を開始する
	# RhythmTypes.EventType.EXPECT_CHEERS: 乾杯入力の受付を開始する
	# RhythmTypes.EventType.SHOW_CHEERS: 「杯」で乾杯中の画像へ進める
	# RhythmTypes.EventType.RETURN_NORMAL: キャラクター状態を通常に戻す
	match event_type:
		RhythmTypes.EventType.PREPARE:
			change_character_state(RhythmTypes.CharacterState.PREPARE)

		RhythmTypes.EventType.EXPECT_CHEERS:
			var event_beat: float = chart_event["beat"]
			# 旧形式の明示譜面は、従来どおり受付開始と同時に画像も切り替える。
			var should_show_state: bool = (
				not chart_event.has("show_state")
				or chart_event["show_state"] == true
			)
			start_cheers_window(event_beat, should_show_state)

		RhythmTypes.EventType.SHOW_CHEERS:
			show_cheers_if_pending(float(chart_event["beat"]))

		RhythmTypes.EventType.RETURN_NORMAL:
			change_character_state(RhythmTypes.CharacterState.NORMAL)


# 入力受付を開始する
func start_cheers_window(
	event_beat: float,
	show_state_immediately: bool = true
) -> void:
	pending_inputs.append({
		"beat": event_beat,
		"state_shown": show_state_immediately,
	})
	update_current_input()
	if show_state_immediately:
		change_character_state(RhythmTypes.CharacterState.JUDGING)


# 早めの成功で解決済みなら、SUCCESS画像をJUDGINGで上書きしない。
func show_cheers_if_pending(event_beat: float) -> void:
	for pending_input: Dictionary in pending_inputs:
		if is_equal_approx(float(pending_input["beat"]), event_beat):
			pending_input["state_shown"] = true
			change_character_state(RhythmTypes.CharacterState.JUDGING)
			return


# 入力タイミングを判定する
func judge_input_timing(song_time: float) -> bool:
	if pending_inputs.is_empty():
		set_judgement("NO INPUT EXPECTED")
		return false

	var target_beat: float = pending_inputs[0]["beat"]
	var target_time: float = timing.beat_to_seconds(target_beat)

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
	if pending_inputs.is_empty():
		return

	var resolved_beat: float = pending_inputs.pop_front()["beat"]
	set_judgement(judgement)
	update_current_input()
	# PERFECTとGOODはいずれも乾杯成功として集計する。
	cheers_success_count += 1
	change_character_state(RhythmTypes.CharacterState.SUCCESS)
	input_resolved.emit(
		resolved_beat,
		RhythmTypes.InputType.CHEERS,
		judgement
	)

	restore_pending_character_state()


# 入力されないまま判定可能時間を過ぎた場合
func process_missed_inputs(song_time: float) -> void:
	while not pending_inputs.is_empty():
		var target_beat: float = pending_inputs[0]["beat"]
		var target_time: float = timing.beat_to_seconds(target_beat)

		# 次の乾杯受付開始と前の受付終了が同時でも、前を先に確定する。
		if song_time < target_time + MISS_WINDOW:
			break

		var judgement: String = (
			"MISS: %s"
			% RhythmTypes.InputType.keys()[RhythmTypes.InputType.CHEERS]
		)
		pending_inputs.pop_front()
		update_current_input()
		set_judgement(judgement)
		cheers_failure_count += 1
		change_character_state(RhythmTypes.CharacterState.FAILURE)
		input_resolved.emit(
			target_beat,
			RhythmTypes.InputType.CHEERS,
			judgement
		)

	restore_pending_character_state()


# 次の入力対象がすでに「杯」まで進んでいる場合だけJUDGINGへ戻す。
func restore_pending_character_state() -> void:
	if (
		input_expected
		and bool(pending_inputs[0].get("state_shown", true))
	):
		change_character_state(RhythmTypes.CharacterState.JUDGING)


# 既存UIが参照する互換プロパティをキュー先頭へ同期する。
func update_current_input() -> void:
	input_expected = not pending_inputs.is_empty()
	current_input_beat = (
		float(pending_inputs[0]["beat"]) if input_expected else 0.0
	)


# 既存テストと外部呼出し向けに単数形メソッドも残す。
func process_missed_input(song_time: float) -> void:
	process_missed_inputs(song_time)


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
