## Fullscreen speed effect.
##
## Owns the CanvasLayer + ColorRect overlay that renders the speed shader.
## The visible intensity can be driven by the player's horizontal speed,
## by boost multipliers (from dash / zip / etc), or by explicit override
## calls (slide / slope / fly / swing / landing). A slap pulse takes
## absolute priority while it plays.
##
## Priority table (higher wins while its timer is active):
##   1  = fall
##   2  = slide / slope
##   3  = fly
##   5  = swing
##   6  = landing
##   8  = zip
##   10 = dash
class_name SpeedEffectComponent
extends Node

# -----------------------------------------------------------------------------
# Exports
# -----------------------------------------------------------------------------

@export_group("Features")
## Master toggle. When false, update() does nothing and the overlay hides.
@export var enabled: bool = true
## Derive intensity from the player's horizontal speed.
@export var speed_driven: bool = true

@export_group("Speed Response")
## Below this horizontal speed the shader is off.
@export var min_speed: float = 10.0
## At or above this horizontal speed the shader is at full intensity.
@export var max_speed: float = 28.0
## Multiplier applied to target intensity while a boost is active.
@export var boost_multiplier: float = 1.8
## How quickly the current intensity chases its target.
@export var intensity_lerp: float = 6.0

@export_group("Default Profile")
## Profile used when no other profile is supplied.
@export var default_profile: SpeedEffectProfile = null

@export_group("Screen Effect")
## Shader that renders the effect on the overlay ColorRect.
@export var effect_shader: Shader = preload("res://shaders/speed_effect.gdshader")

@export_group("Rendering")
## Layer used for the auto-created overlay. Higher = drawn on top.
@export var canvas_layer_index: int = 100
## When true, create the CanvasLayer + ColorRect at runtime.
@export var auto_create_overlay: bool = true
## When assigned, reuse this ColorRect instead of creating one.
@export var overlay_rect: ColorRect = null

# -----------------------------------------------------------------------------
# Internal state
# -----------------------------------------------------------------------------

var _player: CharacterBody3D
var _current_intensity: float = 0.0

var _boost_value: float = 1.0
var _boost_timer: float = 0.0

var _suppress_timer: float = 0.0

var _base_profile: SpeedEffectProfile = null

var _override_intensity: float = -1.0
var _override_timer: float = 0.0
var _override_profile: SpeedEffectProfile = null
var _override_priority: int = -999
var _override_priority_timer: float = 0.0

var _slap_timer: float = 0.0
var _slap_duration: float = 1.0
var _slap_intensity: float = 1.0
var _slap_profile: SpeedEffectProfile = null

var _canvas_layer: CanvasLayer
var _color_rect: ColorRect
var _material: ShaderMaterial
var _time_offset: float = 0.0

# -----------------------------------------------------------------------------
# Setup
# -----------------------------------------------------------------------------

## Cache the player and build the overlay.
func setup(p: CharacterBody3D) -> void:
	_player = p

	if overlay_rect != null:
		_color_rect = overlay_rect
		_material = _ensure_material(_color_rect)
	elif auto_create_overlay:
		_build_overlay()

	if _material == null:
		return

	_apply_profile(default_profile)
	_material.set_shader_parameter("intensity", 0.0)

	if _color_rect != null:
		_color_rect.visible = false

func _build_overlay() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var root: Window = tree.current_scene as Window
	if root == null:
		# Fall back to the tree root when there's no current scene.
		root = tree.root as Window
	if root == null:
		return

	# Build the node tree in isolation first. The Material and shader
	# parameters can all be set up before the nodes are attached.
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = canvas_layer_index

	_color_rect = ColorRect.new()
	_color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_color_rect.anchor_right = 1.0
	_color_rect.anchor_bottom = 1.0
	_color_rect.offset_left = 0.0
	_color_rect.offset_top = 0.0
	_color_rect.offset_right = 0.0
	_color_rect.offset_bottom = 0.0
	_color_rect.visible = false

	_material = _ensure_material(_color_rect)

	# Deferred attachment: setup() is called from player._ready(), and
	# Godot blocks add_child() while the scene is still building its
	# own children. Deferring the tree attachment avoids the error.
	_canvas_layer.add_child.call_deferred(_color_rect)
	root.add_child.call_deferred(_canvas_layer)

func _ensure_material(rect: ColorRect) -> ShaderMaterial:
	if rect == null or effect_shader == null:
		return null
	var m: ShaderMaterial = rect.material as ShaderMaterial
	if m == null:
		m = ShaderMaterial.new()
		rect.material = m
	m.shader = effect_shader
	return m

# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

## Apply a temporary multiplier to the current intensity source.
func add_boost(multiplier: float, duration: float,
		profile: SpeedEffectProfile = null) -> void:
	if multiplier > _boost_value:
		_boost_value = multiplier
	if duration > _boost_timer:
		_boost_timer = duration
	if profile != null:
		_base_profile = profile
		_apply_profile(profile)

## Block speed-driven intensity for a short window (used by dash, etc).
func suppress_for(duration: float) -> void:
	if duration > _suppress_timer:
		_suppress_timer = duration

## Assert an explicit intensity. Priority rules:
##   - lower than current priority → ignored
##   - equal → value + duration + profile updated
##   - higher → takes over
func set_override_intensity(value: float, duration: float = 0.2,
		profile: SpeedEffectProfile = null, priority: int = 0) -> void:
	if priority < _override_priority:
		return
	_override_intensity = value
	_override_timer = duration
	_override_profile = profile
	_override_priority = priority
	_override_priority_timer = duration
	if profile != null:
		_base_profile = profile
		_apply_profile(profile)

## Convenience wrapper matching the FPC_PROJECT.md planned API.
## The duration is currently informational — profiles persist until
## another profile is set.
func set_active_profile(profile: SpeedEffectProfile,
		_duration: float) -> void:
	if profile == null:
		return
	_base_profile = profile
	_apply_profile(profile)

## Fire a two-beat slap screen pulse that overrides everything.
func play_slap_pulse(duration: float = 1.2, intensity: float = 1.0,
		profile: SpeedEffectProfile = null) -> void:
	if not enabled:
		return
	_slap_duration = maxf(duration, 0.0001)
	_slap_timer = _slap_duration
	_slap_intensity = intensity
	_slap_profile = profile
	if profile != null:
		_base_profile = profile
		_apply_profile(profile)

# -----------------------------------------------------------------------------
# Update
# -----------------------------------------------------------------------------

## Advance timers and write intensity to the shader.
func update(delta: float) -> void:
	if not enabled or _material == null:
		if _color_rect != null:
			_color_rect.visible = false
		return

	# Keep the shader's TIME_OFFSET monotonic so flicker stays coherent
	# even when we don't want the full TIME.
	_time_offset += delta
	_material.set_shader_parameter("TIME_OFFSET", _time_offset)

	# --- Slap pulse takes absolute priority. ---
	if _slap_timer > 0.0:
		_slap_timer -= delta
		var progress: float = 1.0 - _slap_timer / _slap_duration
		var beat: float = _slap_beat_curve(progress)
		_current_intensity = clampf(
			beat * _slap_intensity * (1.0 - progress), 0.0, 1.5
		)
		_material.set_shader_parameter("intensity", _current_intensity)
		if _color_rect != null:
			_color_rect.visible = _current_intensity > 0.005
		return

	# --- Tick timers. ---
	if _boost_timer > 0.0:
		_boost_timer -= delta
		if _boost_timer <= 0.0:
			_boost_value = 1.0

	if _suppress_timer > 0.0:
		_suppress_timer -= delta

	if _override_timer > 0.0:
		_override_timer -= delta
		if _override_timer <= 0.0:
			_override_intensity = -1.0
			_override_profile = null

	# Release priority after its own grace window so lower systems can
	# take over without flicker.
	if _override_priority_timer > 0.0:
		_override_priority_timer -= delta
		if _override_priority_timer <= 0.0:
			_override_priority = -999

	# --- Compute target. ---
	var target: float = 0.0
	if _override_intensity >= 0.0:
		target = _override_intensity * _boost_value
	elif _suppress_timer <= 0.0 and speed_driven and _player != null:
		var v: Vector3 = _player.velocity
		var speed: float = Vector3(v.x, 0.0, v.z).length()
		if speed >= max_speed:
			target = 1.0
		elif speed > min_speed:
			target = (speed - min_speed) / maxf(max_speed - min_speed, 0.0001)
		target *= _boost_value

	target = clampf(target, 0.0, 1.5)
	_current_intensity = lerpf(
		_current_intensity, target, clampf(delta * intensity_lerp, 0.0, 1.0)
	)
	_material.set_shader_parameter("intensity", _current_intensity)

	if _color_rect != null:
		_color_rect.visible = _current_intensity > 0.005

# -----------------------------------------------------------------------------
# Internal — curves and profiles
# -----------------------------------------------------------------------------

## Two-beat heartbeat curve. p is normalised [0, 1].
func _slap_beat_curve(p: float) -> float:
	if p < 0.10:
		return p / 0.10
	if p < 0.20:
		return 1.0 - (p - 0.10) / 0.10
	if p < 0.30:
		return ((p - 0.20) / 0.10) * 0.7
	if p < 0.45:
		return 0.7 * (1.0 - (p - 0.30) / 0.15)
	return 0.0

func _apply_profile(profile: SpeedEffectProfile) -> void:
	if _material == null or profile == null:
		return
	_material.set_shader_parameter("effect_color", profile.effect_color)
	_material.set_shader_parameter("tint_strength", profile.tint_strength)
	_material.set_shader_parameter("zoom_amount", profile.zoom_amount)
	_material.set_shader_parameter("edge_start", profile.edge_start)
	_material.set_shader_parameter("edge_end", profile.edge_end)
	_material.set_shader_parameter("contrast_boost", profile.contrast_boost)
	_material.set_shader_parameter("flicker_amount", profile.flicker_amount)
	_material.set_shader_parameter("flicker_speed", profile.flicker_speed)
