## Required baseline: converts input intent into a velocity request with gravity and a ground jump.
extends Node
class_name BasicLocomotion

## Ground walking speed in meters per second.
@export var walk_speed: float = 5.0

## Horizontal lerp rate (per second) applied when matching requested velocity.
@export var acceleration: float = 10.0

## Downward acceleration while airborne, in meters per second squared.
## Rate at which downward speed increases (rate, not limit).
@export var gravity: float = 20.0

## Terminal fall speed cap, in meters per second (negative direction).
## Upper bound on downward speed magnitude (limit, not rate). Prevents tunneling during long falls.
@export var max_fall_speed: float = 50.0

## Upward velocity applied on a ground jump, in meters per second.
@export var jump_velocity: float = 6.0

var _player: CharacterBody3D
var _input_router: InputRouter
var _movement_authority: MovementAuthority
var _active: bool = false

## Maximum downward speed (positive magnitude) observed during the current airborne session.
var _peak_fall_speed: float = 0.0

## Impact speed recorded at the most recent landing (positive magnitude).
var _last_landing_speed: float = 0.0

## Whether the player was on the floor in the previous tick; used to detect the landing edge.
var _was_on_floor: bool = true


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
	var current := _movement_authority.get_current_velocity()

	var desired_xz := _compute_desired_horizontal(intent, delta, current)
	var desired_y := _compute_desired_vertical(current.y, delta)

	# Ground jump: consume this-tick jump press while grounded.
	if _player.is_on_floor() and _input_router.get_jump_just_pressed():
		desired_y = jump_velocity

	# Track fall speed / detect landing using the velocity we are about to apply.
	_update_fall_tracking(desired_y)

	_movement_authority.submit_velocity_request(
		"basic_locomotion",
		Vector3(desired_xz.x, desired_y, desired_xz.z)
	)


func _compute_desired_horizontal(intent: Vector2, delta: float, current: Vector3) -> Vector3:
	# Input.get_vector: +x = right, -y = forward.
	# World mapping: forward = -Z, right = +X.
	var target_world := Vector3(intent.x, 0.0, intent.y) * walk_speed
	var current_horizontal := Vector3(current.x, 0.0, current.z)
	var t := clampf(acceleration * delta, 0.0, 1.0)
	return current_horizontal.lerp(target_world, t)


func _compute_desired_vertical(current_y: float, delta: float) -> float:
	if _player.is_on_floor():
		# Grounded: suppress falling velocity; preserve positive (jump) velocity.
		return maxf(current_y, 0.0)
	# Airborne: apply gravity, clamp to terminal velocity.
	return maxf(current_y - gravity * delta, -max_fall_speed)


## Tracks peak fall speed while airborne and records impact speed on the landing edge.
## Uses the velocity we're about to submit (not the last applied velocity) so the
## recorded impact matches the frame that actually leaves the airborne state.
func _update_fall_tracking(about_to_apply_y: float) -> void:
	var on_floor := _player.is_on_floor()

	if not on_floor:
		var fall_speed := maxf(-about_to_apply_y, 0.0)
		_peak_fall_speed = maxf(_peak_fall_speed, fall_speed)

	if on_floor and not _was_on_floor:
		_last_landing_speed = _peak_fall_speed
		_peak_fall_speed = 0.0

	_was_on_floor = on_floor


## Peak downward speed (positive magnitude) during the current airborne session.
func get_peak_fall_speed() -> float:
	return _peak_fall_speed


## Impact speed (positive magnitude) recorded at the most recent landing.
func get_last_landing_speed() -> float:
	return _last_landing_speed
