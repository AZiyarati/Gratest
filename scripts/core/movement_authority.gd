## The single authority that writes Player.velocity and calls move_and_slide().
extends Node
class_name MovementAuthority

var _player: CharacterBody3D
var _pending_velocity: Vector3 = Vector3.ZERO


func setup(player: CharacterBody3D) -> void:
	if player == null:
		push_error("MovementAuthority: player reference is null.")
		return
	_player = player


## Called by an ability to submit its full 3D velocity contribution for this tick.
## One-shot: consumed by the next tick() and cleared to zero.
func submit_velocity_request(_source: String, velocity: Vector3) -> void:
	_pending_velocity = velocity


## Resolves the final velocity (zero if no request was made this tick),
## writes it once, and executes move_and_slide().
func tick(_delta: float) -> void:
	if _player == null:
		return
	var v := _pending_velocity
	_pending_velocity = Vector3.ZERO
	_player.velocity = v
	_player.move_and_slide()


func get_current_velocity() -> Vector3:
	if _player == null:
		return Vector3.ZERO
	return _player.velocity


func get_player() -> CharacterBody3D:
	return _player
