class_name IconButton
extends Control

## 圆形图标钮（1.2.1 触控重做）：半透明圆底 + 程序绘制的符号（不用文字、不用外部贴图）。
## kind: fire=准星 / jump=上箭头 / prone=下箭头+地面线。
## 信号与 Button 对齐（button_down/button_up/toggled），main 按原口径接线。
## 只处理触摸事件（理由同 JoyStick：防触摸模拟鼠标双重触发）。

signal button_down
signal button_up
signal toggled(on: bool)

var kind := "fire"
var diameter := 76.0
var toggle_mode := false
var button_pressed := false # toggle 模式的开关状态

var _touch_id := -1
var _held := false

func _ready() -> void:
	custom_minimum_size = Vector2(diameter, diameter)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and _touch_id == -1:
			_touch_id = t.index
			_held = true
			button_down.emit()
			if toggle_mode:
				button_pressed = not button_pressed
				toggled.emit(button_pressed)
			queue_redraw()
			accept_event()
		elif not t.pressed and t.index == _touch_id:
			_touch_id = -1
			_held = false
			button_up.emit()
			queue_redraw()
			accept_event()

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 2.0
	var bg := Color(0.05, 0.07, 0.06, 0.42)
	if _held or (toggle_mode and button_pressed):
		bg = Color(0.95, 0.55, 0.15, 0.55) # 按下/开启态：橙色高亮
	draw_circle(c, r, bg)
	draw_arc(c, r - 1.5, 0.0, TAU, 44, Color(1, 1, 1, 0.6), 3.0)
	var col := Color(1, 0.95, 0.85, 0.95)
	var w := 5.0
	match kind:
		"fire":
			# 准星：圆环 + 十字缺口 + 中心点
			draw_arc(c, r * 0.52, 0.0, TAU, 36, col, w)
			draw_circle(c, 3.5, col)
			for a in [0.0, PI * 0.5, PI, PI * 1.5]:
				var d := Vector2(cos(a), sin(a))
				draw_line(c + d * (r * 0.62), c + d * (r * 0.86), col, w)
		"jump":
			# 上箭头
			var pts := PackedVector2Array([
				c + Vector2(0, -r * 0.55), c + Vector2(r * 0.5, r * 0.05),
				c + Vector2(r * 0.2, r * 0.05), c + Vector2(r * 0.2, r * 0.55),
				c + Vector2(-r * 0.2, r * 0.55), c + Vector2(-r * 0.2, r * 0.05),
				c + Vector2(-r * 0.5, r * 0.05)])
			draw_colored_polygon(pts, col)
		"prone":
			# 下箭头 + 地面线（趴伏）
			var pts2 := PackedVector2Array([
				c + Vector2(0, r * 0.32), c + Vector2(r * 0.5, -r * 0.28),
				c + Vector2(r * 0.2, -r * 0.28), c + Vector2(r * 0.2, -r * 0.62),
				c + Vector2(-r * 0.2, -r * 0.62), c + Vector2(-r * 0.2, -r * 0.28),
				c + Vector2(-r * 0.5, -r * 0.28)])
			draw_colored_polygon(pts2, col)
			draw_line(c + Vector2(-r * 0.62, r * 0.62), c + Vector2(r * 0.62, r * 0.62), col, w)
