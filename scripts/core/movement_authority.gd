extends Node
class_name MovementAuthority

var _player: CharacterBody3D
var _pending_horizontal: Vector3 = Vector3.ZERO


func setup(player: CharacterBody3D) -> void:
	if player == null:
		push_error("MovementAuthority: player reference is null.")
		return
	_player = player


## Called by an ability to submit its horizontal velocity contribution for this tick.
## One-shot: consumed by the next tick() and cleared.
func submit_velocity_request(_source: String, horizontal_velocity: Vector3) -> void:
	_pending_horizontal = horizontal_velocity


## Consumes the pending request, resolves final velocity, executes move_and_slide().
## Session 4: vertical velocity is preserved (no gravity yet).
func tick(_delta: float) -> void:
	if _player == null:
		return
	var horizontal := _pending_horizontal
	_pending_horizontal = Vector3.ZERO

	_player.velocity = Vector3(horizontal.x, _player.velocity.y, horizontal.z)
	_player.move_and_slide()


func get_current_velocity() -> Vector3:
	if _player == null:
		return Vector3.ZERO
	return _player.velocity


func get_player() -> CharacterBody3D:
	return _player
