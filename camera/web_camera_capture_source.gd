class_name WebCameraCaptureSource
extends CameraCaptureSource

const SUPPORTED_PLATFORMS: Array[String] = [
	"macOS",
]
# YCbCrからRGBへの変換は、Godot標準のCameraTextureでは行えないため、Shaderで変換する。
const YCBCR_TO_RGB_SHADER: Shader = preload(
	"res://camera/ycbcr_to_rgb.gdshader"
)

@export var preferred_size: Vector2i = Vector2i(1280, 720)

var camera_feed: CameraFeed
var primary_camera_texture: CameraTexture
var cbcr_camera_texture: CameraTexture
var preview_texture: Texture2D
var conversion_viewport: SubViewport
var conversion_rect: ColorRect
var configured_data_type: CameraFeed.FeedDataType = CameraFeed.FEED_NOIMAGE


func start() -> void:
	if state != State.IDLE:
		return

	if OS.get_name() not in SUPPORTED_PLATFORMS:
		_set_state(
			State.ERROR,
			"このOSではGodot標準のWebカメラ取得を利用できません。"
		)
		return

	_connect_camera_server_signals()
	_set_state(State.DISCOVERING, "Webカメラを探しています。")

	# CameraServerは監視開始後に非同期でフィード一覧を更新する。
	CameraServer.monitoring_feeds = true
	_discover_camera()


func stop() -> void:
	_release_camera()
	_disconnect_camera_server_signals()

	# カメラを使う画面の外では監視コストとカメラ利用を残さない。
	CameraServer.monitoring_feeds = false
	_set_state(State.IDLE)


func capture_frame() -> void:
	if state != State.READY or preview_texture == null:
		capture_failed.emit("カメラの準備ができていません。")
		return

	_set_state(State.CAPTURING, "撮影しています。")

	# YCbCr変換用SubViewportを含め、最新フレームの描画完了を待つ。
	await RenderingServer.frame_post_draw

	if state != State.CAPTURING or preview_texture == null:
		return

	# GPUからの読み戻しは高コストなので、入力された瞬間に1回だけ行う。
	var captured_image := preview_texture.get_image()

	if captured_image == null or captured_image.is_empty():
		_set_state(State.READY, "画像を取得できませんでした。")
		capture_failed.emit(state_message)
		return

	if captured_image.get_format() != Image.FORMAT_RGBA8:
		captured_image.convert(Image.FORMAT_RGBA8)

	_set_state(State.CAPTURED, "撮影しました。")
	capture_succeeded.emit(captured_image)


# 対応形式の中から希望解像度との差が最も小さいものを選ぶ。
static func find_preferred_format_index(
	formats: Array,
	target_size: Vector2i
) -> int:
	var best_index := -1
	var best_score := INF

	for index: int in range(formats.size()):
		var format := formats[index] as Dictionary
		var width := int(format.get("width", 0))
		var height := int(format.get("height", 0))

		if width <= 0 or height <= 0:
			continue

		var score: float = (
			abs(width - target_size.x) + abs(height - target_size.y)
		)

		if score < best_score:
			best_index = index
			best_score = score

	return best_index


func _connect_camera_server_signals() -> void:
	if not CameraServer.camera_feeds_updated.is_connected(
		_on_camera_feeds_updated
	):
		CameraServer.camera_feeds_updated.connect(_on_camera_feeds_updated)

	if not CameraServer.camera_feed_removed.is_connected(
		_on_camera_feed_removed
	):
		CameraServer.camera_feed_removed.connect(_on_camera_feed_removed)


func _disconnect_camera_server_signals() -> void:
	if CameraServer.camera_feeds_updated.is_connected(
		_on_camera_feeds_updated
	):
		CameraServer.camera_feeds_updated.disconnect(_on_camera_feeds_updated)

	if CameraServer.camera_feed_removed.is_connected(
		_on_camera_feed_removed
	):
		CameraServer.camera_feed_removed.disconnect(_on_camera_feed_removed)


func _discover_camera() -> void:
	if state == State.IDLE:
		return

	var feeds := CameraServer.feeds()

	if feeds.is_empty():
		_set_state(
			State.UNAVAILABLE,
			"Webカメラが見つかりません。接続と権限を確認してください。"
		)
		return

	_activate_camera(feeds[0] as CameraFeed)


func _activate_camera(feed: CameraFeed) -> void:
	if feed == null:
		_set_state(State.ERROR, "カメラ情報を取得できませんでした。")
		return

	if camera_feed == feed and primary_camera_texture != null:
		return

	_release_camera()
	camera_feed = feed

	# set_formatの既定動作でRGBへ変換し、プレビューと静止画を共通化する。
	var format_index := find_preferred_format_index(
		camera_feed.formats,
		preferred_size
	)

	if format_index >= 0:
		var format_selected := camera_feed.set_format(format_index, {})

		if not format_selected:
			push_warning(
				"希望するカメラ形式を選択できないため既定形式を使います。"
			)

	# FeedImageの0番はRGB、結合YCbCr、分離Yのいずれでも主画像になる。
	primary_camera_texture = _create_camera_texture(
		CameraServer.FEED_RGBA_IMAGE
	)

	if not camera_feed.frame_changed.is_connected(_on_camera_frame_changed):
		camera_feed.frame_changed.connect(_on_camera_frame_changed)

	_set_state(
		State.DISCOVERING,
		"%s の映像を待っています。" % camera_feed.get_name()
	)
	# CameraTextureの利便プロパティを通じてCameraFeedを有効化する。
	# 実際のデータ形式は最初のframe_changedで確定してから表示する。
	primary_camera_texture.camera_is_active = true


func _create_camera_texture(which_feed: CameraServer.FeedImage) -> CameraTexture:
	var texture := CameraTexture.new()
	texture.camera_feed_id = camera_feed.get_id()
	texture.which_feed = which_feed
	return texture


# RGBはそのまま、YCbCrは変換用SubViewportを経由して表示する。
func _configure_preview(data_type: CameraFeed.FeedDataType) -> bool:
	if data_type == configured_data_type and preview_texture != null:
		return true

	_release_conversion_viewport()
	configured_data_type = data_type

	match data_type:
		CameraFeed.FEED_RGB, CameraFeed.FEED_EXTERNAL:
			preview_texture = primary_camera_texture

		CameraFeed.FEED_YCBCR:
			_setup_ycbcr_conversion(false)

		CameraFeed.FEED_YCBCR_SEP:
			cbcr_camera_texture = _create_camera_texture(
				CameraServer.FEED_CBCR_IMAGE
			)
			_setup_ycbcr_conversion(true)

		_:
			preview_texture = null
			return false

	preview_ready.emit(preview_texture)
	return true


func _setup_ycbcr_conversion(split_planes: bool) -> void:
	conversion_viewport = SubViewport.new()
	conversion_viewport.name = "CameraColorConversion"
	conversion_viewport.disable_3d = true
	conversion_viewport.size = preferred_size
	conversion_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(conversion_viewport)

	conversion_rect = ColorRect.new()
	conversion_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	conversion_viewport.add_child(conversion_rect)

	var conversion_material := ShaderMaterial.new()
	conversion_material.shader = YCBCR_TO_RGB_SHADER
	conversion_material.set_shader_parameter(
		"camera_y",
		primary_camera_texture
	)
	conversion_material.set_shader_parameter(
		"camera_cbcr",
		cbcr_camera_texture if split_planes else primary_camera_texture
	)
	conversion_material.set_shader_parameter("split_planes", split_planes)
	conversion_rect.material = conversion_material
	preview_texture = conversion_viewport.get_texture()


func _update_conversion_viewport_size() -> void:
	if conversion_viewport == null or primary_camera_texture == null:
		return

	var texture_size := primary_camera_texture.get_size()

	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return

	var frame_size := Vector2i(texture_size)

	if conversion_viewport.size != frame_size:
		conversion_viewport.size = frame_size


func _release_camera() -> void:
	if camera_feed != null and camera_feed.frame_changed.is_connected(
		_on_camera_frame_changed
	):
		camera_feed.frame_changed.disconnect(_on_camera_frame_changed)

	if primary_camera_texture != null:
		primary_camera_texture.camera_is_active = false

	_release_conversion_viewport()
	primary_camera_texture = null
	cbcr_camera_texture = null
	preview_texture = null
	configured_data_type = CameraFeed.FEED_NOIMAGE
	camera_feed = null


func _release_conversion_viewport() -> void:
	if conversion_viewport != null:
		conversion_viewport.queue_free()

	conversion_viewport = null
	conversion_rect = null
	cbcr_camera_texture = null
	preview_texture = null


func _on_camera_feeds_updated() -> void:
	_discover_camera()


func _on_camera_feed_removed(feed_id: int) -> void:
	if camera_feed == null or camera_feed.get_id() != feed_id:
		return

	_release_camera()
	_set_state(
		State.UNAVAILABLE,
		"使用中のWebカメラが切断されました。再接続を待っています。"
	)


func _on_camera_frame_changed() -> void:
	if camera_feed == null:
		return

	var data_type := camera_feed.get_datatype()

	if not _configure_preview(data_type):
		_set_state(
			State.ERROR,
			"カメラの色形式を判別できませんでした: %d" % data_type
		)
		return

	_update_conversion_viewport_size()

	if state == State.DISCOVERING:
		_set_state(
			State.READY,
			"%s の準備ができました（%s）。" % [
				camera_feed.get_name(),
				_get_data_type_name(data_type),
			]
		)


func _get_data_type_name(data_type: CameraFeed.FeedDataType) -> String:
	match data_type:
		CameraFeed.FEED_RGB:
			return "RGB"
		CameraFeed.FEED_YCBCR:
			return "YCbCr → RGB変換"
		CameraFeed.FEED_YCBCR_SEP:
			return "Y/CbCr → RGB変換"
		CameraFeed.FEED_EXTERNAL:
			return "外部RGB"
		_:
			return "不明"
