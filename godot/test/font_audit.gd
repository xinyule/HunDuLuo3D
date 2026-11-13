extends SceneTree

## 1.2.0 字体修复审计：打包全字体须自含全游戏文字语料，零系统回退依赖
## ① 扫全部脚本/场景源码的 CJK 与标点码位，逐个查 FontFile.has_char
## ② 旧子集缺字样本（鉴/说/击/肃/锁等）专项复查
## ③ 默认主题字体（Label 实际取到的）须与打包字体为同一资源
## 运行：godot --headless --path . --script res://test/font_audit.gd

var _fails := 0

func _check(cond: bool, label: String) -> void:
	print(("  OK   " if cond else "  FAIL ") + label)
	if not cond:
		_fails += 1

func _initialize() -> void:
	var font := load("res://assets/font/noto_sc_full.otf") as FontFile
	_check(font != null, "打包全字体可加载")
	if font == null:
		print("FONT AUDIT FAIL")
		quit(1)
		return
	# 语料：全部脚本 + 主场景源码里的 CJK/假名/全角标点码位
	var corpus := {}
	var files := ["res://main.tscn"]
	var dir := DirAccess.open("res://scripts")
	if dir:
		for fn in dir.get_files():
			if fn.ends_with(".gd"):
				files.append("res://scripts/" + fn)
	for path in files:
		var t := FileAccess.get_file_as_string(path)
		for i in t.length():
			var cp := t.unicode_at(i)
			if (cp >= 0x4E00 and cp <= 0x9FFF) or (cp >= 0x3000 and cp <= 0x30FF) or (cp >= 0xFF00 and cp <= 0xFFEF):
				corpus[cp] = true
	var missing := []
	for cp in corpus.keys():
		if not font.has_char(int(cp)):
			missing.append(int(cp))
	_check(missing.is_empty(), "全语料 %d 个 CJK 码位在打包字体内零缺失（缺 %d）" % [corpus.size(), missing.size()])
	if not missing.is_empty():
		var s := ""
		for cp in missing.slice(0, 40):
			s += char(int(cp))
		print("    缺字样本: ", s)
	# 旧子集缺字专项（曾在网页端变方框的）
	var sample := "鉴说击肃锁屏图鉴操作说明点击画面开始战斗正在生成地形肃清本区敌人解除封锁隐藏鹰徽"
	var sample_missing := ""
	for i in sample.length():
		if not font.has_char(sample.unicode_at(i)):
			sample_missing += sample[i]
	_check(sample_missing.is_empty(), "旧缺字专项全覆盖（缺: %s）" % sample_missing)
	# 主题字体同一性：随便建个 Label，它取到的默认字体须为打包字体本体
	var lb := Label.new()
	var theme_font := lb.get_theme_font("font")
	_check(theme_font == font, "Control 默认主题字体 == 打包全字体（非系统回退）")
	lb.free()
	print("FONT AUDIT ", "PASS" if _fails == 0 else "FAIL x%d" % _fails)
	quit(0 if _fails == 0 else 1)
