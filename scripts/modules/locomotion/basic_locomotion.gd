## Required baseline: converts input intent into a velocity request with gravity, ground jump, jump cut, air steer, and stance management (crouch/prone).
extends Node
class_name BasicLocomotion

## Ground walking speed in meters per second.
@export var walk_speed: float = 5.0

## Horizontal speed while crouched, in meters per second.
@export var crouch_speed: float = 3.0

## Horizontal speed while prone, in meters per second.
@export var prone_speed: float = 1.5

## Horizontal lerp rate (per second) applied when matching requested velocity.
@export var acceleration: float = 10.0

## Downward acceleration while airborne, in meters per second squared.
@export var gravity: float = 20.0

## Terminal fall speed cap, in meters per second (negative direction).
@export var max_fall_speed: float = 50.0

## Upward velocity applied on a ground jump, in meters per second.
@export var jump_velocity: float = 6.0

## Grace window (seconds) after walking off a ledge during which a jump still works.
@export var coyote_time: float = 0.1

## Window (seconds) during which a jump press is remembered and fires on landing.
@export var jump_buffer_time: float = 0.15

## Multiplier applied to upward velocity when jump is released mid-rise.
@export var jump_cut_scale: float = 0.45

## Air steer: degrees of horizontal velocity rotation per mouse pixel, while airborne and moving.
@export var air_steer_strength: float = 0.3

## Minimum horizontal speed (m/s) required for air steer to apply.
@export var air_steer_min_speed: float = 0.5

## Safety cap: maximum degrees of air-steer rotation per physics tick.
@export var air_steer_max_degrees_per_tick: float = 10.0

## Crouch mode. 0 = Hold (crouch while held), 1 = Toggle (press to switch).
@export_enum("Hold", "Toggle") var crouch_mode: int = 0

## Prone mode. 0 = Hold (prone while held), 1 = Toggle (press to switch).
@export_enum("Hold", "Toggle") var prone_mode: int = 1

## When true, pressing jump while crouched or prone attempts to stand up first.
## This is standard FPS behavior: a jump from a low stance clears the stance if headroom allows.
@export var jump_clears_stance: bool = true

var _player: Player
var _input_router: InputRouter
var _movement_authority: MovementAuthority
var _active: bool = false

var _peak_fall_speed: float = 0.0
var _last_landing_speed: float = 0.0
var _was_on_floor: bool = true
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _desired_crouched: bool = false
var _desired_prone: bool = false


func setup(player: Player) -> void:
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
	_handle_stance()

	var intent := _input_router.get_move_intent()
	var current := _movement_authority.get_current_velocity()

	var desired_xz := _compute_desired_horizontal(intent, delta, current)
	var desired_y := _compute_desired_vertical(current.y, delta)

	if _can_jump() and _wants_to_jump() and not _player.is_prone():
		desired_y = jump_velocity
		_coyote_timer = 0.0
		_jump_buffer_timer = 0.0

	if _input_router.get_jump_just_released() and desired_y > 0.0:
		desired_y *= jump_cut_scale

	_update_fall_tracking(desired_y)

	_movement_authority.submit_velocity_request(
		"basic_locomotion",
		Vector3(desired_xz.x, desired_y, desired_xz.z)
	)


func _handle_stance() -> void:
	# --- Jump clears stance ---
	# Pressing jump while crouched or prone attempts to stand. If headroom blocks,
	# the attempt is retried every tick until it succeeds or the player releases.
	if jump_clears_stance and _input_router.get_jump_just_pressed():
		_desired_crouched = false
		_desired_prone = false

	# --- Crouch desire ---
	if crouch_mode == 0:  # HOLD
		_desired_crouched = _input_router.get_crouch_held()
	else:  # TOGGLE
		if _input_router.get_crouch_just_pressed():
			_desired_crouched = not _desired_crouched

	# --- Prone desire ---
	if prone_mode == 0:  # HOLD
		_desired_prone = _input_router.get_prone_held()
	else:  # TOGGLE
		if _input_router.get_prone_just_pressed():
			_desired_prone = not _desired_prone

	# --- Apply stance (priority: prone > crouch > stand) ---
	if _desired_prone and not _player.is_prone():
		_player.prone()
	elif not _desired_prone and _player.is_prone():
		_player.try_unprone()
	elif not _player.is_prone():
		if _desired_crouched and not _player.is_crouched():
			_player.crouch()
		elif not _desired_crouched and _player.is_crouched():
			_player.try_stand()


func _update_jump_timers(delta: float) -> void:
	if _player.is_on_floor():
		_coyote_timer = coyote_time
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)

	if _input_router.get_jump_just_pressed():
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)


func _can_jump() -> bool:
	return _player.is_on_floor() or _coyote_timer > 0.0


func _wants_to_jump() -> bool:
	return _jump_buffer_timer > 0.0 or _input_router.get_jump_just_pressed()


func _compute_desired_horizontal(intent: Vector2, delta: float, current: Vector3) -> Vector3:
	var speed := walk_speed
	if _player.is_prone():
		speed = prone_speed
	elif _player.is_crouched():
		speed = crouch_speed

	var target_world := Vector3(intent.x, 0.0, intent.y) * speed
	var current_horizontal := Vector3(current.x, 0.0, current.z)
	var t := clampf(acceleration * delta, 0.0, 1.0)
	var result := current_horizontal.lerp(target_world, t)

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
			result = result.rotated(Vector3.UP, -deg_to_rad(degrees))

	return result


func _compute_desired_vertical(current_y: float, delta: float) -> float:
	if _player.is_on_floor():
		return maxf(current_y, 0.0)
	return maxf(current_y - gravity * delta, -max_fall_speed)


func _update_fall_tracking(about_to_apply_y: float) -> void:
	var on_floor := _player.is_on_floor()
	if not on_floor:
		var fall_speed := maxf(-about_to_apply_y, 0.0)
		_peak_fall_speed = maxf(_peak_fall_speed, fall_speed)
	if on_floor and not _was_on_floor:
		_last_landing_speed = _peak_fall_speed
		_peak_fall_speed = 0.0
	_was_on_floor = on_floor


func get_peak_fall_speed() -> float:
	return _peak_fall_speed


func get_last_landing_speed() -> float:
	return _last_landing_speed
