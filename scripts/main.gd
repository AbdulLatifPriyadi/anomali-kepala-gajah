extends Node2D
## Coordinates UI signals with gameplay (player / SadNPC).

func _ready() -> void:
	var inv: Node = $UI/Inventory
	var player: Node = $Player
	var npc: Node = $SadNPC
	var gameover: Node = $UI/GameOver
	if not inv:
		return
	if inv.has_signal("gun_dropped_on_player"):
		inv.gun_dropped_on_player.connect(_on_gun_to_player)
	if inv.has_signal("gun_dropped_on_npc"):
		inv.gun_dropped_on_npc.connect(_on_gun_to_npc)
	if inv.has_signal("bullet_dropped_on_npc"):
		inv.bullet_dropped_on_npc.connect(_on_bullet_to_npc)
	if inv.has_signal("gun_returned_to_backpack"):
		inv.gun_returned_to_backpack.connect(_on_gun_returned_to_backpack)
	if inv.has_signal("item_returned_to_slot"):
		inv.item_returned_to_slot.connect(_on_item_returned_to_slot)
	if player and gameover and player.has_signal("player_died"):
		player.player_died.connect(_on_player_died)

func _on_player_died() -> void:
	var gameover := get_node_or_null("UI/GameOver")
	if gameover and gameover.has_method("show_overlay"):
		gameover.show_overlay()

func _on_gun_to_player() -> void:
	SoundManager.play_equip_gun()
	var player := get_node_or_null("Player")
	if player and player.has_method("equip_gun"):
		player.equip_gun()

func _on_gun_to_npc() -> void:
	SoundManager.play_gun_to_npc()
	var npc := get_node_or_null("SadNPC")
	if npc and npc.has_method("receive_gun"):
		npc.receive_gun()

func _on_bullet_to_npc() -> void:
	var player := get_node_or_null("Player")
	var npc := get_node_or_null("SadNPC")
	if not npc:
		return
	# If the NPC is already holding a gun, it shoots back at the player
	# (game over). Otherwise the bullet becomes a normal aim-and-fire
	# interaction handled by the player.
	if npc._state == 2 and npc.has_method("receive_bullet_armed"):
		SoundManager.play_shoot()
		SoundManager.play_hit()
		npc.receive_bullet_armed()
		return
	SoundManager.play_shoot()
	SoundManager.play_hit()
	if player and player.has_method("shoot_at") and npc:
		player.shoot_at(npc)

func _on_gun_returned_to_backpack() -> void:
	SoundManager.play_unequip()
	var player := get_node_or_null("Player")
	if player and player.has_method("unequip_gun"):
		player.unequip_gun()

func _on_item_returned_to_slot(_kind: String) -> void:
	# Triggered when a drag misses every target and the item tweens back.
	SoundManager.play_put_away()
