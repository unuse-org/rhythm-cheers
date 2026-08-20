#pragma once

#include <functional>
#include <cstdint>
#include <vector>

namespace kanpai_image {

struct GenerationConfig {
    int output_width = 628;
    int output_height = 1116;
    int max_input_width = 1920;
    int max_input_height = 1080;
    int minimum_face_size = 60;
    int face_blur_size = 7;
    float face_score_threshold = 0.85F;
    float face_nms_threshold = 0.3F;
    // 各装飾は検出顔の幅・高さを1.0とする座標で独立配置する。
    double hair_width_ratio = 0.90;
    double hair_top_ratio = -0.08;
    // YuNetの左右口角間距離からひげ幅を決め、中心を人中側へ少し上げる。
    double mustache_mouth_width_multiplier = 1.65;
    double mustache_vertical_offset_ratio = -0.02;
    double mustache_max_rotation_degrees = 20.0;
    double cheeks_width_ratio = 0.63;
    double cheeks_top_ratio = 0.60;
    double failure_mark_width_ratio = 0.23;
    double failure_mark_left_ratio = 0.68;
    double failure_mark_top_ratio = 0.15;
    double head_width_ratio = 0.36;
    std::vector<std::uint8_t> face_detector_model;
    std::function<bool()> cancellation_requested;
};

}  // namespace kanpai_image
