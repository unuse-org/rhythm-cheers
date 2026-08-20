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

enum class FaceDetectionStatus {
    Found,
    InvalidModel,
    NotFound,
};

struct DetectedFace {
    cv::Rect bounds;
    cv::Point2f right_eye;
    cv::Point2f left_eye;
    cv::Point2f nose_tip;
    cv::Point2f right_mouth_corner;
    cv::Point2f left_mouth_corner;
};

struct ExtractedFace {
    cv::Mat image;
    cv::Point2f mouth_center;
    float mouth_width = 0.0F;
    double mouth_angle_degrees = 0.0;
};

FaceDetectionStatus detect_primary_face(
    const cv::Mat& input_bgra,
    const GenerationConfig& config,
    DetectedFace& out_face
) {
    if (config.face_detector_model.empty()) {
        return FaceDetectionStatus::InvalidModel;
    }

    try {
        const std::vector<uchar> empty_config;
        auto detector = cv::FaceDetectorYN::create(
            "onnx",
            config.face_detector_model,
            empty_config,
            input_bgra.size(),
            config.face_score_threshold,
            config.face_nms_threshold
        );
        if (detector.empty()) {
            return FaceDetectionStatus::InvalidModel;
        }

        cv::Mat input_bgr;
        cv::cvtColor(input_bgra, input_bgr, cv::COLOR_BGRA2BGR);
        cv::Mat faces;
        detector->detect(input_bgr, faces);
        if (faces.empty()) {
            return FaceDetectionStatus::NotFound;
        }

        int primary_index = -1;
        float largest_area = 0.0F;
        for (int index = 0; index < faces.rows; ++index) {
            const float width = faces.at<float>(index, 2);
            const float height = faces.at<float>(index, 3);
            if (
                width < config.minimum_face_size
                || height < config.minimum_face_size
            ) {
                continue;
            }
            const float area = width * height;
            if (area > largest_area) {
                largest_area = area;
                primary_index = index;
            }
        }

        if (primary_index < 0) {
            return FaceDetectionStatus::NotFound;
        }

        const auto value = [&faces, primary_index](int column) {
            return faces.at<float>(primary_index, column);
        };
        out_face.bounds = cv::Rect(
            static_cast<int>(std::floor(value(0))),
            static_cast<int>(std::floor(value(1))),
            std::max(1, static_cast<int>(std::ceil(value(2)))),
            std::max(1, static_cast<int>(std::ceil(value(3))))
        );
        out_face.right_eye = cv::Point2f(value(4), value(5));
        out_face.left_eye = cv::Point2f(value(6), value(7));
        out_face.nose_tip = cv::Point2f(value(8), value(9));
        out_face.right_mouth_corner = cv::Point2f(value(10), value(11));
        out_face.left_mouth_corner = cv::Point2f(value(12), value(13));
        return FaceDetectionStatus::Found;
    } catch (const cv::Exception&) {
        return FaceDetectionStatus::InvalidModel;
    }
}

cv::Point2f normalized(const cv::Point2f& vector) {
    const float length = cv::norm(vector);
    return length > 0.001F
        ? vector * (1.0F / length)
        : cv::Point2f(0.0F, 1.0F);
}

cv::Point2f contour_point(
    const cv::Point2f& center,
    const cv::Point2f& horizontal_axis,
    const cv::Point2f& vertical_axis,
    float horizontal_offset,
    float vertical_offset
) {
    return center
        + horizontal_axis * horizontal_offset
        + vertical_axis * vertical_offset;
}

std::vector<cv::Point> smooth_closed_contour(
    const std::vector<cv::Point2f>& anchors,
    const cv::Size& bounds
) {
    constexpr int kStepsPerSegment = 8;
    std::vector<cv::Point> result;
    result.reserve(anchors.size() * kStepsPerSegment);
    const auto count = static_cast<int>(anchors.size());

    for (int index = 0; index < count; ++index) {
        const cv::Point2f& point0 = anchors[(index - 1 + count) % count];
        const cv::Point2f& point1 = anchors[index];
        const cv::Point2f& point2 = anchors[(index + 1) % count];
        const cv::Point2f& point3 = anchors[(index + 2) % count];

        for (int step = 0; step < kStepsPerSegment; ++step) {
            const float t = static_cast<float>(step) / kStepsPerSegment;
            const float t2 = t * t;
            const float t3 = t2 * t;
            const cv::Point2f point = 0.5F * (
                2.0F * point1
                + (-point0 + point2) * t
                + (2.0F * point0 - 5.0F * point1
                    + 4.0F * point2 - point3) * t2
                + (-point0 + 3.0F * point1
                    - 3.0F * point2 + point3) * t3
            );
            result.emplace_back(
                std::clamp(cvRound(point.x), 1, bounds.width - 2),
                std::clamp(cvRound(point.y), 1, bounds.height - 2)
            );
        }
    }
    return result;
}

ExtractedFace extract_face(
    const cv::Mat& input_bgra,
    const DetectedFace& detected_face,
    const GenerationConfig& config
) {
    const cv::Rect safe_face = detected_face.bounds
        & cv::Rect(0, 0, input_bgra.cols, input_bgra.rows);
    if (safe_face.width <= 0 || safe_face.height <= 0) {
        return {};
    }

    cv::Mat face = input_bgra(safe_face).clone();
    cv::Mat mask = cv::Mat::zeros(safe_face.size(), CV_8UC1);
    const cv::Point2f crop_offset(
        static_cast<float>(safe_face.x),
        static_cast<float>(safe_face.y)
    );
    const cv::Point2f right_eye = detected_face.right_eye - crop_offset;
    const cv::Point2f left_eye = detected_face.left_eye - crop_offset;
    const cv::Point2f nose_tip = detected_face.nose_tip - crop_offset;
    const cv::Point2f right_mouth = (
        detected_face.right_mouth_corner - crop_offset
    );
    const cv::Point2f left_mouth = (
        detected_face.left_mouth_corner - crop_offset
    );
    const cv::Point2f eye_center = (right_eye + left_eye) * 0.5F;
    const cv::Point2f mouth_center = (right_mouth + left_mouth) * 0.5F;
    const cv::Point2f vertical_axis = normalized(mouth_center - eye_center);
    const cv::Point2f horizontal_axis(
        vertical_axis.y,
        -vertical_axis.x
    );
    const float width = static_cast<float>(safe_face.width);
    const float height = static_cast<float>(safe_face.height);
    const float detected_center_x = (
        eye_center.x + nose_tip.x + mouth_center.x
    ) / 3.0F;
    const cv::Point2f center_correction(
        width * 0.5F - detected_center_x,
        0.0F
    );
    const cv::Point2f contour_eye_center = eye_center + center_correction;
    const cv::Point2f contour_nose_tip = nose_tip + center_correction;
    const cv::Point2f contour_mouth_center = mouth_center + center_correction;

    // YuNetの目・鼻・口を顔軸として使い、額、頬、顎を結ぶ輪郭を作る。
    // 上側は髪素材で隠れるため、頬から顎の形状を優先している。
    const std::vector<cv::Point2f> contour_anchors = {
        contour_point(contour_eye_center, horizontal_axis, vertical_axis, 0.0F, -0.34F * height),
        contour_point(contour_eye_center, horizontal_axis, vertical_axis, 0.28F * width, -0.29F * height),
        contour_point(contour_eye_center, horizontal_axis, vertical_axis, 0.42F * width, -0.03F * height),
        contour_point(contour_nose_tip, horizontal_axis, vertical_axis, 0.43F * width, 0.03F * height),
        contour_point(contour_mouth_center, horizontal_axis, vertical_axis, 0.36F * width, 0.05F * height),
        contour_point(contour_mouth_center, horizontal_axis, vertical_axis, 0.23F * width, 0.14F * height),
        contour_point(contour_mouth_center, horizontal_axis, vertical_axis, 0.0F, 0.19F * height),
        contour_point(contour_mouth_center, horizontal_axis, vertical_axis, -0.23F * width, 0.14F * height),
        contour_point(contour_mouth_center, horizontal_axis, vertical_axis, -0.36F * width, 0.05F * height),
        contour_point(contour_nose_tip, horizontal_axis, vertical_axis, -0.43F * width, 0.03F * height),
        contour_point(contour_eye_center, horizontal_axis, vertical_axis, -0.42F * width, -0.03F * height),
        contour_point(contour_eye_center, horizontal_axis, vertical_axis, -0.28F * width, -0.29F * height),
    };
    const std::vector<cv::Point> contour = smooth_closed_contour(
        contour_anchors,
        safe_face.size()
    );
    const std::vector<std::vector<cv::Point>> contours = {contour};
    cv::fillPoly(mask, contours, cv::Scalar(255), cv::LINE_AA);

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
    ExtractedFace result;
    result.image = std::move(face);
    result.mouth_center = mouth_center;
    result.mouth_width = cv::norm(left_mouth - right_mouth);
    result.mouth_angle_degrees = std::clamp(
        std::atan2(
            left_mouth.y - right_mouth.y,
            left_mouth.x - right_mouth.x
        ) * 180.0 / CV_PI,
        -config.mustache_max_rotation_degrees,
        config.mustache_max_rotation_degrees
    );
    return result;
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

cv::Mat resize_decoration(
    const ImageBuffer& decoration,
    int target_width
) {
    cv::Mat source = trim_transparent_margin(to_bgra(decoration));
    if (source.empty() || target_width <= 0) {
        return {};
    }

    const double scale = static_cast<double>(target_width)
        / static_cast<double>(source.cols);
    cv::Mat resized;
    cv::resize(
        source,
        resized,
        cv::Size(),
        scale,
        scale,
        scale < 1.0 ? cv::INTER_AREA : cv::INTER_CUBIC
    );
    return resized;
}

struct PositionedLayer {
    cv::Mat image;
    cv::Point position;
};

void append_centered_decoration(
    std::vector<PositionedLayer>& layers,
    const ImageBuffer& decoration,
    const cv::Mat& face,
    double width_ratio,
    double top_ratio
) {
    cv::Mat image = resize_decoration(
        decoration,
        std::max(1, static_cast<int>(std::round(face.cols * width_ratio)))
    );
    const int position_x = (face.cols - image.cols) / 2;
    layers.push_back({
        std::move(image),
        cv::Point(
            position_x,
            static_cast<int>(std::round(face.rows * top_ratio))
        ),
    });
}

cv::Mat build_head(
    const ExtractedFace& extracted_face,
    const CharacterDecorations& decorations,
    CharacterState state,
    const GenerationConfig& config
) {
    const cv::Mat& face = extracted_face.image;
    std::vector<PositionedLayer> layers;
    layers.push_back({face, cv::Point(0, 0)});

    if (state == CharacterState::Success) {
        append_centered_decoration(
            layers,
            decorations.cheeks,
            face,
            config.cheeks_width_ratio,
            config.cheeks_top_ratio
        );
    }
    const int mustache_width = std::clamp(
        static_cast<int>(std::round(
            extracted_face.mouth_width
                * config.mustache_mouth_width_multiplier
        )),
        std::max(1, static_cast<int>(std::round(face.cols * 0.35))),
        std::max(1, static_cast<int>(std::round(face.cols * 0.75)))
    );
    cv::Mat mustache = resize_decoration(
        decorations.mustache,
        mustache_width
    );
    mustache = rotate_image(
        mustache,
        // atan2は画像座標の下向きYで求めるため、OpenCVの回転角とは符号が逆。
        -extracted_face.mouth_angle_degrees
    );
    const cv::Point mustache_position(
        cvRound(extracted_face.mouth_center.x) - mustache.cols / 2,
        cvRound(
            extracted_face.mouth_center.y
                + face.rows * config.mustache_vertical_offset_ratio
        ) - mustache.rows / 2
    );
    layers.push_back({
        std::move(mustache),
        mustache_position,
    });
    append_centered_decoration(
        layers,
        decorations.hair,
        face,
        config.hair_width_ratio,
        config.hair_top_ratio
    );

    if (state == CharacterState::Failure) {
        cv::Mat failure_mark = resize_decoration(
            decorations.failure_mark,
            std::max(1, static_cast<int>(std::round(
                face.cols * config.failure_mark_width_ratio
            )))
        );
        layers.push_back({
            std::move(failure_mark),
            cv::Point(
                static_cast<int>(std::round(
                    face.cols * config.failure_mark_left_ratio
                )),
                static_cast<int>(std::round(
                    face.rows * config.failure_mark_top_ratio
                ))
            ),
        });
    }

    int minimum_x = 0;
    int minimum_y = 0;
    int maximum_x = face.cols;
    int maximum_y = face.rows;
    for (const auto& layer : layers) {
        if (layer.image.empty()) {
            return {};
        }
        minimum_x = std::min(minimum_x, layer.position.x);
        minimum_y = std::min(minimum_y, layer.position.y);
        maximum_x = std::max(
            maximum_x,
            layer.position.x + layer.image.cols
        );
        maximum_y = std::max(
            maximum_y,
            layer.position.y + layer.image.rows
        );
    }

    cv::Mat head = cv::Mat::zeros(
        maximum_y - minimum_y,
        maximum_x - minimum_x,
        CV_8UC4
    );
    for (const auto& layer : layers) {
        alpha_over_in_place(
            head,
            layer.image,
            cv::Point(
                layer.position.x - minimum_x,
                layer.position.y - minimum_y
            )
        );
    }
    return head;
}

GenerationResult validate_inputs(
    const ImageBuffer& captured_face,
    const CharacterTemplateSet& templates,
    const CharacterDecorations& decorations,
    const GenerationConfig& config
) {
    if (!captured_face.is_valid()) {
        return GenerationResult::failure(
            GenerationError::EmptyInput,
            "撮影画像が空、または画像サイズが不正です。"
        );
    }
    if (config.face_detector_model.empty()) {
        return GenerationResult::failure(
            GenerationError::MissingFaceModel,
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
        if (!item.body.is_valid()) {
            return GenerationResult::failure(
                GenerationError::MissingTemplate,
                std::string("状態素材が不足しています: ")
                    + kCharacterStateNames[index]
            );
        }
        if (
            item.body.format != PixelFormat::Rgba8
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

    const std::array<const ImageBuffer*, 4> decoration_images = {
        &decorations.hair,
        &decorations.mustache,
        &decorations.cheeks,
        &decorations.failure_mark,
    };
    const std::array<const char*, 4> decoration_names = {
        "hair", "mustache", "cheeks", "failure_mark",
    };
    for (std::size_t index = 0; index < decoration_images.size(); ++index) {
        const auto& image = *decoration_images[index];
        if (!image.is_valid()) {
            return GenerationResult::failure(
                GenerationError::MissingTemplate,
                std::string("装飾素材が不足しています: ")
                    + decoration_names[index]
            );
        }
        if (image.format != PixelFormat::Rgba8) {
            return GenerationResult::failure(
                GenerationError::InvalidTemplate,
                std::string("装飾素材の形式が不正です: ")
                    + decoration_names[index]
            );
        }
    }

    return GenerationResult::success({});
}

}  // namespace

GenerationResult generate_character_images(
    const ImageBuffer& captured_face,
    const CharacterTemplateSet& templates,
    const CharacterDecorations& decorations,
    const GenerationConfig& config
) {
    const GenerationResult validation = validate_inputs(
        captured_face,
        templates,
        decorations,
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
        DetectedFace detected_face;
        const auto detection = detect_primary_face(
            input,
            config,
            detected_face
        );
        if (detection == FaceDetectionStatus::InvalidModel) {
            return GenerationResult::failure(
                GenerationError::InvalidFaceModel,
                "顔検出モデルを読み込めませんでした。"
            );
        }
        if (detection == FaceDetectionStatus::NotFound) {
            return GenerationResult::failure(
                GenerationError::FaceNotFound,
                "写真から顔を検出できませんでした。"
            );
        }

        ExtractedFace face = extract_face(input, detected_face, config);
        if (face.image.empty()) {
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
            cv::Mat head = build_head(
                face,
                decorations,
                static_cast<CharacterState>(index),
                config
            );
            if (head.empty()) {
                return GenerationResult::failure(
                    GenerationError::ProcessingFailed,
                    "装飾素材の配置に失敗しました。"
                );
            }
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

ImageBuffer compose_head(
    const ImageBuffer& face,
    const CharacterDecorations& decorations,
    CharacterState state,
    const GenerationConfig& config
) {
    if (!face.is_valid() || face.format != PixelFormat::Rgba8) {
        return {};
    }

    ExtractedFace extracted_face;
    extracted_face.image = to_bgra(face);
    extracted_face.mouth_center = cv::Point2f(
        face.width * 0.5F,
        face.height * 0.75F
    );
    extracted_face.mouth_width = face.width * 0.35F;
    const cv::Mat head = build_head(
        extracted_face,
        decorations,
        state,
        config
    );
    return head.empty() ? ImageBuffer{} : from_bgra(head);
}

}  // namespace detail
}  // namespace kanpai_image
