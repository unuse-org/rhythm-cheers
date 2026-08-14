class_name RunContext
extends RefCounted

const AMOUNT_PER_SUCCESS: int = 500
const AMOUNT_PER_FAILURE: int = -50

# 1プレイの間だけ保持し、リザルトからタイトルへ戻る際に破棄する。
var captured_face_image: Image
var processed_face_image: Image
var tutorial_completed: bool = false
var cheers_success_count: int = 0
var cheers_failure_count: int = 0


func calculate_success_amount() -> int:
	return cheers_success_count * AMOUNT_PER_SUCCESS


func calculate_failure_amount() -> int:
	return cheers_failure_count * AMOUNT_PER_FAILURE


func calculate_total_amount() -> int:
	return calculate_success_amount() + calculate_failure_amount()


func clear() -> void:
	captured_face_image = null
	processed_face_image = null
	tutorial_completed = false
	cheers_success_count = 0
	cheers_failure_count = 0
