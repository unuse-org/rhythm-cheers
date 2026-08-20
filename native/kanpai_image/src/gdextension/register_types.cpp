#include <gdextension_interface.h>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>

#include "kanpai_image/kanpai_character_image_set.hpp"
#include "kanpai_image/kanpai_image_processor.hpp"

using namespace godot;

void initialize_kanpai_image_module(ModuleInitializationLevel level) {
    if (level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }

    GDREGISTER_CLASS(KanpaiCharacterImageSet);
    GDREGISTER_CLASS(KanpaiImageProcessor);
}

void uninitialize_kanpai_image_module(ModuleInitializationLevel level) {
    if (level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
}

extern "C" {

GDExtensionBool GDE_EXPORT kanpai_image_library_init(
    GDExtensionInterfaceGetProcAddress get_proc_address,
    GDExtensionClassLibraryPtr library,
    GDExtensionInitialization* initialization
) {
    GDExtensionBinding::InitObject init_object(
        get_proc_address,
        library,
        initialization
    );
    init_object.register_initializer(initialize_kanpai_image_module);
    init_object.register_terminator(uninitialize_kanpai_image_module);
    init_object.set_minimum_library_initialization_level(
        MODULE_INITIALIZATION_LEVEL_SCENE
    );
    return init_object.init();
}

}
