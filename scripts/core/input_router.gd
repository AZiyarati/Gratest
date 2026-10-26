extends Node
class_name InputRouter

var _player: CharacterBody3D


func setup(player: CharacterBody3D) -> void:
	if player == null:
		push_error("InputRouter: player reference is null.")
		return
	_player = player
