extends Node
class_name Player

# Example script of what this is what the UI will match against
@export var ExternalIdUiMarkup: String = ""

signal health_changed(new_health: float)
signal ammo_updated(count: int)

var max_slots := 5

var max_health := 350.0
var health := 275.0:
	set(value): 
		health = clamp(value, 0.0, max_health)
		emit_signal("health_changed", health)
		
var ammo := 30:
	set(value): 
		ammo = max(value, 0)
		emit_signal("ammo_updated", ammo)

func _enter_tree() -> void:
	health = health + 5

func _process(delta: float):
	if Input.is_action_just_pressed("ui_accept"):  # e.g., Enter key or "A" on gamepad
		apply_damage(10)
		print("ui_accept pressed  ")

func apply_damage(amount: int) -> void:
	health -= amount
	print("Player took damage! Health is now: ", health)
