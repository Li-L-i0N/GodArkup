extends Node
class_name PlayerWithInventory

@export var ExternalIdUiMarkup: String = ""

signal inventory_size_changed(new_size)

@export var inventory_size: int = 5:
	set(value):
		var old_size = inventory_size
		inventory_size = max(0, value)
		if inventory_size != old_size:
			inventory_size_changed.emit(inventory_size)

func _ready():
	# Emit initial signal to set up UI
	inventory_size_changed.emit(inventory_size)

func add_item():
	inventory_size += 1
	print("Inventory size increased to: ", inventory_size)

func remove_item():
	inventory_size -= 1
	print("Inventory size decreased to: ", inventory_size)
