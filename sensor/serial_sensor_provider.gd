class_name SerialSensorProvider
extends SensorProvider

var manager: GdSerialManager

# ls /dev/cu.usbserial-* で確認すること
var port_name: String = "/dev/cu.usbserial-B152356A38"
var baud_rate: int = 115200

# ============================================================
# 判定閾値（起動時オートキャリブレーションで上書きされる）
# ============================================================
var CHEERS_THRESHOLD: float = 0.3   # フォールバック値

@export var calibration_duration: float = 3.0
@export var cheers_k: float = 2.0
@export var cheers_min_margin: float = 0.05  # std≈0対策の下限

# 乾杯方向の単位ベクトル（センサーローカル座標系）。
# バネの主振動軸と直交に近いほどノイズ除去効果が高い。要実測。
@export var cheers_direction: Vector3 = Vector3(1, 0, 0)

# 方向成分判定によりバネ振動の混入を抑制できるため短縮可能。要実機調整。
@export var cooldown_duration: float = 0.15

@export var debug_enabled: bool = false

var _line_buffer: String = ""

enum _State { CALIBRATING, IDLE, COOLDOWN }
var _state: _State = _State.CALIBRATING

var _calibration_samples: Array[Vector3] = []
var _calibration_timer: float = 0.0

var _baseline_vec: Vector3 = Vector3.ZERO  # 重力込み静止姿勢の基準ベクトル
var _baseline_std: float = 0.05

var _cooldown_timer: float = 0.0


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
	# poll_events()を呼ばないとdata_receivedが発火しない（GdSerialManager仕様）
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


# 受信データは改行区切りJSON1行=1サンプル前提。TCP的な分割/結合が起こりうるため
# バッファに貯めてから改行単位で切り出す。
func _on_data_received(port: String, data: PackedByteArray) -> void:
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

	var accel_vec := Vector3(parsed["x"], parsed["y"], parsed["z"])

	if debug_enabled:
		print("[Accel] x=%.3f y=%.3f z=%.3f" % [accel_vec.x, accel_vec.y, accel_vec.z])

	if _state == _State.CALIBRATING:
		_calibration_samples.append(accel_vec)
		return

	_judge(accel_vec)


# 合成加速度ではなく乾杯方向への射影成分で判定する。
# 理由: バネ振動は特定軸（主に鉛直）に集中するため、直交方向を見れば
# 振動由来の誤検出を構造的に排除できる。cooldownを短縮できるのはこのため。
func _judge(accel_vec: Vector3) -> void:
	var dir := cheers_direction.normalized()
	var directional_accel := (accel_vec - _baseline_vec).dot(dir)

	if debug_enabled:
		var raw_magnitude := (accel_vec - _baseline_vec).length()
		print("[Judge] directional=%.3f  raw_magnitude=%.3f  threshold=%.3f" % [directional_accel, raw_magnitude, CHEERS_THRESHOLD])

	if _state == _State.IDLE and directional_accel >= CHEERS_THRESHOLD:
		_fire_cheers()


func _fire_cheers() -> void:
	if debug_enabled:
		print("[Judge] CHEERS detected")
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

	var sum_vec := Vector3.ZERO
	for v in _calibration_samples:
		sum_vec += v
	_baseline_vec = sum_vec / n

	# 射影成分の標準偏差からノイズ幅を算出。平均は定義上0になる。
	var dir := cheers_direction.normalized()
	var sq_sum := 0.0
	for v in _calibration_samples:
		var proj := (v - _baseline_vec).dot(dir)
		sq_sum += proj * proj
	_baseline_std = sqrt(sq_sum / n)
	_baseline_std = max(_baseline_std, 0.01)  # 無音環境でのゼロ割/過敏化防止

	CHEERS_THRESHOLD = max(cheers_k * _baseline_std, cheers_min_margin)

	if debug_enabled:
		print("[SerialSensorProvider] キャリブレーション完了")
		print("  baseline_vec=%s  baseline_std=%.4f" % [_baseline_vec, _baseline_std])
		print("  CHEERS_THRESHOLD=%.4f" % CHEERS_THRESHOLD)

	_state = _State.IDLE


func recalibrate() -> void:
	_start_calibration()


func get_calibration_info() -> Dictionary:
	return {
		"baseline_vec": _baseline_vec,
		"baseline_std": _baseline_std,
		"cheers_threshold": CHEERS_THRESHOLD,
		"cheers_direction": cheers_direction,
		"state": _State.keys()[_state],
	}
