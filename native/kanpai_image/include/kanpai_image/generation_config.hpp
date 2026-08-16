#pragma once

#include <functional>
#include <string>

namespace kanpai_image {

struct GenerationConfig {
    int output_width = 628;
    int output_height = 1116;
    int max_input_width = 1920;
    int max_input_height = 1080;
    int minimum_face_size = 60;
    double face_cut_scale = 1.0;
    double face_aspect_x = 0.72;
    double face_aspect_y = 0.95;
    int face_blur_size = 7;
    double panel_scale_multiplier = 0.90;
    double panel_lift_ratio = -0.063;
    double head_width_ratio = 0.36;
    std::string face_cascade_xml;
    std::function<bool()> cancellation_requested;
};

}  // namespace kanpai_image
