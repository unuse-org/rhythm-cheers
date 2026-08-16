class_name CharacterGenerationService
extends Node

signal generation_succeeded(request_id: int, images: Resource)
signal generation_failed(request_id: int, error_code: int, message: String)

# C++のGenerationErrorと同じ順序に揃え、画面側で再撮影可能な失敗を判別する。
enum GenerationError {
	NONE = 0,
	EMPTY_INPUT,
	UNSUPPORTED_PIXEL_FORMAT,
	MISSING_CASCADE,
	INVALID_CASCADE,
	FACE_NOT_FOUND,
	MISSING_TEMPLATE,
	INVALID_TEMPLATE,
	CANCELLED,
	PROCESSING_FAILED,
}

const BODY_TEXTURE_PATHS: Array[String] = [
	"res://assets/character_templates/normal.png",
	"res://assets/character_templates/prepare.png",
	"res://assets/character_templates/judging.png",
	"res://assets/character_templates/success.png",
	"res://assets/character_templates/failure.png",
]
const PANEL_TEXTURE_PATHS: Array[String] = [
	"res://assets/character_templates/default_hair.png",
	"res://assets/character_templates/default_hair.png",
	"res://assets/character_templates/default_hair.png",
	"res://assets/character_templates/success_overlay.png",
	"res://assets/character_templates/failure_overlay.png",
]
# 正面顔検出用のカスケード分類器。
# OpenCVの公式リポジトリから取得。
# https://github.com/opencv/opencv/blob/master/data/haarcascades/haarcascade_frontalface_alt.xml
const CASCADE_PATH: String = (
	"res://assets/character_templates/haarcascade_frontalface_alt.xml"
)

# ヘッドレステストでは物理カメラと重い画像処理を起動しない。
@export var native_processing_enabled: bool = (
	DisplayServer.get_name() != "headless"
)

var processor: Node
var next_request_id: int = 1
var active_request_id: int = 0
var native_request_id: int = 0
var pending_request_id: int = 0
var pending_input_image: Image
var is_available: bool = false


func _ready() -> void:
	if processor == null and native_processing_enabled:
		processor = _create_native_processor()

	if processor == null:
		return

	if processor.get_parent() == null:
		add_child(processor)

	processor.connect(
		"generation_completed",
		_on_native_generation_completed
	)
	processor.connect(
		"generation_failed",
		_on_native_generation_failed
	)
	is_available = _configure_processor()


func _exit_tree() -> void:
	cancel_active_request()


# テストでは_ready()前にFake processorを注入できる。
func set_processor(custom_processor: Node) -> void:
	if is_node_ready():
		push_error("画像生成Processorは_ready()より前に設定してください。")
		return

	processor = custom_processor


func generate(captured_image: Image) -> int:
	var request_id := next_request_id
	next_request_id += 1
	cancel_active_request()
	active_request_id = request_id

	if (
		not is_available
		or processor == null
		or captured_image == null
		or captured_image.is_empty()
	):
		call_deferred(
			"_emit_unavailable_failure",
			request_id,
			GenerationError.PROCESSING_FAILED,
			"キャラクター画像生成を利用できません。"
		)
		return request_id

	# WebCameraCaptureSourceはRGBA8へ変換済みだが、他の撮影元も正規化する。
	var input_image := captured_image.duplicate() as Image
	if input_image.get_format() != Image.FORMAT_RGBA8:
		input_image.convert(Image.FORMAT_RGBA8)

	_start_or_queue_generation(request_id, input_image)

	return request_id


func cancel_active_request() -> void:
	if (
		native_request_id != 0
		and processor != null
		and processor.has_method("cancel")
	):
		processor.call("cancel", native_request_id)

	# ネイティブ処理が停止する前でも、以後の結果を無効化する。
	active_request_id = 0
	pending_request_id = 0
	pending_input_image = null


func has_active_generation() -> bool:
	return (
		active_request_id != 0
		and processor != null
		and (
			pending_request_id == active_request_id
			or (
				processor.has_method("is_generation_in_progress")
				and bool(processor.call("is_generation_in_progress"))
			)
		)
	)


# cancelはワーカーを停止要求するだけなので、停止完了までは最新写真を1件待機する。
func _start_or_queue_generation(request_id: int, input_image: Image) -> void:
	if (
		processor.has_method("is_generation_in_progress")
		and bool(processor.call("is_generation_in_progress"))
	):
		pending_request_id = request_id
		pending_input_image = input_image
		return

	native_request_id = request_id
	if processor.call("generate_async", input_image, request_id):
		return

	native_request_id = 0
	call_deferred(
		"_emit_unavailable_failure",
		request_id,
		GenerationError.PROCESSING_FAILED,
		"キャラクター画像生成を開始できませんでした。"
	)


func _start_pending_generation() -> void:
	if (
		pending_request_id == 0
		or pending_request_id != active_request_id
		or pending_input_image == null
	):
		return

	var request_id := pending_request_id
	var input_image := pending_input_image
	pending_request_id = 0
	pending_input_image = null
	_start_or_queue_generation(request_id, input_image)


func _create_native_processor() -> Node:
	if not ClassDB.class_exists("KanpaiImageProcessor"):
		return null

	return ClassDB.instantiate("KanpaiImageProcessor") as Node


func _configure_processor() -> bool:
	if processor == null or not processor.has_method("configure"):
		return false

	var body_images: Array[Image] = []
	var panel_images: Array[Image] = []

	for path: String in BODY_TEXTURE_PATHS:
		var image := _load_texture_image(path)
		if image == null:
			return false
		body_images.append(image)

	for path: String in PANEL_TEXTURE_PATHS:
		var image := _load_texture_image(path)
		if image == null:
			return false
		panel_images.append(image)

	var cascade_xml := FileAccess.get_file_as_string(CASCADE_PATH)
	if cascade_xml.is_empty():
		return false

	return bool(processor.call(
		"configure",
		body_images,
		panel_images,
		cascade_xml
	))


func _load_texture_image(path: String) -> Image:
	var texture := load(path) as Texture2D
	if texture == null:
		return null

	var image := texture.get_image()
	if image == null or image.is_empty():
		return null

	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)

	return image


func _on_native_generation_completed(
	request_id: int,
	images: Resource
) -> void:
	if request_id == native_request_id:
		native_request_id = 0

	if request_id != active_request_id:
		_start_pending_generation()
		return

	active_request_id = 0
	generation_succeeded.emit(request_id, images)


func _on_native_generation_failed(
	request_id: int,
	error_code: int,
	message: String
) -> void:
	if request_id == native_request_id:
		native_request_id = 0

	if request_id != active_request_id:
		_start_pending_generation()
		return

	active_request_id = 0
	generation_failed.emit(request_id, error_code, message)


func _emit_unavailable_failure(
	request_id: int,
	error_code: int,
	message: String
) -> void:
	if request_id != active_request_id:
		return

	active_request_id = 0
	if request_id == pending_request_id:
		pending_request_id = 0
		pending_input_image = null
	generation_failed.emit(request_id, error_code, message)
