#pragma once

#include <cstdint>
#include <vector>

namespace kanpai_image {

enum class PixelFormat {
    Rgb8,
    Rgba8,
};

struct ImageBuffer {
    int width = 0;
    int height = 0;
    int stride = 0;
    PixelFormat format = PixelFormat::Rgba8;
    std::vector<std::uint8_t> pixels;

    [[nodiscard]] int channel_count() const {
        return format == PixelFormat::Rgba8 ? 4 : 3;
    }

    [[nodiscard]] bool is_valid() const {
        if (width <= 0 || height <= 0 || stride < width * channel_count()) {
            return false;
        }

        return pixels.size() >= static_cast<std::size_t>(stride * height);
    }
};

}  // namespace kanpai_image
