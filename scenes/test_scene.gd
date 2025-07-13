extends Node

@export var ExternalIdUiMarkup: String = "test_scene"


func _ready():
	# Load your demo godarkup UI and add it as a child
	var markupUI = GodArkup.new()
	var ui = markupUI.load_markup("res://demos/demo_inventory.godarkup", self)
	if ui:
		add_child(ui)
	else:
		push_error("Failed to build UI from godarkup.")


func handle_click():
	print("Button clicked")


func handle_accept():
	print("Button accept clicked")


func handle_cancel():
	print("Button cancel clicked")
