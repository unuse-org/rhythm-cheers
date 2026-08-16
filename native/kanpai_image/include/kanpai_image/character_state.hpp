#pragma once

#include <array>
#include <cstddef>

namespace kanpai_image {

enum class CharacterState : std::size_t {
    Normal = 0,
    Prepare,
    Judging,
    Success,
    Failure,
    Count,
};

constexpr std::size_t kCharacterStateCount =
    static_cast<std::size_t>(CharacterState::Count);

constexpr std::array<const char*, kCharacterStateCount> kCharacterStateNames = {
    "normal",
    "prepare",
    "judging",
    "success",
    "failure",
};

}  // namespace kanpai_image
