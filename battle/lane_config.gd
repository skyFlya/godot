class_name LaneConfig
extends RefCounted

const VIEWPORT := Vector2(720, 1280)
const LANE_COUNT := 3
const LANE_WIDTH := 240.0

const SPAWN_ZONE_END_Y := 260.0
const ARENA_END_Y := 1040.0

const ENEMY_SPEED := 90.0
const ITEM_SPEED := 130.0
## 相撞后先等待这么久，再开始按对峙规则扣点
const STALEMATE_CONTACT_DELAY := 0.2
const STALEMATE_TICK_INTERVAL := 0.2
## 每 0.2 秒前排承伤球的基础扣量；实际扣量 = 基础值 × 对方球数量
const STALEMATE_DAMAGE_PER_TICK := 1.0
const UNIT_RADIUS := 28.0
## 对峙时红蓝球心的竖直间距（略大于直径，避免叠在一起看不见）
const STALEMATE_VISUAL_GAP := UNIT_RADIUS * 2.15

const ENEMY_HP_MIN := 7
const ENEMY_HP_MAX := 16
const ITEM_DURABILITY_MIN := 12
const ITEM_DURABILITY_MAX := 22

const ENEMY_SPAWN_INTERVAL := 2.2
const ITEM_LAUNCH_COOLDOWN := 0.35

static func lane_center_x(lane: int) -> float:
	return LANE_WIDTH * 0.5 + float(lane) * LANE_WIDTH

static func lane_from_screen_x(screen_x: float) -> int:
	return clampi(int(screen_x / LANE_WIDTH), 0, LANE_COUNT - 1)

static func is_in_safe_zone(screen_y: float) -> bool:
	return screen_y >= ARENA_END_Y
