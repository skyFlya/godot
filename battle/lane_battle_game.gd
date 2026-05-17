extends Node2D

@onready var _units_root: Node2D = $Units
@onready var _hud: Label = $UI/HUD

var _enemy_spawn_timer: float = 0.0
var _item_cooldown: float = 0.0
## 同路多单位对峙组：enemies / items / tick_timer / anchor_y / lane
var _stalemate_groups: Array[Dictionary] = []

func _ready() -> void:
	_stalemate_groups.clear()
	_enemy_spawn_timer = 0.8
	_update_hud()

func _process(delta: float) -> void:
	_enemy_spawn_timer -= delta
	if _enemy_spawn_timer <= 0.0:
		_spawn_enemy()
		_enemy_spawn_timer = LaneConfig.ENEMY_SPAWN_INTERVAL

	if _item_cooldown > 0.0:
		_item_cooldown -= delta

	_try_start_and_join_stalemates(delta)
	_move_units(delta)
	_lock_stalemate_positions()
	_process_stalemates(delta)
	_lock_stalemate_positions()
	_cleanup_offscreen()
	_update_hud()

func _unhandled_input(event: InputEvent) -> void:
	if _item_cooldown > 0.0:
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			_try_launch_from_screen(mouse.position)
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_try_launch_from_screen(touch.position)
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			var lane := -1
			match key.keycode:
				KEY_1, KEY_KP_1, KEY_Z:
					lane = 0
				KEY_2, KEY_KP_2, KEY_X:
					lane = 1
				KEY_3, KEY_KP_3, KEY_C:
					lane = 2
			if lane >= 0:
				_launch_item(lane)

func _try_launch_from_screen(screen_pos: Vector2) -> void:
	if not LaneConfig.is_in_safe_zone(screen_pos.y):
		return
	var lane := LaneConfig.lane_from_screen_x(screen_pos.x)
	_launch_item(lane)

func _launch_item(lane: int) -> void:
	if _item_cooldown > 0.0:
		return
	var item := _create_unit(BattleUnit.Kind.ITEM, lane)
	item.position.y = LaneConfig.VIEWPORT.y - 70.0
	item.stat_value = randi_range(LaneConfig.ITEM_DURABILITY_MIN, LaneConfig.ITEM_DURABILITY_MAX)
	item.refresh_label()
	_item_cooldown = LaneConfig.ITEM_LAUNCH_COOLDOWN
	_update_hud()

func _spawn_enemy() -> void:
	var lane := randi() % LaneConfig.LANE_COUNT
	var enemy := _create_unit(BattleUnit.Kind.ENEMY, lane)
	enemy.position.y = 120.0
	enemy.stat_value = randi_range(LaneConfig.ENEMY_HP_MIN, LaneConfig.ENEMY_HP_MAX)
	enemy.refresh_label()

func _create_unit(kind: BattleUnit.Kind, lane: int) -> BattleUnit:
	var unit := BattleUnit.new()
	unit.kind = kind
	unit.lane = lane
	_units_root.add_child(unit)
	return unit

func _move_units(delta: float) -> void:
	for child in _units_root.get_children():
		if not child is BattleUnit:
			continue
		var unit := child as BattleUnit
		if not is_instance_valid(unit) or not unit.is_moving or unit.is_in_stalemate():
			continue
		if unit.kind == BattleUnit.Kind.ENEMY:
			unit.position.y += LaneConfig.ENEMY_SPEED * delta
		else:
			unit.position.y -= LaneConfig.ITEM_SPEED * delta

func _try_start_and_join_stalemates(delta: float) -> void:
	var hit_distance := LaneConfig.UNIT_RADIUS * 2.2
	var moving_enemies: Array[BattleUnit] = []
	var moving_items: Array[BattleUnit] = []

	for child in _units_root.get_children():
		if not child is BattleUnit:
			continue
		var unit := child as BattleUnit
		if not is_instance_valid(unit) or not unit.is_moving or unit.is_in_stalemate():
			continue
		if unit.kind == BattleUnit.Kind.ENEMY:
			moving_enemies.append(unit)
		else:
			moving_items.append(unit)

	# 1) 两个移动单位首次对撞 → 新建对峙组
	for enemy in moving_enemies:
		if not is_instance_valid(enemy) or not enemy.is_moving:
			continue
		for item in moving_items:
			if not is_instance_valid(item) or not item.is_moving:
				continue
			if enemy.lane != item.lane:
				continue
			if not _will_units_touch(enemy, item, hit_distance, delta):
				continue
			_create_stalemate_group(enemy, item)

	# 2) 移动单位碰到已有对峙组 → 加入该组
	for unit in moving_enemies + moving_items:
		if not is_instance_valid(unit) or not unit.is_moving:
			continue
		var group_id := _find_group_to_join(unit, hit_distance, delta)
		if group_id >= 0:
			_join_stalemate_group(unit, group_id)

func _find_group_to_join(unit: BattleUnit, hit_distance: float, delta: float) -> int:
	for group_id in _stalemate_groups.size():
		var group: Dictionary = _stalemate_groups[group_id]
		if int(group.get("lane", -1)) != unit.lane:
			continue
		for member in _group_members(group):
			if not is_instance_valid(member):
				continue
			if _will_units_touch(unit, member, hit_distance, delta):
				return group_id
	return -1

func _create_stalemate_group(enemy: BattleUnit, item: BattleUnit) -> void:
	if not is_instance_valid(enemy) or not is_instance_valid(item):
		return
	if enemy.is_in_stalemate() or item.is_in_stalemate():
		return

	var group_id := _stalemate_groups.size()
	var anchor_y := (enemy.position.y + item.position.y) * 0.5
	_stalemate_groups.append({
		"lane": enemy.lane,
		"enemies": [enemy],
		"items": [item],
		"anchor_y": anchor_y,
		"tick_timer": LaneConfig.STALEMATE_CONTACT_DELAY,
		"started_frame": Engine.get_process_frames(),
	})

	enemy.enter_stalemate_group(group_id)
	item.enter_stalemate_group(group_id)
	_layout_stalemate_group(group_id)

func _join_stalemate_group(unit: BattleUnit, group_id: int) -> void:
	if group_id < 0 or group_id >= _stalemate_groups.size():
		return
	if not is_instance_valid(unit) or unit.is_in_stalemate():
		return

	var group: Dictionary = _stalemate_groups[group_id]
	if int(group.get("lane", -1)) != unit.lane:
		return

	var enemies: Array = group.get("enemies", [])
	var items: Array = group.get("items", [])
	if unit in enemies or unit in items:
		return

	if unit.kind == BattleUnit.Kind.ENEMY:
		enemies.append(unit)
	else:
		items.append(unit)
	group["enemies"] = enemies
	group["items"] = items
	_stalemate_groups[group_id] = group

	unit.enter_stalemate_group(group_id)
	# 锚点不变，只把新成员摆进固定对峙位
	_layout_stalemate_group(group_id)

func _lock_stalemate_positions() -> void:
	for group_id in _stalemate_groups.size():
		_layout_stalemate_group(group_id)
		var group: Dictionary = _stalemate_groups[group_id]
		var enemies: Array = _valid_members(group.get("enemies", []))
		var items: Array = _valid_members(group.get("items", []))
		_mark_stalemate_frontline(enemies, items)
		for member in _group_members(group):
			if is_instance_valid(member):
				member.lock_stalemate_position()

func _apply_stalemate_damage_tick(enemies: Array, items: Array) -> void:
	var enemy_count := enemies.size()
	var item_count := items.size()
	if enemy_count == 0 or item_count == 0:
		return

	_mark_stalemate_frontline(enemies, items)

	var front_enemy: BattleUnit = _get_front_enemy(enemies)
	var front_item: BattleUnit = _get_front_item(items)
	var base := LaneConfig.STALEMATE_DAMAGE_PER_TICK

	# 仅前排承伤；扣量 = 基础 × 对方球数（例：2 蓝 vs 1 红 → 红每 0.2s 扣 2，仅首个蓝每 0.2s 扣 1）
	if front_enemy != null:
		front_enemy.drain_stat(base * float(item_count))
	if front_item != null:
		front_item.drain_stat(base * float(enemy_count))

func _mark_stalemate_frontline(enemies: Array, items: Array) -> void:
	for enemy in enemies:
		if enemy is BattleUnit:
			var unit := enemy as BattleUnit
			unit.is_stalemate_frontline = false
			unit.queue_redraw()
	for item in items:
		if item is BattleUnit:
			var unit := item as BattleUnit
			unit.is_stalemate_frontline = false
			unit.queue_redraw()

	var front_enemy := _get_front_enemy(enemies)
	var front_item := _get_front_item(items)
	if front_enemy != null:
		front_enemy.is_stalemate_frontline = true
		front_enemy.queue_redraw()
	if front_item != null:
		front_item.is_stalemate_frontline = true
		front_item.queue_redraw()

func _get_front_enemy(enemies: Array) -> BattleUnit:
	# 最接近交战线的敌人（Y 最大）
	var front: BattleUnit = null
	var best_y := -INF
	for enemy in enemies:
		if not enemy is BattleUnit or not is_instance_valid(enemy):
			continue
		var unit := enemy as BattleUnit
		if unit.position.y > best_y:
			best_y = unit.position.y
			front = unit
	return front

func _get_front_item(items: Array) -> BattleUnit:
	# 最接近交战线的道具（Y 最小）
	var front: BattleUnit = null
	var best_y := INF
	for item in items:
		if not item is BattleUnit or not is_instance_valid(item):
			continue
		var unit := item as BattleUnit
		if unit.position.y < best_y:
			best_y = unit.position.y
			front = unit
	return front

func _layout_stalemate_group(group_id: int) -> void:
	if group_id < 0 or group_id >= _stalemate_groups.size():
		return
	var group: Dictionary = _stalemate_groups[group_id]
	var anchor_y: float = group.get("anchor_y", 0.0)
	var half_gap := LaneConfig.STALEMATE_VISUAL_GAP * 0.5
	var stack_step := LaneConfig.UNIT_RADIUS * 2.05

	var enemies: Array = _valid_members(group.get("enemies", []))
	var items: Array = _valid_members(group.get("items", []))

	for i in enemies.size():
		var enemy: BattleUnit = enemies[i]
		enemy.position.y = anchor_y - half_gap - float(i) * stack_step
		enemy.z_index = 20 + i

	for i in items.size():
		var item: BattleUnit = items[i]
		item.position.y = anchor_y + half_gap + float(i) * stack_step
		item.z_index = 10 + i

func _group_members(group: Dictionary) -> Array[BattleUnit]:
	var out: Array[BattleUnit] = []
	for enemy in group.get("enemies", []):
		if enemy is BattleUnit and is_instance_valid(enemy):
			out.append(enemy)
	for item in group.get("items", []):
		if item is BattleUnit and is_instance_valid(item):
			out.append(item)
	return out

func _valid_members(members: Array) -> Array:
	var out: Array = []
	for member in members:
		if member is BattleUnit and is_instance_valid(member):
			out.append(member)
	return out

func _will_units_touch(a: BattleUnit, b: BattleUnit, hit_distance: float, delta: float) -> bool:
	if not is_instance_valid(a) or not is_instance_valid(b):
		return false
	var now_dist := absf(a.position.y - b.position.y)
	if now_dist <= hit_distance:
		return true

	var a_next := a.position.y
	var b_next := b.position.y
	if a.is_moving:
		a_next += LaneConfig.ENEMY_SPEED * delta if a.kind == BattleUnit.Kind.ENEMY else -LaneConfig.ITEM_SPEED * delta
	if b.is_moving:
		b_next += LaneConfig.ENEMY_SPEED * delta if b.kind == BattleUnit.Kind.ENEMY else -LaneConfig.ITEM_SPEED * delta
	return absf(a_next - b_next) <= hit_distance

func _process_stalemates(delta: float) -> void:
	var frame := Engine.get_process_frames()
	var gi := _stalemate_groups.size() - 1
	while gi >= 0:
		var group: Dictionary = _stalemate_groups[gi]
		_sanitize_group_members(group)
		_stalemate_groups[gi] = group

		var enemies: Array = _valid_members(group.get("enemies", []))
		var items: Array = _valid_members(group.get("items", []))
		if enemies.is_empty() or items.is_empty():
			_dissolve_stalemate_group(gi, enemies, items)
			gi -= 1
			continue

		if frame <= int(group.get("started_frame", -1)):
			gi -= 1
			continue

		var tick_timer: float = group.get("tick_timer", 0.0)
		tick_timer -= delta
		if tick_timer > 0.0:
			group["tick_timer"] = tick_timer
			_stalemate_groups[gi] = group
			gi -= 1
			continue

		group["tick_timer"] = LaneConfig.STALEMATE_TICK_INTERVAL
		_stalemate_groups[gi] = group

		_apply_stalemate_damage_tick(enemies, items)

		_remove_dead_from_group(group)
		_stalemate_groups[gi] = group
		enemies = _valid_members(group.get("enemies", []))
		items = _valid_members(group.get("items", []))

		if enemies.is_empty() or items.is_empty():
			_dissolve_stalemate_group(gi, enemies, items)
		else:
			_layout_stalemate_group(gi)

		gi -= 1

func _sanitize_group_members(group: Dictionary) -> void:
	var enemies: Array = []
	var items: Array = []
	for enemy in group.get("enemies", []):
		if enemy is BattleUnit and is_instance_valid(enemy) and enemy.stat_value > 0.0:
			enemies.append(enemy)
		elif enemy is BattleUnit and is_instance_valid(enemy):
			_remove_unit(enemy)
	for item in group.get("items", []):
		if item is BattleUnit and is_instance_valid(item) and item.stat_value > 0.0:
			items.append(item)
		elif item is BattleUnit and is_instance_valid(item):
			_remove_unit(item)
	group["enemies"] = enemies
	group["items"] = items

func _remove_dead_from_group(group: Dictionary) -> void:
	var enemies: Array = []
	var items: Array = []
	for enemy in group.get("enemies", []):
		if not enemy is BattleUnit or not is_instance_valid(enemy):
			continue
		if (enemy as BattleUnit).stat_value <= 0.0:
			_remove_unit(enemy)
		else:
			enemies.append(enemy)
	for item in group.get("items", []):
		if not item is BattleUnit or not is_instance_valid(item):
			continue
		if (item as BattleUnit).stat_value <= 0.0:
			_remove_unit(item)
		else:
			items.append(item)
	group["enemies"] = enemies
	group["items"] = items

func _dissolve_stalemate_group(group_id: int, survivors_enemies: Array, survivors_items: Array) -> void:
	for enemy in survivors_enemies:
		if enemy is BattleUnit and is_instance_valid(enemy):
			(enemy as BattleUnit).release_from_stalemate(true)
	for item in survivors_items:
		if item is BattleUnit and is_instance_valid(item):
			(item as BattleUnit).release_from_stalemate(true)

	if group_id >= 0 and group_id < _stalemate_groups.size():
		_stalemate_groups.remove_at(group_id)
	_reindex_stalemate_groups()

func _reindex_stalemate_groups() -> void:
	for group_id in _stalemate_groups.size():
		var group: Dictionary = _stalemate_groups[group_id]
		for enemy in group.get("enemies", []):
			if enemy is BattleUnit and is_instance_valid(enemy):
				(enemy as BattleUnit).stalemate_group_id = group_id
		for item in group.get("items", []):
			if item is BattleUnit and is_instance_valid(item):
				(item as BattleUnit).stalemate_group_id = group_id

func _remove_unit(unit: BattleUnit) -> void:
	if not is_instance_valid(unit):
		return
	var old_group := unit.stalemate_group_id
	unit.release_from_stalemate(false)
	unit.request_remove()
	if old_group >= 0 and old_group < _stalemate_groups.size():
		var group: Dictionary = _stalemate_groups[old_group]
		_sanitize_group_members(group)
		_stalemate_groups[old_group] = group

func _cleanup_offscreen() -> void:
	for child in _units_root.get_children():
		if not child is BattleUnit:
			continue
		var unit := child as BattleUnit
		if not is_instance_valid(unit) or unit.is_in_stalemate():
			continue
		if unit.kind == BattleUnit.Kind.ENEMY and unit.position.y > LaneConfig.VIEWPORT.y + 80.0:
			_remove_unit(unit)
		elif unit.kind == BattleUnit.Kind.ITEM and unit.position.y < -80.0:
			_remove_unit(unit)

func _update_hud() -> void:
	var enemy_count := 0
	var item_count := 0
	var brawl_count := _stalemate_groups.size()
	for child in _units_root.get_children():
		if child is BattleUnit and is_instance_valid(child):
			if (child as BattleUnit).kind == BattleUnit.Kind.ENEMY:
				enemy_count += 1
			else:
				item_count += 1
	var brawl_hint := ""
	if brawl_count > 0:
		brawl_hint = " | 对峙组:%d" % brawl_count
	_hud.text = (
		"三路独立对战 Demo | 敌人:%d  道具:%d%s\n点击下方蓝区发射(1/2/3 或 Z/X/C)"
		% [enemy_count, item_count, brawl_hint]
	)
