shader_type canvas_item;

uniform float source_aspect = 1.7777778;
uniform float target_aspect = 1.0;
uniform float key_start = 0.12;
uniform float key_end = 0.38;


void fragment() {
	// 動画を引き伸ばさず、表示領域の縦横比に合わせて中央を切り抜く。
	vec2 sample_uv = UV;

	if (target_aspect < source_aspect) {
		float visible_width = target_aspect / source_aspect;
		sample_uv.x = (sample_uv.x - 0.5) * visible_width + 0.5;
	} else {
		float visible_height = source_aspect / target_aspect;
		sample_uv.y = (sample_uv.y - 0.5) * visible_height + 0.5;
	}

	vec4 video_color = texture(TEXTURE, sample_uv);
	float green_dominance = (
		video_color.g - max(video_color.r, video_color.b)
	);
	float alpha = 1.0 - smoothstep(key_start, key_end, green_dominance);

	// 半透明の輪郭に緑色が残りにくいよう、キー部分の緑を抑える。
	float neutral_green = max(video_color.r, video_color.b);
	video_color.g = mix(neutral_green, video_color.g, alpha);
	COLOR = vec4(video_color.rgb, alpha);
}
