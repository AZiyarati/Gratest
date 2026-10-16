## Procedural camera bumps on jump, land, hard landing, roll, and slap.
##
## Each trigger runs a short animation that offsets the camera through the
## Player's accumulator API (add_cam_rotation / add_cam_offset). Never
## writes camera state directly and never emits signals. The only place
## this file reads Input is the slap mouse-roll term.
class_name MotionVisualComponent
extends Node

# -----------------------------------------------------------------------------
# Internal enum
# -----------------------------------------------------------------------------

enum MotionState { NONE, JUMP, LANDING, HARD_LANDING, ROLL, SLAP }

# -----------------------------------------------------------------------------
# Exports
# -----------------------------------------------------------------------------

@export_group("Features")
## Master toggle. When false, update() and all triggers no-op.
@export var enabled: bool = true

@export_group("Jump")
## Allow the jump bump to fire.
@export var jump_enabled: bool = true
## Total duration of the jump bump.
@export var jump_duration: float = 0.3
## Time (seconds) at which the bump reaches its peak.
@export var jump_peak_time: float = 0.1
## Peak pitch in degrees.
@export var jump_pitch_degrees: float = -3.0
## Peak roll in degrees.
@export var jump_roll_degrees: float = 2.0
## Peak Y offset (local eye-space units).
@export var jump_y_offset: float = -0.1

@export_group("Landing")
## Allow the landing bump to fire.
@export var landing_enabled: bool = true
## Total duration of the landing bump.
@export var landing_duration: float = 0.3
## Time (seconds) at which the bump reaches its peak.
@export var landing_peak_time: float = 0.1
## Peak pitch in degrees.
@export var landing_pitch_degrees: float = -3.0
## Peak roll in degrees.
@export var landing_roll_degrees: float = 2.0
## Peak Y offset.
@export var landing_y_offset: float = -0.1

@export_group("Hard Landing")
## Allow the hard landing bump to fire.
@export var hard_landing_enabled: bool = true
## Total duration of the hard landing bump.
@export var hard_landing_duration: float = 0.8
## Time (seconds) at which the bump reaches its peak.
@export var hard_landing_peak_time: float = 0.1
## Peak pitch in degrees.
@export var hard_landing_pitch_degrees: float = -10.0
## Peak roll in degrees.
@export var hard_landing_roll_degrees: float = -10.0
## Peak Y offset.
@export var hard_landing_y_offset: float = -0.8

@export_group("Roll")
## Allow the roll animation to fire.
@export var roll_enabled: bool = true
## Total duration of the roll animation.
@export var roll_duration: float = 1.0
## When true, roll spins a full 360 degrees regardless of roll_pitch_degrees.
@export var roll_full_rotation: bool = true
## Peak pitch for the roll (used when roll_full_rotation is false).
@export var roll_pitch_degrees: float = 360.0
## Peak Y offset at the middle of the roll.
@export var roll_y_offset: float = -0.5
## Time (seconds) to reach the peak. Retained for parity; not used by the
## roll curve itself.
@export var roll_peak_time: float = 0.2
## Normalised [start, end] window over the roll during which the Y offset
## is held at its peak.
@export var roll_hold_range: Vector2 = Vector2(0.15, 0.7)
## When true, flips the roll direction (backward instead of forward).
@export var roll_spin_backward: bool = false

@export_group("Slap")
## Allow the slap animation to fire.
@export var slap_enabled: bool = true
## Total duration of the slap.
@export var slap_duration: float = 1.2
## Time (seconds from start) at which the slam reaches full rotation.
@export var slap_slam_in: float = 0.15
## Time (seconds from start) at which the hold phase ends and recovery starts.
@export var slap_hold_end: float = 0.45
## Peak pitch in degrees.
@export var slap_pitch_degrees: float = -85.0
## Peak roll in degrees.
@export var slap_roll_degrees: float = 0.0
## Peak Y offset.
@export var slap_y_offset: float = -1.3
## Max additional roll from horizontal mouse motion while slapping.
@export var slap_mouse_max_roll: float = 12.0
## How quickly the mouse roll term lerps toward its target.
@export var slap_mouse_lerp_speed: float = 10.0

# -----------------------------------------------------------------------------
# Internal state
# -----------------------------------------------------------------------------

var _player: CharacterBody3D
var _state: MotionState = MotionState.NONE
var _timer: float = 0.0
var _duration: float = 0.0
var _peak_time: float = 0.0
var _peak_pitch: float = 0.0
var _peak_roll: float = 0.0
var _peak_y: float = 0.0
var _slap_mouse_roll: float = 0.0

# -----------------------------------------------------------------------------
# Setup
# -----------------------------------------------------------------------------

## Cache the owning player. Called by player.gd during _ready.
func setup(p: CharacterBody3D) -> void:
	_player = p

# -----------------------------------------------------------------------------
# Public queries
# -----------------------------------------------------------------------------

## True while any motion is playing.
func is_playing() -> bool:
	return _state != MotionState.NONE

# -----------------------------------------------------------------------------
# Public triggers
# -----------------------------------------------------------------------------

## Fire the jump bump.
func trigger_jump() -> void:
	if not enabled or not jump_enabled:
		return
	_state = MotionState.JUMP
	_duration = jump_duration
	_peak_time = jump_peak_time
	_peak_pitch = jump_pitch_degrees
	_peak_roll = jump_roll_degrees
	_peak_y = jump_y_offset
	_timer = 0.0

## Fire the landing bump.
func trigger_landing() -> void:
	if not enabled or not landing_enabled:
		return
	_state = MotionState.LANDING
	_duration = landing_duration
	_peak_time = landing_peak_time
	_peak_pitch = landing_pitch_degrees
	_peak_roll = landing_roll_degrees
	_peak_y = landing_y_offset
	_timer = 0.0

## Fire the hard landing bump.
func trigger_hard_landing() -> void:
	if not enabled or not hard_landing_enabled:
		return
	_state = MotionState.HARD_LANDING
	_duration = hard_landing_duration
	_peak_time = hard_landing_peak_time
	_peak_pitch = hard_landing_pitch_degrees
	_peak_roll = hard_landing_roll_degrees
	_peak_y = hard_landing_y_offset
	_timer = 0.0

## Fire the roll animation.
func trigger_roll() -> void:
	if not enabled or not roll_enabled:
		return
	_state = MotionState.ROLL
	_duration = roll_duration
	_peak_time = roll_peak_time
	_peak_pitch = 360.0 if roll_full_rotation else roll_pitch_degrees
	_peak_roll = 0.0
	_peak_y = roll_y_offset
	_timer = 0.0

## Fire the slap animation. When duration > 0 it overrides slap_duration.
## Intensity scales pitch / roll / y peak values.
func trigger_slap(duration: float = -1.0, intensity: float = 1.0) -> void:
	if not enabled or not slap_enabled:
		return
	_state = MotionState.SLAP
	_duration = duration if duration > 0.0 else slap_duration
	_peak_time = 0.0
	_peak_pitch = slap_pitch_degrees * intensity
	_peak_roll = slap_roll_degrees * intensity
	_peak_y = slap_y_offset * intensity
	_slap_mouse_roll = 0.0
	_timer = 0.0

## Cancel any active motion immediately.
func cancel() -> void:
	_state = MotionState.NONE
	_timer = 0.0

# -----------------------------------------------------------------------------
# Update
# -----------------------------------------------------------------------------

## Advance the active motion and push accumulator offsets to the player.
func update(delta: float) -> void:
	if not enabled or _state == MotionState.NONE:
		return

	_timer += delta
	var t: float = clampf(_timer / maxf(_duration, 0.0001), 0.0, 1.0)

	match _state:
		MotionState.JUMP, MotionState.LANDING, MotionState.HARD_LANDING:
			_apply_bump(t)
		MotionState.ROLL:
			_apply_roll(t)
		MotionState.SLAP:
			_apply_slap(t)
		_:
			pass

	if t >= 1.0:
		_reset()

# -----------------------------------------------------------------------------
# Internal — curves
# -----------------------------------------------------------------------------

func _apply_bump(t: float) -> void:
	var peak_ratio: float = clampf(_peak_time / maxf(_duration, 0.0001), 0.01, 0.99)
	var bump: float = 0.0
	if t <= peak_ratio:
		var u: float = t / peak_ratio
		bump = 1.0 - (1.0 - u) * (1.0 - u)
	else:
		var u: float = (t - peak_ratio) / (1.0 - peak_ratio)
		bump = (1.0 - u) * (1.0 - u)

	if _player == null:
		return
	_player.add_cam_rotation(
		deg_to_rad(_peak_pitch) * bump,
		0.0,
		deg_to_rad(_peak_roll) * bump
	)
	_player.add_cam_offset(0.0, _peak_y * bump, 0.0)

func _apply_roll(t: float) -> void:
	# Godot's +X rotation pitches the camera UP (backward somersault).
	# A forward somersault needs negative rotation, so we negate the
	# peak pitch. roll_spin_backward flips back to the backward spin.
	var pitch: float = -deg_to_rad(_peak_pitch) * t
	if roll_spin_backward:
		pitch = -pitch

	var hold_start: float = clampf(roll_hold_range.x, 0.0, 0.99)
	var hold_end: float = clampf(roll_hold_range.y, hold_start + 0.01, 1.0)
	var y_dip: float = 0.0
	if t < hold_start:
		y_dip = t / hold_start
	elif t < hold_end:
		y_dip = 1.0
	else:
		y_dip = 1.0 - (t - hold_end) / (1.0 - hold_end)

	if _player == null:
		return
	_player.add_cam_rotation(pitch, 0.0, 0.0)
	_player.add_cam_offset(0.0, _peak_y * y_dip, 0.0)

func _apply_slap(t: float) -> void:
	var slam_in: float = clampf(slap_slam_in / maxf(_duration, 0.0001), 0.01, 0.9)
	var hold_end: float = clampf(slap_hold_end, slam_in + 0.01, 0.98)

	var bump: float = 0.0
	if t < slam_in:
		var u: float = t / slam_in
		bump = u * u
	elif t < hold_end:
		bump = 1.0
	else:
		var u: float = (t - hold_end) / (1.0 - hold_end)
		var s: float = u * u * (3.0 - 2.0 * u)
		bump = 1.0 - s

	var mouse_roll_deg: float = 0.0
	if slap_mouse_max_roll > 0.0:
		var mv: Vector2 = Input.get_last_mouse_velocity()
		var target: float = clampf(
			-mv.x / 600.0 * slap_mouse_max_roll,
			-slap_mouse_max_roll,
			slap_mouse_max_roll
		)
		_slap_mouse_roll = lerpf(
			_slap_mouse_roll,
			target,
			clampf(slap_mouse_lerp_speed * get_physics_process_delta_time(), 0.0, 1.0)
		)
		mouse_roll_deg = _slap_mouse_roll

	if _player == null:
		return
	_player.add_cam_rotation(
		deg_to_rad(_peak_pitch) * bump,
		0.0,
		deg_to_rad(_peak_roll + mouse_roll_deg) * bump
	)
	_player.add_cam_offset(0.0, _peak_y * bump, 0.0)

# -----------------------------------------------------------------------------
# Internal — reset
# -----------------------------------------------------------------------------

func _reset() -> void:
	_state = MotionState.NONE
	_timer = 0.0
