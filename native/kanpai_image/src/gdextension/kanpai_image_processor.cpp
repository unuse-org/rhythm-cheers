#include "kanpai_image/kanpai_image_processor.hpp"

#include <algorithm>
#include <utility>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

namespace godot {
namespace {

constexpr std::int64_t kDecorationCount = 4;
constexpr std::array<double, kanpai_image::kCharacterStateCount> kAngles = {
    0.0, -13.0, 10.0, 0.0, 0.0,
};
constexpr std::array<double, kanpai_image::kCharacterStateCount> kOffsetsX = {
    0.0, 0.047, -0.005, 0.019, 0.019,
};
// 各身体素材の襟元より少し下へ頭部下端を重ね、境界の隙間を防ぐ。
constexpr std::array<double, kanpai_image::kCharacterStateCount> kAnchorsY = {
    0.465, 0.460, 0.480, 0.480, 0.450,
};

}  // namespace

KanpaiImageProcessor::KanpaiImageProcessor() {
    set_process(false);
}

KanpaiImageProcessor::~KanpaiImageProcessor() {
    stop_worker();
}

void KanpaiImageProcessor::_bind_methods() {
    ClassDB::bind_method(
        D_METHOD(
            "configure",
            "body_images",
            "decoration_images",
            "face_detector_model"
        ),
        &KanpaiImageProcessor::configure
    );
    ClassDB::bind_method(
        D_METHOD("generate_sync", "input_image"),
        &KanpaiImageProcessor::generate_sync
    );
    ClassDB::bind_method(
        D_METHOD("generate_async", "input_image", "request_id"),
        &KanpaiImageProcessor::generate_async
    );
    ClassDB::bind_method(
        D_METHOD("cancel", "request_id"),
        &KanpaiImageProcessor::cancel
    );
    ClassDB::bind_method(
        D_METHOD("is_generation_in_progress"),
        &KanpaiImageProcessor::is_generation_in_progress
    );

    ADD_SIGNAL(MethodInfo(
        "generation_completed",
        PropertyInfo(Variant::INT, "request_id"),
        PropertyInfo(
            Variant::OBJECT,
            "images",
            PROPERTY_HINT_RESOURCE_TYPE,
            "KanpaiCharacterImageSet"
        )
    ));
    ADD_SIGNAL(MethodInfo(
        "generation_failed",
        PropertyInfo(Variant::INT, "request_id"),
        PropertyInfo(Variant::INT, "error_code"),
        PropertyInfo(Variant::STRING, "message")
    ));
}

bool KanpaiImageProcessor::configure(
    const Array& body_images,
    const Array& decoration_images,
    const PackedByteArray& face_detector_model
) {
    if (
        processing_.load()
        || body_images.size() != kanpai_image::kCharacterStateCount
        || decoration_images.size() != kDecorationCount
        || face_detector_model.is_empty()
    ) {
        return false;
    }

    kanpai_image::CharacterTemplateSet next_templates;
    for (std::size_t index = 0; index < next_templates.size(); ++index) {
        const Ref<Image> body = body_images[static_cast<std::int64_t>(index)];
        next_templates[index].body = image_to_buffer(body);
        next_templates[index].head_angle_degrees = kAngles[index];
        next_templates[index].head_offset_x_ratio = kOffsetsX[index];
        next_templates[index].head_anchor_y_ratio = kAnchorsY[index];

        if (!next_templates[index].body.is_valid()) {
            return false;
        }
    }

    kanpai_image::CharacterDecorations next_decorations;
    const Ref<Image> hair = decoration_images[0];
    const Ref<Image> mustache = decoration_images[1];
    const Ref<Image> cheeks = decoration_images[2];
    const Ref<Image> failure_mark = decoration_images[3];
    next_decorations.hair = image_to_buffer(hair);
    next_decorations.mustache = image_to_buffer(mustache);
    next_decorations.cheeks = image_to_buffer(cheeks);
    next_decorations.failure_mark = image_to_buffer(failure_mark);
    if (
        !next_decorations.hair.is_valid()
        || !next_decorations.mustache.is_valid()
        || !next_decorations.cheeks.is_valid()
        || !next_decorations.failure_mark.is_valid()
    ) {
        return false;
    }

    templates_ = std::move(next_templates);
    decorations_ = std::move(next_decorations);
    config_.face_detector_model.assign(
        face_detector_model.ptr(),
        face_detector_model.ptr() + face_detector_model.size()
    );
    config_.cancellation_requested = [this]() {
        return cancellation_requested_.load();
    };
    configured_ = true;
    return true;
}

Ref<KanpaiCharacterImageSet> KanpaiImageProcessor::generate_sync(
    const Ref<Image>& input_image
) {
    if (!configured_ || processing_.load()) {
        return {};
    }

    cancellation_requested_.store(false);
    const auto result = kanpai_image::generate_character_images(
        image_to_buffer(input_image),
        templates_,
        decorations_,
        config_
    );
    if (!result.succeeded) {
        return {};
    }
    return result_to_resource(result.images);
}

bool KanpaiImageProcessor::generate_async(
    const Ref<Image>& input_image,
    std::int64_t request_id
) {
    if (!configured_ || processing_.exchange(true)) {
        return false;
    }

    const auto input = image_to_buffer(input_image);
    if (!input.is_valid()) {
        processing_.store(false);
        return false;
    }

    if (worker_.joinable()) {
        worker_.join();
    }
    active_request_id_ = request_id;
    completed_.store(false);
    cancellation_requested_.store(false);
    set_process(true);

    worker_ = std::thread([this, input]() {
        auto result = kanpai_image::generate_character_images(
            input,
            templates_,
            decorations_,
            config_
        );
        {
            std::lock_guard<std::mutex> lock(result_mutex_);
            pending_result_ = std::move(result);
        }
        completed_.store(true);
    });
    return true;
}

void KanpaiImageProcessor::cancel(std::int64_t request_id) {
    if (processing_.load() && request_id == active_request_id_) {
        cancellation_requested_.store(true);
    }
}

bool KanpaiImageProcessor::is_generation_in_progress() const {
    return processing_.load();
}

void KanpaiImageProcessor::_process(double /*delta*/) {
    if (!completed_.exchange(false)) {
        return;
    }

    if (worker_.joinable()) {
        worker_.join();
    }

    kanpai_image::GenerationResult result;
    {
        std::lock_guard<std::mutex> lock(result_mutex_);
        result = std::move(pending_result_);
    }
    processing_.store(false);
    set_process(false);

    if (result.succeeded) {
        emit_signal(
            "generation_completed",
            active_request_id_,
            result_to_resource(result.images)
        );
        return;
    }

    emit_signal(
        "generation_failed",
        active_request_id_,
        static_cast<std::int64_t>(result.error),
        String::utf8(result.message.c_str())
    );
}

kanpai_image::ImageBuffer KanpaiImageProcessor::image_to_buffer(
    const Ref<Image>& image
) {
    if (
        image.is_null()
        || image->is_empty()
        || image->has_mipmaps()
        || (
            image->get_format() != Image::FORMAT_RGBA8
            && image->get_format() != Image::FORMAT_RGB8
        )
    ) {
        return {};
    }

    const bool has_alpha = image->get_format() == Image::FORMAT_RGBA8;
    const PackedByteArray bytes = image->get_data();
    kanpai_image::ImageBuffer result;
    result.width = image->get_width();
    result.height = image->get_height();
    result.stride = result.width * (has_alpha ? 4 : 3);
    result.format = has_alpha
        ? kanpai_image::PixelFormat::Rgba8
        : kanpai_image::PixelFormat::Rgb8;
    result.pixels.assign(bytes.ptr(), bytes.ptr() + bytes.size());
    return result;
}

Ref<Image> KanpaiImageProcessor::buffer_to_image(
    const kanpai_image::ImageBuffer& image
) {
    if (!image.is_valid() || image.format != kanpai_image::PixelFormat::Rgba8) {
        return {};
    }

    PackedByteArray bytes;
    bytes.resize(static_cast<std::int64_t>(image.pixels.size()));
    std::copy(image.pixels.begin(), image.pixels.end(), bytes.ptrw());
    return Image::create_from_data(
        image.width,
        image.height,
        false,
        Image::FORMAT_RGBA8,
        bytes
    );
}

Ref<KanpaiCharacterImageSet> KanpaiImageProcessor::result_to_resource(
    const kanpai_image::CharacterImageSet& images
) {
    Ref<KanpaiCharacterImageSet> result;
    result.instantiate();
    result->set_normal(buffer_to_image(images.at(kanpai_image::CharacterState::Normal)));
    result->set_prepare(buffer_to_image(images.at(kanpai_image::CharacterState::Prepare)));
    result->set_judging(buffer_to_image(images.at(kanpai_image::CharacterState::Judging)));
    result->set_success(buffer_to_image(images.at(kanpai_image::CharacterState::Success)));
    result->set_failure(buffer_to_image(images.at(kanpai_image::CharacterState::Failure)));
    return result;
}

void KanpaiImageProcessor::stop_worker() {
    cancellation_requested_.store(true);
    if (worker_.joinable()) {
        worker_.join();
    }
    processing_.store(false);
    completed_.store(false);
}

}  // namespace godot
