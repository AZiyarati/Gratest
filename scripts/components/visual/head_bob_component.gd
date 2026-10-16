## Active walk/sprint/crouch/prone bob + idle breathing.
##
## Writes procedural camera motion through the Player's accumulator API
## (add_eye_offset / add_eye_rotation). Never writes eyes.* or cam.*
## directly. Never emits signals.
##
## Idle breathing fades in via a smoothed `_idle_weight` so the
## transition between active bob and breathing has no visible pop in
## either position or rotation.
class_name HeadBobComponent
extends Node

# -----------------------------------------------------------------------------
# Exports
# -----------------------------------------------------------------------------

@export_group("Features — Active Bob")
## Master toggle. When false, update() does nothing.
@export var enabled: bool = true
## Apply the lateral (X) component of the active bob.
@export var bob_x: bool = true
## Apply the vertical (Y) component of the active bob.
@export var bob_y: bool = true

@export_group("Active Bob — Y Frequency")
## Vertical bob frequency while sprinting.
@export var sprint_freq_y: float = 22.0
## Vertical bob frequency while walking.
@export var walk_freq_y: float = 14.0
## Vertical bob frequency while crouching.
@export var crouch_freq_y: float = 10.0

@export_group("Active Bob — Y Intensity")
## Vertical bob amplitude while sprinting (meters).
@export var sprint_intensity_y: float = 0.04
## Vertical bob amplitude while walking (meters).
@export var walk_intensity_y: float = 0.03
## Vertical bob amplitude while crouching (meters).
@export var crouch_intensity_y: float = 0.015

@export_group("Active Bob — X Frequency")
## Lateral bob frequency while sprinting.
@export var sprint_freq_x: float = 11.0
## Lateral bob frequency while walking.
@export var walk_freq_x: float = 7.0
## Lateral bob frequency while crouching.
@export var crouch_freq_x: float = 5.0

@export_group("Active Bob — X Intensity")
## Lateral bob amplitude while sprinting (meters).
@export var sprint_intensity_x: float = 0.04
## Lateral bob amplitude while walking (meters).
@export var walk_intensity_x: float = 0.03
## Lateral bob amplitude while crouching (meters).
@export var crouch_intensity_x: float = 0.015

@export_group("Active Bob — Prone")
## Vertical bob frequency while prone.
@export var prone_freq_y: float = 5.0
## Lateral bob frequency while prone.
@export var prone_freq_x: float = 2.5
## Vertical bob amplitude while prone (meters).
@export var prone_intensity_y: float = 0.02
## Lateral bob amplitude while prone (meters). Wider than Y — side sway.
@export var prone_intensity_x: float = 0.04

@export_group("Active Bob — General")
## How quickly the current offsets chase their targets.
@export var lerp_speed: float = 10.0

@export_group("Idle — Features")
## Enable idle breathing when the player is still.
@export var idle_enabled: bool = true
## Seconds of stillness before idle breathing kicks in.
@export var idle_enter_delay: float = 3.0
## Mouse velocity above this (px/s) counts as "moving" and cancels idle.
@export var idle_mouse_threshold: float = 5.0
## How quickly idle breathing fades in / out. Higher = quicker blend.
@export var idle_fade_speed: float = 1.5

@export_group("Idle — Breathing")
## Vertical breathing amplitude (meters).
@export var idle_breathing_amplitude: float = 0.02
## Breathing rate in cycles per second.
@export var idle_breathing_frequency: float = 0.3
## Peak pitch component of breathing (degrees).
@export var idle_breathing_pitch: float = 1.2
## Peak roll component of breathing (degrees).
@export var idle_breathing_roll: float = 1.5

# -----------------------------------------------------------------------------
# Internal state
# -----------------------------------------------------------------------------

var _player: CharacterBody3D
var _bob_index: float = 0.0
var _intensity_y: float = 0.0
var _intensity_x: float = 0.0
var _current_offset_x: float = 0.0
var _current_offset_y: float = 0.0
var _current_pitch: float = 0.0
var _current_roll: float = 0.0
var _idle_timer: float = 0.0
var _idle_active: bool = false
## Smoothed 0..1 weight for blending between active bob and idle breathing.
var _idle_weight: float = 0.0
var _breathing_phase: float = 0.0

# -----------------------------------------------------------------------------
# Setup
# -----------------------------------------------------------------------------

## Cache the owning player. Called by player.gd during _ready.
func setup(p: CharacterBody3D) -> void:
	_player = p

# -----------------------------------------------------------------------------
# Update
# -----------------------------------------------------------------------------

## Advance the head-bob / breathing state and push offsets to the player.
func update(delta: float) -> void:
	if not enabled or _player == null:
		return

	# --- Activity detection ---
	var mouse_v: Vector2 = Input.get_last_mouse_velocity()
	var mouse_moving: bool = mouse_v.length() > idle_mouse_threshold
	var input_dir: Vector2 = Input.get_vector("left", "right", "forward", "backward")
	var player_moving: bool = input_dir != Vector2.ZERO
	var on_floor: bool = _player.is_on_floor()
	var any_activity: bool = mouse_moving or player_moving or not on_floor

	if any_activity:
		_idle_timer = 0.0
		if _idle_active:
			_idle_active = false
	else:
		_idle_timer += delta
		if idle_enabled and _idle_timer >= idle_enter_delay:
			_idle_active = true

	# --- Smooth idle weight ---
	var target_w: float = 1.0 if _idle_active else 0.0
	_idle_weight = move_toward(_idle_weight, target_w, delta * idle_fade_speed)

	# --- Active bob offsets ---
	var active_y: float = 0.0
	var active_x: float = 0.0

	var freq_y: float = 0.0
	var freq_x: float = 0.0
	var int_y: float = 0.0
	var int_x: float = 0.0

	if _player.sprinting:
		freq_y = sprint_freq_y
		freq_x = sprint_freq_x
		int_y = sprint_intensity_y
		int_x = sprint_intensity_x
	elif _player.walking:
		freq_y = walk_freq_y
		freq_x = walk_freq_x
		int_y = walk_intensity_y
		int_x = walk_intensity_x
	elif _player.crouching:
		freq_y = crouch_freq_y
		freq_x = crouch_freq_x
		int_y = crouch_intensity_y
		int_x = crouch_intensity_x
	elif _player.prone:
		freq_y = prone_freq_y
		freq_x = prone_freq_x
		int_y = prone_intensity_y
		int_x = prone_intensity_x

	_intensity_y = int_y
	_intensity_x = int_x

	var should_bob: bool = on_floor \
		and not _player.sliding \
		and input_dir != Vector2.ZERO

	if should_bob:
		_bob_index += freq_y * delta
		if bob_y:
			active_y = sin(_bob_index) * _intensity_y
		if bob_x:
			var x_scale: float = _x_freq_scale(freq_x, freq_y)
			active_x = sin(_bob_index * x_scale) * _intensity_x

	# --- Idle breathing offsets ---
	_breathing_phase += idle_breathing_frequency * TAU * delta

	var idle_y: float = sin(_breathing_phase) * idle_breathing_amplitude
	var idle_pitch: float = sin(_breathing_phase * 0.5) \
		* deg_to_rad(idle_breathing_pitch)
	var idle_roll: float = sin(_breathing_phase * 0.75) \
		* deg_to_rad(idle_breathing_roll)

	# --- Blend ---
	var w: float = _idle_weight
	var target_x: float = active_x * (1.0 - w)
	var target_y: float = active_y * (1.0 - w) + idle_y * w
	var target_pitch: float = idle_pitch * w
	var target_roll: float = idle_roll * w

	var a: float = clampf(delta * lerp_speed, 0.0, 1.0)
	_current_offset_x = lerpf(_current_offset_x, target_x, a)
	_current_offset_y = lerpf(_current_offset_y, target_y, a)
	_current_pitch = lerpf(_current_pitch, target_pitch, a)
	_current_roll = lerpf(_current_roll, target_roll, a)

	if _player.has_method("add_eye_offset"):
		_player.add_eye_offset(_current_offset_x, _current_offset_y, 0.0)
	if _player.has_method("add_eye_rotation"):
		_player.add_eye_rotation(_current_pitch, 0.0, _current_roll)

func _x_freq_scale(freq_x: float, freq_y: float) -> float:
	if freq_y <= 0.0001:
		return 1.0
	return freq_x / freq_y
