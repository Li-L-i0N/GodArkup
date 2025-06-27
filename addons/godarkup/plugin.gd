@tool
extends EditorPlugin

# plugin.gd - main entry point when activating the plugin

var current_path: String = ""
var preview_dock

func _handles(resource: Object) -> bool:
	return resource is Resource and resource.resource_path.to_lower().ends_with(".godarkup")

func _edit(resource: Object) -> void:
	if not resource or not resource is Resource:
		return
	var path = resource.resource_path
	current_path = path

	if preview_dock and preview_dock.has_method("preview_markup"):
		preview_dock.preview_markup(path)
		
 # Set scene ownership so child nodes are saved
func _set_owner_recursive(node: Node, owner: Node) -> void:
	for child in node.get_children():
		if child is Node:
			child.owner = owner
			_set_owner_recursive(child, owner)

func _generate_scene(path: String) -> void:
	var parser = GodArkup.new()
	var ui_root = parser.load_markup(path, self)
	if not ui_root:
		printerr('[GodArkup] Failed to parse %s' % path)
		return

	_set_owner_recursive(ui_root, ui_root)

	var packed = PackedScene.new()
	var err = packed.pack(ui_root)
	if err != OK:
		printerr('[GodArkup] Failed to pack scene for %s' % path)
		return
	var base_dir = path.get_base_dir()
	var file_name = path.get_file().get_basename()
	var save_path = base_dir + "/" + file_name + ".tscn"
	var save_err = ResourceSaver.save(packed, save_path)
	if save_err != OK:
		printerr('[GodArkup] Failed to save scene to %s' % save_path)
	else:
		print('[GodArkup] Scene generated: %s' % save_path)
		
func _enter_tree() -> void:
	 # Add "Generate UI Scene" to the Tools menu
	add_tool_menu_item("Generate UI Scene", Callable(self, "_on_generate_button_pressed"))
	
	# Instantiate preview dock from script, not a missing .tscn
	var PreviewScript := preload("res://addons/godarkup/scripts/markup_ui_preview.gd")
	preview_dock = PreviewScript.new()
	add_control_to_bottom_panel(preview_dock, "UI Markup Preview")

	# Register .godarkup extension with the editor
	var editor_settings := get_editor_interface().get_editor_settings()
	var filters := editor_settings.get_setting("docks/filesystem/textfile_extensions")
	if filters == null:
		printerr('Filter not found when registering extension!')
	if not filters.split(",").has("godarkup"):
		filters += ",godarkup"
		editor_settings.set_setting("docks/filesystem/textfile_extensions", filters)
		print("[GodArkup] Registered .godarkup as visible file type.")

func _exit_tree() -> void:
	# Remove menu item when plugin disabled
	remove_tool_menu_item("Generate UI Scene")
	preview_dock.queue_free()
	remove_control_from_bottom_panel(preview_dock)
	
	# Unregister .godarkup extension with the editor
	var editor_settings := get_editor_interface().get_editor_settings()
	var filters := editor_settings.get_setting("docks/filesystem/textfile_extensions")
	if filters == null:
		printerr('Filter not found when registering extension!')
	if filters.contains("godarkup"):
		var index: int = filters.find("godarkup") - 1
		var len := 8
		filters = filters.substr(0, index) + filters.substr(index + len + 1)
		editor_settings.set_setting("docks/filesystem/textfile_extensions", filters)
		print("[GodArkup] Unregistered .godarkup as visible file type.")

func _on_generate_button_pressed() -> void:
	var selected := get_editor_interface().get_selected_paths()
	for path in selected:
		if path.ends_with(".godarkup"):
			_generate_scene(path)
			return
	printerr("[GodArkup] No .godarkup file selected in FileSystem.")
	
