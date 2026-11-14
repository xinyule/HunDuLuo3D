class_name JoyStick
extends Control

## 虚拟摇杆（1.2.1 触控重做）：自绘半透明圆盘底座 + 跟随摇杆头。
## 旧实现是没设实际尺寸、没有任何绘制的裸 Control——屏上不可见、命中面积≈0，等于没有摇杆。
## 本控件有真实尺寸（160×160），命中区与可见圆盘一致；拖动时头跟随偏移、松手回中归零。
## value 语义与 main._touch_move 一致：x 右正，y 下正（=后退）。
## 只处理触摸事件：引擎会把触摸模拟成鼠标事件（emulate_mouse_from_touch），
## 两类都收会双重触发；触控层只在触屏设备显示，桌面无需鼠标兜底。

const RADIUS := 80.0 # 底座半径（控件 160×160）
const KNOB_R := 30.0 # 摇杆头半径
const TRAVEL := 46.0 # 摇杆头最大偏移

var value := Vector2.ZERO
var touch_index := -1 # 当前占用的触点（-1=空闲），main 用它排除镜头拖屏

func _ready() -> void:
	custom_minimum_size = Vector2(RADIUS * 2.0, RADIUS * 2.0)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _center() -> Vector2:
	return size * 0.5

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and touch_index == -1:
			touch_index = t.index
			_update_value(t.position)
			accept_event()
		elif not t.pressed and t.index == touch_index:
			touch_index = -1
			value = Vector2.ZERO
			queue_redraw()
			accept_event()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == touch_index:
			_update_value(d.position)
			accept_event()

func _update_value(local_pos: Vector2) -> void:
	# gui_input 给的是控件本地坐标
	value = ((local_pos - _center()) / TRAVEL).limit_length(1.0)
	queue_redraw()

func _draw() -> void:
	var c := _center()
	# 底座：半透明盘 + 描边环 + 十字刻度
	draw_circle(c, RADIUS, Color(0.05, 0.07, 0.06, 0.38))
	draw_arc(c, RADIUS - 2.0, 0.0, TAU, 48, Color(1, 1, 1, 0.55), 3.0)
	draw_line(c + Vector2(-RADIUS + 12.0, 0), c + Vector2(RADIUS - 12.0, 0), Color(1, 1, 1, 0.18), 2.0)
	draw_line(c + Vector2(0, -RADIUS + 12.0), c + Vector2(0, RADIUS - 12.0), Color(1, 1, 1, 0.18), 2.0)
	# 摇杆头：跟随 value 偏移
	var kc := c + value * TRAVEL
	var col := Color(0.95, 0.8, 0.4, 0.85) if touch_index != -1 else Color(0.9, 0.92, 0.88, 0.6)
	draw_circle(kc, KNOB_R, col)
	draw_arc(kc, KNOB_R - 1.5, 0.0, TAU, 40, Color(0.1, 0.1, 0.1, 0.5), 2.5)
