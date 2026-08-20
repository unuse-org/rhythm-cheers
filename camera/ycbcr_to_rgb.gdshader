shader_type canvas_item;

// macOSのCameraFeedが分離して返すY面とCbCr面を受け取る。
uniform sampler2D camera_y : filter_linear;
uniform sampler2D camera_cbcr : filter_linear;
uniform bool split_planes = true;


void fragment() {
	vec3 ycbcr;
	vec4 primary_sample = texture(camera_y, UV);

	if (split_planes) {
		ycbcr.r = primary_sample.r;
		ycbcr.gb = texture(camera_cbcr, UV).rg - vec2(0.5);
	} else {
		ycbcr = primary_sample.rgb - vec3(0.0, 0.5, 0.5);
	}

	// Webカメラで一般的なBT.709係数でYCbCrをsRGBへ変換する。
	vec3 rgb = mat3(
		vec3(1.00000, 1.00000, 1.00000),
		vec3(0.00000, -0.18732, 1.85560),
		vec3(1.57481, -0.46813, 0.00000)
	) * ycbcr;

	COLOR = vec4(rgb, 1.0);
}
