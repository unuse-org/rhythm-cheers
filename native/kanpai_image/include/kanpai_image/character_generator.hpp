#pragma once

#include "kanpai_image/character_image_set.hpp"
#include "kanpai_image/character_templates.hpp"
#include "kanpai_image/generation_config.hpp"
#include "kanpai_image/image_buffer.hpp"

namespace kanpai_image {

GenerationResult generate_character_images(
    const ImageBuffer& captured_face,
    const CharacterTemplateSet& templates,
    const CharacterDecorations& decorations,
    const GenerationConfig& config
);

namespace detail {

// 単体テストから、画面外クリップと半透明合成を直接検証するために公開する。
ImageBuffer alpha_over(
    const ImageBuffer& base,
    const ImageBuffer& overlay,
    int position_x,
    int position_y
);

// 顔検出とは分けて、状態別の装飾レイヤー構成を単体テストする。
ImageBuffer compose_head(
    const ImageBuffer& face,
    const CharacterDecorations& decorations,
    CharacterState state,
    const GenerationConfig& config
);

}  // namespace detail

}  // namespace kanpai_image
