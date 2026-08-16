class_name SerialSensorProvider
extends SensorProvider

var manager: GdSerialManager

# シリアル接続先を固定値で持つ。
# 実運用では環境差異に応じてポート選択や設定の自動判定を入れると安全。
var port_name: String = "/dev/cu.usbserial-B152356A38"
var baud_rate: int = 115200  # Receiver側が Serial.begin(115200)

# ============================================================
# 判定用しきい値（起動時オートキャリブレーションで自動算出される）
# 以下は算出前・キャリブレーション失敗時のフォールバック値
# ============================================================
var CHEERS_THRESHOLD: float = 2.0   # 乾杯の強い加速度変化

# --- キャリブレーション設定 ---
# 起動時に静止状態を数秒間サンプリングし、
# 基準値（baseline）とノイズ幅（std_dev）から判定閾値を自動計算する。
@export var calibration_duration: float = 3.0   # 起動時に静止状態をサンプリングする時間（秒）
@export var cheers_k: float = 3.0                # CHEERS  = baseline + k * std_dev

# しきい値がbaseline付近まで下がりすぎないようにする絶対マージン
# （静かな環境でキャリブレーションするとstd_devが小さくなりすぎる対策）
@export var cheers_min_margin: float = 0.05

# --- ヒステリシス/クールダウン設定（バネマウントの余韻振動対策） ---
@export var cooldown_duration: float = 0.4       # 発火後の不感時間（秒）。バネの減衰時間に合わせて調整
@export var peak_window: float = 0.08            # しきい値超過後、ピークを探すウィンドウ（秒）

# デバッグ出力の有無（不要になったら false に）
@export var debug_enabled: bool = false

var _line_buffer: String = ""

# --- 判定ステートマシン ---
enum _State { CALIBRATING, IDLE, ARMED_ABOVE, COOLDOWN }
var _state: _State = _State.CALIBRATING

var _calibration_samples: Array[float] = []
var _calibration_timer: float = 0.0

var _baseline_mean: float = 1.0
var _baseline_std: float = 0.05

var _cooldown_timer: float = 0.0

var _peak_timer: float = 0.0
var _peak_value: float = 0.0


func start() -> void:
	manager = GdSerialManager.new()

	if not manager.data_received.is_connected(_on_data_received):
		manager.data_received.connect(_on_data_received)

	if manager.open(port_name, baud_rate, 1000):
		connection_changed.emit(true)
		_start_calibration()
	else:
		sensor_error.emit("シリアルポートを開けませんでした: " + port_name)
		connection_changed.emit(false)


func stop() -> void:
	if manager != null:
		if manager.data_received.is_connected(_on_data_received):
			manager.data_received.disconnect(_on_data_received)
		manager.close(port_name)
	_line_buffer = ""
	_state = _State.CALIBRATING
	_calibration_samples.clear()
	_calibration_timer = 0.0
	connection_changed.emit(false)


func _process(delta: float) -> void:
	# SensorProvider が Node を継承しシーンツリーに追加されていないと呼ばれない点に注意
	if manager != null:
		manager.poll_events()

	match _state:
		_State.CALIBRATING:
			_calibration_timer += delta
			if _calibration_timer >= calibration_duration:
				_finish_calibration()
		_State.COOLDOWN:
			_cooldown_timer -= delta
			if _cooldown_timer <= 0.0:
				_state = _State.IDLE
		_State.ARMED_ABOVE:
			_peak_timer -= delta
			if _peak_timer <= 0.0:
				_fire_peak()


# データは1行1JSONで届く想定（Serial.printf(...\n) なので改行区切り）
func _on_data_received(port: String, data: PackedByteArray) -> void:
	# 自分が開いているポート以外からのデータは無視する
	if port != port_name:
		return

	_line_buffer += data.get_string_from_utf8()

	while true:
		var newline_index := _line_buffer.find("\n")
		if newline_index == -1:
			break

		var line := _line_buffer.substr(0, newline_index).strip_edges()
		_line_buffer = _line_buffer.substr(newline_index + 1)

		if line.is_empty():
			continue

		_parse_and_judge(line)


func _parse_and_judge(json_line: String) -> void:
	var json := JSON.new()
	var parse_result := json.parse(json_line)

	if parse_result != OK:
		sensor_error.emit("JSONパース失敗: " + json_line)
		return

	if typeof(json.data) != TYPE_DICTIONARY:
		sensor_error.emit("予期しないJSON形式: " + json_line)
		return

	var parsed: Dictionary = json.data
	if not (parsed.has("x") and parsed.has("y") and parsed.has("z")):
		return

	var x: float = parsed["x"]
	var y: float = parsed["y"]
	var z: float = parsed["z"]

	# 合成加速度の大きさで判定（一例。重力補正済みの値が届く前提）
	var magnitude := Vector3(x, y, z).length()

	if debug_enabled:
		print("[Accel] x=%.3f y=%.3f z=%.3f | magnitude=%.3f" % [x, y, z, magnitude])

	# キャリブレーション中はサンプルを貯めるだけ
	if _state == _State.CALIBRATING:
		_calibration_samples.append(magnitude)
		return

	_judge(magnitude)


func _judge(magnitude: float) -> void:
	# 判定は状態ごとに分岐し、閾値を超えたあとに
	# 一定時間だけピーク値を追うことで、余韻や振動揺れを抑える。
	match _state:
		_State.IDLE:
			if magnitude >= CHEERS_THRESHOLD:
				_start_peak_window(magnitude)

		_State.ARMED_ABOVE:
			# ピークウィンドウ中は最大値だけ更新し、判定タイミングを1回に限定する
			if magnitude > _peak_value:
				_peak_value = magnitude

		_State.COOLDOWN:
			# クールダウン中はバネの余韻振動とみなして無視
			pass


func _start_peak_window(magnitude: float) -> void:
	# 閾値を超えた瞬間からピーク探索を開始し、
	# その後の短時間内で最大値を拾って入力判定を安定化させる。
	_state = _State.ARMED_ABOVE
	_peak_value = magnitude
	_peak_timer = peak_window


func _fire_peak() -> void:
	# ピーク時刻を過ぎたら、計測済みの最大値を実入力として取り込む。
	if debug_enabled:
		print("[Judge] CHEERS detected (magnitude=%.3f)" % _peak_value)
	input_detected.emit(RhythmTypes.InputType.CHEERS)

	_state = _State.COOLDOWN
	_cooldown_timer = cooldown_duration


func _start_calibration() -> void:
	_state = _State.CALIBRATING
	_calibration_samples.clear()
	_calibration_timer = 0.0
	if debug_enabled:
		print("[SerialSensorProvider] キャリブレーション開始。%.1f秒間静止させてください..." % calibration_duration)


func _finish_calibration() -> void:
	if _calibration_samples.is_empty():
		push_warning("[SerialSensorProvider] キャリブレーションサンプルが0件。フォールバック値を使用します。")
		_state = _State.IDLE
		return

	var n := _calibration_samples.size()
	var sum := 0.0
	for v in _calibration_samples:
		sum += v
	_baseline_mean = sum / n

	var sq_sum := 0.0
	for v in _calibration_samples:
		sq_sum += (v - _baseline_mean) * (v - _baseline_mean)
	_baseline_std = sqrt(sq_sum / n)
	_baseline_std = max(_baseline_std, 0.01)  # ノイズがほぼ無い場合の下限

	# k*std方式に加えて絶対マージンの下限を保証する
	# （静かな環境でstdが小さくなりすぎて過敏になるのを防ぐ）
	CHEERS_THRESHOLD = max(
		_baseline_mean + cheers_k * _baseline_std,
		_baseline_mean + cheers_min_margin
	)

	if debug_enabled:
		print("[SerialSensorProvider] キャリブレーション完了")
		print("  baseline_mean=%.4f  baseline_std=%.4f" % [_baseline_mean, _baseline_std])
		print("  CHEERS_THRESHOLD=%.4f" % CHEERS_THRESHOLD)

	_state = _State.IDLE


# 手動で再キャリブレーションしたい場合（デバッグUIから呼ぶ想定）
func recalibrate() -> void:
	_start_calibration()


# デバッグUI表示用にキャリブレーション値を取得
func get_calibration_info() -> Dictionary:
	return {
		"baseline_mean": _baseline_mean,
		"baseline_std": _baseline_std,
		"cheers_threshold": CHEERS_THRESHOLD,
		"state": _State.keys()[_state],
	}
