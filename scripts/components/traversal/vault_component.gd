## Vault component. Auto-vaults or manually vaults (W / Space) over
## waist-high obstacles, arcs the player over them, and drops them on
## a verified flat landing zone.
##
## Kong vault: while airborne with forward momentum, approaching a
## vaultable obstacle triggers a Kong vault — a faster, lower-arc,
## dive-over motion with a forward exit push. Auto-only (no Space
## trigger) so double-jump stays available near obstacles.
##
## Ledge vault: while airborne below a platform edge, approaching the
## wall triggers a pull-up onto the top surface. This is the
## lightweight aerial version — the full LedgeGrabComponent (hang,
## shimmy, corner detection, slingshot) is a separate later component
## and will override this when implemented.
##
## Kong and Ledge are mutually exclusive by height: Kong fires when
## the player is at/above the obstacle top; Ledge fires when the
## player is below it.
##
## DOCUMENTED RAY-CAST EXCEPTION: SensorHub has no vault sensors, so
## this component casts its own rays and shape queries — all on
## `vault_mask` (obstacle detection) and `landing_check_mask` (landing
## probes). See FPC_PROJECT.md "Components that legitimately cast
## their own rays".
##
## Never writes eyes.* / cam.* directly — uses
## _player.add_cam_rotation.
##
## play_jump() is NOT called by this component.
class_name VaultComponent
extends Node

enum VaultStyle { LAZY, DASH, SPEED, KONG, LEDGE }
## High-level motion kind. Determines which style sub-range applies.
enum VaultKind { GROUND, KONG, LEDGE }

# -----------------------------------------------------------------------------
# Exports
# -----------------------------------------------------------------------------

@export_group("Features")
@export var enabled: bool = true
@export var auto_vault: bool = true
@export var vault_on_w: bool = true
@export var vault_on_jump: bool = true
@export var side_movement: bool = true
@export var turn_enabled: bool = true

@export_group("Input")
@export var turn_action: String = "turn_around"
@export var accept_action: String = "ui_accept"

@export_group("Detection")
@export var waist_height: float = 0.8
@export var min_vault_height: float = 0.4
@export var max_vault_height: float = 1.6
@export var vault_reach: float = 1.2
@export_flags_3d_physics var vault_mask: int = 4
@export var min_forward_speed: float = 1.5

@export_group("Kong Vault")
## Master toggle. Kong fires automatically when airborne with forward
## momentum against a vaultable obstacle. Auto-only by design — Space
## stays reserved for jump / double-jump.
@export var kong_vault_enabled: bool = true
## Minimum horizontal speed required to trigger a Kong.
@export var kong_min_forward_speed: float = 3.0
## Maximum fall speed at which Kong still triggers. Prevents Kong from
## firing during a long freefall (you want to be rising or near peak).
@export var kong_max_fall_speed: float = 5.0
## Kong motion duration (shorter = punchier dive).
@export var kong_duration: float = 0.28
## Natural Kong arc (lower than normal vault — you're diving, not
## jumping). Still auto-clamped up if the obstacle would be clipped.
@export var kong_arc_margin: float = 0.2
## Multiplier on momentum carry for Kong.
@export var kong_carry_mult: float = 1.1
## Extra forward velocity added on Kong finish (dive-through push).
@export var kong_forward_push: float = 2.5
## Forward pitch lean during Kong (degrees, negative = lean forward).
@export var kong_pitch_lean: float = -18.0

@export_group("Ledge Vault")
## Master toggle. Ledge vault fires automatically when airborne below
## a platform edge within reach. Auto-only — no input trigger.
@export var ledge_vault_enabled: bool = true
## Physics mask for the ledge wall. Defaults to the same mask as
## vault_mask so any tagged platform works without extra setup.
## Broaden to landing_check_mask if you want it on general geometry.
@export_flags_3d_physics var ledge_vault_mask: int = 4
## Height above the feet at which the forward grab ray fires. Must be
## below the ledge top you want to grab — 0.6 catches most chest-to-
## hip-height ledges.
@export var ledge_grab_height: float = 0.6
## How far above the forward-hit to start searching for the ledge top.
## Larger values catch taller walls; the height gate filters the rest.
@export var ledge_top_search_height: float = 5.0
## Minimum ledge height above the player's feet.
@export var ledge_min_grab_height: float = 0.4
## Maximum ledge height above the player's feet.
@export var ledge_max_grab_height: float = 2.0
## Ledge motion duration.
@export var ledge_vault_duration: float = 0.4
## Natural arc for the pull-up. Still clamped up if the ledge would
## otherwise be clipped.
@export var ledge_arc_margin: float = 0.5
## How far past the edge the landing point sits. Keep this larger
## than (landing_probe_spread / 2 + landing_capsule_radius) so probes
## and the capsule fit cleanly on the top surface.
@export var ledge_landing_inset: float = 0.7
## Forward velocity on ledge exit — small, you just want to step
## onto the platform, not launch.
@export var ledge_exit_velocity: float = 1.0
## Momentum carry multiplier for ledge vault.
@export var ledge_carry_mult: float = 0.5
## Pitch lean during ledge pull-up (positive = look up).
@export var ledge_pitch_lean: float = 12.0

@export_group("Landing Safety")
@export var max_vault_landing_drop: float = 2.0
@export var landing_probe_count: int = 5
@export var landing_probe_spread: float = 0.6
@export var landing_flatness_tolerance: float = 0.25
@export var landing_capsule_check: bool = true
@export var landing_capsule_radius: float = 0.35
@export var landing_capsule_height: float = 1.7
@export_flags_3d_physics var landing_check_mask: int = 0xFFFFFFFF

@export_group("Motion")
@export var vault_duration: float = 0.35
@export var vault_arc_margin: float = 0.4
@export var vault_clearance: float = 0.15
@export var vault_forward_bonus: float = 1.0
@export var vault_side_speed: float = 5.0
@export var vault_exit_velocity: float = 1.5
@export var vault_momentum_carry: float = 0.7
@export var vault_easing: float = 0.6
@export var vault_cooldown: float = 0.25

@export_group("Motion — Styles")
@export var lazy_vault_max_speed: float = 3.0
@export var dash_vault_max_speed: float = 6.0
@export var style_duration_mult: Vector3 = Vector3(1.5, 1.0, 0.6)
@export var style_arc_mult: Vector3 = Vector3(1.5, 1.0, 0.4)
@export var style_carry_mult: Vector3 = Vector3(0.3, 1.0, 1.5)

@export_group("Turn")
@export var turn_degrees: float = 180.0
@export var turn_speed: float = 10.0

@export_group("Camera")
@export var vault_cam_pitch: float = -8.0
@export var vault_cam_roll: float = 4.0
@export var vault_cam_blend_in: float = 0.2
@export var vault_cam_blend_out: float = 0.3

@export_group("Camera — Dynamic Look")
@export var vault_look_roll_enabled: bool = true
@export var vault_look_roll_max: float = 15.0
@export var vault_look_roll_lerp: float = 10.0
@export var vault_look_pitch_max: float = 12.0
@export var vault_look_pitch_lerp: float = 10.0

@export_group("Debug")
@export var debug_draw: bool = false

# -----------------------------------------------------------------------------
# Public state
# -----------------------------------------------------------------------------

var vaulting: bool = false
var turned: bool = false

# -----------------------------------------------------------------------------
# Internal state
# -----------------------------------------------------------------------------

var _player: CharacterBody3D
var _sensors: SensorHub
var _fall_behavior: Node
var _wall_run: Node
var _ladder_climb: Node
var _ledge_grab: Node

var _cooldown_timer: float = 0.0
var _progress: float = 0.0
var _vault_start: Vector3 = Vector3.ZERO
var _vault_end: Vector3 = Vector3.ZERO
var _vault_top_y: float = 0.0
var _vault_dir: Vector3 = Vector3.ZERO
var _vault_right: Vector3 = Vector3.ZERO
var _entry_velocity: Vector3 = Vector3.ZERO
var _lateral_offset: float = 0.0
var _cam_blend: float = 0.0
var _vault_start_facing: float = 0.0

var _current_style: int = VaultStyle.DASH
var _current_kind: int = VaultKind.GROUND
var _actual_duration: float = 0.35
var _actual_arc: float = 0.4
var _actual_carry: float = 0.7
var _dynamic_roll: float = 0.0
var _dynamic_pitch: float = 0.0

var _last_landing: Vector3 = Vector3.ZERO

# -----------------------------------------------------------------------------
# Setup
# -----------------------------------------------------------------------------

func setup(p: CharacterBody3D) -> void:
	_player = p
	_sensors = p.sensors
	_fall_behavior = p.get_node_or_null("FallBehaviorComponent")
	_wall_run = p.get_node_or_null("WallRunComponent")
	_ladder_climb = p.get_node_or_null("LadderClimbComponent")
	_ledge_grab = p.get_node_or_null("LedgeGrabComponent")

# -----------------------------------------------------------------------------
# Public queries
# -----------------------------------------------------------------------------

func is_active() -> bool:
	return vaulting

# -----------------------------------------------------------------------------
# Detection
# -----------------------------------------------------------------------------

func detect(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta

	if not enabled or _player == null or _sensors == null:
		return
	if vaulting:
		return

	# Higher-priority gate.
	if _fall_behavior != null and _fall_behavior.has_method("is_active") \
			and _fall_behavior.is_active():
		return
	if _player.do_dash:
		return
	if _wall_run != null and _wall_run.has_method("is_active") \
			and _wall_run.is_active():
		return
	if _ladder_climb != null and _ladder_climb.has_method("is_active") \
			and _ladder_climb.is_active():
		return
	if _ledge_grab != null and _ledge_grab.has_method("is_active") \
			and _ledge_grab.is_active():
		return

	if _cooldown_timer > 0.0:
		return

	var is_airborne: bool = not _player.is_on_floor()

	var forward: Vector3 = -_player.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return
	forward = forward.normalized()

	if is_airborne:
		# Ledge first — it handles the below-ledge case Kong cannot.
		if _try_ledge_vault(forward):
			return
		_try_kong(forward)
		return

	_try_ground_vault(forward)

# --- Ground vault (unchanged behaviour) --------------------------------------

func _try_ground_vault(forward: Vector3) -> void:
	var manual: bool = false
	if vault_on_w and Input.is_action_pressed("forward"):
		manual = true
	if vault_on_jump and Input.is_action_just_pressed(accept_action):
		manual = true

	var speed: float = Vector3(_player.velocity.x, 0.0, _player.velocity.z).length()
	var auto: bool = auto_vault and speed > min_forward_speed

	if not manual and not auto:
		return

	var waist_origin: Vector3 = _player.global_position \
		+ Vector3.UP * waist_height
	var waist_end: Vector3 = waist_origin + forward * vault_reach
	var waist_hit: Dictionary = _cast_ray(waist_origin, waist_end, vault_mask)
	if waist_hit.is_empty():
		return

	var top_origin: Vector3 = waist_hit.position + Vector3.UP * (waist_height + 1.0)
	var top_end: Vector3 = waist_hit.position - Vector3.UP * 0.1
	var top_hit: Dictionary = _cast_ray(top_origin, top_end, vault_mask)
	if top_hit.is_empty():
		return

	var top_y: float = top_hit.position.y
	var obstacle_height: float = top_y - _player.global_position.y
	if obstacle_height < min_vault_height or obstacle_height > max_vault_height:
		return

	var normal: Vector3 = waist_hit.normal
	var flat_normal := Vector3(normal.x, 0.0, normal.z)
	if flat_normal.length_squared() < 0.0001:
		return
	flat_normal = flat_normal.normalized()
	var into_wall: Vector3 = -flat_normal

	var found_landing: bool = false
	for mult in [1.0, 2.0, 3.0]:
		var candidate: Vector3 = waist_hit.position \
			+ into_wall * (vault_forward_bonus * mult)
		if _check_landing_at(candidate, top_y, into_wall):
			found_landing = true
			break

	if not found_landing:
		return

	_begin(_last_landing, top_y, into_wall, VaultKind.GROUND)

# --- Kong vault (unchanged) --------------------------------------------------

## Kong fires automatically when airborne, moving forward fast enough,
## not falling too fast, and there's a vaultable obstacle in front of
## the player with ground past it.
func _try_kong(forward: Vector3) -> bool:
	if not kong_vault_enabled or not auto_vault:
		return false

	if _player.velocity.y < -kong_max_fall_speed:
		return false

	var speed_h: float = Vector3(
		_player.velocity.x, 0.0, _player.velocity.z
	).length()
	if speed_h < kong_min_forward_speed:
		return false

	var near_mid: Vector3 = _player.global_position + forward * (vault_reach * 0.6)
	var near_origin: Vector3 = near_mid + Vector3.UP * 0.5
	var near_end: Vector3 = near_mid - Vector3.UP * (max_vault_height + 3.0)
	var near_hit: Dictionary = _cast_ray(near_origin, near_end, vault_mask)
	if near_hit.is_empty():
		return false

	var far_mid: Vector3 = _player.global_position + forward * (vault_reach * 2.5)
	var far_origin: Vector3 = far_mid + Vector3.UP * 0.5
	var far_end: Vector3 = far_mid - Vector3.UP * (max_vault_height + 5.0)
	var far_hit: Dictionary = _cast_ray(far_origin, far_end, landing_check_mask)
	if far_hit.is_empty():
		return false

	var top_y: float = near_hit.position.y
	var ground_y: float = far_hit.position.y
	var obs_height: float = top_y - ground_y

	if _player.global_position.y < top_y - 0.1:
		return false

	if obs_height < min_vault_height or obs_height > max_vault_height:
		return false

	if not _check_landing_at(far_hit.position, top_y, forward):
		return false

	_begin(_last_landing, top_y, forward, VaultKind.KONG)
	return true

# --- Ledge vault (new) -------------------------------------------------------

## Ledge vault fires when the player is airborne BELOW a platform edge
## and within reach. Detection:
##   1. Forward ray at grab height (low chest) finds the wall.
##   2. Down-ray from above the wall hit finds the top edge.
##   3. Height gate: ledge top must be above the feet (below = Kong or
##      ground vault territory) but within reach.
##   4. Landing point is on top of the surface, past the edge by
##      ledge_landing_inset.
##   5. Landing safety check at that point.
func _try_ledge_vault(forward: Vector3) -> bool:
	if not ledge_vault_enabled or not auto_vault:
		return false

	# 1. Grab ray at grab height.
	var grab_origin: Vector3 = _player.global_position \
		+ Vector3.UP * ledge_grab_height
	var grab_end: Vector3 = grab_origin + forward * vault_reach
	var wall_hit: Dictionary = _cast_ray(
		grab_origin, grab_end, ledge_vault_mask
	)
	if wall_hit.is_empty():
		return false

	# 2. Top search from above the wall hit.
	var top_origin: Vector3 = wall_hit.position \
		+ Vector3.UP * ledge_top_search_height
	var top_end: Vector3 = wall_hit.position - Vector3.UP * 0.1
	var top_hit: Dictionary = _cast_ray(top_origin, top_end, ledge_vault_mask)
	if top_hit.is_empty():
		return false

	var ledge_top_y: float = top_hit.position.y
	var height_above_feet: float = ledge_top_y - _player.global_position.y

	# 3. Height gate.
	if height_above_feet < ledge_min_grab_height:
		return false
	if height_above_feet > ledge_max_grab_height:
		return false

	# 4. Landing point on top of the surface, past the edge.
	var landing_candidate := Vector3(
		top_hit.position.x + forward.x * ledge_landing_inset,
		ledge_top_y,
		top_hit.position.z + forward.z * ledge_landing_inset
	)

	# 5. Landing safety check.
	if not _check_landing_at(landing_candidate, ledge_top_y, forward):
		return false

	_begin(_last_landing, ledge_top_y, forward, VaultKind.LEDGE)
	return true

# --- Landing safety (unchanged) ----------------------------------------------

func _check_landing_at(candidate: Vector3, top_y: float, into_wall: Vector3) -> bool:
	var right: Vector3 = into_wall.cross(Vector3.UP)
	if right.length_squared() < 0.0001:
		return false
	right = right.normalized()

	var count: int = maxi(landing_probe_count, 1)
	var spread: float = landing_probe_spread
	var start_offset: float = -spread * 0.5

	var hit_points: Array[Vector3] = []

	for i in count:
		var offset: float = start_offset
		if count > 1:
			offset += (spread / float(count - 1)) * float(i)
		var probe_origin: Vector3 = candidate + right * offset + Vector3.UP * 1.5
		var probe_end: Vector3 = candidate + right * offset \
			- Vector3.UP * (1.5 + max_vault_landing_drop)
		var probe_hit: Dictionary = _cast_ray(
			probe_origin, probe_end, landing_check_mask
		)
		if probe_hit.is_empty():
			return false
		var hit_normal: Vector3 = probe_hit.normal
		if hit_normal.dot(Vector3.UP) < (1.0 - landing_flatness_tolerance):
			return false
		if probe_hit.position.y < (top_y - max_vault_landing_drop):
			return false
		hit_points.append(probe_hit.position)

	if hit_points.is_empty():
		return false

	var avg_y: float = 0.0
	for p in hit_points:
		avg_y += p.y
	avg_y /= float(hit_points.size())

	var landing := Vector3(candidate.x, avg_y, candidate.z)

	if landing_capsule_check:
		var shape := CapsuleShape3D.new()
		shape.radius = landing_capsule_radius
		shape.height = landing_capsule_height
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = Transform3D(
			Basis(),
			landing + Vector3.UP * (landing_capsule_height * 0.5)
		)
		query.collision_mask = landing_check_mask
		query.exclude = [_player.get_rid()]
		query.collide_with_areas = false
		query.collide_with_bodies = true
		var space = _sensors.space
		if space != null:
			var results: Array[Dictionary] = space.intersect_shape(query, 1)
			if results.size() > 0:
				return false

	_last_landing = landing
	return true

# -----------------------------------------------------------------------------
# Begin
# -----------------------------------------------------------------------------

func _begin(landing_point: Vector3, top_y: float, into_wall: Vector3,
		kind: int) -> void:
	vaulting = true
	turned = false
	_progress = 0.0
	_vault_start = _player.global_position
	_vault_end = landing_point
	_vault_top_y = top_y
	_vault_dir = into_wall
	_vault_right = into_wall.cross(Vector3.UP).normalized()
	_entry_velocity = _player.velocity
	_lateral_offset = 0.0
	_cam_blend = 0.0
	_vault_start_facing = _player.rotation.y
	_dynamic_roll = 0.0
	_dynamic_pitch = 0.0
	_current_kind = kind

	var style_arc: float

	if kind == VaultKind.KONG:
		_current_style = VaultStyle.KONG
		_actual_duration = kong_duration
		_actual_carry = vault_momentum_carry * kong_carry_mult
		style_arc = kong_arc_margin
	elif kind == VaultKind.LEDGE:
		_current_style = VaultStyle.LEDGE
		_actual_duration = ledge_vault_duration
		_actual_carry = vault_momentum_carry * ledge_carry_mult
		style_arc = ledge_arc_margin
	else:
		var speed: float = Vector3(
			_entry_velocity.x, 0.0, _entry_velocity.z
		).length()
		if speed < lazy_vault_max_speed:
			_current_style = VaultStyle.LAZY
		elif speed > dash_vault_max_speed:
			_current_style = VaultStyle.SPEED
		else:
			_current_style = VaultStyle.DASH
		_actual_duration = vault_duration * style_duration_mult[_current_style]
		_actual_carry = vault_momentum_carry * style_carry_mult[_current_style]
		style_arc = vault_arc_margin * style_arc_mult[_current_style]

	var interp_peak: float = (_vault_start.y + _vault_end.y) * 0.5
	var required_arc: float = maxf(
		0.0,
		_vault_top_y + vault_clearance - interp_peak
	)
	_actual_arc = maxf(style_arc, required_arc)

# -----------------------------------------------------------------------------
# Apply
# -----------------------------------------------------------------------------

func apply(delta: float) -> void:
	if _player == null or not vaulting:
		return

	if turn_enabled and not turned \
			and Input.is_action_just_pressed(turn_action):
		turned = true

	var target_yaw: float = atan2(_vault_dir.x, _vault_dir.z)
	if turned:
		target_yaw = _vault_start_facing + deg_to_rad(turn_degrees)
	_player.rotation.y = lerp_angle(
		_player.rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0)
	)

	var x_input: float = Input.get_axis("left", "right")
	if side_movement and absf(x_input) > 0.01:
		_lateral_offset += x_input * vault_side_speed * delta
		_lateral_offset = clampf(
			_lateral_offset,
			-vault_forward_bonus,
			vault_forward_bonus
		)

	# Style-based lean.
	var speed_lean: float = 0.0
	if _current_style == VaultStyle.SPEED:
		speed_lean = -vault_look_pitch_max
	elif _current_style == VaultStyle.LAZY:
		speed_lean = vault_look_pitch_max * 0.3
	elif _current_style == VaultStyle.KONG:
		speed_lean = kong_pitch_lean
	elif _current_style == VaultStyle.LEDGE:
		speed_lean = ledge_pitch_lean

	_dynamic_roll = lerpf(
		_dynamic_roll,
		-x_input * vault_look_roll_max,
		clampf(vault_look_roll_lerp * delta, 0.0, 1.0)
	)
	_dynamic_pitch = lerpf(
		_dynamic_pitch,
		speed_lean,
		clampf(vault_look_pitch_lerp * delta, 0.0, 1.0)
	)

	_progress += delta / maxf(_actual_duration, 0.0001)
	_progress = clampf(_progress, 0.0, 1.0)
	var eased: float = lerpf(
		_progress, smoothstep(0.0, 1.0, _progress), vault_easing
	)

	var base_pos: Vector3 = _vault_start.lerp(_vault_end, eased)
	var arc: float = sin(_progress * PI) * _actual_arc
	var side: Vector3 = _vault_right * _lateral_offset
	_player.global_position = base_pos + Vector3.UP * arc + side
	_player.velocity = Vector3.ZERO

	if _progress >= 1.0:
		_finish_vault()

func _finish_vault() -> void:
	var finished_style: int = _current_style

	vaulting = false
	turned = false
	_lateral_offset = 0.0
	_cooldown_timer = vault_cooldown

	var floor_hit: Dictionary = _cast_ray(
		_player.global_position + Vector3.UP * 0.2,
		_player.global_position - Vector3.UP * 0.6,
		landing_check_mask
	)
	var on_floor: bool = false
	if not floor_hit.is_empty():
		var dy: float = absf(_player.global_position.y - floor_hit.position.y)
		if dy < 0.15:
			_player.global_position.y = floor_hit.position.y
		on_floor = true

	var carry: Vector3 = Vector3(_entry_velocity.x, 0.0, _entry_velocity.z) \
		* _actual_carry

	if finished_style == VaultStyle.KONG:
		_player.velocity = carry + _vault_dir * (vault_exit_velocity + kong_forward_push)
	elif finished_style == VaultStyle.LEDGE:
		# Small forward step onto the platform — no launch, we're
		# standing on the surface now.
		_player.velocity = carry + _vault_dir * ledge_exit_velocity
	elif on_floor:
		_player.velocity = carry + _vault_dir * vault_exit_velocity
	else:
		_player.velocity = carry

# -----------------------------------------------------------------------------
# Camera
# -----------------------------------------------------------------------------

func update_camera(delta: float) -> void:
	if _player == null:
		return

	if vaulting:
		_cam_blend = minf(1.0, _cam_blend + delta / maxf(vault_cam_blend_in, 0.0001))
	else:
		_cam_blend = maxf(0.0, _cam_blend - delta / maxf(vault_cam_blend_out, 0.0001))

	if _cam_blend <= 0.0001:
		return

	var pitch_deg: float = vault_cam_pitch * _cam_blend
	var roll_deg: float = vault_cam_roll * _cam_blend

	pitch_deg += _dynamic_pitch * _cam_blend
	roll_deg += _dynamic_roll * _cam_blend

	_player.add_cam_rotation(
		deg_to_rad(pitch_deg),
		0.0,
		deg_to_rad(roll_deg)
	)

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

func _cast_ray(from: Vector3, to: Vector3, mask: int) -> Dictionary:
	if _sensors == null or _sensors.space == null or _player == null:
		return {}
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = mask
	q.exclude = [_player.get_rid()]
	q.collide_with_areas = false
	q.collide_with_bodies = true
	return _sensors.space.intersect_ray(q)
