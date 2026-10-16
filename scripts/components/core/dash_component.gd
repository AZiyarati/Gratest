## Dash component.
##
## Launches the player horizontally for a short duration. Owns the
## horizontal portion of player.velocity while active and sets a brief
## movement_lockout each frame so MovementComponent cannot fight the
## dash trajectory.
##
## The dash can be directional (uses WASD at the moment of the trigger)
## or fixed forward. It can be scope-limited to ground / air. It fires
## a camera FOV punch and a speed-effect boost, both optional.
##
## Session 2 additions:
##   - Dashes from a wall or ladder are capped per airtime. Ground
##     contact resets the counters.
##   - Dashing while mounted on a wall or ladder uses the player's
##     camera-look direction instead of body forward.
class_name DashComponent
extends Node

# -----------------------------------------------------------------------------
# Scope enum
# -----------------------------------------------------------------------------

enum DashScope { BOTH = 0, GROUND_ONLY = 1, AIR_ONLY = 2 }

# -----------------------------------------------------------------------------
# Exports
# -----------------------------------------------------------------------------

@export_group("Features")
## Master toggle. When false, update() and trigger() no-op.
@export var enabled: bool = true
## Fire a camera FOV punch when the dash starts.
@export var camera_effects: bool = true
## Fire a speed-effect boost when the dash starts.
@export var speed_effects: bool = true

@export_group("Features — Scope")
## Which environment the dash is allowed in.
@export_enum("Both", "Ground Only", "Air Only") var dash_scope: int = 0

@export_group("Features — Directional")
## When true, WASD steers the dash direction at trigger time.
@export var enable_directional_dash: bool = true
## Allow directional dash while grounded.
@export var directional_ground: bool = true
## Allow directional dash while airborne.
@export var directional_air: bool = true
## Minimum input magnitude to count as a directional request.
@export var directional_min_input: float = 0.1

@export_group("Features — Prone")
## Allow dashing while prone. Off by default.
@export var enable_prone_dash: bool = false

@export_group("Features — Wall / Ladder")
## Maximum dashes allowed while mounted on a wall (wall_run or
## wall_climb) before landing. -1 = unlimited, 0 = none.
@export var max_dashes_per_wall_contact: int = 1
## Maximum dashes allowed while attached to a ladder before landing.
## -1 = unlimited, 0 = none.
@export var max_dashes_per_ladder_contact: int = 1
## When true, dashing while mounted on a wall or ladder uses the
## camera-forward look direction instead of the player's body forward.
@export var dash_uses_look_when_mounted: bool = true

@export_group("Timing")
## How long the dash velocity is applied.
@export var duration: float = 0.2
## How long before another dash can fire.
@export var cooldown: float = 0.8

@export_group("Dash Speed")
## Multiplier applied to walk_speed when dash_uses_walk_speed is true.
@export var dash_speed_multiplier: float = 3.0
## When true, dash speed is walk_speed * dash_speed_multiplier.
@export var dash_uses_walk_speed: bool = true
## Fallback dash speed when the movement component is unavailable.
@export var dash_speed_flat: float = 15.0

@export_group("Camera")
## FOV target held during the dash.
@export var fov_dash: float = 100.0
## Extra hold time after the dash ends.
@export var fov_hold_extra: float = 0.15
## When true, the FOV punch only fires when the player is airborne.
@export var fov_air_only: bool = true

@export_group("Speed Effect")
## Multiplier passed to the speed-effect boost.
@export var speed_effect_boost: float = 1.8
## Extra time the boost stays active after the dash ends.
@export var speed_effect_boost_duration: float = 0.3
## Profile applied while the boost is active.
@export var speed_effect_profile: SpeedEffectProfile = null

# -----------------------------------------------------------------------------
# Internal state
# -----------------------------------------------------------------------------

var _player: CharacterBody3D
var _movement: Node
var _sensors: SensorHub
var _wall_run: Node
var _ladder_climb: Node

var _can_dash: bool = true
var _dash_active: bool = false
var _dash_timer: float = 0.0
var _cooldown_timer: float = 0.0
var _dash_direction: Vector3 = Vector3.ZERO

## Dashes fired while mounted on a wall since the last ground contact.
var _wall_dash_count: int = 0
## Dashes fired while attached to a ladder since the last ground contact.
var _ladder_dash_count: int = 0

# -----------------------------------------------------------------------------
# Setup
# -----------------------------------------------------------------------------

## Cache the player, its movement component, sensors, and the wall /
## ladder traversal components used by the mounted-dash gates.
func setup(p: CharacterBody3D) -> void:
	_player = p
	_movement = p.get_node_or_null("MovementComponent")
	_sensors = p.sensors
	_wall_run = p.get_node_or_null("WallRunComponent")
	_ladder_climb = p.get_node_or_null("LadderClimbComponent")

# -----------------------------------------------------------------------------
# Update
# -----------------------------------------------------------------------------

## Tick cooldown, apply active dash velocity, and poll the dash action.
func update(delta: float) -> void:
	if not enabled or _player == null:
		return

	# Reset the mounted-dash counters on ground contact. Between jumps
	# these counters persist so the player cannot chain infinite wall
	# or ladder dashes.
	if _player.is_on_floor():
		_wall_dash_count = 0
		_ladder_dash_count = 0

	# Tick cooldown timer. Re-enable as soon as it expires.
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta
		if _cooldown_timer <= 0.0 and not _can_dash:
			_can_dash = true

	# Active dash: own horizontal velocity and enforce a short lockout.
	if _dash_active:
		_dash_timer -= delta
		var dash_speed: float = _resolve_dash_speed()
		var v: Vector3 = _player.velocity
		v.x = _dash_direction.x * dash_speed
		v.z = _dash_direction.z * dash_speed
		if not _player.is_on_floor():
			# Float horizontally — no vertical dash.
			v.y = 0.0
		_player.velocity = v

		var lockout: float = _safe_float("movement_lockout", 0.0)
		_player.set("movement_lockout", maxf(lockout, 0.05))
		_player.set("do_dash", true)
		_player.set("dash_direction", _dash_direction)

		if _dash_timer <= 0.0:
			_dash_active = false
			_player.set("do_dash", false)
	else:
		if Input.is_action_just_pressed("dash"):
			trigger()

# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

## Attempt a dash. Silently returns if the dash is not available.
func trigger() -> void:
	if not enabled or not _can_dash or _player == null:
		return

	var is_on_floor: bool = _player.is_on_floor()
	var is_prone: bool = _safe_bool("prone", false)
	if is_prone and not enable_prone_dash:
		return

	# Scope gate.
	if dash_scope == DashScope.GROUND_ONLY and not is_on_floor:
		return
	if dash_scope == DashScope.AIR_ONLY and is_on_floor:
		return

	# Mounted-dash caps. 0 = no dashes allowed at all; -1 = unlimited.
	var on_wall: bool = _on_wall()
	var on_ladder: bool = _on_ladder()
	var mounted: bool = on_wall or on_ladder

	if on_wall \
			and max_dashes_per_wall_contact >= 0 \
			and _wall_dash_count >= max_dashes_per_wall_contact:
		return
	if on_ladder \
			and max_dashes_per_ladder_contact >= 0 \
			and _ladder_dash_count >= max_dashes_per_ladder_contact:
		return

	# Base direction: camera look when mounted, body forward otherwise.
	var dir: Vector3
	if mounted and dash_uses_look_when_mounted \
			and _sensors != null \
			and _sensors.cam_forward_xz.length_squared() > 0.0001:
		dir = _sensors.cam_forward_xz.normalized()
	else:
		var forward: Vector3 = -_player.global_transform.basis.z
		forward.y = 0.0
		if forward.length_squared() < 0.0001:
			forward = Vector3.FORWARD
		else:
			forward = forward.normalized()
		dir = forward

	# Directional WASD override — only when NOT mounted. A mounted dash
	# always uses the look direction so WASD stays free for climbing.
	if not mounted and enable_directional_dash:
		var allow_dir: bool = true
		if is_on_floor and not directional_ground:
			allow_dir = false
		if not is_on_floor and not directional_air:
			allow_dir = false

		if allow_dir:
			var input: Vector2 = Input.get_vector(
				"left", "right", "forward", "backward")
			if input.length() >= directional_min_input:
				var basis: Basis = _player.global_transform.basis
				var d: Vector3 = basis.x * input.x + basis.z * input.y
				d.y = 0.0
				if d.length_squared() > 0.0001:
					dir = d.normalized()

	# Commit dash state.
	_dash_active = true
	_dash_timer = duration
	_dash_direction = dir
	_can_dash = false
	_cooldown_timer = cooldown + duration

	if on_wall:
		_wall_dash_count += 1
	if on_ladder:
		_ladder_dash_count += 1

	_player.set("do_dash", true)
	_player.set("dash_direction", _dash_direction)

	# Camera FOV punch.
	if camera_effects:
		if not fov_air_only or not is_on_floor:
			if _player.has_method("hold_camera_fov"):
				_player.hold_camera_fov(fov_dash, duration + fov_hold_extra)

	# Speed effect boost.
	if speed_effects:
		var fx: Node = _safe_node("speed_effect")
		if fx == null:
			fx = _player.get_node_or_null("SpeedEffectComponent")
		if fx != null and fx.has_method("add_boost"):
			fx.add_boost(
				speed_effect_boost,
				duration + speed_effect_boost_duration,
				speed_effect_profile
			)

# -----------------------------------------------------------------------------
# Internal helpers
# -----------------------------------------------------------------------------

func _on_wall() -> bool:
	if _wall_run == null or not _wall_run.has_method("is_active"):
		return false
	return _wall_run.is_active()

func _on_ladder() -> bool:
	if _ladder_climb == null or not _ladder_climb.has_method("is_active"):
		return false
	return _ladder_climb.is_active()

func _resolve_dash_speed() -> float:
	if dash_uses_walk_speed and _movement != null:
		var ws: float = _safe_float_from(_movement, "walk_speed", 0.0)
		if ws > 0.0:
			return ws * dash_speed_multiplier
	return dash_speed_flat

func _safe_float(key: String, fallback: float) -> float:
	if _player == null:
		return fallback
	var v: Variant = _player.get(key)
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		return float(v)
	return fallback

func _safe_bool(key: String, fallback: bool) -> bool:
	if _player == null:
		return fallback
	var v: Variant = _player.get(key)
	if typeof(v) == TYPE_BOOL:
		return v
	return fallback

func _safe_node(key: String) -> Node:
	if _player == null:
		return null
	var v: Variant = _player.get(key)
	if v is Node:
		return v
	return null

func _safe_float_from(src: Node, key: String, fallback: float) -> float:
	if src == null:
		return fallback
	var v: Variant = src.get(key)
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		return float(v)
	return fallback
