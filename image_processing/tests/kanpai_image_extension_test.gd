extends SceneTree

const BODY_PATHS: Array[String] = [
	"res://assets/character_templates/normal.png",
	"res://assets/character_templates/prepare.png",
	"res://assets/character_templates/judging.png",
	"res://assets/character_templates/success.png",
	"res://assets/character_templates/failure.png",
]
const PANEL_PATHS: Array[String] = [
	"res://assets/character_templates/default_hair.png",
	"res://assets/character_templates/default_hair.png",
	"res://assets/character_templates/default_hair.png",
	"res://assets/character_templates/success_overlay.png",
	"res://assets/character_templates/failure_overlay.png",
]
const CASCADE_PATH: String = (
	"res://assets/character_templates/haarcascade_frontalface_alt.xml"
)

var failures: Array[String] = []
var async_completed_request_id: int = 0
var async_images: Resource
var async_failure_request_id: int = 0


func _initialize() -> void:
	call_deferred("run_tests")


func run_tests() -> void:
	expect_true(
		ClassDB.class_exists("KanpaiImageProcessor"),
		"KanpaiImageProcessorをClassDBへ登録する"
	)
	expect_true(
		ClassDB.class_exists("KanpaiCharacterImageSet"),
		"KanpaiCharacterImageSetをClassDBへ登録する"
	)
	if not failures.is_empty():
		finish_tests()
		return

	var processor := ClassDB.instantiate("KanpaiImageProcessor") as Node
	root.add_child(processor)
	processor.connect("generation_completed", _on_generation_completed)
	processor.connect("generation_failed", _on_generation_failed)
	var body_images: Array[Image] = []
	var panel_images: Array[Image] = []
	for path: String in BODY_PATHS:
		body_images.append((load(path) as Texture2D).get_image())
	for path: String in PANEL_PATHS:
		panel_images.append((load(path) as Texture2D).get_image())

	expect_true(
		processor.call(
			"configure",
			body_images,
			panel_images,
			FileAccess.get_file_as_string(CASCADE_PATH)
		),
		"Godot Imageから5状態の素材を設定する"
	)
	expect_true(
		processor.call("generate_sync", Image.new()) == null,
		"空のImageを拒否する"
	)

	# 手動・CI確認時だけ、Git管理外の顔写真で成功経路まで検証する。
	var private_face_path := OS.get_environment("KANPAI_TEST_FACE")
	if not private_face_path.is_empty():
		var input := Image.load_from_file(private_face_path)
		if input.get_format() != Image.FORMAT_RGBA8:
			input.convert(Image.FORMAT_RGBA8)
		var images := processor.call("generate_sync", input) as Resource
		expect_true(images != null, "顔写真から画像セットを生成する")
		if images != null:
			expect_true(bool(images.call("is_complete")), "5状態をすべて生成する")
			for property_name: String in [
				"normal", "prepare", "judging", "success", "failure"
			]:
				var image := images.get(property_name) as Image
				expect_true(
					image.get_size() == Vector2i(628, 1116),
					"%sを628×1116で生成する" % property_name
				)
				expect_true(
					image.get_format() == Image.FORMAT_RGBA8,
					"%sをRGBA8で生成する" % property_name
				)

		var async_request_id := 42
		expect_true(
			processor.call("generate_async", input, async_request_id),
			"非同期画像生成を開始する"
		)
		var frame_count := 0
		while (
			processor.call("is_generation_in_progress")
			and frame_count < 600
		):
			await process_frame
			frame_count += 1
		expect_true(frame_count < 600, "非同期画像生成が完了する")
		expect_true(
			async_completed_request_id == async_request_id,
			"完了signalへrequest IDを返す"
		)
		expect_true(
			async_images != null and bool(async_images.call("is_complete")),
			"完了signalへ5状態の画像を返す"
		)
		expect_true(
			async_failure_request_id == 0,
			"成功した非同期処理では失敗signalを送らない"
		)

	processor.free()
	await process_frame
	finish_tests()


func _on_generation_completed(request_id: int, images: Resource) -> void:
	async_completed_request_id = request_id
	async_images = images


func _on_generation_failed(
	request_id: int,
	_error_code: int,
	_message: String
) -> void:
	async_failure_request_id = request_id


func expect_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish_tests() -> void:
	if failures.is_empty():
		print("Kanpai image extension tests passed.")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)

	quit(1)
