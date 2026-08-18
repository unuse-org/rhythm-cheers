extends SceneTree

class FakeProcessor:
	extends Node

	signal generation_completed(request_id: int, images: Resource)
	signal generation_failed(request_id: int, error_code: int, message: String)

	var processing: bool = false
	var configured: bool = false
	var configured_decoration_count: int = 0
	var cancelled_requests: Array[int] = []
	var started_requests: Array[int] = []

	func configure(
		_body_images: Array,
		_decoration_images: Array,
		_face_detector_model: PackedByteArray
	) -> bool:
		configured = true
		configured_decoration_count = _decoration_images.size()
		return true

	func generate_async(_image: Image, request_id: int) -> bool:
		processing = true
		started_requests.append(request_id)
		return true

	func cancel(request_id: int) -> void:
		cancelled_requests.append(request_id)

	func is_generation_in_progress() -> bool:
		return processing

	func succeed(request_id: int, images: Resource) -> void:
		processing = false
		generation_completed.emit(request_id, images)


class FakeImageSet:
	extends Resource

	var normal: Image
	var prepare: Image
	var judging: Image
	var success: Image
	var failure: Image


var failures: Array[String] = []
var succeeded_requests: Array[int] = []


func _initialize() -> void:
	call_deferred("run_tests")


func run_tests() -> void:
	var processor := FakeProcessor.new()
	var service := CharacterGenerationService.new()
	service.native_processing_enabled = false
	service.set_processor(processor)
	service.generation_succeeded.connect(_on_generation_succeeded)
	root.add_child(service)
	await process_frame

	expect_true(service.is_available, "Fake processorを初期化する")
	expect_equal(
		processor.configured_decoration_count,
		4,
		"髪・ひげ・ほっぺ・失敗マークを個別に設定する"
	)
	var input := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	input.fill(Color.WHITE)
	var first_request := service.generate(input)
	var second_request := service.generate(input)
	expect_true(
		processor.cancelled_requests.has(first_request),
		"新しい撮影時に前のrequestをキャンセルする"
	)

	var images := FakeImageSet.new()
	processor.succeed(first_request, images)
	expect_equal(succeeded_requests.size(), 0, "古い生成結果を破棄する")
	expect_equal(
		processor.started_requests,
		[first_request, second_request],
		"旧request停止後に最新写真の生成を開始する"
	)
	processor.succeed(second_request, images)
	expect_equal(succeeded_requests, [second_request], "最新結果だけを通知する")

	service.free()
	await process_frame
	finish_tests()


func _on_generation_succeeded(request_id: int, _images: Resource) -> void:
	succeeded_requests.append(request_id)


func expect_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append(
			"%s: expected=%s actual=%s" % [message, expected, actual]
		)


func finish_tests() -> void:
	if failures.is_empty():
		print("CharacterGenerationService tests passed.")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)

	quit(1)
