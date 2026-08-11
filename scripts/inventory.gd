extends Control
## Backpack inventory system.
##
## - Backpack icon in top-left opens a horizontal banner showing the gun and bullet.
## - Drag an item from the banner. Drop targets:
##     * Drop gun on player       -- player equips gun (silhouette remains in backpack)
##     * Tap gun silhouette        -- unequip gun, player returns to idle
##     * Drop gun on SadNPC       -- SadNPC becomes armed, kills player (game over)
##     * Drop bullet on SadNPC    -- only works while player is equipped with gun;
##                                  player shoots, NPC sprite becomes SadPlayer_2
##     * Drop bullet on player    -- no-op
##     * Drop elsewhere           -- item tweens back to its slot
##
## Signals
## - gun_dropped_on_player      -- gun was equipped by the player
## - gun_dropped_on_npc         -- gun was given to SadNPC (triggers game over)
## - bullet_dropped_on_npc      -- bullet was shot at SadNPC
## - gun_returned_to_backpack   -- player unequipped the gun (gun goes back to slot)

signal gun_dropped_on_player
signal gun_dropped_on_npc
signal bullet_dropped_on_npc
signal gun_returned_to_backpack
signal inventory_toggled(is_open: bool)
## Fired when a drag fails to land on a target and the item tweens back to its
## slot. Used by main.gd to play a "put away" sound.
signal item_returned_to_slot(kind: String)

# Tweens -- slide horizontally.
@export var open_offset_x: float = 280.0
@export var tween_time: float = 0.25
@export var back_to_slot_time: float = 0.35

# Drop targets
@export var player_target_path: NodePath
@export var npc_target_path: NodePath
@export var interact_radius: float = 90.0

# Gun silhouette appearance when equipped.
@export var gun_silhouette_modulate: Color = Color(1, 1, 1, 0.35)

# UI nodes
@onready var _backpack_button: Button = $Backpack
@onready var _panel: Control = $InventoryPanel
@onready var _gun_slot: TextureRect = $InventoryPanel/GunSlot
@onready var _bullet_slot: TextureRect = $InventoryPanel/BulletSlot
@onready var _drag_layer: Control = $DragLayer
@onready var _dragging_gun: TextureRect = $DragLayer/DraggingGun
@onready var _dragging_bullet: TextureRect = $DragLayer/DraggingBullet

enum DragItem { NONE, GUN, BULLET }

var _is_open: bool = false
var _drag_item: DragItem = DragItem.NONE
var _drag_offset: Vector2 = Vector2.ZERO
var _is_gun_equipped: bool = false

var _panel_closed_x: float = 0.0

func _ready() -> void:
	_panel_closed_x = _panel.position.x - open_offset_x
	_panel.position.x = _panel_closed_x
	_panel.modulate.a = 0.0
	# Drag visuals
	_dragging_gun.texture = _gun_slot.texture
	_dragging_gun.visible = false
	_dragging_gun.modulate.a = 0.85
	_dragging_bullet.texture = _bullet_slot.texture
	_dragging_bullet.visible = false
	_dragging_bullet.modulate.a = 0.85
	# Click handling
	mouse_filter = Control.MOUSE_FILTER_PASS
	_backpack_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_backpack_button.pressed.connect(_toggle)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.gui_input.connect(_on_panel_gui_input)
	_drag_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Track which slots still have items (gun starts available, bullet available)
	inventory_toggled.connect(func (is_open: bool) -> void:
		if is_open:
			_panel.mouse_filter = Control.MOUSE_FILTER_STOP
		else:
			_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	)

# ---------- Panel input (begin drag / silhouette tap) ----------
func _on_panel_gui_input(event: InputEvent) -> void:
	if not _is_open:
		return
	# Tapping the gun silhouette returns it to idle.
	if _is_gun_equipped:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var global_pos: Vector2 = _panel.get_global_rect().position + event.position
			if _gun_slot.get_global_rect().has_point(global_pos):
				gun_returned_to_backpack.emit()
				_hide_gun_silhouette()
				return
		elif event is InputEventScreenTouch and event.pressed:
			var global_pos: Vector2 = _panel.get_global_rect().position + event.position
			if _gun_slot.get_global_rect().has_point(global_pos):
				gun_returned_to_backpack.emit()
				_hide_gun_silhouette()
				return
	var panel_origin: Vector2 = _panel.get_global_rect().position
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var global_pos: Vector2 = panel_origin + mb.position
			_try_begin_drag(global_pos)
	elif event is InputEventScreenTouch:
		if event.pressed:
			var global_pos: Vector2 = panel_origin + event.position
			_try_begin_drag(global_pos)

# ---------- Global input (end drag) ----------
func _input(event: InputEvent) -> void:
	if _drag_item == DragItem.NONE:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_end_drag(mb.position)
	elif event is InputEventScreenTouch:
		if not event.pressed:
			_end_drag(event.position)

# ---------- Drag logic ----------
func _try_begin_drag(screen_pos: Vector2) -> void:
	if _backpack_button.get_global_rect().has_point(screen_pos):
		return
	# Check gun slot first, then bullet slot.
	if _gun_slot.visible and not _is_gun_equipped and _gun_slot.get_global_rect().has_point(screen_pos):
		_drag_item = DragItem.GUN
		_dragging_gun.global_position = _gun_slot.get_global_rect().position
		_dragging_gun.size = _gun_slot.size
		_dragging_gun.visible = true
		_dragging_gun.modulate.a = 0.9
		_gun_slot.visible = false
		return
	if _bullet_slot.visible and _bullet_slot.get_global_rect().has_point(screen_pos):
		_drag_item = DragItem.BULLET
		_dragging_bullet.global_position = _bullet_slot.get_global_rect().position
		_dragging_bullet.size = _bullet_slot.size
		_dragging_bullet.visible = true
		_dragging_bullet.modulate.a = 0.9
		_bullet_slot.visible = false
		return

func _end_drag(screen_pos: Vector2) -> void:
	var item := _drag_item
	_drag_item = DragItem.NONE
	if item == DragItem.GUN:
		_dragging_gun.modulate.a = 0.85
	elif item == DragItem.BULLET:
		_dragging_bullet.modulate.a = 0.85
	# Decide where the drop landed.
	var world := _screen_to_world(screen_pos)
	var on_player := false
	var on_npc := false
	if player_target_path != NodePath(""):
		var n := get_node_or_null(player_target_path)
		if n and n is Node2D:
			if (n.global_position - world).length() <= interact_radius:
				on_player = true
	if npc_target_path != NodePath(""):
		var n := get_node_or_null(npc_target_path)
		if n and n is Node2D:
			if (n.global_position - world).length() <= interact_radius:
				on_npc = true
	# Resolve the drop.
	if item == DragItem.GUN:
		if on_player:
			gun_dropped_on_player.emit()
			_hide_dragging_gun()
			return
		if on_npc:
			gun_dropped_on_npc.emit()
			_hide_dragging_gun()
			return
		_return_gun_to_slot()
	elif item == DragItem.BULLET:
		if on_npc:
			bullet_dropped_on_npc.emit()
			_hide_dragging_bullet()
			return
		if on_player:
			# No effect when dropped on the player.
			_return_bullet_to_slot()
			return
		_return_bullet_to_slot()

func _hide_dragging_gun() -> void:
	_dragging_gun.visible = false
	# Gun is now equipped -- show a silhouette in the slot.
	_gun_slot.visible = true
	_gun_slot.modulate = gun_silhouette_modulate
	_is_gun_equipped = true

func _hide_gun_silhouette() -> void:
	# Gun returns to the backpack -- restore the slot to its normal full-alpha state.
	_gun_slot.visible = true
	_gun_slot.modulate.a = 1.0
	_is_gun_equipped = false

func _hide_dragging_bullet() -> void:
	_dragging_bullet.visible = false
	# Bullet is consumed.
	_bullet_slot.visible = false
	_bullet_slot.modulate.a = 1.0

func _return_gun_to_slot() -> void:
	_gun_slot.visible = true
	_gun_slot.modulate.a = 1.0
	_dragging_gun.visible = false
	_is_gun_equipped = false
	item_returned_to_slot.emit("gun")
	var tween := create_tween()
	tween.tween_property(_dragging_gun, "global_position", _gun_slot.get_global_rect().position, back_to_slot_time)
	tween.tween_property(_dragging_gun, "modulate:a", 0.0, back_to_slot_time)
	tween.finished.connect(func ():
		_dragging_gun.modulate.a = 0.85)

func _return_bullet_to_slot() -> void:
	_bullet_slot.visible = true
	_bullet_slot.modulate.a = 1.0
	_dragging_bullet.visible = false
	item_returned_to_slot.emit("bullet")
	var tween := create_tween()
	tween.tween_property(_dragging_bullet, "global_position", _bullet_slot.get_global_rect().position, back_to_slot_time)
	tween.tween_property(_dragging_bullet, "modulate:a", 0.0, back_to_slot_time)
	tween.finished.connect(func ():
		_dragging_bullet.modulate.a = 0.85)

func _screen_to_world(screen_pos: Vector2) -> Vector2:
	var cam := get_viewport().get_camera_2d()
	if cam:
		return get_viewport().get_canvas_transform().affine_inverse() * screen_pos
	return screen_pos

func _process(_delta: float) -> void:
	if _drag_item == DragItem.GUN:
		_dragging_gun.global_position = get_viewport().get_mouse_position() - _drag_offset
	elif _drag_item == DragItem.BULLET:
		_dragging_bullet.global_position = get_viewport().get_mouse_position() - _drag_offset

# ---------- Backpack button ----------
func _toggle() -> void:
	_is_open = not _is_open
	inventory_toggled.emit(_is_open)
	for t in get_tree().get_processed_tweens():
		t.kill()
	var closed_x: float = _panel_closed_x
	var open_x: float = closed_x + open_offset_x
	if _is_open:
		var tween := create_tween().set_parallel(true)
		tween.tween_property(_panel, "position:x", open_x, tween_time)
		tween.tween_property(_panel, "modulate:a", 1.0, tween_time)
	else:
		# Reset slot visuals on close.
		if _is_gun_equipped:
			_gun_slot.modulate = gun_silhouette_modulate
		else:
			_gun_slot.modulate.a = 1.0
		_bullet_slot.modulate.a = 1.0
		var tween := create_tween().set_parallel(true)
		tween.tween_property(_panel, "position:x", closed_x, tween_time)
		tween.tween_property(_panel, "modulate:a", 0.0, tween_time)
