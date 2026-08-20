class_name SceneFlow
extends RefCounted

enum ScreenId {
	TITLE,
	FACE_CAPTURE,
	TUTORIAL,
	MAIN,
	RESULT,
}

const FLOW: Array[ScreenId] = [
	ScreenId.TITLE,
	ScreenId.FACE_CAPTURE,
	ScreenId.TUTORIAL,
	ScreenId.MAIN,
	ScreenId.RESULT,
]

const SCREEN_PATHS: Dictionary = {
	ScreenId.TITLE: "res://screens/title/title_screen.tscn",
	ScreenId.FACE_CAPTURE:
		"res://screens/face_capture/face_capture_screen.tscn",
	ScreenId.TUTORIAL: "res://screens/tutorial/tutorial_screen.tscn",
	ScreenId.MAIN: "res://main/main.tscn",
	ScreenId.RESULT: "res://screens/result/result_screen.tscn",
}


static func get_initial_screen() -> ScreenId:
	return ScreenId.TITLE


static func get_next_screen(current_screen: ScreenId) -> ScreenId:
	var current_index := FLOW.find(current_screen)

	if current_index < 0:
		push_error("Unknown screen id: %s" % current_screen)
		return ScreenId.TITLE

	return FLOW[(current_index + 1) % FLOW.size()]


static func get_scene_path(screen_id: ScreenId) -> String:
	if not SCREEN_PATHS.has(screen_id):
		push_error("Scene path is not defined: %s" % screen_id)
		return ""

	return SCREEN_PATHS[screen_id]
