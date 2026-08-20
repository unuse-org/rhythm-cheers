class_name CameraCaptureSource
extends Node

# 画面側がカメラ固有APIを知らなくても状態を表示できるようにする。
enum State {
	IDLE,
	DISCOVERING,
	READY,
	CAPTURING,
	CAPTURED,
	UNAVAILABLE,
	ERROR,
}

signal preview_ready(texture: Texture2D)
signal state_changed(next_state: State, message: String)
signal capture_succeeded(image: Image)
signal capture_failed(message: String)

var state: State = State.IDLE
var state_message: String = ""


# 派生クラスは、撮影元の初期化を開始してREADYまで状態を進める。
func start() -> void:
	_set_state(State.ERROR, "撮影元が実装されていません。")


# 画面を離れた時に繰り返し呼ばれても安全に停止できるようにする。
func stop() -> void:
	_set_state(State.IDLE)


# 派生クラスは、READYの時点に表示されている1フレームを返す。
func capture_frame() -> void:
	capture_failed.emit("撮影元が実装されていません。")


func _set_state(next_state: State, message: String = "") -> void:
	state = next_state
	state_message = message
	state_changed.emit(next_state, message)
