extends Node
class_name BasicLocomotion

## Required baseline locomotion module.
## Session 3: shell only — setup + validate + activate/deactivate.
## No movement, no input, no velocity. Session 4 fills the body.

var _player: CharacterBody3D
var _active: bool = false


func setup(player: CharacterBody3D) -> void:
	if player == null:
		push_error("BasicLocomotion: player reference is null.")
		return
	_player = player


func validate_dependencies() -> bool:
	if _player == null:
		push_error("BasicLocomotion: cannot validate without player reference.")
		return false
	return true


func activate() -> void:
	_active = true


func deactivate(_reason: String = "") -> void:
	_active = false


func is_active() -> bool:
	return _active
