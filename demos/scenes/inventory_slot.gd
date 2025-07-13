@tool
extends HBoxContainer
class_name InventorySlot

# Get child nodes safely when they are ready
@onready var _icon_rect: TextureRect = $TextureRect
@onready var _label_node: Label = $Label

# --- Public Properties with Setters ---

@export var index: int = -1

# Backing field for the icon property
var _icon: Texture
@export var icon: Texture:
	get: return _icon
	set(value):
		_icon = value
		# If the node is ready, update the child immediately.
		if is_node_ready():
			_icon_rect.texture = _icon

# Backing field for the label_text property
var _label_text: String = ""
@export var label_text: String:
	get: return _label_text
	set(value):
		_label_text = value
		# If the node is ready, update the child immediately.
		if is_node_ready():
			_label_node.text = _label_text

# --- Godot Lifecycle Functions ---

# This function is called when the node and its children have entered the scene tree.
func _ready() -> void:
	# Apply properties that were set *before* this node was ready.
	# The @onready variables are now guaranteed to be assigned.
	_icon_rect.texture = _icon
	_label_node.text = _label_text
