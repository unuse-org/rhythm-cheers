#pragma once

#include <atomic>
#include <cstdint>
#include <mutex>
#include <string>
#include <thread>

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

#include "kanpai_image/character_generator.hpp"
#include "kanpai_image/kanpai_character_image_set.hpp"

namespace godot {

class KanpaiImageProcessor : public Node {
    GDCLASS(KanpaiImageProcessor, Node)

public:
    KanpaiImageProcessor();
    ~KanpaiImageProcessor() override;

    bool configure(
        const Array& body_images,
        const Array& decoration_images,
        const PackedByteArray& face_detector_model
    );
    Ref<KanpaiCharacterImageSet> generate_sync(const Ref<Image>& input_image);
    bool generate_async(const Ref<Image>& input_image, std::int64_t request_id);
    void cancel(std::int64_t request_id);
    bool is_generation_in_progress() const;
    void _process(double delta) override;

protected:
    static void _bind_methods();

private:
    static kanpai_image::ImageBuffer image_to_buffer(const Ref<Image>& image);
    static Ref<Image> buffer_to_image(const kanpai_image::ImageBuffer& image);
    static Ref<KanpaiCharacterImageSet> result_to_resource(
        const kanpai_image::CharacterImageSet& images
    );
    void stop_worker();

    kanpai_image::CharacterTemplateSet templates_;
    kanpai_image::CharacterDecorations decorations_;
    kanpai_image::GenerationConfig config_;
    bool configured_ = false;

    std::thread worker_;
    mutable std::mutex result_mutex_;
    kanpai_image::GenerationResult pending_result_;
    std::atomic_bool processing_{false};
    std::atomic_bool completed_{false};
    std::atomic_bool cancellation_requested_{false};
    std::int64_t active_request_id_ = 0;
};

}  // namespace godot
