@tool
class_name WeaponData
extends Resource

## Data resource for a weapon. Weapons are equippable by any unit (player
## or enemy) — modifiers apply on top of the unit's base stats.
##
## A weapon can be either a stat-boost (e.g. Sword, Knife) or a debuff
## (e.g. Cursed Sword). Both use the same resource type — only the
## modifiers are negative. Equipment is determined at spawn time, but
## a unit can replace its weapon with a different one.

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""

## Stat modifiers applied while this weapon is equipped.
## Positive numbers = boost, negative = debuff. Cursed Sword is the
## canonical debuff example (attack_bonus +1, hp_bonus -5).
@export var attack_bonus: int = 0
@export var hp_bonus: int = 0

## Overrides for the unit's base stats. 0 = use unit's value.
@export var knockback_override: float = 0.0
@export var speed_override: float = 0.0

## Optional ability override (Ability enum id). 0 = use unit's ability.
## Used by Stone Crown to disable a unit's ability entirely.
@export var ability_override: int = -1  # -1 = no override

## Special flags (StringName). Known flags:
##   &"debuff"      — Marks this as a debuff weapon for Genius AI logic.
##   &"advantage"   — Marks this as a stat-boost weapon for Genius AI.
##   &"ability_disabler" — Wearer loses their ability (e.g. Stone Crown).
##   &"confusion"   — Wearer moves randomly (e.g. Ring of Confusion).
@export var flags: Array[StringName] = []

## Visual color of the weapon pickup in the arena.
@export var tint: Color = Color(0.85, 0.85, 0.9, 1.0)

## Optional sprite texture path (res:// path). When set, the weapon pickup
## and equipped weapon display show this sprite instead of a colored rect.
## Empty string = use tint color (backwards-compatible fallback).
@export var sprite_path: String = ""

## Visual scale multiplier for the sprite when equipped on a unit or
## dropped as a pickup. 1.0 = native size, 0.5 = half size, 2.0 = double.
## The final on-screen size is sprite_scale * unit_scale, where unit_scale
## is the faction's body sprite scale (0.88 player, 1.32 enemy).
@export var sprite_scale: float = 1.0

## Whether this weapon is classified as debuff (negative impact regardless of wearer).
## Convenience getter — same as checking `&"debuff" in flags`.
func is_debuff() -> bool:
	return flags.has(&"debuff")

func is_advantage() -> bool:
	return flags.has(&"advantage")