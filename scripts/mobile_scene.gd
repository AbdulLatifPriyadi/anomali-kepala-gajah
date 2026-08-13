extends Control
## Mobile scene orchestrator. Drives the state machine:
##   EMPTY -> PRIZE_PICK -> CHALLENGE_PICK -> COMBAT -> ROUND_END
##   -> (CHECKPOINT if 3rd pick & 3rd round) -> EMPTY
##
## Uses GameState singleton as the source of truth for phase.
## Uses PopupManager for prize/challenge/checkpoint/encounter popups.

const AbilityIds = preload("res://scripts/ability_ids.gd")
const WaveOptionData = preload("res://scripts/wave_option_data.gd")

## Arena node (child of this control). Spawns units & runs combat tick.
@export var arena_path: NodePath
## PopupManager node (CanvasLayer).
@export var popup_manager_path: NodePath

## Card library (UnitData refs) used to roll prize options.
@export var prize_pool: Array = []
## Legacy wave data (used if wave_options is empty).
@export var easy_wave_data: Array = []
@export var hard_wave_data: Array = []
## Wave options display database. Controls popup position, text scales,
## and per-wave title/description/tint/swatch for each wave+tier entry.
@export var wave_options_database: Resource = null
## Wolf pool used by Dark Forest encounter.
@export var wolf_pool: Array = []
## Sword weapon for Dark Forest reward.
@export var sword_reward: Resource = null
## Anomali pool used for "Mancing" reward.
@export var anomali_pool: Array = []

@onready var arena: Arena = get_node_or_null(arena_path)
@onready var popup_manager: PopupManager = get_node_or_null(popup_manager_path)

## Loaded resources (resolved from string paths in editor arrays).
var _prize_pool: Array[Resource] = []
var _easy_wave_data: Array[Resource] = []
var _hard_wave_data: Array[Resource] = []
var _wolf_pool: Array[Resource] = []
var _anomali_pool: Array[Resource] = []
## Guard: prevents _on_wave_cleared from firing twice (once on wave-clear, once on phase change).
var _heal_pending: bool = false

## Helper: resolve the GameState autoload via node path. Avoids the
## "Identifier not found: GameState" compile error that happens when
## Godot's autoload-identifier cache is stale.
func _gs() -> Node:
	return get_node_or_null("/root/GameState")

## Intercept all input to check for outside-arena HP snapshot trigger.
func _input(event: InputEvent) -> void:
	# 'H' key: always toggle HP snapshot overview during combat.
	if event is InputEventKey and event.pressed and event.keycode == KEY_H:
		_handle_h_key()
		return
	# Touch/click outside arena during combat → show HP overview.
	if event is InputEventScreenTouch and event.pressed:
		_handle_outside_arena_touch(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_outside_arena_touch(event.position)

## 'H' key handler — show HP snapshots on all units.
func _handle_h_key() -> void:
	var gs = _gs()
	if gs == null:
		return
	if gs.phase != 4:  # Phase.COMBAT
		return
	_show_all_hp_snapshots()

## Check if touch is outside the arena during combat and show all HP snapshots.
func _handle_outside_arena_touch(screen_pos: Vector2) -> void:
	var gs = _gs()
	if gs == null:
		return
	if gs.phase != 4:  # Phase.COMBAT
		return
	# Check if outside arena bounds.
	var is_outside: bool = true
	for n in get_tree().get_nodes_in_group(&"player_units"):
		var u: BaseUnit = n as BaseUnit
		if u == null:
			continue
		var arena_rect_val = u.get(&"arena_rect")
		if arena_rect_val != null:
			var arena_rect: Rect2 = arena_rect_val
			is_outside = not arena_rect.has_point(screen_pos)
			break
	if is_outside:
		_show_all_hp_snapshots()

## Show HP snapshots on all alive player and enemy units.
func _show_all_hp_snapshots() -> void:
	for n in get_tree().get_nodes_in_group(&"player_units"):
		var u: BaseUnit = n as BaseUnit
		if u != null and u.current_hp > 0 and u.has_method("show_hp_snapshot"):
			u.show_hp_snapshot()
	for n in get_tree().get_nodes_in_group(&"enemy_units"):
		var u: BaseUnit = n as BaseUnit
		if u != null and u.current_hp > 0 and u.has_method("show_hp_snapshot"):
			u.show_hp_snapshot()

func _ready() -> void:
	_prize_pool = _resolve_paths(prize_pool)
	_easy_wave_data = _resolve_paths(easy_wave_data)
	_hard_wave_data = _resolve_paths(hard_wave_data)
	_wolf_pool = _resolve_paths(wolf_pool)
	_anomali_pool = _resolve_paths(anomali_pool)
	_heal_pending = false
	# Subscribe to phase transitions.
	var gs: Node = _gs()
	if gs:
		gs.connect("phase_changed", _on_phase_changed)
	# Subscribe to arena events.
	if arena != null:
		arena.wave_cleared.connect(_on_wave_cleared)
		arena.player_unit_died.connect(_on_player_unit_died)
	# Start the loop after a beat.
	await get_tree().create_timer(0.4).timeout
	if gs:
		gs.call("set_phase", 1)  # PRIZE_PICK

func _resolve_paths(paths: Array) -> Array[Resource]:
	var out: Array[Resource] = []
	for p in paths:
		if p is String:
			var r: Resource = load(p)
			if r != null:
				out.append(r)
		elif p is Resource:
			out.append(p)
	return out

func _on_phase_changed(new_phase: int, _prev: int) -> void:
	# Use literal integer values from the GameState.Phase enum:
	#   EMPTY=0, PRIZE_PICK=1, CHALLENGE_PICK=2, CHECKPOINT=3,
	#   COMBAT=4, ROUND_END=5, GAME_OVER=6
	var gs: Node = _gs()
	if gs == null:
		return
	match new_phase:
		1:  # PRIZE_PICK
			_show_prize()
		2:  # CHALLENGE_PICK
			_show_challenge()
		4:  # COMBAT
			_start_combat()
		5:  # ROUND_END
			await get_tree().create_timer(0.8).timeout
			gs.call("on_round_end_processed")
		3:  # CHECKPOINT
			_show_checkpoint()
		0:  # EMPTY
			await get_tree().create_timer(0.4).timeout
			gs.call("set_phase", 1)  # PRIZE_PICK
		6:  # GAME_OVER
			_show_game_over()

func _show_prize() -> void:
	if popup_manager == null:
		return
	popup_manager.show_prize(_prize_pool, _on_prize_picked)

func _on_prize_picked(unit_data: Resource) -> void:
	if unit_data == null:
		return
	var gs: Node = _gs()
	if arena != null and gs:
		var spawn_idx: int = int(gs.army_data.size())
		arena.spawn_player_unit(unit_data, spawn_idx)
	if gs:
		gs.call("on_prize_picked", unit_data)

func _show_challenge() -> void:
	if popup_manager == null:
		return
	var gs: Node = _gs()
	var wave_num: int = int(gs.rounds_completed) + 1 if gs else 1

	# Build 2 tier options (Easy, Hard), each with 2 sub-possibilities.
	var opts: Array[WaveOptionData] = []
	_build_wave_options_for(wave_num, opts)

	if not opts.is_empty():
		popup_manager.show_wave_options(opts, _on_wave_option_picked)
		return
	popup_manager.show_challenge(_easy_wave_data, _hard_wave_data, _on_challenge_picked)

## Builds two pre-picked popup options for the given wave number.
## Each option is decided RANDOMLY at build time (before popup shows),
## so the description says EXACTLY what will spawn — no "OR" possibilities.
## Enemy pools organized by difficulty tier. Mixed into waves 4+.
const POOL_TIER1 := [
	"res://data/units/berserker_civilian.tres",
	"res://data/units/armored_brute.tres",
]
const POOL_TIER2 := [
	"res://data/units/healer_civilian.tres",
	"res://data/units/speed_demon.tres",
]
const POOL_TIER3 := [
	"res://data/units/knife_gang_leader.tres",
	"res://data/units/wolf_pack_alpha.tres",
	"res://data/units/human_with_knife_drop.tres",
]
const POOL_TIER4 := [
	"res://data/units/vampire_lord.tres",
	"res://data/units/phantom_assassin.tres",
]
const POOL_BOSS := [
	"res://data/units/titan_bruiser.tres",
	"res://data/units/sword_warlord.tres",
	"res://data/units/anomali_tank.tres",
]
## Every 5 waves the scaling multiplier increases by 0.1.
const WAVE_SCALE_STEP: float = 0.1
## Boss waves (every 5th wave starting at wave 10).
func _is_boss_wave(w: int) -> bool:
	return w >= 10 and (w % 5) == 0

func _build_progressive_wave(wave_num: int, difficulty: String) -> Array:
	var is_boss: bool = _is_boss_wave(wave_num)
	var is_hard: bool = difficulty == "hard"
	var scale_factor: float = 1.0 + float(wave_num - 1) * WAVE_SCALE_STEP

	var enemy_count: int = 0
	if wave_num <= 5:
		enemy_count = 3 if is_hard else 2
	elif wave_num <= 8:
		enemy_count = 4 if is_hard else 3
	elif wave_num <= 12:
		enemy_count = 5 if is_hard else 4
	else:
		enemy_count = 6 if is_hard else 5

	var pool: Array = []
	if is_boss:
		# Boss wave: 1 boss + 2-3 escorts
		var boss_idx: int = randi() % POOL_BOSS.size()
		pool.append(POOL_BOSS[boss_idx])
		var escorts: int = 2 if is_hard else 2
		for _i in range(escorts):
			var tier: int = randi() % POOL_TIER3.size()
			pool.append(POOL_TIER3[tier])
	else:
		# Build pool from available tiers
		pool = _build_wave_pool(wave_num, is_hard)
		# Shuffle and trim to desired count
		var rng = RandomNumberGenerator.new()
		rng.seed = hash(wave_num * 1000 + (1 if difficulty == "hard" else 0))
		pool.shuffle()
		if pool.size() > enemy_count:
			pool.resize(enemy_count)
		while pool.size() < enemy_count:
			var tier: int = mini(randi() % POOL_TIER4.size(), POOL_TIER4.size() - 1)
			pool.append(POOL_TIER4[tier])

	return pool

func _build_wave_pool(w: int, hard: bool) -> Array:
	var pool: Array = []
	# Always include some known quantities from earlier waves
	if hard:
		pool.append("res://data/units/human_with_knife_drop.tres")
	# Add tiers based on wave number
	var max_tier: int = mini(4, ((w - 4) / 2) as int + 1)
	var available_pools: Array = [
		POOL_TIER1,
		POOL_TIER2,
		POOL_TIER3,
		POOL_TIER4,
	]
	for tier_idx in range(max_tier + 1):
		if tier_idx < available_pools.size():
			var tier_pool: Array = available_pools[tier_idx]
			var picks: int = (2 if hard else 1) if tier_idx <= 1 else (1 if hard else 1)
			for _i in range(picks):
				var idx: int = randi() % tier_pool.size()
				pool.append(tier_pool[idx])
	return pool

func _build_wave_options_for(wave_num: int, out_opts: Array[WaveOptionData]) -> void:
	out_opts.clear()

	var wave_1_easy_a: Array = ["res://data/units/coward_human.tres", "res://data/units/coward_human.tres"]
	var wave_1_easy_b: Array = ["res://data/units/brave_human.tres", "res://data/units/coward_human.tres"]
	var wave_1_hard_a: Array = ["res://data/units/human_with_knife.tres"]
	var wave_1_hard_b: Array = ["res://data/units/brave_human.tres", "res://data/units/brave_human.tres"]

	var wave_2_easy_a: Array = ["res://data/units/brave_human_w2.tres", "res://data/units/brave_human_w2.tres"]
	var wave_2_easy_b: Array = ["res://data/units/tiny_human.tres", "res://data/units/tiny_human.tres",
								  "res://data/units/tiny_human.tres", "res://data/units/tiny_human.tres"]
	var wave_2_hard_a: Array = ["res://data/units/human_with_knife_drop.tres", "res://data/units/coward_genius_human.tres"]
	var wave_2_hard_b: Array = ["res://data/units/brave_human_w2.tres", "res://data/units/brave_human_w2.tres",
								  "res://data/units/brave_human_w2.tres"]

	var wave_3_easy_a: Array = ["res://data/units/brave_human_knife_w1.tres", "res://data/units/brave_human_knife_w1.tres"]
	var wave_3_easy_b: Array = ["res://data/units/brave_human_w3.tres", "res://data/units/brave_human_w3.tres",
								  "res://data/units/brave_human_knife_w3.tres"]
	var wave_3_hard_a: Array = ["res://data/units/human_with_knife_drop.tres", "res://data/units/coward_genius_fast.tres",
								 "res://data/units/coward_genius_fast.tres", "res://data/units/coward_genius_fast.tres"]
	var wave_3_hard_b: Array = ["res://data/units/tiny_human.tres", "res://data/units/tiny_human.tres",
								 "res://data/units/tiny_human.tres", "res://data/units/tiny_human.tres",
								 "res://data/units/tiny_human.tres", "res://data/units/tiny_human.tres",
								 "res://data/units/tiny_human.tres", "res://data/units/tiny_human.tres"]

	# Randomly pick one option for each difficulty (pre-decided before popup shows).
	var easy_opts: Array = []
	var hard_opts: Array = []
	match wave_num:
		1:
			easy_opts = [wave_1_easy_a, wave_1_easy_b]
			hard_opts = [wave_1_hard_a, wave_1_hard_b]
		2:
			easy_opts = [wave_2_easy_a, wave_2_easy_b]
			hard_opts = [wave_2_hard_a, wave_2_hard_b]
		3:
			easy_opts = [wave_3_easy_a, wave_3_easy_b]
			hard_opts = [wave_3_hard_a, wave_3_hard_b]
		_:
			# Waves 4+: procedurally generated with escalating difficulty
			var easy_a: Array = _build_progressive_wave(wave_num, "easy")
			var hard_a: Array = _build_progressive_wave(wave_num, "hard")
			easy_opts = [easy_a]
			hard_opts = [hard_a]

	# Easy option
	if easy_opts.size() > 0:
		var easy_paths: Array = easy_opts[randi() % easy_opts.size()]
		var easy_opt: WaveOptionData = WaveOptionData.new()
		easy_opt.label = "Wave %d" % wave_num
		easy_opt.description = "Spawn: %s" % _describe_paths(easy_paths)
		if _is_boss_wave(wave_num):
			easy_opt.label = "BOSS — Wave %d" % wave_num
			easy_opt.tint_color = Color(0.7, 0.1, 0.1, 1.0)
			easy_opt.description = "A terrifying boss appears! %s" % _describe_paths(easy_paths)
		else:
			easy_opt.tint_color = Color(0.3 + float(wave_num) * 0.04, 0.7 - float(wave_num) * 0.03, 0.3, 1.0)
			easy_opt.description = "Wave %d escalating. Spawn: %s" % [wave_num, _describe_paths(easy_paths)]
		easy_opt.title_scale = 1.1
		easy_opt.desc_scale = 0.95
		easy_opt.enemy_paths = easy_paths
		out_opts.append(easy_opt)

	# Hard option
	if hard_opts.size() > 0:
		var hard_paths: Array = hard_opts[randi() % hard_opts.size()]
		var hard_opt: WaveOptionData = WaveOptionData.new()
		hard_opt.label = "Wave %d Hard" % wave_num
		if _is_boss_wave(wave_num):
			hard_opt.label = "BOSS — Wave %d Hard" % wave_num
			hard_opt.tint_color = Color(0.85, 0.05, 0.05, 1.0)
		else:
			hard_opt.tint_color = Color(0.8, 0.2 + float(wave_num) * 0.03, 0.2, 1.0)
		hard_opt.description = "Brutal wave %d! Spawn: %s" % [wave_num, _describe_paths(hard_paths)]
		hard_opt.title_scale = 1.15
		hard_opt.desc_scale = 0.9
		hard_opt.enemy_paths = hard_paths
		out_opts.append(hard_opt)

## Applies display metadata from wave_options_database to a WaveOptionData.
## Falls back to sensible defaults if the database entry is empty.
func _apply_db_to_option(wave_num: int, difficulty: String, opt: WaveOptionData) -> void:
	if wave_options_database == null:
		_set_option_defaults(opt, difficulty)
		return
	var entry: Dictionary = wave_options_database.get_entry(wave_num, difficulty)
	if entry.is_empty() or entry.get("title", "") == "":
		_set_option_defaults(opt, difficulty)
		return
	opt.label = entry.get("title", opt.label)
	opt.description = entry.get("description", opt.description)
	opt.tint_color = entry.get("tint_color", opt.tint_color)
	opt.swatch_texture = entry.get("swatch_texture", null)
	opt.title_scale = float(entry.get("title_scale", 1.0))
	opt.desc_scale = float(entry.get("desc_scale", 1.0))

func _set_option_defaults(opt: WaveOptionData, difficulty: String) -> void:
	if difficulty == "hard":
		opt.label = "Hard Wave"
		opt.description = "Dangerous enemies incoming."
		opt.tint_color = Color(0.8, 0.4, 0.4, 1.0)
	else:
		opt.label = "Easy Wave"
		opt.description = "Civilians, no equipment."
		opt.tint_color = Color(0.4, 0.8, 0.4, 1.0)
	opt.title_scale = 1.0
	opt.desc_scale = 1.0
	opt.enemy_paths = []

## Converts a list of unit resource paths into a readable string like
## "4x Coward Human" or "2x Brave Human + 1x Knife Human".
func _describe_paths(paths: Array) -> String:
	var counts: Dictionary = {}
	for p in paths:
		counts[p] = counts.get(p, 0) + 1
	var parts: Array = []
	for p in counts:
		var name: String = "Unknown"
		var data: Resource = load(p)
		if data != null:
			var dn = data.get("display_name")
			if dn != null:
				name = str(dn)
		parts.append("%dx %s" % [counts[p], name])
	return ", ".join(parts)

func _on_wave_option_picked(option: WaveOptionData) -> void:
	if option == null:
		return
	# enemy_paths is pre-picked — no random sub-selection needed.
	var enemy_data: Array = []
	for path in option.enemy_paths:
		var r: Resource = load(path)
		if r != null:
			enemy_data.append(r)
	var gs: Node = _gs()
	if gs:
		gs.call("on_challenge_picked", enemy_data)

func _on_challenge_picked(wave: Array) -> void:
	var gs: Node = _gs()
	if gs:
		gs.call("on_challenge_picked", wave)

func _start_combat() -> void:
	_heal_pending = false
	BaseUnit._heal_sound_played = false
	if arena != null:
		var gs: Node = _gs()
		if gs:
			arena.spawn_wave(gs.pending_wave)

func _on_wave_cleared() -> void:
	# Only process if we're in COMBAT phase — prevents stale calls after phase changes.
	var gs: Node = _gs()
	if gs == null or gs.phase != gs.Phase.COMBAT:
		return
	if _heal_pending:
		return  # Guard: only process the first wave_cleared event per round.
	_heal_pending = true
	# Wait 2 seconds, heal, then signal.
	# Phase transition to ROUND_END happens via _on_phase_changed(5) when
	# game_state.on_combat_ended() eventually calls set_phase(ROUND_END).
	await get_tree().create_timer(2.0).timeout
	# Reset sound guard before healing so the first unit fires the sound.
	BaseUnit._heal_sound_played = false
	# Heal all surviving player units.
	if arena != null:
		for u in get_tree().get_nodes_in_group(&"player_units"):
			var bu: BaseUnit = u as BaseUnit
			if bu != null and is_instance_valid(bu):
				bu.round_end_heal()
	# Notify GameState to increment round counter and transition to ROUND_END.
	if gs:
		gs.call("on_combat_ended")  # increments rounds, emits signals; set_phase is NOT called here
		gs.call("set_phase", 5)     # ROUND_END → triggers _on_phase_changed(5)

func _on_player_unit_died(unit: BaseUnit, _grave_pos: Vector2) -> void:
	if unit != null and unit.unit_data != null:
		var gs: Node = _gs()
		if gs:
			gs.call("on_player_unit_died", unit.unit_data)

func _show_checkpoint() -> void:
	if popup_manager == null:
		return
	popup_manager.show_checkpoint(_on_checkpoint_picked)

func _on_checkpoint_picked(choice: Variant) -> void:
	var gs: Node = _gs()
	if choice == "shop":
		await get_tree().create_timer(0.4).timeout
		if gs:
			gs.call("set_phase", 0)  # EMPTY
	elif choice == "explore":
		_pick_random_encounter()
	elif choice == "rest":
		_rest_all_units()
		await get_tree().create_timer(0.6).timeout
		if gs:
			gs.call("set_phase", 0)  # EMPTY

func _rest_all_units() -> void:
	BaseUnit._heal_sound_played = false
	for u in get_tree().get_nodes_in_group(&"player_units"):
		var bu: BaseUnit = u
		if bu != null and is_instance_valid(bu):
			bu.rest_heal()

func _pick_random_encounter() -> void:
	var choices: Array[String] = ["dark_forest", "statue", "mancing"]
	var pick: String = choices[randi() % choices.size()]
	if popup_manager == null:
		return
	popup_manager.show_encounter(pick, _on_encounter_resolved)

func _on_encounter_resolved(encounter_id: String) -> void:
	match encounter_id:
		"dark_forest":
			_resolve_dark_forest()
		"statue":
			_resolve_statue()
		"mancing":
			_resolve_mancing()
	await get_tree().create_timer(1.2).timeout
	var gs: Node = _gs()
	if gs:
		gs.call("set_phase", 0)  # EMPTY

func _resolve_dark_forest() -> void:
	if arena != null and not _wolf_pool.is_empty():
		var gs: Node = _gs()
		var base_idx: int = int(gs.army_data.size()) if gs else 0
		for i in range(2):
			var wolf_data: Resource = _wolf_pool[0]
			var spawn_idx: int = base_idx + i
			var u: BaseUnit = arena.spawn_player_unit(wolf_data, spawn_idx)
			if u != null:
				u.add_to_group(&"dark_forest_wolves")
	if sword_reward != null and arena != null:
		var drop_pos: Vector2 = arena.size * Vector2(0.5, 0.5)
		arena.drop_weapon(sword_reward, drop_pos, "explore_reward", randi())

func _resolve_statue() -> void:
	var units: Array = get_tree().get_nodes_in_group(&"player_units")
	for u in units:
		var bu: BaseUnit = u
		if bu != null and is_instance_valid(bu):
			bu.sacrifice_current_hp()
	var alive: Array[BaseUnit] = []
	for u in units:
		var bu: BaseUnit = u
		if bu != null and is_instance_valid(bu) and bu.current_hp > 0:
			alive.append(bu)
	if alive.is_empty():
		return
	var chosen: BaseUnit = alive[randi() % alive.size()]
	chosen.eff_ability_id = AbilityIds.DRACULA

func _resolve_mancing() -> void:
	var alive: Array[BaseUnit] = []
	for u in get_tree().get_nodes_in_group(&"player_units"):
		var bu: BaseUnit = u
		if bu != null and is_instance_valid(bu) and bu.current_hp > 0:
			alive.append(bu)
	if alive.is_empty():
		return
	var victim: BaseUnit = alive[randi() % alive.size()]
	victim.take_damage(victim.current_hp, null)
	if _anomali_pool.is_empty():
		return
	var new_data: Resource = _anomali_pool[randi() % _anomali_pool.size()]
	if arena != null:
		var gs: Node = _gs()
		var spawn_idx: int = int(gs.army_data.size()) if gs else 0
		arena.spawn_player_unit(new_data, spawn_idx)
	var gs2: Node = _gs()
	if gs2:
		gs2.army_data.append(new_data)
		gs2.unit_count_changed.emit(int(gs2.army_data.size()))

func _show_game_over() -> void:
	if popup_manager != null:
		popup_manager.hide_panel()
	var label := Label.new()
	label.text = "GAME OVER"
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.add_theme_font_size_override("font_size", 96)
	label.add_theme_color_override("font_color", Color.RED)
	add_child(label)
