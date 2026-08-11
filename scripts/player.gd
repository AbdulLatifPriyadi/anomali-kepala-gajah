extends CharacterBody2D
## Player character with state machine: IDLE / WALK / RUN / EQUIP / RUN_EQUIP / SHOOT / DEAD.

signal player_died

enum State { IDLE, WALK, RUN, EQUIP, RUN_EQUIP, SHOOT, DEAD }

@export var walk_speed: float = 80.0
@export var run_speed: float = 120.0
@export var arrive_threshold: float = 4.0
@export var double_tap_window: float = 0.30
@export var walk_step_interval: float = 0.32
@export var run_step_interval: float = 0.22

@onready var _anim: AnimationPlayer = $AnimationPlayer
@onready var _gun_overlay: Sprite2D = $Sprite/RightArm/Gun
@onready var _right_arm: Sprite2D = $Sprite/RightArm
@onready var _sprite_container: Node2D = $Sprite
@onready var _step_timer: Timer = $StepTimer

var _state: State = State.IDLE
var _target_x: float = 0.0
var _has_target: bool = false
var _last_tap_time: float = -1.0
## Set when the inventory puts us in a "Run with gun" choice -- used to keep
## run_equip when equip_gun is called mid-run.
var _keep_run_with_gun: bool = false

func _ready() -> void:
	_target_x = global_position.x
	if _anim:
		_anim.process_mode = Node.PROCESS_MODE_INHERIT
	_play_idle()
	if _step_timer:
		_step_timer.timeout.connect(_on_step_timer)
		_step_timer.one_shot = false

func _physics_process(_delta: float) -> void:
	if _state == State.DEAD:
		velocity.x = 0.0
		move_and_slide()
		return
	if _has_target:
		var current := global_position.x
		var diff := _target_x - current
		if absf(diff) <= arrive_threshold:
			velocity.x = 0.0
			_has_target = false
			_on_arrived()
		else:
			velocity.x = signf(diff) * _current_speed()
	else:
		velocity.x = 0.0
	move_and_slide()

func _current_speed() -> float:
	if _state == State.RUN or _state == State.RUN_EQUIP:
		return run_speed
	return walk_speed

func _on_arrived() -> void:
	match _state:
		State.WALK, State.RUN:
			_play_idle()
		State.EQUIP, State.RUN_EQUIP, State.SHOOT:
			_keep_run_with_gun = (_state == State.RUN_EQUIP)
			_play_equip_idle()
		_:
			_play_idle()

func _unhandled_input(event: InputEvent) -> void:
	if _state == State.DEAD:
		return
	# Block all movement input while aiming/shooting at the NPC. The aim
	# phase freezes the player in place; only the recoil sequence can run.
	if _state == State.SHOOT:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_handle_tap(event.position)
	elif event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_handle_tap(event.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		var step := 120.0
		match event.keycode:
			KEY_LEFT, KEY_A:
				_handle_tap_key(-step)
			KEY_RIGHT, KEY_D:
				_handle_tap_key(step)

func _handle_tap_key(step: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_tap_time <= double_tap_window:
		_set_target(global_position.x + step, true)
		_last_tap_time = -1.0
	else:
		_set_target(global_position.x + step, false)
		_last_tap_time = now

func _handle_tap(screen_pos: Vector2) -> void:
	var world := _screen_to_world(screen_pos)
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_tap_time <= double_tap_window:
		_set_target(world.x, true)
		_last_tap_time = -1.0
	else:
		_set_target(world.x, false)
		_last_tap_time = now

func _set_target(x: float, force_run: bool) -> void:
	_target_x = x
	_has_target = true
	# Equipped states: pick walk_equip or run_equip based on tap cadence.
	if _state == State.EQUIP or _state == State.RUN_EQUIP or _state == State.SHOOT:
		if force_run:
			_state = State.RUN_EQUIP
			_play_run_equip()
			_keep_run_with_gun = true
		else:
			_state = State.EQUIP
			_play_walk_equip()
			_keep_run_with_gun = false
		return
	# Non-equipped states.
	if force_run or (_state == State.RUN):
		_state = State.RUN
		_play_walk_run()
		_keep_run_with_gun = false
	else:
		_state = State.WALK
		_play_walk_relaxed()
		_keep_run_with_gun = false

func _screen_to_world(screen_pos: Vector2) -> Vector2:
	var cam := get_viewport().get_camera_2d()
	if cam:
		return get_viewport().get_canvas_transform().affine_inverse() * screen_pos
	return screen_pos

# ---------- Animation helpers ----------

func _enable_anim() -> void:
	# Re-enable the AnimationPlayer so it can drive properties again.
	if _anim:
		_anim.process_mode = Node.PROCESS_MODE_INHERIT

func _play_idle() -> void:
	_enable_anim()
	if _state == State.EQUIP or _state == State.RUN_EQUIP:
		_play_equip_idle()
		return
	_state = State.IDLE
	if _anim:
		_anim.play("idle")
	_sprite_container.rotation = 0.0
	_gun_overlay.visible = false
	_stop_step_loop()

func _play_walk_relaxed() -> void:
	_enable_anim()
	_state = State.WALK
	if _anim:
		_anim.play("walk_relaxed")
	_gun_overlay.visible = false
	SoundManager.play_walk_step()
	_start_step_loop(walk_step_interval)

func _play_walk_run() -> void:
	_enable_anim()
	_state = State.RUN
	if _anim:
		_anim.play("walk")
	_gun_overlay.visible = false
	SoundManager.play_run_step()
	_start_step_loop(run_step_interval)

func _play_equip_idle() -> void:
	_enable_anim()
	_state = State.RUN_EQUIP if _keep_run_with_gun else State.EQUIP
	if _anim:
		_anim.play("equip_idle")
	_gun_overlay.visible = true
	_stop_step_loop()

func _play_walk_equip() -> void:
	_enable_anim()
	_state = State.EQUIP
	if _anim:
		_anim.play("walk_equip")
	_gun_overlay.visible = true
	SoundManager.play_walk_step()
	_start_step_loop(walk_step_interval)

func _play_run_equip() -> void:
	_enable_anim()
	_state = State.RUN_EQUIP
	if _anim:
		_anim.play("run_equip")
	_gun_overlay.visible = true
	SoundManager.play_run_step()
	_start_step_loop(run_step_interval)

func _play_shoot() -> void:
	_enable_anim()
	_state = State.SHOOT
	if _anim:
		_anim.play("shoot")
	_stop_step_loop()

func _play_aim() -> void:
	# Aim pose: snap right arm to rotation 0 (horizontal). The animation
	# is stopped so the snap value persists for the aim phase. After the
	# bullet lands the recoil tween animates the arm back to 1.57.
	_state = State.SHOOT
	if _anim:
		_anim.stop()
	_stop_step_loop()
	_has_target = false
	velocity.x = 0.0
	_sprite_container.rotation = 0.0
	# Snap to aim pose: horizontal, gun pointing forward.
	_right_arm.rotation = 0.0

func _play_shoot_recoil() -> void:
	# Recoil after the bullet lands: snap the arm up briefly, then ease back
	# to the walk_equip pose (1.57) and gun base scale.
	if _anim:
		_anim.stop()
	_right_arm.rotation = -0.9
	var gun_base := _gun_overlay.scale
	_gun_overlay.scale = gun_base * 1.25
	var return_tween := create_tween().set_parallel(true)
	return_tween.tween_property(_right_arm, "rotation", 1.57, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return_tween.tween_property(_gun_overlay, "scale", gun_base, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return_tween.tween_property(_sprite_container, "scale", Vector2(1, 1), 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _play_die() -> void:
	_enable_anim()
	_state = State.DEAD
	if _anim:
		_anim.play("die")
	_has_target = false
	velocity.x = 0.0
	_gun_overlay.visible = false
	_stop_step_loop()
	player_died.emit()

# ---------- Footstep helpers ----------

func _start_step_loop(interval: float) -> void:
	if not _step_timer:
		return
	if _step_timer.wait_time != interval:
		_step_timer.wait_time = interval
	if not _step_timer.is_stopped():
		return
	_step_timer.start()

func _stop_step_loop() -> void:
	if _step_timer and not _step_timer.is_stopped():
		_step_timer.stop()

func _on_step_timer() -> void:
	if _state == State.WALK or _state == State.EQUIP:
		SoundManager.play_walk_step()
	elif _state == State.RUN or _state == State.RUN_EQUIP:
		SoundManager.play_run_step()

# ---------- Public API for inventory / NPC interactions ----------

func equip_gun() -> void:
	if _state == State.DEAD:
		return
	if _has_target:
		if _keep_run_with_gun:
			_state = State.RUN_EQUIP
			_play_run_equip()
		else:
			_state = State.EQUIP
			_play_walk_equip()
	else:
		_state = State.EQUIP
		_play_equip_idle()

func unequip_gun() -> void:
	if _state == State.DEAD:
		return
	if not (_state == State.EQUIP or _state == State.RUN_EQUIP or _state == State.SHOOT):
		return
	_state = State.IDLE
	if _anim:
		_anim.play("idle")
	_sprite_container.rotation = 0.0
	_gun_overlay.visible = false
	_has_target = false
	velocity.x = 0.0

func shoot_at(npc: Node) -> void:
	# Bullet-drop interaction:
	#   1. Player aims the gun (arm tweened to horizontal, body still) for 3 s.
	#   2. NPC reacts: shake + sprite swap to SadPlayer_2 + wounded bounce.
	#   3. Brief player recoil, then return to equip idle.
	if _state == State.DEAD:
		return
	if _state != State.EQUIP and _state != State.RUN_EQUIP:
		return
	_play_aim()
	# Kick off NPC anticipation reaction immediately (alive sprite still showing).
	# The NPC swaps to SadPlayer_2 only when apply_shot() is called at the end.
	if npc and npc.has_method("receive_bullet"):
		npc.receive_bullet()
	await get_tree().create_timer(3.0).timeout
	# Finalize the bullet hit: NPC swaps to SadPlayer_2 sprite.
	if npc and npc.has_method("apply_shot"):
		npc.apply_shot()
	_play_shoot_recoil()
	await get_tree().create_timer(0.4).timeout
	if _state == State.SHOOT:
		_play_equip_idle()

func die() -> void:
	_play_die()
