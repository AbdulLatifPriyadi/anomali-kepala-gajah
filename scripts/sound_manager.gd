extends Node
## Centralised sound effects for player / inventory / NPC interactions.
## Autoloaded as "SoundManager" (see project.godot).
## Audio files are preloaded directly from res://assets/ at startup.

@export_range(-60.0, 24.0, 0.1) var default_volume_db: float = -6.0
@export_range(0.0, 0.5, 0.01) var pitch_jitter: float = 0.05

var _players: Dictionary = {}

func _ready() -> void:
	var slots = [
		["equip_gun",   _audio("res://assets/equip.wav", _tone_click(true))],
		["gun_to_npc", _audio("res://assets/npc_threat.wav", _tone_growl())],
		["shoot",      _audio("res://assets/shoot.wav", _tone_shoot())],
		["hit",        _audio("res://assets/hit.wav", _tone_hit())],
		["put_away",   _audio("res://assets/put_away.wav", _tone_thunk())],
		["unequip",    _audio("res://assets/unequip.wav", _tone_thunk())],
		["walk_step",  _audio("res://assets/walk_step.wav", _tone_step(false))],
		["run_step",   _audio("res://assets/run_step.wav", _tone_step(true))],
		["damage",     _audio("res://assets/damage.wav", _tone_hit())],
		["knife",      _audio("res://assets/knife.wav", _tone_knife())],
		["ally_die",   _audio("res://assets/unitallydie.wav", _tone_thunk())],
		["enemy_die",  _audio("res://assets/unitenemydie.wav", _tone_thunk())],
		["heal",       _audio("res://assets/heal.wav", _tone_heal())],
	]
	for entry in slots:
		var key = entry[0]
		var stream = entry[1]
		var p = AudioStreamPlayer.new()
		p.name = "Player_" + str(key)
		p.stream = stream
		p.volume_db = default_volume_db
		p.bus = "Master"
		add_child(p)
		_players[key] = p

func _audio(path: String, fallback) -> AudioStream:
	if FileAccess.file_exists(path):
		return load(path)
	return fallback

func play_equip_gun() -> void:   _s("equip_gun")
func play_gun_to_npc() -> void:  _s("gun_to_npc")
func play_shoot() -> void:        _s("shoot")
func play_hit() -> void:          _s("hit")
func play_put_away() -> void:     _s("put_away")
func play_unequip() -> void:      _s("unequip")
func play_walk_step() -> void:   _s("walk_step")
func play_run_step() -> void:     _s("run_step")
func play_damage() -> void:       _s("damage")
func play_knife() -> void:        _s("knife")
func play_ally_die() -> void:     _s("ally_die")
func play_enemy_die() -> void:    _s("enemy_die")
func play_heal() -> void:        _s("heal")

func _s(key: String) -> void:
	if not _players.has(key):
		return
	var p: AudioStreamPlayer = _players[key]
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()

const SR = 22050

func _tone_thunk() -> AudioStream:
	var n = int(0.15 * SR)
	var out = _make(n, 22.0, 0.5, [180.0], 0.0)
	return _wav(out)

func _tone_click(rising: bool) -> AudioStream:
	var freq = 880.0 if rising else 440.0
	var n = int(0.12 * SR)
	var out = _make(n, 28.0, 0.6, [freq], 0.0)
	return _wav(out)

func _tone_growl() -> AudioStream:
	var n = int(0.4 * SR)
	var out = _make(n, 0.0, 0.7, [90.0, 137.0], 0.15)
	return _wav(out)

func _tone_shoot() -> AudioStream:
	var n = int(0.18 * SR)
	var out = _make(n, 22.0, 0.8, [120.0], 0.7)
	return _wav(out)

func _tone_hit() -> AudioStream:
	var n = int(0.25 * SR)
	var out = _make(n, 16.0, 0.7, [220.0, 330.0], 0.0)
	return _wav(out)

func _tone_step(running: bool) -> AudioStream:
	var freq = 110.0 if running else 85.0
	var n = int(0.08 * SR)
	var out = _make(n, 45.0, 0.5, [freq], 0.2)
	return _wav(out)

func _tone_knife() -> AudioStream:
	var n = int(0.2 * SR)
	var out = _make(n, 18.0, 0.8, [800.0], 0.5)
	return _wav(out)

func _tone_heal() -> AudioStream:
	# Rising chime: ascending arpeggio for healing feedback.
	var n = int(0.4 * SR)
	var out = _make(n, 10.0, 0.6, [523.0, 659.0, 784.0], 0.0)
	return _wav(out)

func _make(n: int, decay: float, gain: float, freqs: Array, noise: float) -> PackedFloat32Array:
	var out = PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t = float(i) / SR
		var env: float
		if decay > 0.0:
			env = exp(-t * decay)
		else:
			env = 1.0 - t / 0.4
		var s = 0.0
		for f in freqs:
			s += sin(TAU * float(f) * t) * 0.5
		s += randf_range(-1.0, 1.0) * float(noise)
		out[i] = s * env * gain
	return out

func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data = PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var v = int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SR
	wav.stereo = false
	wav.data = data
	return wav
