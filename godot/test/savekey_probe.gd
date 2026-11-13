extends SceneTree

## 存档保键探针（4A 任务 5 验证）：_save_hi() 改为先 load 再覆盖已知键后，
## pickups 写入的 progress.emblems_* 等外来键必须存活，已知键必须被新值覆盖。
## 步骤：备份真实存档 → 写一份带 emblems 键的测试存档 → 实例化 Main（_ready 里 _load_hi 读入）
## → 改 hi_score 后调 _save_hi() → 回读断言 → 恢复备份。
## 运行：godot --headless --path . --script res://test/savekey_probe.gd --fixed-fps 60

const PATH := "user://contra3d_save.cfg"

var _main: Node
var _frame := 0
var _backup: PackedByteArray = PackedByteArray()
var _had_backup := false

func _initialize() -> void:
	if FileAccess.file_exists(PATH):
		var f := FileAccess.open(PATH, FileAccess.READ)
		_backup = f.get_buffer(f.get_length())
		f.close()
		_had_backup = true
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "emblems_0", 5)
	cfg.set_value("progress", "emblems_3", 7)
	cfg.set_value("game", "hi", 111)
	cfg.set_value("bestiary", "rifleman", true)
	cfg.save(PATH)
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	process_frame.connect(_on_frame)

func _restore() -> void:
	if _had_backup:
		var f := FileAccess.open(PATH, FileAccess.WRITE)
		f.store_buffer(_backup)
		f.close()
	elif FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)

func _on_frame() -> void:
	_frame += 1
	if _frame < 5:
		return
	process_frame.disconnect(_on_frame)
	var ok := true
	# _load_hi 应已读入测试存档的 hi=111
	if int(_main.get("hi_score")) != 111:
		ok = false
		print("SAVEKEY FAIL: _load_hi hi_score=", _main.get("hi_score"), " 期望 111")
	_main.set("hi_score", 222)
	_main.call("_save_hi")
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		print("SAVEKEY FAIL: 回读存档失败")
		_restore()
		quit(1)
		return
	if int(cfg.get_value("progress", "emblems_0", -1)) != 5:
		ok = false
		print("SAVEKEY FAIL: emblems_0 被抹除，现值 ", cfg.get_value("progress", "emblems_0", "<缺失>"))
	if int(cfg.get_value("progress", "emblems_3", -1)) != 7:
		ok = false
		print("SAVEKEY FAIL: emblems_3 被抹除")
	if int(cfg.get_value("game", "hi", -1)) != 222:
		ok = false
		print("SAVEKEY FAIL: hi 未被新值覆盖，现值 ", cfg.get_value("game", "hi", "<缺失>"))
	if not bool(cfg.get_value("bestiary", "rifleman", false)):
		ok = false
		print("SAVEKEY FAIL: bestiary.rifleman 丢失")
	print("SAVEKEY RESULT: ", "PASS" if ok else "FAIL")
	_restore()
	quit(0 if ok else 1)
