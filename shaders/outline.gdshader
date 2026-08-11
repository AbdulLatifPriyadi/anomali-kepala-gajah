shader_type canvas_item;

// Outline color. Default white so the sprite's modulate property acts as
// the final color tint (lets us animate the outline red at runtime via
// Sprite2D.modulate).
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Outline width in texture pixels (texels). Each pixel is checked at this
// many sample steps outward in 8 directions to detect nearby silhouette.
uniform float outline_width : hint_range(0.0, 30.0) = 14.0;

// Number of angular directions to sample (8 = 8-way).
const int DIRECTIONS = 8;

// Tau constant for circle sampling.
const float TAU = 6.28318530718;

void fragment() {
    vec2 size = vec2(textureSize(TEXTURE, 0));
    float current_alpha = texture(TEXTURE, UV).a;

    // Inside the sprite: discard so the body shows through cleanly.
    if (current_alpha > 0.5) {
        discard;
    }

    // For pixels outside the silhouette, walk outward in 8 directions.
    // If we hit an opaque pixel at any step within outline_width, this pixel
    // is on the outline ring. We use a fixed-step raymarch with a tight
    // step size (1 texel) so we don't overshoot the silhouette.
    vec2 pixel_size = 1.0 / size;
    int max_steps = int(outline_width);

    bool found_outline = false;
    for (int dir = 0; dir < DIRECTIONS; dir++) {
        float angle = float(dir) * TAU / float(DIRECTIONS);
        vec2 step_dir = vec2(cos(angle), sin(angle));
        for (int step = 1; step <= max_steps; step++) {
            vec2 sample_pos = UV + step_dir * pixel_size * float(step);
            if (texture(TEXTURE, sample_pos).a > 0.5) {
                found_outline = true;
                break;
            }
        }
        if (found_outline) {
            break;
        }
    }

    if (found_outline) {
        COLOR = outline_color;
    } else {
        discard;
    }
}