extends Resource
class_name WaveOptionData
## Holds one challenge wave option (label + enemy list).
## Can optionally hold sub-options: if non-empty, picking this tier
## will randomly resolve to one of the sub-options.

var id: String = ""
var label: String = ""
var description: String = ""
var tint_color: Color = Color(0.5, 0.5, 0.5, 1.0)
## Texture2D swatch shown on the popup entry. If null, tint_color is used.
var swatch_texture: Texture2D = null
## Scale multiplier for the title Label on the popup entry.
var title_scale: float = 1.0
## Scale multiplier for the description Label on the popup entry.
var desc_scale: float = 1.0
## Array of UnitData resource paths for this wave (used if sub_options is empty).
var enemy_paths: Array = []
## Array of Arrays: each sub-entry is an array of UnitData paths.
## When non-empty, picking this option randomly picks one sub-entry.
var sub_options: Array = []
