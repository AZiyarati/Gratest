## Fall → land → recover state machine.
##
## Owns landing detection and decides which camera motion plays on
## impact. Ctrl at impact → roll. Otherwise the landing escalates with
## fall speed: soft landing → hard landing → slap.
##
## The roll carries entry momentum forward and adds a decaying thrust
## so it visibly launches the player ahead
##
## When this component is present on the Player, MovementComponent's
## own _on_land() must be gated off so landing visuals fire once.
class_name FallBehaviorComponent
extends Node

# -----------------------------------------------------------------------------
# Internal enum
# -----------------------------------------------------------------------------

enum State { IDLE, FALLING, ROLLING, LANDING }

# -----------------------------------------------------------------------------
# Exports
# -----------------------------------------------------------------------------

@export_group("Features")
## Master toggle. When false, update() does nothing.
@export var enabled: bool = true
## Allow Ctrl-at-impact to fire a roll instead of the default landing.
@export var enable_roll: bool = true
## Allow the heaviest falls to fire a slap by default.
@export var enable_slap: bool = true
## Allow the mid-tier falls to fire a hard landing by default.
@export var enable_hard_landing: bool = true

@export_group("Detection — Fall Speed Thresholds")
## Below this, no camera motion fires.
@export var min_fall_speed: float = 4.0
## At or above this speed, hard landing fires (unless slap or roll).
@export var hard_landing_min_speed: float = 10.0
## At or above this speed, slap fires instead of hard landing.
@export var slap_min_speed: float = 12.0
## Speed at which slap intensity and duration are maxed out.
@export var slap_max_speed: float = 30.0

@export_group("Input Windows")
## Ctrl pressed within this window of impact → roll.
@export var tap_window: float = 0.3
## Ctrl held longer than this at impact → hard landing. Must be >= tap_window
## for the hold check to run before the tap check.
@export var hold_threshold: float = 0.25

@export_group("Roll")
## Base forward speed during the roll (m/s).
@export var roll_speed: float = 8.0
## Fraction of entry horizontal speed carried into the roll.
## 1.0 preserves entry speed; > 1 adds extra launch.
@export var roll_momentum_carry: float = 1.0
## Extra forward thrust applied at the start of the roll (m/s).
## Decays linearly to zero over the roll duration.
@export var roll_forward_thrust: float = 6.0
## How long the roll lasts.
@export var roll_duration: float = 0.7
## movement_lockout applied during the roll.
@export var roll_lockout: float = 0.75
## Mouse X curves the roll direction. 0 disables.
@export var roll_mouse_curve_strength: float = 4.0

@export_group("Roll — Speed Scaling")
## Fall speed at which roll scaling starts (m/s).
@export var roll_scale_min_speed: float = 6.0
## Fall speed at which roll scaling maxes out (m/s).
@export var roll_scale_max_speed: float = 25.0
## Roll duration at roll_scale_min_speed.
@export var roll_duration_min: float = 0.5
## Roll duration at roll_scale_max_speed.
@export var roll_duration_max: float = 0.9
## Roll forward thrust at roll_scale_min_speed.
@export var roll_thrust_min: float = 3.0
## Roll forward thrust at roll_scale_max_speed.
@export var roll_thrust_max: float = 10.0

@export_group("Recovery")
## How long the player is locked out after a slap landing.
@export var slap_recovery: float = 0.9
## How long the player is locked out after a hard landing.
@export var hard_land_recovery: float = 0.6

@export_group("Slap — Screen Effect")
## Fire the fullscreen slap pulse on a slap landing.
@export var slap_screen_effect_enabled: bool = true
## Default pulse duration. Scaled by fall speed.
@export var slap_screen_effect_duration: float = 1.2
## Default pulse intensity. Scaled by fall speed.
@export var slap_screen_effect_intensity: float = 1.0
## Profile for the slap pulse.
@export var slap_screen_effect_profile: SpeedEffectProfile = null

@export_group("Slap — Speed Scaling")
## Slap duration at slap_min_speed.
@export var slap_duration_min: float = 0.8
## Slap duration at slap_max_speed.
@export var slap_duration_max: float = 1.6
## Slap intensity at slap_min_speed.
@export var slap_intensity_min: float = 0.6

# -----------------------------------------------------------------------------
# Internal state
# -----------------------------------------------------------------------------

var _player: CharacterBody3D
var _state: State = State.IDLE
var _timer: float = 0.0
var _peak_fall_speed: float = 0.0
var _was_on_floor: bool = true
var _ctrl_press_time: float = -10.0
var _roll_direction: Vector3 = Vector3.FORWARD
## Base horizontal speed carried through the roll (max of roll_speed
## and the momentum projected onto the roll direction).
var _roll_base_speed: float = 0.0
## Current decaying thrust. Starts at roll_forward_thrust and falls to 0.
var _roll_thrust_current: float = 0.0
## Actual roll duration for the current roll. Set per-roll by _start_roll.
var _roll_duration_actual: float = 0.7
## Initial thrust value for the current roll. Used to compute the decay rate.
var _roll_thrust_initial: float = 0.0

# -----------------------------------------------------------------------------
# Setup
# -----------------------------------------------------------------------------

## Cache the owning player. Called by player.gd during _ready.
func setup(p: CharacterBody3D) -> void:
	_player = p
	_was_on_floor = p.is_on_floor()

# -----------------------------------------------------------------------------
# Public queries
# -----------------------------------------------------------------------------

## True while a roll or a landing recovery is playing.
func is_active() -> bool:
	return _state == State.ROLLING or _state == State.LANDING

# -----------------------------------------------------------------------------
# Update
# -----------------------------------------------------------------------------

## Track fall, detect landing, drive roll / recovery state.
func update(delta: float) -> void:
	if not enabled or _player == null:
		return

	# Track Ctrl press time every frame.
	if Input.is_action_just_pressed("crouch"):
		_ctrl_press_time = Time.get_ticks_msec() / 1000.0

	# Active state ticks. Also keep _was_on_floor synced so we
	# don't re-trigger landing detection when we exit those states.
	if _state == State.ROLLING:
		_tick_roll(delta)
		_was_on_floor = _player.is_on_floor()
		return
	if _state == State.LANDING:
		_tick_landing(delta)
		_was_on_floor = _player.is_on_floor()
		return

	var on_floor_now: bool = _player.is_on_floor()

	if not on_floor_now and not _was_on_floor:
		var v: float = -_player.velocity.y
		if v > _peak_fall_speed:
			_peak_fall_speed = v

	if on_floor_now and not _was_on_floor:
		_on_land()
		_peak_fall_speed = 0.0
		_was_on_floor = on_floor_now
		# CRITICAL: _on_land() chose a state (ROLLING / LANDING / IDLE).
		# Return so this frame does not overwrite it.
		return

	_was_on_floor = on_floor_now

	if not on_floor_now:
		_state = State.FALLING
	else:
		_state = State.IDLE

# -----------------------------------------------------------------------------
# Internal — landing decision
# -----------------------------------------------------------------------------

func _on_land() -> void:
	var fall_speed: float = _peak_fall_speed
	if fall_speed < min_fall_speed:
		_state = State.IDLE
		return

	var ctrl_held: bool = Input.is_action_pressed("crouch")
	var now: float = Time.get_ticks_msec() / 1000.0
	var since_press: float = now - _ctrl_press_time

	# --- HOLD: Ctrl is still down and was pressed more than
	#     hold_threshold ago. This covers "hold Ctrl through the fall".
	if enable_hard_landing and ctrl_held and since_press > hold_threshold:
		_play_hard_landing()
		return

	# --- TAP: Ctrl was pressed within the tap window (whether it is
	#     still held or already released). This covers "tap Ctrl just
	#     before landing → roll".
	if enable_roll and since_press <= tap_window:
		_start_roll(fall_speed)
		return

	# --- No recent Ctrl: escalate by fall speed. ---
	if enable_slap and fall_speed >= slap_min_speed:
		_play_slap_landing(fall_speed)
	elif enable_hard_landing and fall_speed >= hard_landing_min_speed:
		_play_hard_landing()
	else:
		_play_soft_landing()

func _play_soft_landing() -> void:
	if _player.has_method("play_landing"):
		_player.play_landing()
	_state = State.LANDING
	_timer = 0.2

func _play_hard_landing() -> void:
	if _player.has_method("play_hard_landing"):
		_player.play_hard_landing()
	_state = State.LANDING
	_timer = hard_land_recovery
	_add_lockout(hard_land_recovery * 0.8)

func _play_slap_landing(fall_speed: float) -> void:
	var span: float = maxf(slap_max_speed - slap_min_speed, 0.01)
	var t: float = clampf((fall_speed - slap_min_speed) / span, 0.0, 1.0)
	var intensity: float = lerpf(slap_intensity_min, 1.0, t)
	var duration: float = lerpf(slap_duration_min, slap_duration_max, t)
	var recovery: float = duration * 0.85

	if _player.has_method("play_slap"):
		_player.play_slap(duration, intensity)

	_state = State.LANDING
	_timer = recovery
	_add_lockout(recovery)

	if slap_screen_effect_enabled:
		var fx: Variant = _player.get("speed_effect")
		if fx is Node and fx.has_method("play_slap_pulse"):
			fx.play_slap_pulse(
				duration * 1.05, intensity, slap_screen_effect_profile
			)

func _start_roll(fall_speed: float) -> void:
	# Scale duration and thrust with fall speed.
	var span: float = maxf(roll_scale_max_speed - roll_scale_min_speed, 0.01)
	var t: float = clampf((fall_speed - roll_scale_min_speed) / span, 0.0, 1.0)

	var actual_duration: float = lerpf(roll_duration_min, roll_duration_max, t)
	var actual_thrust: float = lerpf(roll_thrust_min, roll_thrust_max, t)

	_state = State.ROLLING
	_timer = actual_duration
	_roll_duration_actual = actual_duration
	_roll_thrust_initial = maxf(actual_thrust, 0.0)
	_roll_thrust_current = _roll_thrust_initial

	_roll_direction = _resolve_roll_direction()

	# Capture entry momentum along the roll direction. Any sideways
	# velocity is dropped so the roll goes forward cleanly.
	var hv := Vector3(_player.velocity.x, 0.0, _player.velocity.z)
	var entry_along: float = maxf(0.0, hv.dot(_roll_direction))
	var carried: float = entry_along * roll_momentum_carry
	_roll_base_speed = maxf(roll_speed, carried)

	if _player.has_method("play_roll"):
		_player.play_roll()

	_add_lockout(roll_lockout)

## Resolve the roll's forward direction.
##
## Priority:
##   1. Movement's current direction (velocity-aligned) — most natural
##      when the player is running before they hit the ground.
##   2. The player's own body forward, flattened to XZ.
##   3. World forward as a last resort.
func _resolve_roll_direction() -> Vector3:
	var d: Variant = _player.get("direction")
	if typeof(d) == TYPE_VECTOR3:
		var dv: Vector3 = d
		var flat_d := Vector3(dv.x, 0.0, dv.z)
		if flat_d.length_squared() > 0.01:
			return flat_d.normalized()

	var body_fwd: Vector3 = -_player.global_transform.basis.z
	var flat_body := Vector3(body_fwd.x, 0.0, body_fwd.z)
	if flat_body.length_squared() > 0.01:
		return flat_body.normalized()

	return Vector3.FORWARD

# -----------------------------------------------------------------------------
# Internal — tick roll / landing
# -----------------------------------------------------------------------------

func _tick_roll(delta: float) -> void:
	_timer -= delta

	# Mouse curve: steer the roll direction with horizontal mouse motion.
	if roll_mouse_curve_strength > 0.0:
		var mv: Vector2 = Input.get_last_mouse_velocity()
		if absf(mv.x) > 1.0:
			var yaw_input: float = clampf(mv.x / 600.0, -1.0, 1.0)
			var curve: float = -yaw_input * roll_mouse_curve_strength * delta
			_roll_direction = _roll_direction.rotated(Vector3.UP, curve)
			_roll_direction.y = 0.0
			if _roll_direction.length_squared() > 0.0001:
				_roll_direction = _roll_direction.normalized()

	# Decay the thrust burst toward zero over the actual roll duration.
	var decay: float = _roll_thrust_initial / maxf(_roll_duration_actual, 0.0001)
	_roll_thrust_current = maxf(0.0, _roll_thrust_current - decay * delta)

	# Drive the roll through player.velocity. player.gd applies it via
	# move_and_slide() at the end of _physics_process, which is the
	# reliable translation path for a CharacterBody3D.
	var speed: float = _roll_base_speed + _roll_thrust_current
	_player.velocity.x = _roll_direction.x * speed
	_player.velocity.z = _roll_direction.z * speed
	# Kill any downward velocity so gravity doesn't pull the player
	# through the floor mid-roll. Positive Y is left untouched so
	# rolls off a ledge still fall naturally.
	if _player.velocity.y < 0.0:
		_player.velocity.y = 0.0

	# Keep the movement component locked out for the rest of the roll.
	_add_lockout(0.05)

	if _timer <= 0.0:
		_state = State.IDLE

func _tick_landing(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_state = State.IDLE

# -----------------------------------------------------------------------------
# Internal — helpers
# -----------------------------------------------------------------------------

func _add_lockout(value: float) -> void:
	if _player == null:
		return
	var current: Variant = _player.get("movement_lockout")
	var base: float = 0.0
	if typeof(current) == TYPE_FLOAT or typeof(current) == TYPE_INT:
		base = float(current)
	_player.set("movement_lockout", maxf(base, value))
