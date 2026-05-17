extends Node2D

const SPAWN_COLOR := Color(0.55, 0.18, 0.18, 0.35)
const ARENA_COLOR := Color(0.1, 0.14, 0.22, 0.55)
const SAFE_COLOR := Color(0.15, 0.35, 0.55, 0.35)
const LINE_COLOR := Color(0.75, 0.78, 0.85, 0.45)
const DASH_LEN := 14.0
const GAP_LEN := 10.0

func _ready() -> void:
	z_index = -20
	queue_redraw()

func _draw() -> void:
	var w := LaneConfig.VIEWPORT.x
	var h := LaneConfig.VIEWPORT.y

	draw_rect(Rect2(0, 0, w, LaneConfig.SPAWN_ZONE_END_Y), SPAWN_COLOR)
	draw_rect(Rect2(0, LaneConfig.SPAWN_ZONE_END_Y, w, LaneConfig.ARENA_END_Y - LaneConfig.SPAWN_ZONE_END_Y), ARENA_COLOR)
	draw_rect(Rect2(0, LaneConfig.ARENA_END_Y, w, h - LaneConfig.ARENA_END_Y), SAFE_COLOR)

	for lane in range(1, LaneConfig.LANE_COUNT):
		var x := lane * LaneConfig.LANE_WIDTH
		_draw_dashed_line(Vector2(x, 0), Vector2(x, h), LINE_COLOR)

	_draw_zone_labels()

func _draw_dashed_line(from: Vector2, to: Vector2, color: Color) -> void:
	var dir := (to - from).normalized()
	var length := from.distance_to(to)
	var pos := 0.0
	var draw_segment := true
	while pos < length:
		var seg_len := DASH_LEN if draw_segment else GAP_LEN
		var next_pos := minf(pos + seg_len, length)
		if draw_segment:
			draw_line(from + dir * pos, from + dir * next_pos, color, 2.0)
		draw_segment = not draw_segment
		pos = next_pos

func _draw_zone_labels() -> void:
	var font := ThemeDB.fallback_font
	var font_size := 18
	draw_string(font, Vector2(16, 36), "怪物刷新区 ↓", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 0.75, 0.75, 0.9))
	draw_string(font, Vector2(16, LaneConfig.ARENA_END_Y + 32), "我方安全区 | 点击三路发射道具 ↑", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.75, 0.9, 1, 0.95))
