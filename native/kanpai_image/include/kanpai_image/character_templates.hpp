#pragma once

#include <array>

#include "kanpai_image/character_state.hpp"
#include "kanpai_image/image_buffer.hpp"

namespace kanpai_image {

struct CharacterTemplate {
    ImageBuffer body;
    double head_angle_degrees = 0.0;
    double head_offset_x_ratio = 0.0;
    // 頭部画像の下端を合わせる首元位置。上端基準だと拡縮時に隙間が生じる。
    double head_anchor_y_ratio = 0.465;
};

using CharacterTemplateSet =
    std::array<CharacterTemplate, kCharacterStateCount>;

// 顔を基準に個別配置する装飾素材。状態別の合成画像を持たないことで、
// 表情素材の有無によって髪やひげの大きさ・位置が変わることを防ぐ。
struct CharacterDecorations {
    ImageBuffer hair;
    ImageBuffer mustache;
    ImageBuffer cheeks;
    ImageBuffer failure_mark;
};

}  // namespace kanpai_image
