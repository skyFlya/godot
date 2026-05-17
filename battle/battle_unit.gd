class_name BattleUnit
extends Node2D

enum Kind { ENEMY, ITEM }

signal removed(unit: BattleUnit)

var kind: Kind = Kind.ENEMY
var lane: int = 1
var stat_value: float = 10.0

var is_moving: bool = true
## 所属对峙组下标，-1 表示不在对峙中
var stalemate_group_id: int = -1
## 本侧前排：只有前排承伤，死后由下一个接替
var is_stalemate_frontline: bool = false

var _radius: float = LaneConfig.UNIT_RADIUS

func _ready() -> void:
	position.x = LaneConfig.lane_center_x(lane)
	queue_redraw()

func _draw() -> void:
	var fill := Color(0.9, 0.25, 0.25) if kind == Kind.ENEMY else Color(0.25, 0.55, 1.0)
	draw_circle(Vector2.ZERO, _radius, fill)
	draw_arc(Vector2.ZERO, _radius + 2.0, 0.0, TAU, 32, fill.darkened(0.25), 2.0)

	if is_in_stalemate():
		var ring := Color(1.0, 0.92, 0.35, 0.85) if is_stalemate_frontline else Color(1.0, 1.0, 1.0, 0.55)
		var ring_w := 3.5 if is_stalemate_frontline else 2.5
		draw_arc(Vector2.ZERO, _radius + 6.0, 0.0, TAU, 40, ring, ring_w)

	var prefix := "血" if kind == Kind.ENEMY else "耐"
	var shown := maxi(int(ceil(stat_value)), 0)
	var text := "%s%d" % [prefix, shown]
	var font := ThemeDB.fallback_font
	var font_size := 16
	var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(
		font,
		Vector2(-text_w * 0.5, font_size * 0.35),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		Color.WHITE
	)

func enter_stalemate_group(group_id: int) -> void:
	stalemate_group_id = group_id
	is_stalemate_frontline = false
	is_moving = false

func lock_stalemate_position() -> void:
	is_moving = false

func release_from_stalemate(resume_movement: bool = true) -> void:
	stalemate_group_id = -1
	is_stalemate_frontline = false
	if resume_movement and stat_value > 0.0:
		is_moving = true

func is_in_stalemate() -> bool:
	return stalemate_group_id >= 0

func drain_stat(amount: float) -> void:
	stat_value = maxf(stat_value - amount, 0.0)
	queue_redraw()

func refresh_label() -> void:
	queue_redraw()

func request_remove() -> void:
	if not is_inside_tree():
		return
	removed.emit(self)
	call_deferred("_deferred_free")

func _deferred_free() -> void:
	if is_inside_tree():
		queue_free()
