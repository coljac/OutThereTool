shader_type canvas_item;

uniform float z_min = 0.0;
uniform float z_max = 1.0;

void fragment() {
    vec4 color = texture(TEXTURE, UV);

    // Apply zscale to each channel
    color.r = clamp((color.r - z_min) / (z_max - z_min), 0.0, 1.0);
    color.g = clamp((color.g - z_min) / (z_max - z_min), 0.0, 1.0);
    color.b = clamp((color.b - z_min) / (z_max - z_min), 0.0, 1.0);

    COLOR = color;
}