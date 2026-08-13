extends CharacterBody2D
class_name BaseUnit
## Static helper: show HP snapshots on all alive units in the scene tree.
## Call as: BaseUnit.show_all_hp_snapshots()
static func show_all_hp_snapshots() -> void:
	for n in Engine.get_main_loop().root.get_tree().get_nodes_in_group(&"player_units"):
		var u: BaseUnit = n as BaseUnit
		if u != null and u.current_hp > 0:
			u.show_hp_snapshot()
	for n in Engine.get_main_loop().root.get_tree().get_nodes_in_group(&"enemy_units"):
		var u: BaseUnit = n as BaseUnit
		if u != null and u.current_hp > 0:
			u.show_hp_snapshot()
## Single unit (player or enemy) in the arena. Holds a UnitData resource
## and drives wander / combat / ability / weapon behavior from it.
##
## Both player armies and enemy waves instantiate this class — only
## `unit_data.faction` and the spawn context (who's in the squad, who's
## in the wave) differs. The collision/shape/AI is shared.
##
## Hierarchy:
##   BaseUnit (CharacterBody2D)
##     CollisionShape2D (circle)
##     HitBox (Area2D)  — detects nearby enemies for combat & weapon pickup
##       CollisionShape2D
##     Sprite (Node2D)  — rotates to face target
##       AnomaliSprite (Sprite2D)
##     WeaponAnchor (Node2D) — visual anchor for equipped weapon

const AbilityIds = preload("res://scripts/ability_ids.gd")

## The data driving this unit's stats, abilities, weapons, and visuals.
@export var unit_data: Resource = null

## Equipped weapon (WeaponData or null). Modifies stats at runtime.
var equipped_weapon: Resource = null

## Origin tracking for weapon-drop-on-death lineage.
var equipped_weapon_origin: String = ""
var equipped_weapon_instance_id: int = 0

## Live HP. max_hp is computed from unit_data + weapon modifiers.
var current_hp: int = 10
var max_hp: int = 10
## Multiplier for max HP (set by Arena to double for longer games).
var _hp_scale: float = 1.0
## Per-wave stat scaling for enemy units. Set by Arena before spawning.
## Applied in apply_data_to_self() to both HP and ATK.
var _wave_scale: float = 1.0

## Effective stats after weapon modifiers applied.
var eff_attack: int = 1
var eff_speed: float = 60.0
var eff_speedwalk: float = 35.0
var eff_knockback: float = 5.0
var eff_ability_id: int = 0

## Combat / movement state.
var _attack_timer: float = 0.0
## Per-target damage cooldown map: {target_instance_id: remaining_seconds}.
## Prevents double damage when both units are in range of each other
## (tick hit + retaliation hit in the same frame).
## Reset per-target when the cooldown expires (not per-tick).
var _target_damage_cooldown: Dictionary = {}
const DAMAGE_COOLDOWN: float = 0.15  # seconds — must expire before dealing damage again to same target
## Cooldown to prevent infinite retaliation chains when two units hit each other.
var _retaliation_cooldown: float = 0.0
const RETALIATION_COOLDOWN: float = 0.12  # seconds
var _wander_dir: Vector2 = Vector2.ZERO
var _wander_timer: float = 0.0
var _walk_phase: float = 0.0
var _is_player: bool = false

## Genius AI overrides.
var _genius_target: Node2D = null
var _genius_has_target: bool = false

## Visual sprite scale per faction. Set once in _ready.
## 4x scale: player Anomali figure at 0.88, enemy Player.png at 1.32
## (Player.png is naturally 1.5x the Anomali texture size).
const PLAYER_SPRITE_SCALE: float = 0.88
const ENEMY_SPRITE_SCALE: float = 1.32

## Optional arena bounds (set by Arena on spawn at global_position).
## Used for vertical/horizontal clamping so units can't escape the
## arena edge.
var arena_rect: Rect2 = Rect2()

## Persistent knockback velocity. When a unit takes a hit, this vector
## is set so the unit actually flies across the arena on contact
## instead of getting a 1-frame velocity nudge that gets overwritten
## by movement next frame. Decays over KNOCKBACK_DURATION seconds.
var _knockback_vel: Vector2 = Vector2.ZERO
var _knockback_timer: float = 0.0
## Tracks whether the active knockback uses the victory duration (1.2s)
## vs. the normal duration (0.35s). Used in _physics_process to pick
## the right decay divisor.
var _kb_is_victory: bool = false
const KNOCKBACK_DURATION: float = 0.35  # seconds (normal combat)
const KNOCKBACK_DURATION_VICTORY: float = 1.8  # longer for the win celebration
const KNOCKBACK_IMPULSE: float = 28.0
const KNOCKBACK_VICTORY_MULTIPLIER: float = 100.0  # 100x for victory burst
const BOUNCE_DAMPING: float = 0.85  # velocity multiplier on bounce

## Victory knockback: 20x the normal knockback force.
## normal: eff_knockback * KNOCKBACK_IMPULSE (e.g. 5 * 28 = 140 px/sec)
## victory: eff_knockback * VICTORY_KNOCKBACK_MULTIPLIER (e.g. 5 * 560 = 2800)
const VICTORY_KNOCKBACK_MULTIPLIER: float = 112.0  # 20 * KNOCKBACK_IMPULSE (20x)
const VICTORY_KNOCKBACK_DURATION: float = 1.2  # longer than normal (0.35s) for floaty feel

## White flash on victory knockback (distinct from red damage flash).
const VICTORY_FLASH_DURATION: float = 0.15
const VICTORY_FLASH_COLOR: Color = Color(3.0, 3.0, 3.0, 1.0)  # overbright white

## Heal outline: green rim glow that fades out over HEAL_OUTLINE_DURATION.
var _heal_outline_active: bool = false
var _heal_outline_timer: float = 0.0
const HEAL_OUTLINE_DURATION: float = 1.0  # seconds
const HEAL_OUTLINE_OFFSET: float = 12.0  # same as normal max outline (1x)

## Base offset applied to all equipped weapons. When a unit's
## weapon_anchor_offset is Vector2(0, 0), the weapon lands at this
## position. Edit this to shift the visual "center" of weapons globally
## without touching every unit .tres file.
const WEAPON_ANCHOR_BASE: Vector2 = Vector2(0, 0)

## Rim glow: a red outline around the unit that grows THICKER and BRIGHTER
## as HP drops. At full HP, the outline is invisible (alpha=0, thin offset).
## At 0 HP, the outline is at maximum thickness (12px) and full opacity.
const RIM_GLOW_MIN_OFFSET: float = 3.0  # Outline thickness at full HP (px)
const RIM_GLOW_MAX_OFFSET: float = 12.0  # Outline thickness at 0 HP (3x thicker)
const RIM_GLOW_MIN_INTENSITY: float = 0.0  # Invisible at full HP
const RIM_GLOW_MAX_ALPHA: float = 1.0  # Peak alpha at 0 HP

## Internal refs (set in _ready).
@onready var _sprite: Node2D = $BodySprite
@onready var _visual: Sprite2D = $BodySprite/AnomaliSprite
@onready var _hit_box: Area2D = $HitBox
@onready var _weapon_anchor: Node2D = $WeaponAnchor
@onready var _rim_glow_layer: Node2D = $BodySprite/RimGlowLayer
@onready var _rim_glow_N: Sprite2D = $BodySprite/RimGlowLayer/N
@onready var _rim_glow_NE: Sprite2D = $BodySprite/RimGlowLayer/NE
@onready var _rim_glow_E: Sprite2D = $BodySprite/RimGlowLayer/E
@onready var _rim_glow_SE: Sprite2D = $BodySprite/RimGlowLayer/SE
@onready var _rim_glow_S: Sprite2D = $BodySprite/RimGlowLayer/S
@onready var _rim_glow_SW: Sprite2D = $BodySprite/RimGlowLayer/SW
@onready var _rim_glow_W: Sprite2D = $BodySprite/RimGlowLayer/W
@onready var _rim_glow_NW: Sprite2D = $BodySprite/RimGlowLayer/NW
@onready var _hover_area: Area2D = $HoverArea
@onready var _hp_bar: Node2D = $HpBar
@onready var _hp_bar_fill: ColorRect = $HpBar/HpBarFill
@onready var _hp_snapshot: Node2D = $HpSnapshot

## Signals
signal died(unit: BaseUnit)
signal hp_changed(new_hp: int, max_hp: int)
signal weapon_equipped(weapon: Resource)
signal weapon_unequipped(weapon: Resource)

func _ready() -> void:
	if unit_data == null:
		push_error("BaseUnit: unit_data is null")
		return
	_is_player = (unit_data.faction == 0)
	# Configure collision layers so opposing-faction units pass through
	# each other (no physical collision) but their HitBoxes still detect
	# each other.
	if _is_player:
		collision_layer = 1
		collision_mask = 0
		_hit_box.collision_layer = 1
		_hit_box.collision_mask = 2
	else:
		collision_layer = 2
		collision_mask = 0
		_hit_box.collision_layer = 2
		_hit_box.collision_mask = 1
	apply_data_to_self()
	_apply_tint()
	# Equip the unit's starting weapon, if one is defined in UnitData.
	# Enemy-default weapons do NOT drop on enemy death (per design rules).
	# Player starting weapons would drop on death (origin = "player_drop").
	if unit_data.starting_weapon != null:
		var origin: String = "enemy_default" if not _is_player else "player_drop"
		equip_weapon(unit_data.starting_weapon, origin, 0)
	_setup_rim_glow()
	_setup_hp_bar()
	_setup_hp_snapshot()
	if _hover_area:
		_hover_area.mouse_entered.connect(_on_hover_entered)
		_hover_area.mouse_exited.connect(_on_hover_exited)
	_walk_phase = randf_range(0.0, TAU)
	_wander_timer = randf_range(0.5, 2.0)
	add_to_group(&"units")
	hp_changed.connect(_on_hp_changed_for_bar)
	if _is_player:
		add_to_group(&"player_units")
	else:
		add_to_group(&"enemy_units")
	_attack_timer = randf_range(0.0, unit_data.attack_cooldown)
	# Spawn particle burst at the unit's position. Added to the
	# grandparent (the Arena) so the effect persists even if the unit
	# moves or is freed mid-animation.
	_spawn_burst()

## Plays a one-shot particle burst at the unit's spawn position.
## The burst is added to the Arena so it outlives the unit if needed.
func _spawn_burst() -> void:
	var burst_scene: PackedScene = preload("res://scenes/spawn_burst.tscn")
	var burst: Node2D = burst_scene.instantiate() as Node2D
	if burst == null:
		return
	# Position at unit's global position so the burst centers on the
	# spawn point regardless of where the unit ends up.
	burst.global_position = global_position
	# Tint the burst with the unit's color so each faction's spawn
	# reads visually distinct.
	if unit_data != null and burst.has_node("Particles"):
		var particles: CPUParticles2D = burst.get_node("Particles") as CPUParticles2D
		if particles != null:
			particles.color = unit_data.tint
	# Add to the Arena (grandparent) so it lives independently of this
	# unit. Falls back to root if the Arena isn't available.
	var arena: Node = get_parent().get_parent() if get_parent() != null else null
	if arena != null and arena is Node:
		arena.add_child(burst)
	else:
		get_tree().root.add_child(burst)

func apply_data_to_self() -> void:
	## Apply unit_data + HP scale to live stats. Called during _ready() and
	## again by Arena when overriding HP scale for harder waves.
	if unit_data == null:
		return
	max_hp = int(unit_data.max_hp * _hp_scale * _wave_scale)
	eff_attack = int(unit_data.attack * _wave_scale)
	eff_speed = unit_data.speed
	eff_speedwalk = unit_data.speedwalk
	eff_knockback = unit_data.knockback_force
	eff_ability_id = unit_data.ability_id
	if equipped_weapon != null:
		max_hp += equipped_weapon.hp_bonus
		eff_attack += equipped_weapon.attack_bonus
		if equipped_weapon.knockback_override > 0.0:
			eff_knockback = equipped_weapon.knockback_override
		if equipped_weapon.speed_override > 0.0:
			eff_speed = equipped_weapon.speed_override
		if equipped_weapon.ability_override >= 0:
			eff_ability_id = equipped_weapon.ability_override
	current_hp = max_hp
	hp_changed.emit(current_hp, max_hp)

func _apply_tint() -> void:
	# Apply unit tint to the visual sprite (single Sprite2D body).
	# Modulate preserves the white sprite color while tinting. Force
	# alpha to 1.0 so the unit is fully opaque regardless of any
	# inherited modulation.
	if unit_data == null:
		return
	# Swap sprite + scale based on faction:
	#   faction 0 (player/army) → Anomali sprite at PLAYER_SPRITE_SCALE
	#   faction 1 (enemy)        → Player.png at ENEMY_SPRITE_SCALE (1.5x)
	if _visual:
		if unit_data.faction == 0:
			_visual.texture = load("res://assets/Kepala Gajah - Tanpa Wajah - Tipe 1.png") as Texture2D
			_visual.scale = Vector2(PLAYER_SPRITE_SCALE, PLAYER_SPRITE_SCALE)
			# Center the 4x figure: texture is 173x491, scale 0.88 -> 152x432.
			# Place feet at origin: vertical offset = -432/2 = -216. Horizontal = -76.
			_visual.position = Vector2(-76.0, -216.0)
		else:
			_visual.texture = load("res://assets/Player.png") as Texture2D
			_visual.scale = Vector2(ENEMY_SPRITE_SCALE, ENEMY_SPRITE_SCALE)
			# Center the 4x figure: texture is 94x242, scale 1.32 -> 124x320.
			# Place feet at origin: vertical offset = -320/2 = -160. Horizontal = -62.
			_visual.position = Vector2(-62.0, -160.0)
		var c: Color = unit_data.tint
		c.a = 1.0
		_visual.self_modulate = c

## Configure the rim glow outline: 8 Sprite2D copies of the body, offset in
## 8 directions. Each is tinted red via the parent RimGlowLayer's modulate.
## The body covers the inner pixels, leaving a red ring around the silhouette.
func _setup_rim_glow() -> void:
	if _rim_glow_layer == null or unit_data == null:
		return
	# All 8 outline sprites share the same texture as the body.
	var tex: Texture2D
	var body_scale: Vector2
	var body_pos: Vector2
	if unit_data.faction == 0:
		tex = load("res://assets/Kepala Gajah - Tanpa Wajah - Tipe 1.png") as Texture2D
		body_scale = Vector2(PLAYER_SPRITE_SCALE, PLAYER_SPRITE_SCALE)
		body_pos = Vector2(-76.0, -216.0)
	else:
		tex = load("res://assets/Player.png") as Texture2D
		body_scale = Vector2(ENEMY_SPRITE_SCALE, ENEMY_SPRITE_SCALE)
		body_pos = Vector2(-62.0, -160.0)
	# Apply texture + scale + position to all 8 outline sprites.
	var sprites: Array[Sprite2D] = [
		_rim_glow_N, _rim_glow_NE, _rim_glow_E, _rim_glow_SE,
		_rim_glow_S, _rim_glow_SW, _rim_glow_W, _rim_glow_NW,
	]
	for s in sprites:
		if s == null:
			continue
		s.texture = tex
		s.scale = body_scale
		s.position = body_pos
		s.z_index = -1  # Behind the body
	# Base modulate: bright red, alpha set later by _update_rim_glow.
	_rim_glow_layer.modulate = Color(1.0, 0.0, 0.0, 1.0)

## Position the HP bar above the unit's head, hidden by default.
func _setup_hp_bar() -> void:
	if _hp_bar == null:
		return
	_hp_bar.visible = false

## Build the HP snapshot display inside _hp_snapshot.
## Layout: [Heart] HP_value / Name (centered below).
func _setup_hp_snapshot() -> void:
	if _hp_snapshot == null:
		return
	_hp_snapshot.visible = false
	# Clear any previous children.
	for c in _hp_snapshot.get_children():
		_hp_snapshot.remove_child(c)
		c.queue_free()

	# Background panel — larger to fit 2x text.
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.05, 0.9)
	bg.size = Vector2(160, 90)
	_hp_snapshot.add_child(bg)

	# HBox: Heart + HP value.
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.position = Vector2(8, 8)
	_hp_snapshot.add_child(hbox)

	# Heart icon — bigger.
	var heart := TextureRect.new()
	heart.texture = load("res://assets/heart.png")
	heart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	heart.size = Vector2(36, 36)
	heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hbox.add_child(heart)

	# HP value label — 2x size.
	var hp_label := Label.new()
	hp_label.text = str(current_hp)
	hp_label.add_theme_font_size_override("font_size", 32)
	hp_label.add_theme_color_override("font_color", Color(1, 0.85, 0.85, 1))
	hp_label.position = Vector2(40, 0)
	hbox.add_child(hp_label)

	# Name label, centered below — 2x size.
	var name_label := Label.new()
	var unit_name: String = unit_data.display_name if unit_data != null else "Head"
	name_label.text = unit_name
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 0.9))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.position = Vector2(0, 44)
	name_label.size = Vector2(160, 30)
	_hp_snapshot.add_child(name_label)

	# Resize bg to fit content.
	bg.size = Vector2(120, 58)

## Show the HP snapshot above the unit (for outside-arena overview).
## Uses the same auto-hide timer as the normal tap HP bar.
func show_hp_snapshot() -> void:
	if _hp_snapshot == null or current_hp <= 0:
		return
	# Always rebuild to reflect current HP value and updated layout.
	_setup_hp_snapshot()
	_hp_snapshot.visible = true
	# Also hide the normal HP bar while snapshot is showing.
	if _hp_bar:
		_hp_bar.visible = false
	# Auto-hide via the shared tap timer.
	if _tap_hp_timer != null:
		_tap_hp_timer.timeout.disconnect(_on_tap_hp_timer_timeout)
		_tap_hp_timer.queue_free()
	_tap_hp_timer = Timer.new()
	_tap_hp_timer.one_shot = true
	_tap_hp_timer.wait_time = TAP_HP_SHOW_DURATION
	add_child(_tap_hp_timer)
	_tap_hp_timer.timeout.connect(_on_tap_hp_timer_timeout)
	_tap_hp_timer.start()

func _hide_hp_snapshot() -> void:
	if _hp_snapshot:
		_hp_snapshot.visible = false

## Update the rim glow based on current HP. The outline grows THICKER and
## BRIGHTER as HP drops. At full HP it's invisible; at 0 HP it's at maximum
## thickness (12px) and full opacity. Pulse makes it feel alive and urgent.
## When _heal_outline_active, the glow is green and fades out over 1 second.
func _update_rim_glow() -> void:
	if _rim_glow_layer == null or max_hp <= 0:
		return

	# Handle heal outline — green glow that fades out.
	if _heal_outline_active:
		var t: float = _heal_outline_timer / HEAL_OUTLINE_DURATION  # 1.0 → 0.0
		_heal_outline_timer -= get_physics_process_delta_time()
		if _heal_outline_timer <= 0.0:
			_heal_outline_active = false
			_heal_outline_timer = 0.0
			t = 0.0
		# Set 3x-thick outline sprites (36px offset) + green color that fades.
		var sprites: Array[Sprite2D] = [
			_rim_glow_N, _rim_glow_NE, _rim_glow_E, _rim_glow_SE,
			_rim_glow_S, _rim_glow_SW, _rim_glow_W, _rim_glow_NW,
		]
		var sqrt2_over_2: float = 0.7071
		var offsets: Array[Vector2] = [
			Vector2(0, -HEAL_OUTLINE_OFFSET),  # N
			Vector2(HEAL_OUTLINE_OFFSET * sqrt2_over_2, -HEAL_OUTLINE_OFFSET * sqrt2_over_2),  # NE
			Vector2(HEAL_OUTLINE_OFFSET, 0),  # E
			Vector2(HEAL_OUTLINE_OFFSET * sqrt2_over_2, HEAL_OUTLINE_OFFSET * sqrt2_over_2),  # SE
			Vector2(0, HEAL_OUTLINE_OFFSET),  # S
			Vector2(-HEAL_OUTLINE_OFFSET * sqrt2_over_2, HEAL_OUTLINE_OFFSET * sqrt2_over_2),  # SW
			Vector2(-HEAL_OUTLINE_OFFSET, 0),  # W
			Vector2(-HEAL_OUTLINE_OFFSET * sqrt2_over_2, -HEAL_OUTLINE_OFFSET * sqrt2_over_2),  # NW
		]
		for i in range(sprites.size()):
			if sprites[i] != null:
				sprites[i].offset = offsets[i]
		_rim_glow_layer.modulate = Color(0.2, 1.0, 0.4, t)
		return

	# Normal HP-based red outline.
	var hp_ratio: float = float(current_hp) / float(max_hp)
	# Outline thickness grows as HP drops. At full HP: 3px. At 0 HP: 12px.
	var offset_amount: float = lerp(RIM_GLOW_MAX_OFFSET, RIM_GLOW_MIN_OFFSET, hp_ratio)
	# Intensity grows from RIM_GLOW_MIN_INTENSITY (0) at full HP to 1.0 at 0 HP.
	var intensity: float = clampf(RIM_GLOW_MIN_INTENSITY + (1.0 - hp_ratio) * (1.0 - RIM_GLOW_MIN_INTENSITY), 0.0, 1.0)
	# More pronounced pulse: oscillates 0.75-1.0 of base intensity
	var pulse: float = 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.004)
	# Update offsets on all 8 outline sprites so the ring grows with HP loss.
	var sprites: Array[Sprite2D] = [
		_rim_glow_N, _rim_glow_NE, _rim_glow_E, _rim_glow_SE,
		_rim_glow_S, _rim_glow_SW, _rim_glow_W, _rim_glow_NW,
	]
	var sqrt2_over_2: float = 0.7071
	var offsets: Array[Vector2] = [
		Vector2(0, -offset_amount),  # N
		Vector2(offset_amount * sqrt2_over_2, -offset_amount * sqrt2_over_2),  # NE
		Vector2(offset_amount, 0),  # E
		Vector2(offset_amount * sqrt2_over_2, offset_amount * sqrt2_over_2),  # SE
		Vector2(0, offset_amount),  # S
		Vector2(-offset_amount * sqrt2_over_2, offset_amount * sqrt2_over_2),  # SW
		Vector2(-offset_amount, 0),  # W
		Vector2(-offset_amount * sqrt2_over_2, -offset_amount * sqrt2_over_2),  # NW
	]
	for i in range(sprites.size()):
		if sprites[i] != null:
			sprites[i].offset = offsets[i]
	# Overbright red (R > 1) so the outline reads as hot. Apply to the layer
	# so all 8 outline sprites inherit the same modulate.
	_rim_glow_layer.modulate = Color(1.4, 0.1, 0.1, intensity * RIM_GLOW_MAX_ALPHA * pulse)

## Update the HP bar fill width based on current HP ratio.
## Also shifts color from green (full) to red (low).
func _update_hp_bar() -> void:
	if _hp_bar_fill == null or max_hp <= 0:
		return
	var ratio: float = clampf(float(current_hp) / float(max_hp), 0.0, 1.0)
	var bar_max_width: float = 80.0
	_hp_bar_fill.size.x = bar_max_width * ratio
	# Color: green (0.2, 0.8, 0.2) at full → red (0.8, 0.2, 0.2) at low.
	_hp_bar_fill.color = Color(
		lerpf(0.2, 0.8, 1.0 - ratio),
		lerpf(0.8, 0.2, 1.0 - ratio),
		0.2, 1.0
	)

## Mouse entered the hover area — do nothing (HP only shows on tap).
func _on_hover_entered() -> void:
	pass

## Mouse left the hover area — do nothing.
func _on_hover_exited() -> void:
	pass

## Keep bar updated if already showing (tap case).
func _on_hp_changed_for_bar(_new_hp: int, _max_hp: int) -> void:
	if _hp_bar and _hp_bar.visible:
		_update_hp_bar()

func has_tag(tag: StringName) -> bool:
	if unit_data == null:
		return false
	if unit_data.tags.has(tag):
		return true
	if equipped_weapon != null and equipped_weapon.flags.has(tag):
		return true
	return false

func equip_weapon(weapon: Resource, origin: String = "player_drop", instance_id: int = 0) -> void:
	if equipped_weapon != null:
		unequip_weapon()
	equipped_weapon = weapon
	equipped_weapon_origin = origin
	equipped_weapon_instance_id = instance_id
	apply_data_to_self()
	if _weapon_anchor:
		_weapon_anchor.visible = true
		var sprite := _weapon_anchor.get_node_or_null("WeaponSprite") as Sprite2D
		if sprite:
			if weapon != null and weapon.sprite_path != "":
				sprite.texture = load(weapon.sprite_path)
				# Scale the weapon to match the unit's sprite scale so the
				# knife reads at the right size on both player and enemy units.
				# Player Anomali is 0.88x, enemy Player.png is 1.32x. The
				# weapon's own sprite_scale (default 1.0) lets you tune per weapon.
				var unit_scale: float = PLAYER_SPRITE_SCALE if _is_player else ENEMY_SPRITE_SCALE
				var s: float = weapon.sprite_scale if weapon != null else 1.0
				sprite.scale = Vector2(unit_scale * s, unit_scale * s)
				# Position the weapon sprite at the unit's configured center.
				# unit_data.weapon_anchor_offset is editable per-unit in the .tres.
				# When the .tres has Vector2(0, 0), the weapon sits at the
				# default anchor position (defined by WEAPON_ANCHOR_BASE).
				# Per-unit values offset FROM that base.
				var anchor_offset: Vector2 = unit_data.weapon_anchor_offset if unit_data != null else Vector2.ZERO
				sprite.offset = anchor_offset * s + WEAPON_ANCHOR_BASE
			else:
				sprite.texture = null
	weapon_equipped.emit(weapon)

func unequip_weapon() -> void:
	if equipped_weapon == null:
		return
	var dropped_weapon: Resource = equipped_weapon
	var dropped_origin: String = equipped_weapon_origin
	var dropped_instance_id: int = equipped_weapon_instance_id
	equipped_weapon = null
	equipped_weapon_origin = ""
	equipped_weapon_instance_id = 0
	apply_data_to_self()
	if _weapon_anchor:
		_weapon_anchor.visible = false
	weapon_unequipped.emit(dropped_weapon)
	var wm: Node = get_tree().root.get_node_or_null("WeaponManager")
	if wm and wm.has_method("spawn_pickup"):
		wm.call("spawn_pickup", dropped_weapon, global_position, dropped_origin, dropped_instance_id)

func take_damage(amount: int, attacker: BaseUnit = null) -> void:
	if current_hp <= 0:
		return
	current_hp -= amount
	_flash_red()
	hp_changed.emit(current_hp, max_hp)
	if current_hp <= 0:
		_die(attacker)
		return
	# Retaliation: if an enemy hit us, immediately strike back.
	# Per-target cooldown prevents double damage: if THIS unit already dealt
	# damage to the attacker recently, skip retaliation.
	# Retaliation cooldown prevents infinite retaliation chains.
	if attacker != null and is_instance_valid(attacker) \
			and attacker.current_hp > 0 \
			and attacker.unit_data != null \
			and attacker.unit_data.faction != unit_data.faction \
			and _retaliation_cooldown <= 0.0 \
			and not _target_damage_cooldown.has(attacker.get_instance_id()):
		_retaliation_cooldown = RETALIATION_COOLDOWN
		attacker._target_damage_cooldown[get_instance_id()] = DAMAGE_COOLDOWN
		# Apply knockback to the attacker.
		var push_dir: Vector2 = (attacker.global_position - global_position).normalized()
		if push_dir.length() < 0.1:
			push_dir = _wander_dir
		var impulse: float = eff_knockback * KNOCKBACK_IMPULSE
		attacker.apply_knockback(-push_dir * impulse)
		attacker.take_damage(eff_attack, self)
		# Face the attacker for visual feedback.
		_face(attacker.global_position)

const FLASH_DURATION: float = 0.35
const FLASH_COLOR: Color = Color(2.5, 0.4, 0.4, 1.0)
var _flash_tween: Tween = null
## Auto-hide timer for tap-triggered HP bar display.
var _tap_hp_timer: Timer = null
## Duration (seconds) the HP bar stays visible after a tap.
const TAP_HP_SHOW_DURATION: float = 2.0

func _flash_red() -> void:
	modulate = FLASH_COLOR
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(self, "modulate", Color.WHITE, FLASH_DURATION)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## White flash for victory knockback — distinct from red damage flash.
func _flash_white() -> void:
	modulate = VICTORY_FLASH_COLOR
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(self, "modulate", Color.WHITE, VICTORY_FLASH_DURATION)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## Apply a victory knockback — 20x stronger than normal, with a longer
## duration and white flash. The impulse direction points AWAY from the
## wave-clear epicenter so every unit flies outward. Bounce at arena
## boundaries is handled in _physics_process using the same bounce system.
func apply_victory_knockback(impulse: Vector2) -> void:
	_knockback_vel = impulse
	_knockback_timer = VICTORY_KNOCKBACK_DURATION
	_kb_is_victory = true
	_flash_white()

func _die(_killer: BaseUnit = null) -> void:
	var should_drop_weapon: bool = false
	if equipped_weapon != null:
		if _is_player:
			should_drop_weapon = true
		elif equipped_weapon_origin == "player_drop":
			should_drop_weapon = true
		elif equipped_weapon.flags.has(&"drop_on_death"):
			should_drop_weapon = true
	var dropped_weapon: Resource = equipped_weapon if should_drop_weapon else null
	var dropped_origin: String = equipped_weapon_origin if should_drop_weapon else ""
	var dropped_instance_id: int = equipped_weapon_instance_id if should_drop_weapon else 0

	equipped_weapon = null
	equipped_weapon_origin = ""
	equipped_weapon_instance_id = 0

	# Play death sound.
	var sm: Node = get_tree().root.get_node_or_null("SoundManager")
	if sm and sm.has_method("play_ally_die") and _is_player:
		sm.call("play_ally_die")
	elif sm and sm.has_method("play_enemy_die"):
		sm.call("play_enemy_die")

	died.emit(self)
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.4)
	t.tween_property(self, "scale", scale * Vector2(0.6, 0.6), 0.4)
	t.tween_callback(queue_free)

	if dropped_weapon != null:
		var wm: Node = get_tree().root.get_node_or_null("WeaponManager")
		if wm and wm.has_method("spawn_pickup"):
			var killer_pos: Vector2 = _killer.global_position if _killer != null else global_position
			# 0.15s delay: weapon drops first, then flies away from killer.
			wm.call("spawn_pickup", dropped_weapon, global_position, dropped_origin, dropped_instance_id, killer_pos, 0.15)

func _physics_process(delta: float) -> void:
	if current_hp <= 0:
		return
	# Tick down per-target damage cooldowns.
	var to_remove: Array = []
	for k in _target_damage_cooldown:
		_target_damage_cooldown[k] -= delta
		if _target_damage_cooldown[k] <= 0.0:
			to_remove.append(k)
	for k in to_remove:
		_target_damage_cooldown.erase(k)
	# Depth sort: units lower on screen (higher Y) draw on top of units
	# higher on screen. z_index is updated every frame so the layering
	# follows the unit as it moves around the arena.
	z_index = int(global_position.y)
	# The weapon anchor sits 1 layer above this unit so the held weapon
	# always draws on top of the unit's body, while Y-depth sorting
	# between different units is still respected (unit A at y=500 with
	# weapon at 501 still draws behind unit B at y=600 with body at 600).
	if _weapon_anchor:
		# z_as_relative defaults to true on CanvasItems, so this is a
		# relative offset (NOT absolute). The weapon's effective z_index
		# becomes unit.z_index + 1, which means it follows the unit's
		# Y-position depth sort between units instead of jumping above all.
		_weapon_anchor.z_index = 1
	# Rim glow alpha tracks HP every frame (so the pulse stays smooth).
	_update_rim_glow()
	if _attack_timer > 0.0:
		_attack_timer -= delta

	_wander_timer -= delta
	# Tick down the persistent knockback state if active.
	if _knockback_timer > 0.0:
		_knockback_timer -= delta
		if _knockback_timer <= 0.0:
			_knockback_vel = Vector2.ZERO
			_knockback_timer = 0.0
			_kb_is_victory = false
	elif _wander_timer <= 0.0:
		_wander_dir = _random_dir()
		_wander_timer = randf_range(0.6, 2.0)

	var move_vec: Vector2 = Vector2.ZERO
	if _knockback_timer > 0.0:
		# Linear decay — unit visibly flies across the arena.
		# Use the victory duration (1.2s) for victory knockback, normal
		# duration (0.35s) for regular combat knockback.
		var base_dur: float = VICTORY_KNOCKBACK_DURATION if _kb_is_victory else KNOCKBACK_DURATION
		var k: float = _knockback_timer / base_dur
		move_vec = _knockback_vel * k
	else:
		move_vec = _resolve_movement_vector(delta)

	velocity = move_vec
	move_and_slide()

	# Clamp inside arena and bounce knockback velocity off boundaries.
	# arena_rect is in GLOBAL coords (set by the Arena node at spawn time,
	# with global_position as origin). The clamp radius matches the unit's
	# visual half-width plus a small safety margin so the visible sprite
	# can't poke outside the arena edge. With 4x scale sprites: player ~80,
	# enemy ~70.
	if arena_rect.size.x > 0.0:
		var r: float = 80.0 if _is_player else 70.0
		var min_pos: Vector2 = arena_rect.position + Vector2(r, r)
		var max_pos: Vector2 = arena_rect.end - Vector2(r, r)

		# Bounce: reflect velocity component when crossing a boundary.
		# Only bounce while being knocked back — wander movement is
		# unaffected by the boundary (units just clamp and continue).
		if _knockback_timer > 0.0 and _knockback_vel.length() > 0.0:
			if global_position.x < min_pos.x:
				global_position.x = min_pos.x
				_knockback_vel.x = absf(_knockback_vel.x) * BOUNCE_DAMPING
			elif global_position.x > max_pos.x:
				global_position.x = max_pos.x
				_knockback_vel.x = -absf(_knockback_vel.x) * BOUNCE_DAMPING
			if global_position.y < min_pos.y:
				global_position.y = min_pos.y
				_knockback_vel.y = absf(_knockback_vel.y) * BOUNCE_DAMPING
			elif global_position.y > max_pos.y:
				global_position.y = max_pos.y
				_knockback_vel.y = -absf(_knockback_vel.y) * BOUNCE_DAMPING
		else:
			global_position = global_position.clamp(min_pos, max_pos)

	# Combat: skip while being knocked back so attackers don't chain
	# hits mid-flight (each contact would re-trigger knockback).
	if _knockback_timer <= 0.0:
		_attack_timer = _tick_combat(_attack_timer)
	# Decay retaliation cooldown every frame so this unit can counter-attack.
	if _retaliation_cooldown > 0.0:
		_retaliation_cooldown -= delta

	_animate_walk(delta)

func _resolve_movement_vector(_delta: float) -> Vector2:
	if unit_data == null:
		return Vector2.ZERO
	if equipped_weapon != null and equipped_weapon.flags.has(&"confusion"):
		var v: Vector2 = _wander_dir * eff_speedwalk
		_face(global_position + _wander_dir)
		return v

	var speed_mult: float = 2.0 if eff_ability_id == AbilityIds.FAST else 1.0

	if _genius_has_target and _genius_target != null and is_instance_valid(_genius_target):
		# Genius weapon target ALWAYS overrides flee. Move toward the weapon pickup.
		var target_pos: Vector2 = _genius_target.global_position
		var dir: Vector2 = (target_pos - global_position).normalized()
		if dir.length() < 0.1:
			dir = _wander_dir
		_face(global_position + dir)
		return dir * eff_speed * speed_mult

	var target: BaseUnit = _find_nearest_target()
	var speed: float = eff_speedwalk

	if target != null:
		var dist: float = (target.global_position - global_position).length()
		if eff_ability_id == AbilityIds.FLEE:
			var away: Vector2 = (global_position - target.global_position).normalized()
			if away.length() < 0.1:
				away = _random_dir()
			var blended: Vector2 = (away * 0.85 + _wander_dir * 0.15).normalized()
			_face(global_position + blended)
			return blended * eff_speed * speed_mult
		var dir2: Vector2 = (target.global_position - global_position).normalized()
		if dir2.length() < 0.1:
			dir2 = _wander_dir
		_face(global_position + dir2)
		speed = eff_speed
		return dir2 * speed * speed_mult

	_face(global_position + _wander_dir)
	return _wander_dir * speed_mult * eff_speedwalk

func _find_nearest_target() -> BaseUnit:
	var opposing_group: StringName = &"enemy_units" if _is_player else &"player_units"
	var nearest: BaseUnit = null
	var best_dist: float = INF
	for n in get_tree().get_nodes_in_group(opposing_group):
		var u: BaseUnit = n as BaseUnit
		if u == null or u.current_hp <= 0:
			continue
		var d: float = (u.global_position - global_position).length()
		if d < best_dist:
			best_dist = d
			nearest = u
	return nearest

func _random_dir() -> Vector2:
	var angle: float = randf_range(0.0, TAU)
	return Vector2(cos(angle), sin(angle)).normalized()

func _face(_target_world: Vector2) -> void:
	# We deliberately do NOT rotate the sprite to face the target.
	# Per design: the unit sprite stays upright and only wobbles ±5°
	# as a slow idle/walk animation. Direction is conveyed by movement,
	# not by sprite rotation.
	pass

func clear_genius_target() -> void:
	if _genius_has_target and (_genius_target == null or not is_instance_valid(_genius_target)):
		_genius_has_target = false
		_genius_target = null

func _animate_walk(delta: float) -> void:
	_walk_phase += delta * 3.0
	var deg: float = sin(_walk_phase) * 5.0
	_sprite.rotation = deg * PI / 180.0
	if current_hp > 0:
		modulate.a = 1.0
		if _visual:
			_visual.self_modulate.a = 1.0

func _tick_combat(prev_timer: float) -> float:
	if unit_data == null:
		return prev_timer
	if eff_ability_id == AbilityIds.FLEE:
		return prev_timer
	if _genius_has_target and _genius_target != null and is_instance_valid(_genius_target):
		return prev_timer

	var opposing_group: StringName = &"enemy_units" if _is_player else &"player_units"
	for n in _hit_box.get_overlapping_bodies():
		var u: BaseUnit = n as BaseUnit
		if u == null or u.current_hp <= 0:
			continue
		if not u.is_in_group(opposing_group):
			continue
		var dist: float = (u.global_position - global_position).length()
		if dist > unit_data.attack_range:
			continue
		if prev_timer > 0.0:
			continue
		# Skip if already on cooldown for this target.
		var target_id: int = u.get_instance_id()
		if _target_damage_cooldown.has(target_id):
			continue
		var push_dir: Vector2 = (u.global_position - global_position).normalized()
		if push_dir.length() < 0.1:
			push_dir = _wander_dir
		# Apply persistent knockback — both units get shoved hard in
		# opposite directions. The velocity persists for KNOCKBACK_DURATION
		# seconds, so units visibly fly across the arena instead of just
		# getting a 1-frame nudge.
		var impulse: float = eff_knockback * KNOCKBACK_IMPULSE
		u.apply_knockback(push_dir * impulse)
		apply_knockback(-push_dir * impulse)
		u.take_damage(eff_attack, self)
		# Set per-target cooldown so we can't damage the same target again until it expires.
		_target_damage_cooldown[target_id] = DAMAGE_COOLDOWN
		# Play attack sound: knife sound if equipped with knife weapon, otherwise damage sound.
		var sm: Node = get_tree().root.get_node_or_null("SoundManager")
		if sm and equipped_weapon != null and equipped_weapon.id == &"knife":
			if sm.has_method("play_knife"):
				sm.call("play_knife")
		elif sm and sm.has_method("play_damage"):
			sm.call("play_damage")
		if eff_ability_id == AbilityIds.DRACULA and u.current_hp > 0:
			var heal: int = int(eff_attack * 0.5)
			if heal > 0:
				current_hp = min(current_hp + heal, max_hp)
				hp_changed.emit(current_hp, max_hp)
		_face(u.global_position)
		return unit_data.attack_cooldown
	return prev_timer

## Apply a knockback impulse. The unit will be pushed by `impulse`
## (pixels/sec) over the next KNOCKBACK_DURATION seconds, with linear
## decay. Movement is suspended for the duration — the unit can't
## fight the impulse with its normal wander/chase logic.
func apply_knockback(impulse: Vector2) -> void:
	_knockback_vel = impulse
	_knockback_timer = KNOCKBACK_DURATION
	_kb_is_victory = false

func round_end_heal() -> void:
	if current_hp <= 0:
		return
	var heal: int = int(max_hp * 0.1)
	if heal > 0:
		current_hp = min(current_hp + heal, max_hp)
		hp_changed.emit(current_hp, max_hp)
		_show_heal_effect()

func rest_heal() -> void:
	if current_hp <= 0:
		return
	var heal: int = int(max_hp * 0.2)
	if heal > 0:
		current_hp = min(current_hp + heal, max_hp)
		hp_changed.emit(current_hp, max_hp)
		_show_heal_effect()

func sacrifice_current_hp() -> bool:
	if current_hp <= 0:
		return false
	var loss: int = int(current_hp * 0.2)
	if loss < 1:
		loss = 1
	var new_hp: int = current_hp - loss
	if new_hp < 1:
		new_hp = 1
	if new_hp == current_hp:
		return false
	current_hp = new_hp
	hp_changed.emit(current_hp, max_hp)
	return true

## Show the HP bar above the unit when tapped. The bar auto-hides
## after TAP_HP_SHOW_DURATION seconds. Repeated taps reset the timer.
func show_hp_on_tap() -> void:
	if _hp_bar == null or current_hp <= 0:
		return
	_update_hp_bar()
	_hp_bar.visible = true
	# Reset the auto-hide timer on each tap.
	if _tap_hp_timer != null:
		_tap_hp_timer.timeout.disconnect(_on_tap_hp_timer_timeout)
		_tap_hp_timer.queue_free()
	_tap_hp_timer = Timer.new()
	_tap_hp_timer.one_shot = true
	_tap_hp_timer.wait_time = TAP_HP_SHOW_DURATION
	add_child(_tap_hp_timer)
	_tap_hp_timer.timeout.connect(_on_tap_hp_timer_timeout)
	_tap_hp_timer.start()

func _on_tap_hp_timer_timeout() -> void:
	if _hp_bar:
		_hp_bar.visible = false
	if _hp_snapshot:
		_hp_snapshot.visible = false

## Triggered by round_end_heal() / rest_heal() when HP is restored.
## Shows a green rim glow that fades out over HEAL_OUTLINE_DURATION seconds,
## plus a burst of "+" particles at the unit's center. Sound fires only once (first unit).
func _show_heal_effect() -> void:
	if _rim_glow_layer == null:
		return
	# Play heal sound only the first time (static guard — resets each heal session).
	if not _heal_sound_played:
		_heal_sound_played = true
		var sm: Node = get_node_or_null("/root/SoundManager")
		if sm != null:
			sm.call("play_heal")
	# Start the green outline.
	_heal_outline_active = true
	_heal_outline_timer = HEAL_OUTLINE_DURATION
	# Spawn a burst of "+" particles at the unit's center.
	_spawn_heal_particles()

## Spawns 3 random "+" particles within a 3x3 grid, centered on the unit's body.
func _spawn_heal_particles() -> void:
	const PARTICLE_COUNT: int = 3  # random 3 particles
	const PARTICLE_SIZE: int = 160  # 2x bigger "+" sign
	const LIFT_AMOUNT: float = 50.0
	const DURATION: float = 1.0
	const CENTER_OFFSET_X: float = -110.0  # center on sprite body X
	const CENTER_OFFSET_Y: float = -260.0  # offset upward to body center Y
	const GRID_SIZE: int = 3
	const SPACING: float = 24.0  # tighter spacing matching centered offset

	# Build a shuffled list of 3x3 grid indices and pick the first 3.
	var indices: Array = range(GRID_SIZE * GRID_SIZE)
	for i in range(indices.size()):
		var j: int = randi() % indices.size()
		var tmp: int = indices[i]
		indices[i] = indices[j]
		indices[j] = tmp
	var chosen: Array = indices.slice(0, PARTICLE_COUNT)

	for idx in chosen:
		var col: int = idx % GRID_SIZE
		var row: int = idx / GRID_SIZE
		var grid_x: float = (col - 1) * SPACING + CENTER_OFFSET_X
		var grid_y: float = (row - 1) * SPACING + CENTER_OFFSET_Y
		var label := Label.new()
		label.text = "+"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", PARTICLE_SIZE)
		label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4, 1.0))
		label.position = Vector2(grid_x, grid_y)
		add_child(label)
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(label, "position:y", label.position.y - LIFT_AMOUNT, DURATION)
		tw.tween_property(label, "modulate:a", 0.0, DURATION)
		tw.finished.connect(label.queue_free)

## Static flag: prevents heal sound from firing multiple times per heal session.
## Set to false at the start of each round-end or rest heal.
static var _heal_sound_played: bool = false
