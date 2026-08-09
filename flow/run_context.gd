class_name RunContext
extends RefCounted

# 1プレイの間だけ保持し、リザルトからタイトルへ戻る際に破棄する。
var captured_face_image: Image
var processed_face_image: Image
var tutorial_completed: bool = false
var cheers_success_count: int = 0
var cheers_failure_count: int = 0
var result_value: int = 0


func clear() -> void:
	captured_face_image = null
	processed_face_image = null
	tutorial_completed = false
	cheers_success_count = 0
	cheers_failure_count = 0
	result_value = 0
