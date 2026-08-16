#include "kanpai_image/character_generator.hpp"

#include <algorithm>
#include <cmath>
#include <exception>
#include <limits>
#include <utility>
#include <vector>

#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/objdetect.hpp>

namespace kanpai_image {
namespace {

cv::Mat to_bgra(const ImageBuffer& image) {
    const int source_type = image.format == PixelFormat::Rgba8
        ? CV_8UC4
        : CV_8UC3;
    cv::Mat source(
        image.height,
        image.width,
        source_type,
        const_cast<std::uint8_t*>(image.pixels.data()),
        static_cast<std::size_t>(image.stride)
    );
    cv::Mat result;

    if (image.format == PixelFormat::Rgba8) {
        cv::cvtColor(source, result, cv::COLOR_RGBA2BGRA);
    } else {
        cv::cvtColor(source, result, cv::COLOR_RGB2BGRA);
    }

    return result;
}

ImageBuffer from_bgra(const cv::Mat& bgra) {
    cv::Mat rgba;
    cv::cvtColor(bgra, rgba, cv::COLOR_BGRA2RGBA);
    if (!rgba.isContinuous()) {
        rgba = rgba.clone();
    }

    ImageBuffer result;
    result.width = rgba.cols;
    result.height = rgba.rows;
    result.stride = rgba.cols * 4;
    result.format = PixelFormat::Rgba8;
    result.pixels.assign(
        rgba.data,
        rgba.data + static_cast<std::ptrdiff_t>(result.stride * result.height)
    );
    return result;
}

bool is_cancelled(const GenerationConfig& config) {
    return config.cancellation_requested && config.cancellation_requested();
}

cv::Mat resize_input_if_needed(
    const cv::Mat& input,
    const GenerationConfig& config
) {
    if (
        input.cols <= config.max_input_width
        && input.rows <= config.max_input_height
    ) {
        return input;
    }

    const double scale_x = static_cast<double>(config.max_input_width)
        / static_cast<double>(input.cols);
    const double scale_y = static_cast<double>(config.max_input_height)
        / static_cast<double>(input.rows);
    const double scale = std::min(scale_x, scale_y);
    cv::Mat resized;
    cv::resize(input, resized, cv::Size(), scale, scale, cv::INTER_AREA);
    return resized;
}

bool load_cascade_from_memory(
    const std::string& cascade_xml,
    cv::CascadeClassifier& classifier
) {
    if (cascade_xml.empty()) {
        return false;
    }

    try {
        cv::FileStorage storage(
            cascade_xml,
            cv::FileStorage::READ | cv::FileStorage::MEMORY
        );
        return storage.isOpened()
            && classifier.read(storage.getFirstTopLevelNode());
    } catch (const cv::Exception&) {
        return false;
    }
}

enum class FaceDetectionStatus {
    Found,
    InvalidCascade,
    NotFound,
};

FaceDetectionStatus detect_primary_face(
    const cv::Mat& input_bgra,
    const GenerationConfig& config,
    cv::Rect& out_face
) {
    cv::CascadeClassifier classifier;
    if (!load_cascade_from_memory(config.face_cascade_xml, classifier)) {
        return FaceDetectionStatus::InvalidCascade;
    }

    cv::Mat gray;
    cv::cvtColor(input_bgra, gray, cv::COLOR_BGRA2GRAY);
    cv::equalizeHist(gray, gray);
    std::vector<cv::Rect> faces;
    classifier.detectMultiScale(
        gray,
        faces,
        1.1,
        3,
        0,
        cv::Size(config.minimum_face_size, config.minimum_face_size)
    );

    if (faces.empty()) {
        return FaceDetectionStatus::NotFound;
    }

    out_face = *std::max_element(
        faces.begin(),
        faces.end(),
        [](const cv::Rect& left, const cv::Rect& right) {
            return left.area() < right.area();
        }
    );
    return FaceDetectionStatus::Found;
}

cv::Mat extract_face(
    const cv::Mat& input_bgra,
    const cv::Rect& detected_face,
    const GenerationConfig& config
) {
    const cv::Rect safe_face = detected_face
        & cv::Rect(0, 0, input_bgra.cols, input_bgra.rows);
    if (safe_face.width <= 0 || safe_face.height <= 0) {
        return {};
    }

    cv::Mat face = input_bgra(safe_face).clone();
    cv::Mat mask = cv::Mat::zeros(safe_face.size(), CV_8UC1);
    const cv::Point center(safe_face.width / 2, safe_face.height / 2);
    const cv::Size axes(
        std::max(1, static_cast<int>(
            safe_face.width * 0.5 * config.face_cut_scale
            * config.face_aspect_x
        )),
        std::max(1, static_cast<int>(
            safe_face.height * 0.5 * config.face_cut_scale
            * config.face_aspect_y
        ))
    );
    cv::ellipse(mask, center, axes, 0, 0, 360, cv::Scalar(255), -1);

    int blur_size = std::max(1, config.face_blur_size);
    if (blur_size % 2 == 0) {
        ++blur_size;
    }
    if (blur_size > 1) {
        cv::GaussianBlur(mask, mask, cv::Size(blur_size, blur_size), 0);
    }

    for (int y = 0; y < face.rows; ++y) {
        auto* pixels = face.ptr<cv::Vec4b>(y);
        const auto* mask_pixels = mask.ptr<std::uint8_t>(y);
        for (int x = 0; x < face.cols; ++x) {
            pixels[x][3] = static_cast<std::uint8_t>(
                static_cast<unsigned int>(pixels[x][3])
                * static_cast<unsigned int>(mask_pixels[x])
                / 255U
            );
        }
    }
    return face;
}

void alpha_over_in_place(
    cv::Mat& base,
    const cv::Mat& overlay,
    const cv::Point position
) {
    const int start_x = std::max(0, position.x);
    const int start_y = std::max(0, position.y);
    const int end_x = std::min(base.cols, position.x + overlay.cols);
    const int end_y = std::min(base.rows, position.y + overlay.rows);

    if (start_x >= end_x || start_y >= end_y) {
        return;
    }

    for (int y = start_y; y < end_y; ++y) {
        auto* base_pixels = base.ptr<cv::Vec4b>(y);
        const auto* overlay_pixels = overlay.ptr<cv::Vec4b>(y - position.y);

        for (int x = start_x; x < end_x; ++x) {
            cv::Vec4b& destination = base_pixels[x];
            const cv::Vec4b& source = overlay_pixels[x - position.x];
            const float source_alpha = source[3] / 255.0F;
            const float destination_alpha = destination[3] / 255.0F;
            const float output_alpha = source_alpha
                + destination_alpha * (1.0F - source_alpha);

            if (output_alpha <= std::numeric_limits<float>::epsilon()) {
                destination = cv::Vec4b(0, 0, 0, 0);
                continue;
            }

            for (int channel = 0; channel < 3; ++channel) {
                const float premultiplied =
                    source[channel] * source_alpha
                    + destination[channel] * destination_alpha
                        * (1.0F - source_alpha);
                destination[channel] = cv::saturate_cast<std::uint8_t>(
                    premultiplied / output_alpha
                );
            }
            destination[3] = cv::saturate_cast<std::uint8_t>(
                output_alpha * 255.0F
            );
        }
    }
}

cv::Mat rotate_image(const cv::Mat& source, double angle_degrees) {
    if (std::abs(angle_degrees) < 0.001) {
        return source.clone();
    }

    const cv::Point2f center(source.cols / 2.0F, source.rows / 2.0F);
    cv::Mat transform = cv::getRotationMatrix2D(center, angle_degrees, 1.0);
    const cv::Rect2f bounds = cv::RotatedRect(
        cv::Point2f(),
        source.size(),
        static_cast<float>(angle_degrees)
    ).boundingRect2f();
    transform.at<double>(0, 2) += bounds.width / 2.0 - center.x;
    transform.at<double>(1, 2) += bounds.height / 2.0 - center.y;

    cv::Mat result;
    cv::warpAffine(
        source,
        result,
        transform,
        bounds.size(),
        cv::INTER_LINEAR,
        cv::BORDER_CONSTANT,
        cv::Scalar(0, 0, 0, 0)
    );
    return result;
}

cv::Mat trim_transparent_margin(const cv::Mat& source) {
    if (source.empty() || source.channels() != 4) {
        return source;
    }

    cv::Mat alpha;
    cv::extractChannel(source, alpha, 3);
    const cv::Rect visible_bounds = cv::boundingRect(alpha);
    if (visible_bounds.width <= 0 || visible_bounds.height <= 0) {
        return {};
    }

    return source(visible_bounds).clone();
}

cv::Mat build_head(
    const cv::Mat& face,
    const cv::Mat& panel,
    const GenerationConfig& config
) {
    const double panel_scale = static_cast<double>(face.cols)
        / static_cast<double>(panel.cols)
        * config.panel_scale_multiplier;
    cv::Mat scaled_panel;
    cv::resize(
        panel,
        scaled_panel,
        cv::Size(),
        panel_scale,
        panel_scale,
        cv::INTER_AREA
    );

    const int panel_x = (face.cols - scaled_panel.cols) / 2;
    const int panel_y = (face.rows - scaled_panel.rows) / 2
        + static_cast<int>(std::round(
            scaled_panel.rows * config.panel_lift_ratio
        ));
    const int minimum_x = std::min(0, panel_x);
    const int minimum_y = std::min(0, panel_y);
    const int maximum_x = std::max(face.cols, panel_x + scaled_panel.cols);
    const int maximum_y = std::max(face.rows, panel_y + scaled_panel.rows);
    cv::Mat head = cv::Mat::zeros(
        maximum_y - minimum_y,
        maximum_x - minimum_x,
        CV_8UC4
    );
    alpha_over_in_place(head, face, cv::Point(-minimum_x, -minimum_y));
    alpha_over_in_place(
        head,
        scaled_panel,
        cv::Point(panel_x - minimum_x, panel_y - minimum_y)
    );
    return head;
}

GenerationResult validate_inputs(
    const ImageBuffer& captured_face,
    const CharacterTemplateSet& templates,
    const GenerationConfig& config
) {
    if (!captured_face.is_valid()) {
        return GenerationResult::failure(
            GenerationError::EmptyInput,
            "撮影画像が空、または画像サイズが不正です。"
        );
    }
    if (config.face_cascade_xml.empty()) {
        return GenerationResult::failure(
            GenerationError::MissingCascade,
            "顔検出モデルが設定されていません。"
        );
    }
    if (config.output_width <= 0 || config.output_height <= 0) {
        return GenerationResult::failure(
            GenerationError::ProcessingFailed,
            "出力画像サイズが不正です。"
        );
    }

    for (std::size_t index = 0; index < templates.size(); ++index) {
        const auto& item = templates[index];
        if (!item.body.is_valid() || !item.panel.is_valid()) {
            return GenerationResult::failure(
                GenerationError::MissingTemplate,
                std::string("状態素材が不足しています: ")
                    + kCharacterStateNames[index]
            );
        }
        if (
            item.body.format != PixelFormat::Rgba8
            || item.panel.format != PixelFormat::Rgba8
            || item.body.width != config.output_width
            || item.body.height != config.output_height
        ) {
            return GenerationResult::failure(
                GenerationError::InvalidTemplate,
                std::string("状態素材の形式またはサイズが不正です: ")
                    + kCharacterStateNames[index]
            );
        }
    }

    return GenerationResult::success({});
}

}  // namespace

GenerationResult generate_character_images(
    const ImageBuffer& captured_face,
    const CharacterTemplateSet& templates,
    const GenerationConfig& config
) {
    const GenerationResult validation = validate_inputs(
        captured_face,
        templates,
        config
    );
    if (!validation.succeeded) {
        return validation;
    }
    if (is_cancelled(config)) {
        return GenerationResult::failure(
            GenerationError::Cancelled,
            "画像生成をキャンセルしました。"
        );
    }

    try {
        cv::Mat input = resize_input_if_needed(to_bgra(captured_face), config);
        cv::Rect face_rectangle;
        const auto detection = detect_primary_face(
            input,
            config,
            face_rectangle
        );
        if (detection == FaceDetectionStatus::InvalidCascade) {
            return GenerationResult::failure(
                GenerationError::InvalidCascade,
                "顔検出モデルを読み込めませんでした。"
            );
        }
        if (detection == FaceDetectionStatus::NotFound) {
            return GenerationResult::failure(
                GenerationError::FaceNotFound,
                "写真から顔を検出できませんでした。"
            );
        }

        cv::Mat face = extract_face(input, face_rectangle, config);
        if (face.empty()) {
            return GenerationResult::failure(
                GenerationError::ProcessingFailed,
                "顔画像の切り抜きに失敗しました。"
            );
        }

        CharacterImageSet outputs;
        for (std::size_t index = 0; index < templates.size(); ++index) {
            if (is_cancelled(config)) {
                return GenerationResult::failure(
                    GenerationError::Cancelled,
                    "画像生成をキャンセルしました。"
                );
            }

            const CharacterTemplate& item = templates[index];
            cv::Mat body = to_bgra(item.body);
            const cv::Mat panel = to_bgra(item.panel);
            cv::Mat head = build_head(face, panel, config);
            const int target_width = std::max(1, static_cast<int>(std::round(
                config.output_width * config.head_width_ratio
            )));
            const double scale = static_cast<double>(target_width)
                / static_cast<double>(head.cols);
            cv::resize(
                head,
                head,
                cv::Size(),
                scale,
                scale,
                scale < 1.0 ? cv::INTER_AREA : cv::INTER_CUBIC
            );
            head = rotate_image(head, item.head_angle_degrees);
            // 回転で増えた透明余白を除き、見えている頭部の下端を首元へ合わせる。
            head = trim_transparent_margin(head);
            if (head.empty()) {
                return GenerationResult::failure(
                    GenerationError::ProcessingFailed,
                    "頭部画像の配置領域を計算できませんでした。"
                );
            }

            const int position_x = (config.output_width - head.cols) / 2
                + static_cast<int>(std::round(
                    config.output_width * item.head_offset_x_ratio
                ));
            // 状態素材の首元へ頭部の下端を合わせる。頭部サイズや回転後の
            // bounding boxが変わっても、顔と身体の間に隙間を作らない。
            const int position_y = static_cast<int>(std::round(
                config.output_height * item.head_anchor_y_ratio
            )) - head.rows;
            alpha_over_in_place(
                body,
                head,
                cv::Point(position_x, position_y)
            );
            outputs.images[index] = from_bgra(body);
        }
        return GenerationResult::success(std::move(outputs));
    } catch (const cv::Exception& exception) {
        return GenerationResult::failure(
            GenerationError::ProcessingFailed,
            std::string("OpenCV処理に失敗しました: ") + exception.what()
        );
    } catch (const std::exception& exception) {
        return GenerationResult::failure(
            GenerationError::ProcessingFailed,
            std::string("画像処理に失敗しました: ") + exception.what()
        );
    }
}

namespace detail {

ImageBuffer alpha_over(
    const ImageBuffer& base,
    const ImageBuffer& overlay,
    int position_x,
    int position_y
) {
    if (
        !base.is_valid()
        || !overlay.is_valid()
        || base.format != PixelFormat::Rgba8
        || overlay.format != PixelFormat::Rgba8
    ) {
        return {};
    }

    cv::Mat base_bgra = to_bgra(base);
    const cv::Mat overlay_bgra = to_bgra(overlay);
    alpha_over_in_place(
        base_bgra,
        overlay_bgra,
        cv::Point(position_x, position_y)
    );
    return from_bgra(base_bgra);
}

}  // namespace detail
}  // namespace kanpai_image
