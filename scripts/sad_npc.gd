extends CharacterBody2D
## Sad NPC. Interactions:
## 1. Player drops gun on us -> we stand up as a Man (head, body, arms, legs),
##    mirror to face the player, hold the gun with our LEFT arm, and rotate
##    the left arm to point at the player.
## 2. Player drops bullet on us (while unarmed) -> we stay sitting, alive. The
##    player aims 3s, then we get shot and swap to SadPlayer_2.
## 3. Player drops bullet on us (while ARMED) -> NPC shoots back, we trigger
##    a player death and the Game Over scene with retry.

@onready var _sprite_container: Node2D = $Sprite
@onready var _anim: AnimationPlayer = $AnimationPlayer

# Default (sitting) sprite -- its texture swaps between SadPlayer.png (alive)
# and SadPlayer_2.png (shot).
@onready var _body_sitting: Sprite2D = $Sprite/BodySitting

# Man-state body parts -- these mirror the Player anatomy.
@onready var _head: Sprite2D = $Sprite/Head
@onready var _body: Sprite2D = $Sprite/Body
@onready var _left_arm: Sprite2D = $Sprite/LeftArm
@onready var _right_arm: Sprite2D = $Sprite/RightArm
@onready var _gun_overlay: Sprite2D = $Sprite/LeftArm/Gun
@onready var _left_leg: Sprite2D = $Sprite/LeftLeg
@onready var _right_leg: Sprite2D = $Sprite/RightLeg

const TEXTURE_SAD_PLAYER := preload("res://assets/SadPlayer.png")
const TEXTURE_SAD_PLAYER_2 := preload("res://assets/SadPlayer_2.png")

var _state: int = 0  # 0=sitting, 1=shot, 2=armed
var _player_ref: Node2D = null

func _ready() -> void:
	velocity = Vector2.ZERO
	_player_ref = get_parent().get_node_or_null("Player")
	_reset_to_sitting()

func _physics_process(_delta: float) -> void:
	move_and_slide()
	# While armed, keep the left arm and body rotated to face the player so
	# the gun tracks the player's horizontal position.
	if _state == 2 and _player_ref and is_instance_valid(_player_ref):
		_aim_at_player()

# ---------- Public API ----------

func receive_bullet() -> void:
	# Bullet dropped while NPC is still sitting (unarmed). Two-phase hit:
	#   1. receive_bullet() -- alive sprite, no immediate shock. The player
	#      aims for 3 s.
	#   2. apply_shot()      -- actually swap to SadPlayer_2 and wobble.
	if _state != 0:
		return
	_state = 1
	for t in get_tree().get_processed_tweens():
		t.kill()
	if _anim and _anim.is_playing():
		_anim.stop()
	for part in [_head, _body, _left_arm, _right_arm, _gun_overlay, _left_leg, _right_leg]:
		part.visible = false
	_sprite_container.scale = Vector2(1, 1)
	_sprite_container.rotation = 0.0
	_sprite_container.position = Vector2(-16, -82)
	_body_sitting.texture = TEXTURE_SAD_PLAYER
	_body_sitting.visible = true
	_body_sitting.modulate.a = 1.0

func apply_shot() -> void:
	# Called by the player after the 3 s aim. Sprite swaps to SadPlayer_2
	# and the NPC wobbles.
	if _state != 1:
		return
	_play_shake()
	_show_shot_state()
	_play_wounded_bounce()

func receive_gun() -> void:
	# Player gave us a gun. Stand up holding it.
	if _state != 0:
		return
	_state = 2
	for t in get_tree().get_processed_tweens():
		t.kill()
	_show_man_state()

func receive_bullet_armed() -> void:
	# Player dropped a bullet while we are holding the gun. We shoot back
	# and kill the player.
	if _state != 2:
		return
	_shoot_at_player()

# ---------- State helpers ----------

func _reset_to_sitting() -> void:
	if _anim and _anim.is_playing():
		_anim.stop()
	_body_sitting.texture = TEXTURE_SAD_PLAYER
	_body_sitting.visible = true
	_body_sitting.modulate.a = 1.0
	for part in [_head, _body, _left_arm, _right_arm, _gun_overlay, _left_leg, _right_leg]:
		part.visible = false
	_sprite_container.scale = Vector2(1, 1)
	_sprite_container.rotation = 0.0
	_sprite_container.position = Vector2(-16, -82)

func _show_shot_state() -> void:
	if _anim and _anim.is_playing():
		_anim.stop()
	for part in [_head, _body, _left_arm, _right_arm, _gun_overlay, _left_leg, _right_leg]:
		part.visible = false
	_body_sitting.visible = true
	_body_sitting.texture = TEXTURE_SAD_PLAYER_2
	_body_sitting.modulate.a = 1.0
	_sprite_container.scale = Vector2(1, 1)
	_sprite_container.rotation = 0.0
	_sprite_container.position = Vector2(-16, -82)

func _show_man_state() -> void:
	# Stand up as a Man holding a gun. Mirror so the body faces the player
	# (player is to the left of the NPC).
	_body_sitting.visible = false
	_head.visible = true
	_body.visible = true
	_left_leg.visible = true
	_right_leg.visible = true
	# Left arm holds the gun and aims at the player -- rotation is updated
	# each frame in _aim_at_player(). The gun sprite is parented to the
	# left arm so it inherits the aim rotation.
	_left_arm.visible = true
	_left_arm.scale = Vector2(0.35, 0.51)
	_right_arm.visible = true
	_right_arm.rotation = 1.57
	_gun_overlay.visible = true
	_gun_overlay.modulate.a = 1.0
	_sprite_container.position = Vector2(0, 0)
	_sprite_container.rotation = 0.0
	_sprite_container.scale = Vector2(-1, 1)  # mirror so face points at player

func _aim_at_player() -> void:
	# Rotate the left arm so the gun points at the player. The sprite
	# container is mirrored horizontally (scale.x = -1) so the "forward"
	# direction is towards the player (to the left in world space). We
	# compute the angle between the arm's forward axis and the player.
	var npc_world := global_position
	var player_world := _player_ref.global_position
	# Direction from NPC to player in world coordinates.
	var dir := player_world - npc_world
	# After mirroring (scale.x = -1), local +Y points toward world -X. So
	# the arm's "forward" in local space is +Y when rotation = 1.57 (pointing
	# down the arm). We compute the angle needed for the gun to point at
	# the player in local space and set the arm rotation.
	# In mirrored space, the gun direction in WORLD = mirrored(local +
	# rotated). We pick the rotation that best matches the desired world
	# direction. Use atan2 of the direction and the length of the arm.
	var desired_world_angle := atan2(dir.y, dir.x)
	# Without mirror, the arm's local +X is the "right side of body". With
	# mirror (scale.x = -1), local +X maps to world -X. The arm sprite is
	# drawn pointing toward local +Y when rotation = 1.57. After scale.x = -1,
	# local +Y maps to world +Y. We want the gun (drawn extending along
	# local +Y at rotation 1.57) to point in world angle `desired_world_angle`.
	# The rotation is the local rotation; with mirror, world angle =
	# -local_angle + reflection. We solve: arm.rotation = desired_world_angle +
	# PI/2 (since the gun extends in +Y at rotation PI/2) + mirror_offset.
	# Simpler approach: use the unmirrored sprite container for the arm
	# only by computing the desired arm rotation that points the gun at the
	# player, accounting for the mirror with +PI.
	var target_rotation := desired_world_angle + PI * 0.5
	# Because the sprite container is mirrored, a local rotation of R is
	# visually a world rotation of -R. So flip the sign.
	if _sprite_container.scale.x < 0:
		target_rotation = -target_rotation
	_right_arm.rotation = 1.57
	_left_arm.rotation = target_rotation

# ---------- Combat ----------

func _shoot_at_player() -> void:
	# Brief aim pose, then kill the player and open the Game Over scene.
	# Snap-aim to player so the recoil looks aimed.
	_left_arm.rotation = _compute_aim_angle()
	_gun_overlay.scale = _gun_overlay.scale * 1.3
	# Player is shot: tell the player to die.
	var player := _player_ref
	if player and player.has_method("die"):
		player.die()
	# The player's player_died signal is already wired to the Game Over
	# overlay through main.gd.

# ---------- Animation helpers ----------

func _play_shake() -> void:
	var tween := create_tween().set_loops(2)
	tween.tween_property(_sprite_container, "position:x", _sprite_container.position.x - 5, 0.05)
	tween.tween_property(_sprite_container, "position:x", _sprite_container.position.x + 5, 0.05)

func _play_wounded_bounce() -> void:
	var tween := create_tween()
	tween.tween_property(_sprite_container, "position:y", _sprite_container.position.y - 6, 0.12)
	tween.tween_property(_sprite_container, "position:y", _sprite_container.position.y, 0.18)

func _compute_aim_angle() -> float:
	if not _player_ref or not is_instance_valid(_player_ref):
		return 1.57
	var dir := _player_ref.global_position - global_position
	var world_angle := atan2(dir.y, dir.x)
	var target := world_angle + PI * 0.5
	if _sprite_container.scale.x < 0:
		target = -target
	return target
