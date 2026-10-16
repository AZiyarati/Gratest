## Walk + sprint + ground jump + double jump + variable jump + coyote time
## + jump buffering + crouch + prone + slide + crouch-sprint + bunny hop
## + air mouse steer locomotion component.
##
## Reads every input and surface fact from the SensorHub. Writes the
## horizontal part of player.velocity, the jump impulses, stance state,
## slide state, crouch-sprint speed, bunny-hop air strafe, air mouse
## steer, and a few player-level tracking fields. Never casts rays,
## never touches camera nodes directly.
class_name MovementComponent
extends Node

# -----------------------------------------------------------------------------
# Exports
# -----------------------------------------------------------------------------

@export_group("Features — Locomotion")
## Master toggle. When false, update() does nothing.
@export var enabled: bool = true
## Allow sprinting on the ground when the sprint action is held.
@export var enable_sprinting: bool = true
## Allow a single ground jump.
@export var enable_jumping: bool = true
## Allow crouching (collision swap + head drop).
@export var enable_crouching: bool = true
## Allow prone (lowest stance).
@export var enable_prone: bool = true
## Allow sliding (sprint + crouch on ground).
@export var enable_sliding: bool = true
## Toggle: hold sprint while crouched to move at sprint speed.
@export var enable_crouch_sprint: bool = true

@export_group("Features — Advanced")
## Allow a second, mid-air jump after a ground jump.
@export var enable_double_jump: bool = true
## Master toggle for bunny hop.
@export var enable_bunny_hop: bool = false
## Allow auto-hop when holding jump through a landing.
@export var bhop_auto_hop: bool = true
## Allow Quake-style air strafe (WASD + mouse turning).
@export var bhop_air_strafe: bool = true
## While actively bunny hopping, mouse yaw rotates the camera only
## (body keeps its momentum direction; folded back on landing/disable).
@export var bhop_camera_strafe: bool = true

@export_group("Features — Variable Jump")
## Allow jump height to scale with how long the jump action is held.
@export var enable_variable_jump: bool = true
## Minimum upward velocity after a jump cut.
@export var min_jump_velocity: float = 2.0
## Fraction of current upward velocity kept when the jump is cut.
@export var jump_cut_scale: float = 0.45

@export_group("Features — Jump Feel")
## Allow a ground jump shortly after walking off a ledge.
@export var enable_coyote_time: bool = true
## Grace window (seconds) after leaving the ground during which a jump still fires.
@export var coyote_time: float = 0.15
## Remember an early jump press and fire it on landing.
@export var enable_jump_buffer: bool = true
## How long (seconds) an early jump press is remembered.
@export var jump_buffer_time: float = 0.15

@export_group("Speeds — Ground")
## Target horizontal speed while walking.
@export var walk_speed: float = 5.0
## Target horizontal speed while sprinting.
@export var sprint_speed: float = 10.0
## Target horizontal speed while crouching.
@export var crouch_speed: float = 3.0
## Target horizontal speed while prone.
@export var prone_speed: float = 1.5

@export_group("Speeds — Slide")
## Locked horizontal speed during a slide.
@export var slide_speed: float = 10.0
## How long a slide lasts before auto-ending.
@export var slide_duration: float = 1.0
## Slide end rule. Timer ends after slide_duration; Hold also ends on crouch release.
@export_enum("Timer", "Hold") var slide_end_mode: int = 0
## Minimum horizontal speed required to start a slide. Prevents
## sliding from standing still.
@export var slide_min_speed: float = 3.0

@export_group("Speeds — Jump")
## Upward velocity applied on a ground jump.
@export var jump_velocity: float = 5.0
## Upward velocity applied on the air (second) jump.
@export var double_jump_velocity: float = 5.0
## Maximum number of jumps per airtime.
@export var max_jumps: int = 2

@export_group("Bunny Hop")
## Air-acceleration constant (Quake units). Higher = faster ramp
## toward wish_speed. CS uses ~10; 4 is a slow ramp; 15+ is snappy.
@export var bhop_air_accel: float = 4.0
## Target speed along the wish direction for air acceleration.
@export var bhop_wish_speed: float = 5.0
## Cap on total horizontal speed from air strafe.
@export var bhop_max_speed: float = 20.0
## Window after landing during which holding jump auto-bhops.
@export var bhop_landing_window: float = 0.15

@export_group("Air Mouse Steer")
## Enable steering by turning the mouse while airborne.
@export var enable_air_mouse_steer: bool = false
## Steering acceleration per rad of yaw change.
@export var air_mouse_steer_strength: float = 6.0
## Max horizontal speed that mouse-steer can accelerate to.
@export var air_mouse_steer_max_speed: float = 20.0
## Low-pass smoothing on the mouse-yaw rate (0 = raw, 0.9 = very smooth).
@export_range(0.0, 0.95, 0.01) var air_mouse_steer_smoothing: float = 0.5

@export_group("Stance")
## Crouch input style.
@export_enum("Hold", "Toggle") var crouch_mode: int = 0
## Prone entry style. Hold = hold crouch past prone_hold_time.
## Toggle = double-tap crouch (from standing OR crouched).
@export_enum("Hold", "Toggle") var prone_mode: int = 0
## Maximum time between two crouch presses (toggle double-tap) to enter prone.
@export var double_tap_time: float = 0.3
## How long to hold crouch (hold mode) before entering prone.
@export var prone_hold_time: float = 0.5
## Space stands up from crouch (Toggle) or prone (any mode).
@export var space_stands: bool = true
## Vertical clearance required above the feet to stand.
@export var stand_clearance: float = 1.7
## Vertical clearance required above the feet to crouch.
@export var crouch_clearance: float = 1.0

@export_group("Slide")
## Require sprint to be held to start a slide.
@export var slide_requires_sprint: bool = true
## Require movement input to start a slide.
@export var slide_requires_input: bool = true

@export_group("Input")
## Input action used to trigger sprinting.
@export var sprint_action: String = "sprint"
## Input action used to trigger a jump (also stands from crouch/prone).
@export var jump_action: String = "ui_accept"
## Input action used to trigger crouch / prone / slide.
@export var crouch_action: String = "crouch"

@export_group("Feel")
## How fast horizontal velocity approaches the target on the ground.
@export var lerp_speed: float = 10.0
## How fast horizontal velocity approaches the target in the air.
@export var air_lerp_speed: float = 3.0
## Deceleration applied when no input and grounded.
@export var idle_deceleration: float = 30.0
## Local Y offset applied to the head node while crouched.
@export var crouch_depth: float = -0.5
## Local Y offset applied to the head node while prone.
@export var prone_depth: float = -0.85
## How fast the head lerps between stance heights.
@export var crouch_lerp_speed: float = 10.0

# -----------------------------------------------------------------------------
# Public state
# -----------------------------------------------------------------------------

## True while the player has movement input and is on the floor.
var walking: bool = false
## True while sprinting on the ground with input.
var sprinting: bool = false
## True while crouched.
var crouching: bool = false
## True while prone.
var prone: bool = false
## True while sliding.
var sliding: bool = false
## 0 = grounded/no jump used, 1 = ground jump used, 2 = double jump used.
var jumps_made: int = 0
## Length of the horizontal velocity this frame.
var current_speed: float = 0.0
## Normalized horizontal movement direction (ZERO when idle).
var direction: Vector3 = Vector3.ZERO

# -----------------------------------------------------------------------------
# Cached refs
# -----------------------------------------------------------------------------

var _player: CharacterBody3D
var _sensors: SensorHub
var _head: Node3D
var _neck: Node3D
var _standing_shape: CollisionShape3D
var _crouching_shape: CollisionShape3D
var _prone_shape: CollisionShape3D

# -----------------------------------------------------------------------------
# Private state
# -----------------------------------------------------------------------------

var _jump_cut_done: bool = false
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _crouch_toggled: bool = false
var _last_crouch_press: float = -10.0
var _crouch_hold_time: float = 0.0
var _jump_consumed_this_frame: bool = false
var _slide_timer: float = 0.0
var _slide_direction: Vector3 = Vector3.ZERO
var _can_slide: bool = true
var _bhop_landing_timer: float = 0.0
var _was_on_floor: bool = true
var _last_yaw: float = 0.0
var _bhop_chain_active: bool = false
var _air_mouse_steer_smoothed_rate: float = 0.0
## Peak downward speed (positive value) observed across the current airtime.
## Reset on each landing. Used so _on_land() has a valid fall speed even
## though move_and_slide() zeroes velocity.y on the impact frame.
var _fall_speed_peak: float = 0.0

# -----------------------------------------------------------------------------
# Setup
# -----------------------------------------------------------------------------

## Cache the owning player and its SensorHub.
func setup(p: CharacterBody3D) -> void:
	_player = p
	_sensors = p.sensors
	_head = p.head
	_neck = p.neck
	_standing_shape = p.get_node_or_null("standing_collision_shape") as CollisionShape3D
	_crouching_shape = p.get_node_or_null("crouching_collision_shape") as CollisionShape3D
	_prone_shape = p.get_node_or_null("prone_collision_shape") as CollisionShape3D
	_last_yaw = _effective_yaw()
	_was_on_floor = p.is_on_floor()
	_fall_speed_peak = 0.0

# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

## Attempt a mid-air double jump. Returns true when the jump fired.
func try_double_jump() -> bool:
	if not enable_jumping or not enable_double_jump:
		return false
	if prone:
		return false
	if _player.is_on_floor():
		return false
	if jumps_made >= max_jumps:
		return false
	_player.velocity.y = double_jump_velocity
	jumps_made += 1
	_jump_cut_done = false
	_player.set("jumps_made", jumps_made)
	if _player.has_method("play_jump"):
		_player.play_jump()
	return true

## Force the player to the standing stance. Used by body-owning
## components (wall-run, ladder, etc.) to clear any lingering crouch
## or prone state on entry so it can't interact with their physics.
## Does not touch `sliding` — that is a locomotion state, not a
## stance, and belongs to whichever component owns the body.
func force_stand() -> void:
	if not crouching and not prone:
		return
	crouching = false
	prone = false
	_crouch_toggled = false
	_crouch_hold_time = 0.0
	_apply_stance_shapes()
	_player.set("crouching", false)
	_player.set("prone", false)

## Prevent variable-jump from cutting any future upward impulse this airtime.
func lock_jump_cut() -> void:
	_jump_cut_done = true

## Raw WASD input as Vector2. Mirrors SensorHub.input_dir.
func wish_input() -> Vector2:
	return Input.get_vector("left", "right", "forward", "backward")

## True while bhop camera-strafe should take over mouse yaw: an active
## bhop chain (auto-hop fired through a landing) and airborne. A single
## jump from idle does NOT activate this — only chained hops do.
func is_bhop_camera_strafing() -> bool:
	if not enable_bunny_hop or not bhop_camera_strafe:
		return false
	if _player == null:
		return false
	if not _bhop_chain_active:
		return false
	return not _player.is_on_floor()

# -----------------------------------------------------------------------------
# Internal — landing detection
# -----------------------------------------------------------------------------

func _on_land() -> void:
	# When FallBehaviorComponent is present on the Player, it owns all
	# landing visuals (hard landing / roll / slap). Skip our simple
	# fallback so we don't double-fire.
	var fb: Node = _player.get_node_or_null("FallBehaviorComponent")
	if fb != null and fb.has_method("is_active"):
		return

	if _player == null:
		return
	# Use the peak downward speed recorded across the airtime. Calling
	# absf(_player.last_velocity.y) here would return 0 because
	# move_and_slide() zeroes velocity.y on the impact frame.
	var v: float = _fall_speed_peak
	_fall_speed_peak = 0.0

	if v >= 10.0:
		if _player.has_method("play_hard_landing"):
			_player.play_hard_landing()
	elif v >= 4.0:
		if _player.has_method("play_landing"):
			_player.play_landing()
	# Else: soft landing, no camera motion.

# -----------------------------------------------------------------------------
# Internal — variable jump
# -----------------------------------------------------------------------------

func _handle_variable_jump() -> void:
	if prone:
		return
	if not enable_variable_jump or _jump_cut_done:
		return
	if _player.is_on_floor():
		return
	if _player.velocity.y <= 0.0:
		_jump_cut_done = true
		return
	if Input.is_action_pressed(jump_action):
		return
	var cut: float = maxf(_player.velocity.y * jump_cut_scale, min_jump_velocity)
	_player.velocity.y = cut
	_jump_cut_done = true

# -----------------------------------------------------------------------------
# Internal — bunny hop
# -----------------------------------------------------------------------------

func _apply_bhop_air(delta: float) -> void:
	if not enable_bunny_hop or not bhop_air_strafe:
		return
	var input_dir: Vector2 = Input.get_vector(
		"left", "right", "forward", "backward")
	if input_dir == Vector2.ZERO:
		return

	# Build wish direction from EFFECTIVE VIEW YAW (body + neck),
	# NOT the body. In bhop camera-strafe the body is frozen while
	# the mouse rotates the neck, so this is the only yaw that
	# actually tracks the player's look direction.
	var yaw: float = _player.rotation.y
	if _neck != null:
		yaw += _neck.rotation.y
	var yaw_basis := Basis(Vector3.UP, yaw)
	var wish_dir: Vector3 = yaw_basis.x * input_dir.x \
		+ yaw_basis.z * input_dir.y
	wish_dir.y = 0.0
	if wish_dir.length_squared() < 0.0001:
		return
	wish_dir = wish_dir.normalized()

	var vel := Vector3(_player.velocity.x, 0.0, _player.velocity.z)

	# Quake / Counter-Strike air acceleration.
	var projection: float = vel.dot(wish_dir)
	var add_speed: float = bhop_wish_speed - projection
	if add_speed <= 0.0:
		return

	var accel_step: float = bhop_air_accel * bhop_wish_speed * delta
	accel_step = minf(accel_step, add_speed)

	_player.velocity.x += wish_dir.x * accel_step
	_player.velocity.z += wish_dir.z * accel_step

	# Hard cap.
	vel = Vector3(_player.velocity.x, 0.0, _player.velocity.z)
	if vel.length() > bhop_max_speed:
		vel = vel.normalized() * bhop_max_speed
		_player.velocity.x = vel.x
		_player.velocity.z = vel.z

func _apply_bhop_ground_steer(delta: float) -> void:
	if not enable_bunny_hop or not bhop_air_strafe:
		return
	var input_dir: Vector2 = Input.get_vector("left", "right", "forward", "backward")
	if input_dir == Vector2.ZERO:
		return
	var basis: Basis = _player.global_transform.basis
	var wish_dir: Vector3 = basis.x * input_dir.x + basis.z * input_dir.y
	wish_dir.y = 0.0
	if wish_dir.length_squared() < 0.0001:
		return
	wish_dir = wish_dir.normalized()
	var steer: float = 4.0 * delta
	_player.velocity.x += wish_dir.x * steer
	_player.velocity.z += wish_dir.z * steer

func _update_bhop_state(delta: float) -> void:
	if _bhop_landing_timer > 0.0:
		_bhop_landing_timer -= delta
	if not enable_bunny_hop:
		_bhop_landing_timer = 0.0
		_was_on_floor = _player.is_on_floor()
		_bhop_chain_active = false
		return
	var on_floor: bool = _player.is_on_floor()
	if on_floor and not _was_on_floor:
		_bhop_landing_timer = bhop_landing_window
		# Landing without holding jump breaks the bhop chain.
		if not Input.is_action_pressed(jump_action):
			_bhop_chain_active = false
	_was_on_floor = on_floor
	# Chain ends if the player goes into a non-locomotion stance.
	if prone or crouching or sliding:
		_bhop_chain_active = false

# -----------------------------------------------------------------------------
# Internal — air mouse steer
# -----------------------------------------------------------------------------

## Effective view yaw. When bhop camera-strafe is active, view yaw is the
## sum of the body yaw and the neck yaw offset. Otherwise it's just the
## body yaw.
func _effective_yaw() -> float:
	if _player == null:
		return 0.0
	if _neck == null:
		return _player.rotation.y
	return _player.rotation.y + _neck.rotation.y

func _handle_air_mouse_steer(delta: float) -> void:
	var current_yaw: float = _effective_yaw()
	var yaw_delta: float = angle_difference(_last_yaw, current_yaw)
	_last_yaw = current_yaw

	if not enable_air_mouse_steer:
		_air_mouse_steer_smoothed_rate = 0.0
		return
	if _player.is_on_floor():
		_air_mouse_steer_smoothed_rate = 0.0
		return

	# Convert per-frame yaw change into a rate.
	var yaw_rate: float = 0.0
	if delta > 0.0:
		yaw_rate = yaw_delta / delta

	# Low-pass filter to avoid single-frame spikes.
	var alpha: float = 1.0 - clampf(air_mouse_steer_smoothing, 0.0, 0.95)
	_air_mouse_steer_smoothed_rate = lerpf(
		_air_mouse_steer_smoothed_rate, yaw_rate, alpha
	)

	if absf(_air_mouse_steer_smoothed_rate) < 0.01:
		return

	var flat_vel := Vector3(_player.velocity.x, 0.0, _player.velocity.z)
	if flat_vel.length() >= air_mouse_steer_max_speed:
		return

	var right: Vector3 = _sensors.player_right
	# Turning left (positive yaw_rate) → push left (opposite of right).
	var accel: float = -_air_mouse_steer_smoothed_rate * air_mouse_steer_strength
	_player.velocity.x += right.x * accel * delta
	_player.velocity.z += right.z * accel * delta

# -----------------------------------------------------------------------------
# Internal — stance helpers
# -----------------------------------------------------------------------------

func _enter_prone() -> void:
	prone = true
	crouching = false
	sliding = false
	_crouch_toggled = false
	_apply_stance_shapes()

func _exit_prone() -> void:
	prone = false
	crouching = false
	_crouch_toggled = false
	_apply_stance_shapes()

func _apply_stance_shapes() -> void:
	if _standing_shape != null:
		_standing_shape.disabled = true
	if _crouching_shape != null:
		_crouching_shape.disabled = true
	if _prone_shape != null:
		_prone_shape.disabled = true

	if prone and _prone_shape != null:
		_prone_shape.disabled = false
	elif crouching and _crouching_shape != null:
		_crouching_shape.disabled = false
	elif _standing_shape != null:
		_standing_shape.disabled = false

func _lerp_head(delta: float) -> void:
	if _head == null:
		return
	var target_y: float = 0.0
	if prone:
		target_y = prone_depth
	elif crouching or sliding:
		target_y = crouch_depth
	_head.position.y = lerpf(
		_head.position.y, target_y,
		clampf(crouch_lerp_speed * delta, 0.0, 1.0)
	)

func _clearance_above_feet() -> float:
	if _sensors == null or not _sensors.ceiling_hit:
		return INF
	return _sensors.ceiling_point.y - _player.global_position.y

## Pick the tallest stance that fits given the current ceiling clearance.
## Used when a slide ends so we don't clip the standing shape into a low ceiling.
func _resolve_stance_after_slide() -> void:
	var c: float = _clearance_above_feet()
	if c >= stand_clearance:
		prone = false
		crouching = false
	elif c >= crouch_clearance:
		prone = false
		crouching = true
	else:
		prone = true
		crouching = false
	_apply_stance_shapes()

# -----------------------------------------------------------------------------
# Internal — crouch + prone
# -----------------------------------------------------------------------------

func _check_prone_during_slide(delta: float) -> void:
	if not enable_prone:
		return
	var just: bool = Input.is_action_just_pressed(crouch_action)
	var pressed: bool = Input.is_action_pressed(crouch_action)

	if prone_mode == 1:
		if just:
			var now: float = Time.get_ticks_msec() / 1000.0
			var is_double: bool = (now - _last_crouch_press) < double_tap_time
			_last_crouch_press = now
			if is_double:
				_enter_prone()
				_last_crouch_press = -10.0
				_crouch_hold_time = 0.0
	else:
		if pressed:
			_crouch_hold_time += delta
			if _crouch_hold_time >= prone_hold_time:
				_enter_prone()
				_crouch_hold_time = 0.0
		else:
			_crouch_hold_time = 0.0

func _handle_crouch(delta: float) -> void:
	if sliding:
		_check_prone_during_slide(delta)
		_lerp_head(delta)
		return

	if not enable_crouching and not enable_prone:
		if crouching or prone:
			prone = false
			crouching = false
			_crouch_toggled = false
			_apply_stance_shapes()
		_lerp_head(delta)
		return

	var pressed: bool = Input.is_action_pressed(crouch_action)
	var just: bool = Input.is_action_just_pressed(crouch_action)
	var space_just: bool = Input.is_action_just_pressed(jump_action)

	var clearance: float = _clearance_above_feet()
	var can_stand: bool = clearance >= stand_clearance
	var can_crouch: bool = clearance >= crouch_clearance

	if space_stands and space_just and (crouching or prone):
		if prone:
			if can_stand:
				_exit_prone()
			elif can_crouch:
				prone = false
				crouching = true
				_crouch_toggled = (crouch_mode == 1)
				_apply_stance_shapes()
			_jump_consumed_this_frame = true
			_jump_buffer_timer = 0.0
		elif crouching and crouch_mode == 1:
			if can_stand:
				crouching = false
				_crouch_toggled = false
				_apply_stance_shapes()
			_jump_consumed_this_frame = true
			_jump_buffer_timer = 0.0

	if prone:
		if just:
			if can_stand:
				_exit_prone()
			elif can_crouch:
				prone = false
				crouching = true
				_crouch_toggled = (crouch_mode == 1)
				_apply_stance_shapes()
		_lerp_head(delta)
		return

	if enable_prone and prone_mode == 1 and just:
		var now: float = Time.get_ticks_msec() / 1000.0
		var is_double: bool = (now - _last_crouch_press) < double_tap_time
		_last_crouch_press = now
		if is_double:
			if can_crouch:
				_enter_prone()
				_last_crouch_press = -10.0
				_crouch_hold_time = 0.0
				_lerp_head(delta)
				return

	var wants_crouch: bool = false
	if crouch_mode == 0:
		wants_crouch = pressed
	else:
		if just:
			_crouch_toggled = not _crouch_toggled
		wants_crouch = _crouch_toggled

	if not wants_crouch and crouching:
		if _sensors != null and _sensors.ceiling_hit and not can_stand:
			wants_crouch = true
			if crouch_mode == 1:
				_crouch_toggled = true

	if wants_crouch != crouching:
		crouching = wants_crouch
		_apply_stance_shapes()

	if enable_prone and prone_mode == 0:
		if crouching and pressed and _player.is_on_floor():
			_crouch_hold_time += delta
			if _crouch_hold_time >= prone_hold_time:
				_enter_prone()
				_crouch_hold_time = 0.0
				_lerp_head(delta)
				return
		else:
			_crouch_hold_time = 0.0

	_lerp_head(delta)

# -----------------------------------------------------------------------------
# Internal — slide
# -----------------------------------------------------------------------------

func _handle_slide(delta: float) -> void:
	if not enable_sliding:
		sliding = false
		return

	if _can_slide and not sliding and not prone:
		var on_floor: bool = _player.is_on_floor()
		var input_ok: bool = not slide_requires_input \
			or _sensors.input_dir != Vector2.ZERO
		# Slide triggers on a FRESH crouch press while sprint is held.
		# Holding crouch and then pressing sprint must not start a slide;
		# that path lives in crouch-sprint.
		var crouch_just: bool = Input.is_action_just_pressed(crouch_action)
		var sprint_held: bool = Input.is_action_pressed(sprint_action)
		var sprint_ok: bool = not slide_requires_sprint or sprint_held
		# Require the player to actually be moving.
		var h_vel := Vector3(_player.velocity.x, 0.0, _player.velocity.z)
		var has_momentum: bool = h_vel.length() >= slide_min_speed

		if crouch_just and sprint_ok and input_ok and on_floor and has_momentum:
			sliding = true
			crouching = true
			_slide_timer = slide_duration
			_can_slide = false
			var w: Vector3 = _sensors.wish_dir_world
			if w.length_squared() < 0.01:
				w = -_player.global_transform.basis.z
			_slide_direction = w.normalized()
			_apply_stance_shapes()
			_crouch_toggled = false
			_crouch_hold_time = 0.0
			_last_crouch_press = -10.0

	if not sliding and not Input.is_action_pressed(crouch_action):
		_can_slide = true

	if sliding:
		var should_end: bool = false
		if slide_end_mode == 1 and not Input.is_action_pressed(crouch_action):
			should_end = true
		_slide_timer -= delta
		if _slide_timer <= 0.0:
			should_end = true
		if should_end:
			sliding = false
			_resolve_stance_after_slide()
			return
		var v: Vector3 = _player.velocity
		v.x = _slide_direction.x * slide_speed
		v.z = _slide_direction.z * slide_speed
		_player.velocity = v

# -----------------------------------------------------------------------------
# Update
# -----------------------------------------------------------------------------

## Apply stance, slide, walk/sprint movement, airborne gravity, and jumps.
func update(delta: float) -> void:
	if not enabled:
		return
	if _player == null or _sensors == null:
		return

	# --- Landing detection runs unconditionally so state stays fresh. ---
	var on_floor_now: bool = _player.is_on_floor()
	if not _was_on_floor:
		var fall_v: float = -_player.velocity.y
		if fall_v > _fall_speed_peak:
			_fall_speed_peak = fall_v
	if on_floor_now and not _was_on_floor:
		_on_land()

	# Bhop state must be resolved BEFORE the strafe paths run so this
	# frame's chain activity is accurate. Also updates _was_on_floor.
	_update_bhop_state(delta)

	# --- Higher-priority system owns the body. ---
	if _player.movement_lockout > 0.0:
		walking = false
		sprinting = false
		current_speed = 0.0
		direction = Vector3.ZERO
		_player.set("walking", false)
		_player.set("sprinting", false)
		_player.set("current_speed", 0.0)
		_player.set("direction", Vector3.ZERO)
		return

	_jump_consumed_this_frame = false
	_handle_crouch(delta)
	_handle_slide(delta)

	var wish: Vector3 = _sensors.wish_dir_world
	var on_floor: bool = _player.is_on_floor()

	# Coyote time tick.
	if on_floor:
		_coyote_timer = coyote_time
	else:
		_coyote_timer -= delta
		if _coyote_timer < 0.0:
			_coyote_timer = 0.0

	# Jump buffer tick. Skipped if the stance layer consumed the jump.
	if Input.is_action_just_pressed(jump_action) and not _jump_consumed_this_frame:
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer -= delta
		if _jump_buffer_timer < 0.0:
			_jump_buffer_timer = 0.0

	var has_input: bool = wish.length_squared() > 0.01

	var sprint_held: bool = Input.is_action_pressed(sprint_action)
	var sprinting_now: bool = enable_sprinting \
		and sprint_held \
		and has_input \
		and on_floor \
		and not crouching \
		and not prone \
		and not sliding

	var velocity: Vector3 = _player.velocity
	var current_h: Vector3

	if sliding:
		current_h = Vector3(velocity.x, 0.0, velocity.z)
	else:
		var crouch_sprinting: bool = crouching \
			and enable_crouch_sprint \
			and enable_sprinting \
			and sprint_held \
			and has_input

		var target_speed: float = walk_speed
		if prone:
			target_speed = prone_speed
		elif crouch_sprinting:
			target_speed = sprint_speed
		elif crouching:
			target_speed = crouch_speed
		elif sprinting_now:
			target_speed = sprint_speed

		var target_h: Vector3 = wish * target_speed
		current_h = Vector3(velocity.x, 0.0, velocity.z)

		var bhop_handled: bool = false
		if enable_bunny_hop:
			if not on_floor and bhop_air_strafe:
				_player.velocity.x = current_h.x
				_player.velocity.z = current_h.z
				_apply_bhop_air(delta)
				current_h = Vector3(_player.velocity.x, 0.0, _player.velocity.z)
				bhop_handled = true
			elif _bhop_landing_timer > 0.0 and bhop_air_strafe:
				_player.velocity.x = current_h.x
				_player.velocity.z = current_h.z
				_apply_bhop_ground_steer(delta)
				current_h = Vector3(_player.velocity.x, 0.0, _player.velocity.z)
				bhop_handled = true

		if not bhop_handled:
			var rate: float = lerp_speed
			if not on_floor:
				rate = air_lerp_speed
			elif not has_input:
				rate = idle_deceleration

			current_h = current_h.lerp(target_h, clampf(rate * delta, 0.0, 1.0))

			if not has_input and on_floor and current_h.length() < 0.1:
				current_h = Vector3.ZERO

		velocity.x = current_h.x
		velocity.z = current_h.z

	if not on_floor:
		velocity.y += _sensors.gravity.y * delta

	# Reset jump counter the instant we touch ground.
	if on_floor:
		jumps_made = 0
		_jump_cut_done = false

	# Jump block. Prone always blocks. Crouch blocks only in Toggle mode
	# (Space stands in Toggle, jumps in Hold). Slide lets the jump through.
	var crouch_blocks_jump: bool = crouching and crouch_mode == 1 and not sliding
	if not prone and not _jump_consumed_this_frame and not crouch_blocks_jump:
		var can_ground_jump: bool = on_floor \
			or (enable_coyote_time and _coyote_timer > 0.0)
		var buffer_ready: bool = enable_jump_buffer and _jump_buffer_timer > 0.0
		var pressed_now: bool = Input.is_action_just_pressed(jump_action)
		var wants_ground_jump: bool = pressed_now or buffer_ready

		var jump_held: bool = Input.is_action_pressed(jump_action)

		# Auto-hop path (bhop chain).
		var bhop_auto_hop_now: bool = enable_bunny_hop \
			and bhop_auto_hop \
			and on_floor \
			and _bhop_landing_timer > 0.0 \
			and jump_held
		if bhop_auto_hop_now:
			wants_ground_jump = true

		if enable_jumping and wants_ground_jump:
			if can_ground_jump and jumps_made == 0:
				velocity.y = jump_velocity
				jumps_made = 1
				_jump_cut_done = false
				_coyote_timer = 0.0
				_jump_buffer_timer = 0.0
				if _player.has_method("play_jump"):
					_player.play_jump()
				if sliding:
					sliding = false
					_resolve_stance_after_slide()
				if enable_bunny_hop and jump_held:
					if bhop_auto_hop_now or _bhop_landing_timer > 0.0:
						_bhop_chain_active = true
			elif enable_double_jump \
					and pressed_now \
					and not on_floor \
					and jumps_made >= 1 \
					and jumps_made < max_jumps:
				velocity.y = double_jump_velocity
				jumps_made += 1
				_jump_cut_done = false
				_jump_buffer_timer = 0.0
				if _player.has_method("play_jump"):
					_player.play_jump()

	_player.velocity = velocity

	_handle_variable_jump()

	walking = has_input and on_floor and not sliding
	sprinting = sprinting_now
	current_speed = current_h.length()
	if current_h.length() > 0.01:
		direction = current_h.normalized()
	else:
		direction = Vector3.ZERO

	# Player-level mirrors.
	_player.set("walking", walking)
	_player.set("sprinting", sprinting)
	_player.set("crouching", crouching)
	_player.set("prone", prone)
	_player.set("sliding", sliding)
	_player.set("jumps_made", jumps_made)
	_player.set("current_speed", current_speed)
	_player.set("direction", direction)
	_player.set("last_velocity", velocity)

	# Air mouse steer.
	_handle_air_mouse_steer(delta)
