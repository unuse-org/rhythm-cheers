class_name PlayerCountStore
extends RefCounted

# 体験者数はプレイ中の一時データとは分け、アプリを終了しても残す。
const DEFAULT_SAVE_PATH: String = "user://player_count.cfg"
const SAVE_SECTION: String = "players"
const TOTAL_COUNT_KEY: String = "total_count"

var save_path: String


func _init(count_save_path: String = DEFAULT_SAVE_PATH) -> void:
	save_path = count_save_path


# 保存ファイルがまだない場合は、最初の体験者を1人目として扱う。
func get_total_count() -> int:
	var config := ConfigFile.new()
	var load_error := config.load(save_path)

	if load_error == ERR_FILE_NOT_FOUND:
		return 0

	if load_error != OK:
		push_warning(
			"体験者数を読み込めませんでした: %s" % error_string(load_error)
		)
		return 0

	return maxi(
		0,
		int(config.get_value(SAVE_SECTION, TOTAL_COUNT_KEY, 0))
	)


# Resultへ到達したプレイを1人として保存し、保存後の累計人数を返す。
# 保存に失敗した場合は0を返し、Result側では人数を未確定表示にする。
func record_player() -> int:
	var next_count := get_total_count() + 1
	var config := ConfigFile.new()
	config.set_value(SAVE_SECTION, TOTAL_COUNT_KEY, next_count)

	var save_error := config.save(save_path)
	if save_error != OK:
		push_error(
			"体験者数を保存できませんでした: %s" % error_string(save_error)
		)
		return 0

	return next_count
