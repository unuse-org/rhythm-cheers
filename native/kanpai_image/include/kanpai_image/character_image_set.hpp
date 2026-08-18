#pragma once

#include <array>
#include <string>
#include <utility>

#include "kanpai_image/character_state.hpp"
#include "kanpai_image/image_buffer.hpp"

namespace kanpai_image {

struct CharacterImageSet {
    std::array<ImageBuffer, kCharacterStateCount> images;

    [[nodiscard]] const ImageBuffer& at(CharacterState state) const {
        return images.at(static_cast<std::size_t>(state));
    }

    [[nodiscard]] ImageBuffer& at(CharacterState state) {
        return images.at(static_cast<std::size_t>(state));
    }
};

enum class GenerationError {
    None = 0,
    EmptyInput,
    UnsupportedPixelFormat,
    MissingFaceModel,
    InvalidFaceModel,
    FaceNotFound,
    MissingTemplate,
    InvalidTemplate,
    Cancelled,
    ProcessingFailed,
};

struct GenerationResult {
    bool succeeded = false;
    GenerationError error = GenerationError::ProcessingFailed;
    std::string message;
    CharacterImageSet images;

    static GenerationResult success(CharacterImageSet image_set) {
        GenerationResult result;
        result.succeeded = true;
        result.error = GenerationError::None;
        result.images = std::move(image_set);
        return result;
    }

    static GenerationResult failure(
        GenerationError error_code,
        std::string error_message
    ) {
        GenerationResult result;
        result.error = error_code;
        result.message = std::move(error_message);
        return result;
    }
};

}  // namespace kanpai_image
