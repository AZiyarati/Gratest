## Required baseline: converts input intent into a velocity request with gravity, ground jump, variable jump cut, and air steer.
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

## Grace window (seconds) after walking off a ledge during which a jump still works.
## 0.0 disables coyote time (jump only from actual ground contact).
@export var coyote_time: float = 0.1

## Window (seconds) during which a jump press is remembered and fires on landing.
## 0.0 disables buffering (jump must be pressed on the exact landing frame).
@export var jump_buffer_time: float = 0.15

## Multiplier applied to upward velocity when jump is released mid-rise.
## 1.0 disables variable jump height (jump peak is independent of hold duration).
## 0.45 gives a tap-jump peak of roughly 20% of a full-held jump (Mario-style).
@export var jump_cut_scale: float = 0.45

## Air steer: degrees of horizontal velocity rotation per mouse pixel, while airborne and moving.
## 0.0 disables air steer. Recommended 0.2–0.5. Has no effect while grounded or while nearly stationary.
@export var air_steer_strength: float = 0.3

## Minimum horizontal speed (m/s) required for air steer to apply.
## Below this threshold, mouse motion does not rotate velocity (no momentum to redirect).
@export var air_steer_min_speed: float = 0.5

## Safety cap: maximum degrees of air-steer rotation per physics tick.
## Prevents very large mouse deltas (macros, extreme sensitivity) from causing an instant spin.
@export var air_steer_max_degrees_per_tick: float = 10.0

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

## Remaining coyote grace time; set to coyote_time while on floor, counts down while airborne.
var _coyote_timer: float = 0.0

## Remaining jump buffer time; set to jump_buffer_time when jump is pressed, counts down.
var _jump_buffer_timer: float = 0.0


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
	_update_jump_timers(delta)

	var intent := _input_router.get_move_intent()
	var current := _movement_authority.get_current_velocity()

	var desired_xz := _compute_desired_horizontal(intent, delta, current)
	var desired_y := _compute_desired_vertical(current.y, delta)

	# Jump: fires when the buffered intent meets ground contact or coyote grace.
	if _can_jump() and _wants_to_jump():
		desired_y = jump_velocity
		_coyote_timer = 0.0
		_jump_buffer_timer = 0.0

	# Variable jump cut: release jump mid-rise to shorten the jump arc.
	# Only applies while rising (desired_y > 0); falling frames are untouched.
	if _input_router.get_jump_just_released() and desired_y > 0.0:
		desired_y *= jump_cut_scale

	# Track fall speed / detect landing using the velocity we are about to apply.
	_update_fall_tracking(desired_y)

	_movement_authority.submit_velocity_request(
		"basic_locomotion",
		Vector3(desired_xz.x, desired_y, desired_xz.z)
	)


func _update_jump_timers(delta: float) -> void:
	if _player.is_on_floor():
		_coyote_timer = coyote_time
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)

	if _input_router.get_jump_just_pressed():
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)


## True if a jump is allowed right now: on the floor, or within coyote grace.
func _can_jump() -> bool:
	return _player.is_on_floor() or _coyote_timer > 0.0


## True if the player has requested a jump recently enough to matter.
## The "or just_pressed" branch handles the case where jump_buffer_time is 0.
func _wants_to_jump() -> bool:
	return _jump_buffer_timer > 0.0 or _input_router.get_jump_just_pressed()


func _compute_desired_horizontal(intent: Vector2, delta: float, current: Vector3) -> Vector3:
	# Input.get_vector: +x = right, -y = forward.
	# World mapping: forward = -Z, right = +X.
	var target_world := Vector3(intent.x, 0.0, intent.y) * walk_speed
	var current_horizontal := Vector3(current.x, 0.0, current.z)
	var t := clampf(acceleration * delta, 0.0, 1.0)
	var result := current_horizontal.lerp(target_world, t)

	# Air steer: rotate horizontal velocity based on mouse yaw while airborne and moving.
	# Rotation preserves momentum (no free energy) — the impulse comes from existing speed.
	# Requires horizontal momentum to matter, so idle jumps in place cannot be steered.
	if air_steer_strength > 0.0 \
		and not _player.is_on_floor() \
		and result.length() > air_steer_min_speed:
		var mouse_dx := _input_router.get_mouse_delta_x()
		if mouse_dx != 0.0:
			var degrees := clampf(
				mouse_dx * air_steer_strength,
				-air_steer_max_degrees_per_tick,
				air_steer_max_degrees_per_tick
			)
			# Negative rotation: mouse-right (positive dx) turns velocity clockwise (right) when viewed from above.
			result = result.rotated(Vector3.UP, -deg_to_rad(degrees))

	return result


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
