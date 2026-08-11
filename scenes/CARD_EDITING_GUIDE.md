# Card Editing Guide

This guide shows how to edit the prize/challenge/checkpoint/encounter
popups by adjusting the scenes. All three popup types use the same
underlying structure.

## Files involved

- `res://scenes/popup_panel.tscn` — the outer panel (title + container)
- `res://scenes/popup_entry.tscn` — one card per option (template + text)
- `res://scripts/popup_manager.gd` — builds and shows the panel
- `res://scripts/popup_entry.gd` — fills each card's text/colors

## Edit the card itself (`popup_entry.tscn`)

Open the scene in the Godot editor. The Scene tree on the left will
look like:

```
PopupEntry (Button)            <- the whole card, 572x162 pixels
├── CardBg (TextureRect)        <- background image, z_index = -1
├── Swatch (ColorRect)          <- small color square on the left
├── Title (Label)               <- big heading text
└── Desc (Label)                <- smaller description text
```

All four children are direct children of `PopupEntry`, so you can
click any one in the Scene tree and drag it freely in the 2D viewport.

### To change the card image

1. Click `CardBg` in the Scene tree.
2. In the Inspector, find **Texture** and pick a different `.png`.
3. The image will stretch to fill the card automatically.

### To change the swatch color

1. Click `Swatch` in the Scene tree.
2. In the Inspector, find **Color** and change it. (Or leave it — the
   popup manager will overwrite it with the unit's faction color at
   runtime via `apply_meta()`.)

### To move the title text

1. Click `Title` in the Scene tree.
2. Drag it freely in the 2D viewport. Or change **offset_left**,
   **offset_top**, **offset_right**, **offset_bottom** in the Inspector
   for precise positioning.
3. Edit **text** to change the displayed text.
4. Adjust **theme_override_font_sizes/font_size** to make it bigger
   or smaller.

### To move the description text

1. Click `Desc` in the Scene tree.
2. Same tips as Title. Just smaller default font size (16).

### Font

All text uses **Comic Sans MS** via the theme override
`fonts/comic-sans-ms.ttf`. To change the font:

1. Open the file in the Godot editor.
2. Find the **Theme Overrides > Font** property on the Label.
3. Pick a different FontFile resource, or load a new one in the
   Inspector.

## Edit the panel itself (`popup_panel.tscn`)

```
PopupPanel (Control)            <- the whole panel, 800x700 pixels
├── Bg (Panel)                  <- dim backdrop
├── Title (Label)               <- the "Pick a unit to recruit" header
└── EntriesContainer            <- VBoxContainer that stacks the cards
	├── PopupEntry (Button)     <- one card
	└── ...                     <- more cards
```

### Move the panel title

1. Click `Title` in the Scene tree.
2. Drag it. Edit **text** in the Inspector.

### Change card spacing

1. Click `EntriesContainer`.
2. In the Inspector, find **Theme Overrides > Constants > Separation**.
3. Adjust the number — bigger = more space between cards.

## Edit runtime behavior (`popup_manager.gd`)

Most users won't need to touch this, but if you want to change the
default size, animation speed, or behavior:

- `SLIDE_DURATION` — how long the slide-in/out animation takes.
- `popup_panel_scene` — which scene to use as the panel template.
- `show_prize`, `show_challenge`, `show_checkpoint`, `show_encounter`
  — the four popup types and their text/colors.

## Adding a new card type

1. In `popup_manager.gd`, find the relevant `show_*` method.
2. Build the entries array with the new title/desc/tint/data.
3. The `data` key is what gets passed to the picked callback — make
   sure the consumer (e.g. `mobile_scene.gd::_on_prize_picked`) knows
   what to do with it.
