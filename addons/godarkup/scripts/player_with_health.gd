extends Node

# The External ID used by GodArkup to find this node for data binding.
@export var ExternalIdUiMarkup: String = ""

signal health_changed(new_health: int)

var health: int = 100:
	set(value):
		health = clamp(value, 0, 100)
		emit_signal("health_changed", health)

func _ready():
	# Example of how to change health over time for the demo.
	var tween = create_tween().set_loops()
	tween.tween_property(self, "health", 0, 5.0).set_delay(1.0)
	tween.tween_property(self, "health", 100, 5.0).set_delay(1.0)
