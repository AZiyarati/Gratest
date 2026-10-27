extends Node
class_name BasicLocomotion

## Required baseline locomotion module.
## Session 4: computes a horizontal velocity contribution from input intent
## and submits it to MovementAuthority. No gravity, jump, stance, or feel yet.

## Ground walking speed in meters per second.
@export var walk_speed: float = 5.0

## Lerp rate (per second) applied when matching the requested horizontal velocity.
@export var acceleration: float = 10.0

var _player: CharacterBody3D
var _input_router: InputRouter
var _movement_authority: MovementAuthority
var _active: bool = false


func setup(player: CharacterBody3D) -> void:
	if player == null:
		push_error("BasicLocomotion: player reference is null.")
		return
	_player = player


func set_collaborators(ir: InputRouter, ma: MovementAuthority) -> void:
	_input_router = ir
	_movement_authority = ma


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


func tick(delta: float) -> void:
	if not _active or _player == null or _input_router == null or _movement_authority == null:
		return
	var intent := _input_router.get_move_intent()
	var desired := _compute_desired_horizontal(intent, delta)
	_movement_authority.submit_velocity_request("basic_locomotion", desired)


func _compute_desired_horizontal(intent: Vector2, delta: float) -> Vector3:
	# Input.get_vector: +x = right, -y = forward.
	# World mapping: forward = -Z, right = +X.
	var target_world := Vector3(intent.x, 0.0, intent.y) * walk_speed

	var current_horizontal := Vector3.ZERO
	var v := _movement_authority.get_current_velocity()
	current_horizontal = Vector3(v.x, 0.0, v.z)

	var t := clampf(acceleration * delta, 0.0, 1.0)
	return current_horizontal.lerp(target_world, t)
