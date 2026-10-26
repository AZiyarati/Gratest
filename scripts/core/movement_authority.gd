extends Node
class_name MovementAuthority

var _player: CharacterBody3D


func setup(player: CharacterBody3D) -> void:
	if player == null:
		push_error("MovementAuthority: player reference is null.")
		return
	_player = player


func get_player() -> CharacterBody3D:
	return _player
