#include <array>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <string>

#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>

#include "kanpai_image/character_generator.hpp"

namespace {

kanpai_image::ImageBuffer load_image(const std::filesystem::path& path) {
    const cv::Mat source = cv::imread(path.string(), cv::IMREAD_UNCHANGED);
    if (source.empty()) {
        return {};
    }

    cv::Mat rgba;
    if (source.channels() == 4) {
        cv::cvtColor(source, rgba, cv::COLOR_BGRA2RGBA);
    } else {
        cv::cvtColor(source, rgba, cv::COLOR_BGR2RGBA);
    }

    kanpai_image::ImageBuffer image;
    image.width = rgba.cols;
    image.height = rgba.rows;
    image.stride = rgba.cols * 4;
    image.format = kanpai_image::PixelFormat::Rgba8;
    image.pixels.assign(
        rgba.data,
        rgba.data + static_cast<std::ptrdiff_t>(image.stride * image.height)
    );
    return image;
}

bool save_image(
    const std::filesystem::path& path,
    const kanpai_image::ImageBuffer& image
) {
    cv::Mat rgba(
        image.height,
        image.width,
        CV_8UC4,
        const_cast<std::uint8_t*>(image.pixels.data()),
        image.stride
    );
    cv::Mat bgra;
    cv::cvtColor(rgba, bgra, cv::COLOR_RGBA2BGRA);
    return cv::imwrite(path.string(), bgra);
}

std::string read_text(const std::filesystem::path& path) {
    std::ifstream input(path);
    return {
        std::istreambuf_iterator<char>(input),
        std::istreambuf_iterator<char>()
    };
}

}  // namespace

int main(int argument_count, char** arguments) {
    if (argument_count != 6) {
        std::cerr
            << "Usage: kanpai_image_cli <input> <template-dir> <cascade.xml> "
            << "<output-dir> <panel-dir>\n";
        return 2;
    }

    const std::filesystem::path input_path = arguments[1];
    const std::filesystem::path template_directory = arguments[2];
    const std::filesystem::path cascade_path = arguments[3];
    const std::filesystem::path output_directory = arguments[4];
    const std::filesystem::path panel_directory = arguments[5];

    kanpai_image::CharacterTemplateSet templates;
    const std::array<const char*, kanpai_image::kCharacterStateCount> panels = {
        "default_hair.png",
        "default_hair.png",
        "default_hair.png",
        "success_overlay.png",
        "failure_overlay.png",
    };
    const std::array<double, kanpai_image::kCharacterStateCount> angles = {
        0.0, -13.0, 10.0, 0.0, 0.0,
    };
    const std::array<double, kanpai_image::kCharacterStateCount> offsets = {
        0.0, 0.047, -0.005, 0.019, 0.019,
    };
    const std::array<double, kanpai_image::kCharacterStateCount> anchors_y = {
        0.465, 0.460, 0.480, 0.480, 0.450,
    };

    for (std::size_t index = 0; index < templates.size(); ++index) {
        templates[index].body = load_image(
            template_directory
                / (std::string(kanpai_image::kCharacterStateNames[index]) + ".png")
        );
        templates[index].panel = load_image(panel_directory / panels[index]);
        templates[index].head_angle_degrees = angles[index];
        templates[index].head_offset_x_ratio = offsets[index];
        templates[index].head_anchor_y_ratio = anchors_y[index];
    }

    kanpai_image::GenerationConfig config;
    config.face_cascade_xml = read_text(cascade_path);
    auto result = kanpai_image::generate_character_images(
        load_image(input_path),
        templates,
        config
    );
    if (!result.succeeded) {
        std::cerr << result.message << '\n';
        return static_cast<int>(result.error);
    }

    std::error_code directory_error;
    std::filesystem::create_directories(output_directory, directory_error);
    if (directory_error) {
        std::cerr << "出力ディレクトリを作成できません: "
                  << directory_error.message() << '\n';
        return 3;
    }

    for (std::size_t index = 0; index < result.images.images.size(); ++index) {
        const auto output_path = output_directory
            / (std::string(kanpai_image::kCharacterStateNames[index]) + ".png");
        if (!save_image(output_path, result.images.images[index])) {
            std::cerr << "画像を保存できません: " << output_path << '\n';
            return 4;
        }
    }

    std::cout << "5状態のキャラクター画像を生成しました: "
              << output_directory << '\n';
    return 0;
}
