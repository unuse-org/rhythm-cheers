shader_type canvas_item;

void fragment() {
    vec4 c = texture(TEXTURE, UV);
    float gray = c.r * 0.299 + c.g * 0.587 + c.b * 0.114;
    COLOR = vec4(gray, gray, gray, c.a);
}
