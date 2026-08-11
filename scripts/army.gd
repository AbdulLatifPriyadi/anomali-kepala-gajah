extends CharacterBody2D
## An Army unit recruited from a Card option. Walks toward the Enemy and
## attacks on contact. Different options (speed / power) tune the stats.
##
## Anatomy mirrors the SadNPC stick figure: head + body + left/right
## arms + left/right legs, drawn as Sprite2D children.

## Tunable stats (set by Card option when spawned).
@export var army_type: String = "speed"  # "speed" or "power"
@export var max_hp: int = 2
@export var walk_speed: float = 60.0
@export var attack_damage: int = 1
@export var attack_range: float = 28.0
## How long to wait between attacks (seconds).
@export var attack_cooldown: float = 0.55
## Tint applied to the body parts. Lets each unit look slightly different.
@export var tint: Color = Color(0.4, 0.7, 1.0, 1.0)

## Reference to the Enemy (set by CardManager when spawning). May be null
## if the Enemy has been removed -- in that case the army just stands.
@export var enemy_path: NodePath

## Path to the Sprite container so we can tint all body parts at once.
@onready var _sprite_container: Node2D = $Sprite

@onready var _head: Sprite2D = $Sprite/Head
@onready var _body: Sprite2D = $Sprite/Body
@onready var _left_arm: Sprite2D = $Sprite/LeftArm
@onready var _right_arm: Sprite2D = $Sprite/RightArm
@onready var _left_leg: Sprite2D = $Sprite/LeftLeg
@onready var _right_leg: Sprite2D = $Sprite/RightLeg

var _hp: int = 0
var _attack_timer: float = 0.0
var _walk_phase: float = 0.0

func _ready() -> void:
	_hp = max_hp
	_apply_tint()
	# Stagger walk phase per army so a pack doesn't bob in unison.
	_walk_phase = randf_range(0.0, TAU)

func _physics_process(delta: float) -> void:
	if _attack_timer > 0.0:
		_attack_timer -= delta

	var enemy := get_node_or_null(enemy_path)
	if enemy and is_instance_valid(enemy):
		var to_enemy: Vector2 = enemy.global_position - global_position
		var dist: float = to_enemy.length()
		if dist <= attack_range:
			# In attack range: face the enemy and swing.
			_face_target(enemy.global_position)
			if _attack_timer <= 0.0:
				_attack(enemy)
				_attack_timer = attack_cooldown
			velocity = Vector2.ZERO
		else:
			# Walk toward the enemy.
			var dir: Vector2 = to_enemy.normalized()
			velocity = dir * walk_speed
			_face_target(global_position + dir)
			_animate_walk(delta)
	else:
		# No enemy: stand still.
		velocity = Vector2.ZERO
		_animate_walk(delta)

	move_and_slide()

func _face_target(target_world: Vector2) -> void:
	# The sprite's "forward" is local +Y after our Player anatomy; rotate
	# so local +Y points at the target.
	var diff: Vector2 = target_world - global_position
	if diff.length() < 0.1:
		return
	rotation = diff.angle() + PI * 0.5

func _animate_walk(delta: float) -> void:
	# Subtle step pulse: bob scale.
	_walk_phase += delta * 6.0
	var pulse: float = sin(_walk_phase) * 0.04
	_sprite_container.scale = Vector2(0.55 + pulse, 0.55 - pulse)

func _attack(enemy: Node) -> void:
	if not enemy.has_method("take_damage"):
		return
	# Quick visual punch: pull the body in toward the enemy briefly.
	var tween := create_tween()
	tween.tween_property(_sprite_container, "scale", _sprite_container.scale * 1.15, 0.08)
	tween.tween_property(_sprite_container, "scale", _sprite_container.scale * 0.9, 0.12)
	enemy.call("take_damage", attack_damage)
	# Optional: kill the enemy when its HP drops to zero (caller handles).

func take_damage(amount: int) -> void:
	_hp -= amount
	# Quick red flash on hit.
	modulate = Color(2.0, 0.5, 0.5, 1.0)
	var t := create_tween()
	t.tween_property(self, "modulate", Color.WHITE, 0.2)
	if _hp <= 0:
		_die()

func _die() -> void:
	# Quick collapse and remove.
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.4)
	t.tween_property(self, "scale", scale * Vector2(0.6, 0.6), 0.4)
	t.finished.connect(queue_free)

func _apply_tint() -> void:
	# Tint the body parts to differentiate units visually.
	for part: Node2D in [_head, _body, _left_arm, _right_arm, _left_leg, _right_leg]:
		if part:
			part.modulate = tint