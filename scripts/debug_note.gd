class_name DebugNote
extends Node2D

@onready var visual: ColorRect = $Visual

var beat: float = 0.0


func set_debug_color(color: Color) -> void:
	visual.color = color
