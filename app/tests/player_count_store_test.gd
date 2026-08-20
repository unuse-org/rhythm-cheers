extends SceneTree

const TEST_SAVE_PATH: String = "user://player_count_store_test.cfg"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_tests")


func run_tests() -> void:
	_remove_test_save()

	var store := PlayerCountStore.new(TEST_SAVE_PATH)
	expect_equal(store.get_total_count(), 0, "未保存時の累計人数")
	expect_equal(store.record_player(), 1, "最初の体験者を保存する")
	expect_equal(store.record_player(), 2, "次の体験者を加算する")

	# 新しいインスタンスでもファイルから同じ人数を復元できることを確認する。
	var reloaded_store := PlayerCountStore.new(TEST_SAVE_PATH)
	expect_equal(reloaded_store.get_total_count(), 2, "累計人数を再読込する")

	_remove_test_save()
	finish_tests()


func _remove_test_save() -> void:
	var absolute_path := ProjectSettings.globalize_path(TEST_SAVE_PATH)
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(absolute_path)


func expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append(
			"%s: expected=%s actual=%s" % [message, expected, actual]
		)


func finish_tests() -> void:
	if failures.is_empty():
		print("PlayerCountStore tests passed.")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)

	quit(1)
