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

kanpai_image::ImageBuffer padded_solid_image(
    int content_width,
    int content_height,
    int padding,
    std::uint8_t red,
    std::uint8_t green,
    std::uint8_t blue
) {
    auto image = solid_image(
        content_width + padding * 2,
        content_height + padding * 2,
        0,
        0,
        0,
        0
    );
    for (int y = padding; y < padding + content_height; ++y) {
        for (int x = padding; x < padding + content_width; ++x) {
            const auto index = static_cast<std::size_t>(
                (y * image.width + x) * 4
            );
            image.pixels[index] = red;
            image.pixels[index + 1] = green;
            image.pixels[index + 2] = blue;
            image.pixels[index + 3] = 255;
        }
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

bool contains_color(
    const kanpai_image::ImageBuffer& image,
    std::uint8_t red,
    std::uint8_t green,
    std::uint8_t blue
) {
    for (std::size_t index = 0; index < image.pixels.size(); index += 4) {
        if (
            image.pixels[index] == red
            && image.pixels[index + 1] == green
            && image.pixels[index + 2] == blue
            && image.pixels[index + 3] == 255
        ) {
            return true;
        }
    }
    return false;
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
    kanpai_image::CharacterDecorations decorations;
    const auto result = kanpai_image::generate_character_images(
        {},
        templates,
        decorations,
        config
    );
    expect_true(!result.succeeded, "空画像を成功扱いにしない");
    expect_true(
        result.error == kanpai_image::GenerationError::EmptyInput,
        "空画像のエラー種別を返す"
    );
}

void test_state_decorations() {
    const auto face = solid_image(100, 100, 255, 255, 255, 255);
    kanpai_image::CharacterDecorations decorations;
    decorations.hair = solid_image(10, 10, 255, 0, 0, 255);
    decorations.mustache = solid_image(10, 10, 0, 255, 0, 255);
    decorations.cheeks = solid_image(10, 10, 0, 0, 255, 255);
    decorations.failure_mark = solid_image(10, 10, 255, 255, 0, 255);
    kanpai_image::GenerationConfig config;

    const auto normal = kanpai_image::detail::compose_head(
        face,
        decorations,
        kanpai_image::CharacterState::Normal,
        config
    );
    const auto success = kanpai_image::detail::compose_head(
        face,
        decorations,
        kanpai_image::CharacterState::Success,
        config
    );
    const auto failure = kanpai_image::detail::compose_head(
        face,
        decorations,
        kanpai_image::CharacterState::Failure,
        config
    );

    expect_true(normal.is_valid(), "通常状態の頭部を合成する");
    expect_true(
        normal.width == success.width && normal.width == failure.width,
        "表情を追加しても頭部幅を変えない"
    );
    expect_true(
        contains_color(normal, 255, 0, 0)
            && contains_color(normal, 0, 255, 0),
        "全状態へ髪とひげを合成する"
    );
    expect_true(
        !contains_color(normal, 0, 0, 255)
            && !contains_color(normal, 255, 255, 0),
        "通常状態へ表情素材を追加しない"
    );
    expect_true(
        contains_color(success, 0, 0, 255),
        "成功状態だけにほっぺを合成する"
    );
    expect_true(
        contains_color(failure, 255, 255, 0),
        "失敗状態だけに失敗マークを合成する"
    );

    auto padded_decorations = decorations;
    padded_decorations.mustache = padded_solid_image(
        10,
        10,
        20,
        0,
        255,
        0
    );
    const auto padded_normal = kanpai_image::detail::compose_head(
        face,
        padded_decorations,
        kanpai_image::CharacterState::Normal,
        config
    );
    expect_true(
        padded_normal.width == normal.width
            && padded_normal.height == normal.height
            && padded_normal.pixels == normal.pixels,
        "素材の透明余白を装飾位置へ反映しない"
    );
}

}  // namespace

int main() {
    test_alpha_over();
    test_clipped_overlay();
    test_validation_error();
    test_state_decorations();

    if (failures == 0) {
        std::cout << "Character generator tests passed.\n";
    }
    return failures == 0 ? 0 : 1;
}
