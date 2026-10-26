extends Node
class_name StateMachine

enum PrimaryState {
	GROUNDED,
	AIRBORNE,
}

var _player: CharacterBody3D
var _state: int = PrimaryState.GROUNDED


func setup(player: CharacterBody3D) -> void:
	if player == null:
		push_error("StateMachine: player reference is null.")
		return
	_player = player


func get_state() -> int:
	return _state


func request_transition(new_state: int) -> bool:
	if new_state != PrimaryState.GROUNDED and new_state != PrimaryState.AIRBORNE:
		return false
	_state = new_state
	return true
