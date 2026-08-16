#include <cmath>
#include <cstdint>
#include <iostream>
#include <string>

#include "kanpai_image/character_generator.hpp"

namespace {

int failures = 0;

kanpai_image::ImageBuffer solid_image(
    int width,
    int height,
    std::uint8_t red,
    std::uint8_t green,
    std::uint8_t blue,
    std::uint8_t alpha
) {
    kanpai_image::ImageBuffer image;
    image.width = width;
    image.height = height;
    image.stride = width * 4;
    image.format = kanpai_image::PixelFormat::Rgba8;
    image.pixels.resize(static_cast<std::size_t>(image.stride * height));
    for (int index = 0; index < width * height; ++index) {
        image.pixels[index * 4] = red;
        image.pixels[index * 4 + 1] = green;
        image.pixels[index * 4 + 2] = blue;
        image.pixels[index * 4 + 3] = alpha;
    }
    return image;
}

void expect_true(bool condition, const std::string& message) {
    if (!condition) {
        std::cerr << "FAILED: " << message << '\n';
        ++failures;
    }
}

void expect_near(
    int actual,
    int expected,
    int tolerance,
    const std::string& message
) {
    if (std::abs(actual - expected) > tolerance) {
        std::cerr << "FAILED: " << message << " expected=" << expected
                  << " actual=" << actual << '\n';
        ++failures;
    }
}

void test_alpha_over() {
    auto base = solid_image(1, 1, 0, 0, 255, 128);
    auto overlay = solid_image(1, 1, 255, 0, 0, 128);
    auto result = kanpai_image::detail::alpha_over(base, overlay, 0, 0);

    expect_true(result.is_valid(), "alpha-overがRGBA8画像を返す");
    expect_near(result.pixels[0], 170, 1, "赤を非乗算alphaで合成する");
    expect_near(result.pixels[1], 0, 1, "緑を合成する");
    expect_near(result.pixels[2], 85, 1, "青を非乗算alphaで合成する");
    expect_near(result.pixels[3], 192, 1, "出力alphaをsource-overで求める");
}

void test_clipped_overlay() {
    auto base = solid_image(2, 2, 0, 0, 0, 0);
    auto overlay = solid_image(2, 2, 10, 20, 30, 255);
    auto result = kanpai_image::detail::alpha_over(base, overlay, -1, -1);

    expect_true(result.is_valid(), "負座標でも出力画像を維持する");
    expect_true(result.pixels[0] == 10, "画面内に入る1画素だけを合成する");
    expect_true(result.pixels[4] == 0, "範囲外の画素を変更しない");
}

void test_validation_error() {
    kanpai_image::GenerationConfig config;
    kanpai_image::CharacterTemplateSet templates;
    const auto result = kanpai_image::generate_character_images(
        {},
        templates,
        config
    );
    expect_true(!result.succeeded, "空画像を成功扱いにしない");
    expect_true(
        result.error == kanpai_image::GenerationError::EmptyInput,
        "空画像のエラー種別を返す"
    );
}

}  // namespace

int main() {
    test_alpha_over();
    test_clipped_overlay();
    test_validation_error();

    if (failures == 0) {
        std::cout << "Character generator tests passed.\n";
    }
    return failures == 0 ? 0 : 1;
}
