#pragma once

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/resource.hpp>

namespace godot {

class KanpaiCharacterImageSet : public Resource {
    GDCLASS(KanpaiCharacterImageSet, Resource)

public:
    void set_normal(const Ref<Image>& image);
    Ref<Image> get_normal() const;
    void set_prepare(const Ref<Image>& image);
    Ref<Image> get_prepare() const;
    void set_judging(const Ref<Image>& image);
    Ref<Image> get_judging() const;
    void set_success(const Ref<Image>& image);
    Ref<Image> get_success() const;
    void set_failure(const Ref<Image>& image);
    Ref<Image> get_failure() const;
    bool is_complete() const;

protected:
    static void _bind_methods();

private:
    Ref<Image> normal_;
    Ref<Image> prepare_;
    Ref<Image> judging_;
    Ref<Image> success_;
    Ref<Image> failure_;
};

}  // namespace godot
