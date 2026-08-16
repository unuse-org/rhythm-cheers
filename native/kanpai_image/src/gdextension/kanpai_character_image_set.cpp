#include "kanpai_image/kanpai_character_image_set.hpp"

#include <godot_cpp/core/class_db.hpp>

namespace godot {

void KanpaiCharacterImageSet::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_normal", "image"), &KanpaiCharacterImageSet::set_normal);
    ClassDB::bind_method(D_METHOD("get_normal"), &KanpaiCharacterImageSet::get_normal);
    ClassDB::bind_method(D_METHOD("set_prepare", "image"), &KanpaiCharacterImageSet::set_prepare);
    ClassDB::bind_method(D_METHOD("get_prepare"), &KanpaiCharacterImageSet::get_prepare);
    ClassDB::bind_method(D_METHOD("set_judging", "image"), &KanpaiCharacterImageSet::set_judging);
    ClassDB::bind_method(D_METHOD("get_judging"), &KanpaiCharacterImageSet::get_judging);
    ClassDB::bind_method(D_METHOD("set_success", "image"), &KanpaiCharacterImageSet::set_success);
    ClassDB::bind_method(D_METHOD("get_success"), &KanpaiCharacterImageSet::get_success);
    ClassDB::bind_method(D_METHOD("set_failure", "image"), &KanpaiCharacterImageSet::set_failure);
    ClassDB::bind_method(D_METHOD("get_failure"), &KanpaiCharacterImageSet::get_failure);
    ClassDB::bind_method(D_METHOD("is_complete"), &KanpaiCharacterImageSet::is_complete);

    ADD_PROPERTY(
        PropertyInfo(Variant::OBJECT, "normal", PROPERTY_HINT_RESOURCE_TYPE, "Image"),
        "set_normal",
        "get_normal"
    );
    ADD_PROPERTY(
        PropertyInfo(Variant::OBJECT, "prepare", PROPERTY_HINT_RESOURCE_TYPE, "Image"),
        "set_prepare",
        "get_prepare"
    );
    ADD_PROPERTY(
        PropertyInfo(Variant::OBJECT, "judging", PROPERTY_HINT_RESOURCE_TYPE, "Image"),
        "set_judging",
        "get_judging"
    );
    ADD_PROPERTY(
        PropertyInfo(Variant::OBJECT, "success", PROPERTY_HINT_RESOURCE_TYPE, "Image"),
        "set_success",
        "get_success"
    );
    ADD_PROPERTY(
        PropertyInfo(Variant::OBJECT, "failure", PROPERTY_HINT_RESOURCE_TYPE, "Image"),
        "set_failure",
        "get_failure"
    );
}

void KanpaiCharacterImageSet::set_normal(const Ref<Image>& image) {
    normal_ = image;
}

Ref<Image> KanpaiCharacterImageSet::get_normal() const {
    return normal_;
}

void KanpaiCharacterImageSet::set_prepare(const Ref<Image>& image) {
    prepare_ = image;
}

Ref<Image> KanpaiCharacterImageSet::get_prepare() const {
    return prepare_;
}

void KanpaiCharacterImageSet::set_judging(const Ref<Image>& image) {
    judging_ = image;
}

Ref<Image> KanpaiCharacterImageSet::get_judging() const {
    return judging_;
}

void KanpaiCharacterImageSet::set_success(const Ref<Image>& image) {
    success_ = image;
}

Ref<Image> KanpaiCharacterImageSet::get_success() const {
    return success_;
}

void KanpaiCharacterImageSet::set_failure(const Ref<Image>& image) {
    failure_ = image;
}

Ref<Image> KanpaiCharacterImageSet::get_failure() const {
    return failure_;
}

bool KanpaiCharacterImageSet::is_complete() const {
    return normal_.is_valid() && !normal_->is_empty()
        && prepare_.is_valid() && !prepare_->is_empty()
        && judging_.is_valid() && !judging_->is_empty()
        && success_.is_valid() && !success_->is_empty()
        && failure_.is_valid() && !failure_->is_empty();
}

}  // namespace godot
