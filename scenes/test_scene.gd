extends Node

func _ready():
	# Load your demo godarkup UI and add it as a child
	var markupUI = GodArkup.new()
	var ui = markupUI.load_markup("res://addons/godarkup/demos/demo_properties.godarkup", self)
	if ui:
		add_child(ui)
	else:
		push_error("Failed to build UI from godarkup.")

func handle_click():
	print("Button clicked")
