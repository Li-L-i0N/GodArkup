@tool
extends Control

# markup_ui_preview - for previewing the markup created

var current_file_path := ""
var ui_instance: Node = null
var parser := GodArkup.new()

func preview_markup(path: String) -> void:
	current_file_path = path
	if ui_instance:
		ui_instance.queue_free()
		ui_instance = null

	ui_instance = parser.load_markup(path, self)
	if not ui_instance:
		print("[Godarkup Preview] Failed to load: %s" % path)
		return

	add_child(ui_instance)
	# Only set anchors if the instance is a Control and NOT a Container
	if ui_instance is Control and not ui_instance is Container:
		ui_instance.set_anchors_preset(Control.PRESET_FULL_RECT)
