extends Node2D
## One-shot particle burst played when a unit spawns into the arena.
## Configured for `one_shot = true` on the CPUParticles2D, so it fires
## all 40 particles at once, then this script frees the node after
## `lifetime` seconds so the burst doesn't linger in the scene tree.

@export var lifetime: float = 0.9

var _timer: float = 0.0

func _ready() -> void:
	# Replay the burst in case it was configured with emitting=false in
	# the editor (some setups leave it false so it starts on demand).
	if has_node("Particles"):
		var p: CPUParticles2D = $Particles
		if not p.emitting:
			p.emitting = true
		# Override the per-particle lifetime to ensure we have a consistent
		# total time before freeing this node.
		if lifetime > p.lifetime:
			lifetime = p.lifetime + 0.05

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= lifetime:
		queue_free()