@tool
class_name UnitData
extends Resource

## Data resource for a single unit/enemy type.
## Holds all the tunables that used to be hardcoded on Army/Enemy nodes.
## Adding a new unit = create a new .tres file with a UnitData class,
## no scene/script edits required.

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""

## Combat stats
@export var max_hp: int = 10
@export var attack: int = 1

## Movement. speed = pixels per second. speedwalk is the slower wander speed
## for units that move on a fixed cadence vs chase (lower = more passive).
@export var speed: float = 60.0
@export var speedwalk: float = 35.0

## Knockback applied on every attack hit (units push each other apart).
@export var knockback_force: float = 5.0

## Attack cadence. Each unit attacks once per attack_cooldown seconds while
## in collision with an enemy.
@export var attack_cooldown: float = 0.6

## Collision range — units within this distance engage combat.
@export var attack_range: float = 28.0

## Abilities (see Ability enum in Ability.gd). NONE = no special behavior.
@export var ability_id: int = 0

## Optional starting weapon (WeaponData .tres). May be null.
@export var starting_weapon: Resource = null

## Tags (array of StringName). Used for special behaviors like Genius.
## Known tags: &"genius", &"enemy_default", &"player_drop_origin", etc.
@export var tags: Array[StringName] = []

## Faction. PLAYER or ENEMY. Determines which side this unit is on
## in combat collision logic.
@export var faction: int = 0  # 0 = PLAYER, 1 = ENEMY

## Visual tint applied to the sprite body parts.
@export var tint: Color = Color(0.4, 0.7, 1.0, 1.0)

## Offset (relative to the unit's origin / feet) where the equipped
## weapon sprite centers. Default Vector2(0, 0) places the weapon at the
## unit's origin (feet). Edit per-unit in the .tres file to tune weapon
## placement (e.g. hand-held vs shoulder-mounted). Y is negative because
## the unit's origin is at the feet and the body extends upward.
@export var weapon_anchor_offset: Vector2 = Vector2(0, 0)
