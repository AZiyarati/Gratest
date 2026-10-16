## Ladder climb component. Attaches to layer-5 (bit 16) ladder geometry
## when the player walks into it, provides smooth or stepped climb, and
## auto-mantles over the top when the player reaches the top while
## holding climb-up.
##
## DOCUMENTED RAY-CAST EXCEPTION: SensorHub has no ladder sensor, so
## this component casts its own rays — all on `ladder_mask` (layer 5,
## bit 16), excluding the player. See FPC_PROJECT.md "Components that
## legitimately cast their own rays".
##
## Ladder geometry must be on layer 5 (bit 16). See FPC_PROJECT.md
## collision layer table.
##
## Never writes eyes.* / cam.* directly — uses _player.add_eye_offset.
## Never calls _player.play_jump (jump-off-a-ladder is a later session).
class_name LadderClimbComponent
extends Node


# -----------------------------------------------------------------------------
# Exports
# -----------------------------------------------------------------------------

@export_group("Features")
## Master toggle. When false, detect() detaches and apply() does nothing.
@export var enabled: bool = true
## When true, the component attaches automatically while airborne.
## On the ground, a FRESH climb-up press is always required — held
## climb-up does not re-grab, so the player can walk away from a
## ladder after climbing down it.
@export var auto_attach: bool = true

@export_group("Input")
## Input action that climbs up.
@export var climb_up_action: String = "forward"
## Secondary input action that climbs up (e.g. Space).
@export var climb_up_alt_action: String = "ui_accept"
## Input action that climbs down.
@export var climb_down_action: String = "backward"
## Secondary input action that triggers a fast smooth descent (Ctrl).
@export var climb_down_alt_action: String = "crouch"
## Input action that drives the auto-mantle at the top (default = W).
@export var mantle_action: String = "forward"
## Input action that jumps the player off the ladder when they are no
## longer looking at it.
@export var jump_off_action: String = "ui_accept"

@export_group("Detection")
## Physics mask for ladder geometry. Layer 5 (bit 16).
@export_flags_3d_physics var ladder_mask: int = 16
## Forward reach of the attach ray, beyond the back offset.
@export var attach_reach: float = 0.8
## Vertical heights (from the feet) at which attach rays fire.
@export var attach_probe_heights: PackedFloat32Array = [0.4, 1.0, 1.6]
## Origin is pushed back this far behind the player before the ray fires.
@export var attach_back_offset: float = 0.25
## How far the ladder can drift before the player detaches mid-climb.
@export var detach_distance: float = 1.6
## How far up the attach point the ladder-top search ray travels.
@export var ladder_top_search_distance: float = 6.0
## XZ distance from the ladder face the player is snapped to.
@export var standoff_distance: float = 0.35

@export_group("Aim")
## Dot-product threshold for "player is facing the ladder". Player
## forward · ladder_normal must be less than -look_dot_threshold. 0.3
## roughly equals a 72° cone around the ladder.
@export var look_dot_threshold: float = 0.3

@export_group("Ladder Centering")
## When true, the character snaps to the horizontal center of the
## ladder face, not just to the point where the attach ray hits.
## A lateral scan along the ladder tangent finds the left and right
## edges; the player is placed at their midpoint.
@export var center_on_ladder: bool = true
## Maximum half-width scanned when centering (metres).
@export var ladder_max_half_width: float = 1.5
## Step size for the lateral scan (metres). Smaller = more accurate.
@export var ladder_scan_step: float = 0.05
## How far in front of the attach point the scan origin sits, before
## it probes back into the ladder (metres).
@export var ladder_scan_forward: float = 0.1
## How deep the scan probes behind the attach point (metres).
@export var ladder_scan_depth: float = 0.6

@export_group("Climb")
## Speed (m/s) of the smooth climb style.
@export var climb_speed: float = 3.0
## Speed (m/s) while holding the down-alt action (Ctrl). Feels like
## sliding down the ladder — fast and smooth, no stepping.
@export var ladder_slide_speed: float = 8.0
## How fast the player snaps onto the ladder axis (XZ) after the
## initial attach lerp has finished.
@export var climb_snap_speed: float = 12.0
## 0 = Smooth (continuous velocity), 1 = Stepped (discrete hops).
@export_enum("Smooth", "Stepped") var climb_style: int = 0
## Gentle XZ lerp rate used during the first moments after attach, so
## the player slides smoothly onto the ladder's center instead of
## snapping sideways.
@export var attach_lerp_speed: float = 6.0
## Seconds after attach during which attach_lerp_speed is used
## instead of climb_snap_speed.
@export var attach_lerp_duration: float = 0.3

@export_group("Climb — Stepped")
## Distance of one discrete step (metres).
@export var step_size: float = 0.4
## Velocity gain per metre of remaining step distance.
@export var step_speed: float = 4.5
## Minimum time between two consecutive step changes.
@export var step_settle_time: float = 0.08

@export_group("Mantle")
## Duration of the mantle arc (seconds).
@export var mantle_duration: float = 0.5
## How high above the ladder top the mantle arc rises.
@export var mantle_rise: float = 1.6
## How far forward (into the ladder) the mantle arc travels.
@export var mantle_forward: float = 0.7
## Movement lockout refreshed each frame during the mantle.
@export var mantle_lockout: float = 0.4

@export_group("Jump Off")
## Horizontal speed applied along the player's look direction when
## jumping off the ladder (they must be looking away from it).
@export var jump_off_forward: float = 5.0
## Upward velocity when jumping off.
@export var jump_off_up: float = 5.0
## Time after a jump-off during which auto-attach is suppressed.
@export var reattach_cooldown: float = 0.3

@export_group("Jump Off — Variable")
## Master toggle for the variable ladder jump. When true, the ladder
## jump-off height scales with how long the jump action is held.
@export var enable_variable_ladder_jump: bool = true
## Minimum upward velocity after a ladder jump cut.
@export var ladder_jump_min_velocity: float = 2.0
## Fraction of current upward velocity kept when the ladder jump is cut.
@export var ladder_jump_cut_scale: float = 0.45

@export_group("Camera")
## Enable the climb head bob.
@export var bob_enabled: bool = true
## Angular frequency of the climb bob.
@export var bob_speed: float = 10.0
## Amplitude of the climb bob (metres).
@export var bob_intensity: float = 0.06

@export_group("Debug")
## Draw debug rays (reserved).
@export var debug_draw: bool = false


# -----------------------------------------------------------------------------
# Cached refs
# -----------------------------------------------------------------------------

var _player: CharacterBody3D
var _sensors: SensorHub
var _fall_behavior: Node
var _wall_run: Node
var _ledge_grab: Node
var _vault: Node


# -----------------------------------------------------------------------------
# Private state
# -----------------------------------------------------------------------------

var _attached: bool = false
var _mantling: bool = false

var _ladder_normal: Vector3 = Vector3.ZERO
var _attach_point: Vector3 = Vector3.ZERO
var _attach_y: float = 0.0
var _ladder_top_y: float = 0.0

var _current_step: int = 0
var _step_target_y: float = 0.0
var _step_settle_timer: float = 0.0

var _mantle_start: Vector3 = Vector3.ZERO
var _mantle_end: Vector3 = Vector3.ZERO
var _mantle_timer: float = 0.0

var _bob_phase: float = 0.0
var _bob_offset: float = 0.0

var _was_on_floor: bool = true
var _reattach_timer: float = 0.0
## Counts down from attach_lerp_duration after each successful attach.
var _attach_lerp_timer: float = 0.0
## True while the ladder jump-off is still eligible for a variable cut.
var _ladder_jump_cut_pending: bool = false


# -----------------------------------------------------------------------------
# Setup
# -----------------------------------------------------------------------------

## Cache the owning player, its SensorHub, and the higher-priority sibling
## components used by the gate. Missing siblings are treated as inactive.
func setup(p: CharacterBody3D) -> void:
	_player = p
	_sensors = p.sensors
	_fall_behavior = p.get_node_or_null("FallBehaviorComponent")
	_wall_run = p.get_node_or_null("WallRunComponent")
	_ledge_grab = p.get_node_or_null("LedgeGrabComponent")
	_vault = p.get_node_or_null("VaultComponent")
	_was_on_floor = p.is_on_floor()


# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

## True while attached to a ladder OR mantling over one.
func is_active() -> bool:
	return _attached or _mantling


## True while attached to a ladder (false during the mantle).
func is_climbing() -> bool:
	return _attached and not _mantling


# -----------------------------------------------------------------------------
# Detection
# -----------------------------------------------------------------------------

## Called each physics frame by player.gd, BEFORE the priority chain.
func detect(delta: float) -> void:
	if _reattach_timer > 0.0:
		_reattach_timer -= delta

	if not enabled or _player == null or _sensors == null:
		_exit_all()
		return
	if _higher_priority_active():
		_exit_all()
		return
		
	# Variable ladder jump cut.
	if _ladder_jump_cut_pending:
		_tick_ladder_jump_cut()
		
	if _mantling:
		_tick_mantle(delta)
		_was_on_floor = _player.is_on_floor()
		return

	if not _attached:
		if auto_attach:
			_try_attach()
		_was_on_floor = _player.is_on_floor()
		return

	_tick_attached(delta)
	_was_on_floor = _player.is_on_floor()


func _higher_priority_active() -> bool:
	if _fall_behavior != null and _fall_behavior.has_method("is_active") \
			and _fall_behavior.is_active():
		return true
	if _player.do_dash:
		return true
	if _wall_run != null and _wall_run.has_method("is_active") \
			and _wall_run.is_active():
		return true
	if _ledge_grab != null and _ledge_grab.has_method("is_active") \
			and _ledge_grab.is_active():
		return true
	if _vault != null and _vault.get("vaulting") == true:
		return true
	return false


func _try_attach() -> void:
	if _reattach_timer > 0.0:
		return

	# A fresh W press always attempts an attach, regardless of
	# auto_attach, so the component is usable with auto_attach off.
	var manual_press: bool = Input.is_action_just_pressed(climb_up_action)

	# When auto_attach is off, only a manual press opens the door.
	if not auto_attach and not manual_press:
		return

	# On the ground, never attach on a held key. Holding W while
	# standing next to a ladder must NOT re-grab it every frame, or
	# the player could not walk away after climbing down. Only a
	# fresh press attaches.
	if _player.is_on_floor() and not manual_press:
		return

	var forward: Vector3 = _body_forward_xz()
	if forward.length_squared() < 0.0001:
		return
	var reach: float = attach_reach + attach_back_offset
	for h in attach_probe_heights:
		var origin: Vector3 = _player.global_position \
			+ Vector3.UP * h - forward * attach_back_offset
		var end: Vector3 = origin + forward * reach
		var hit: Dictionary = _cast_ray(origin, end)
		if hit.is_empty():
			continue
		_enter_attached(hit)
		return


func _enter_attached(hit: Dictionary) -> void:
	_attached = true
	_mantling = false

	var n: Vector3 = hit.normal
	var flat := Vector3(n.x, 0.0, n.z)
	if flat.length_squared() > 0.0001:
		_ladder_normal = flat.normalized()
	else:
		_ladder_normal = -_body_forward_xz()

	_attach_point = hit.position
	# If centering is on, replace the raw hit point with the ladder's
	# horizontal center along its width. The attach lerp then eases
	# the player there smoothly.
	if center_on_ladder:
		_attach_point = _find_ladder_center(_attach_point, _ladder_normal)
	_attach_y = _player.global_position.y
	_ladder_top_y = _find_ladder_top(hit.position)

	_current_step = 0
	_step_target_y = _attach_y
	_step_settle_timer = 0.0
	_bob_phase = 0.0
	_bob_offset = 0.0
	# Start the gentle attach lerp window. The next few apply() frames
	# ease XZ toward the ladder axis at attach_lerp_speed, then
	# climb_snap_speed takes over.
	_attach_lerp_timer = attach_lerp_duration

	_player.velocity = Vector3.ZERO


func _find_ladder_top(start: Vector3) -> float:
	var origin: Vector3 = start
	var last_hit_y: float = start.y
	var hit_any: bool = false
	for i in 32:
		var end: Vector3 = origin + Vector3.UP * ladder_top_search_distance
		var hit: Dictionary = _cast_ray(origin, end)
		if hit.is_empty():
			break
		hit_any = true
		last_hit_y = hit.position.y
		origin = hit.position + Vector3.UP * 0.05
	if hit_any:
		return last_hit_y
	return _attach_y + ladder_top_search_distance

## Walk laterally along the ladder face to find where the ladder
## geometry ends on each side, then return the midpoint of the two
## edges. Falls back to the original point when centering fails.
func _find_ladder_center(attach_point: Vector3, normal: Vector3) -> Vector3:
	var tangent: Vector3 = normal.cross(Vector3.UP)
	if tangent.length_squared() < 0.0001:
		return attach_point
	tangent = tangent.normalized()

	var step: float = maxf(ladder_scan_step, 0.01)
	var max_d: float = maxf(ladder_max_half_width, step)
	var near_face: Vector3 = attach_point + normal * ladder_scan_forward
	var far_face: Vector3 = attach_point - normal * ladder_scan_depth

	var edge_plus: float = 0.0
	var edge_minus: float = 0.0

	# Scan in +tangent until the probe ray misses ladder geometry.
	var d: float = 0.0
	while d < max_d:
		d += step
		var origin: Vector3 = near_face + tangent * d
		var end: Vector3 = far_face + tangent * d
		var hit: Dictionary = _cast_ray(origin, end)
		if hit.is_empty():
			break
		edge_plus = d

	# Scan in -tangent.
	d = 0.0
	while d < max_d:
		d += step
		var origin: Vector3 = near_face - tangent * d
		var end: Vector3 = far_face - tangent * d
		var hit: Dictionary = _cast_ray(origin, end)
		if hit.is_empty():
			break
		edge_minus = d

	# Midpoint between the two edges, projected back onto the near face.
	var center_offset: float = (edge_plus - edge_minus) * 0.5
	return attach_point + tangent * center_offset

func _tick_attached(_delta: float) -> void:
	# On the ground, stay attached only while the player is holding a
	# climb key. Releasing both stands them up and hands control back
	# to locomotion, which is what lets them walk away.
	var up: bool = _is_up_pressed()
	var down: bool = _is_down_pressed()
	if _player.is_on_floor() and not up and not down:
		_detach()
		return

	# Ladder no longer in front of us → detach.
	var dir: Vector3 = -_ladder_normal
	if dir.length_squared() < 0.0001:
		_detach()
		return
	var origin: Vector3 = _player.global_position + Vector3.UP * 1.0
	var end: Vector3 = origin + dir * detach_distance
	var hit: Dictionary = _cast_ray(origin, end)
	if hit.is_empty():
		_detach()


func _detach() -> void:
	_attached = false
	_mantling = false
	_current_step = 0
	_step_settle_timer = 0.0
	_bob_phase = 0.0
	_attach_lerp_timer = 0.0


func _exit_all() -> void:
	if _attached or _mantling:
		_attached = false
		_mantling = false
		_current_step = 0
		_step_settle_timer = 0.0
		_bob_phase = 0.0
		_bob_offset = 0.0
		_attach_lerp_timer = 0.0


# -----------------------------------------------------------------------------
# Apply (physics ownership)
# -----------------------------------------------------------------------------

## Take over physics while attached (or mantling). Called by player.gd
## when is_active() returns true.
func apply(delta: float) -> void:
	if _player == null:
		return
	if _mantling:
		# Mantle is ticked in detect(). We keep velocity zeroed here so
		# move_and_slide() at the end of the frame does not fight the
		# position writes.
		_player.velocity = Vector3.ZERO
		return
	if not _attached:
		return

	# Snap XZ onto the ladder axis. Y is driven purely by climb velocity.
	# On the first moments after attach, a gentler rate eases the player
	# onto the ladder's center — after that climb_snap_speed takes over.
	var snap_rate: float = climb_snap_speed
	if _attach_lerp_timer > 0.0:
		snap_rate = attach_lerp_speed
		_attach_lerp_timer -= delta
	var target_xz: Vector3 = _attach_point + _ladder_normal * standoff_distance
	var t: float = clampf(snap_rate * delta, 0.0, 1.0)
	_player.global_position.x = lerpf(_player.global_position.x, target_xz.x, t)
	_player.global_position.z = lerpf(_player.global_position.z, target_xz.z, t)

	# Facing check: if the player turned away from the ladder, Space
	# becomes a jump-off instead of a climb-up, and W/S are suppressed
	# so the player hangs in place until they look back.
	var facing: bool = _is_facing_ladder()

	if not facing and Input.is_action_just_pressed(jump_off_action):
		_jump_off()
		return

	# Ctrl (down-alt) = fast smooth descent. Works regardless of facing
	# — this is the "slide down the ladder" gesture.
	var ctrl_down: bool = climb_down_alt_action != "" \
		and Input.is_action_pressed(climb_down_alt_action)

	var up: bool = facing and _is_up_pressed()
	var down: bool = facing and _is_down_pressed()

	var vel: Vector3 = _player.velocity
	vel.x = 0.0
	vel.z = 0.0
	vel.y = 0.0

	if ctrl_down:
		vel.y = -ladder_slide_speed
	elif climb_style == 0:
		if up and not down:
			vel.y = climb_speed
		elif down and not up:
			vel.y = -climb_speed
	else:
		# NOTE: Vector3 is a value type in GDScript. Passing `vel` by
		# reference does not work — _apply_stepped returns the Y value.
		vel.y = _apply_stepped(delta, up, down)

	# Auto-mantle when the top is reached while holding up.
	if up and _player.global_position.y >= _ladder_top_y - standoff_distance:
		_player.velocity = vel
		_begin_mantle()
		return

	_player.velocity = vel


func _apply_stepped(delta: float, up: bool, down: bool) -> float:
	var reached: bool = absf(
		_player.global_position.y - _step_target_y) < step_size * 0.25
	var can_step: bool = _step_settle_timer <= 0.0 and reached
	if can_step:
		if up and not down:
			_current_step += 1
			_step_target_y = _attach_y + _current_step * step_size
			_step_settle_timer = step_settle_time
		elif down and not up:
			_current_step -= 1
			_step_target_y = _attach_y + _current_step * step_size
			_step_settle_timer = step_settle_time
	else:
		_step_settle_timer -= delta

	var dy: float = _step_target_y - _player.global_position.y
	var v: float = dy * step_speed
	var max_v: float = step_size * step_speed
	return clampf(v, -max_v, max_v)


# -----------------------------------------------------------------------------
# Facing / jump-off
# -----------------------------------------------------------------------------

## True when the player's body forward is within `look_dot_threshold`
## of pointing at the ladder face. `_ladder_normal` points from the
## ladder toward the player, so facing the ladder means
## forward · normal < 0.
func _is_facing_ladder() -> bool:
	if _ladder_normal.length_squared() < 0.0001:
		return true
	var fwd: Vector3 = _body_forward_xz()
	if fwd.length_squared() < 0.0001:
		return false
	var d: float = fwd.dot(_ladder_normal)
	return d < -look_dot_threshold


func _jump_off() -> void:
	# Jump along the player's CURRENT look direction (body forward on
	# XZ). This is why the look-away requirement exists: while facing
	# the ladder, Space climbs; once turned away, Space launches the
	# player the way they are looking.
	var look_dir: Vector3 = _body_forward_xz()
	if look_dir.length_squared() < 0.0001:
		look_dir = _ladder_normal

	# Tiny away-from-ladder bias so the detach frame can't clip the
	# ladder face if the player is looking near-perpendicular.
	var move_dir: Vector3 = look_dir + _ladder_normal * 0.25
	if move_dir.length_squared() < 0.0001:
		move_dir = _ladder_normal
	move_dir = move_dir.normalized()

	_detach()
	_reattach_timer = reattach_cooldown
	_ladder_jump_cut_pending = enable_variable_ladder_jump
	_player.velocity.x = move_dir.x * jump_off_forward
	_player.velocity.z = move_dir.z * jump_off_forward
	_player.velocity.y = jump_off_up

## Advance the variable ladder jump cut. Fires as soon as Space is
## released while ascending. Suppresses movement's own cut so the
## impulse cannot be clipped twice.
func _tick_ladder_jump_cut() -> void:
	if not enable_variable_ladder_jump:
		_ladder_jump_cut_pending = false
		return
	if _player.is_on_floor():
		_ladder_jump_cut_pending = false
		return
	if _player.velocity.y <= 0.0:
		_ladder_jump_cut_pending = false
		return
	if Input.is_action_pressed(jump_off_action):
		return
	var cut: float = maxf(
		_player.velocity.y * ladder_jump_cut_scale,
		ladder_jump_min_velocity
	)
	_player.velocity.y = cut
	_ladder_jump_cut_pending = false
	# Prevent movement's own variable jump from cutting a second time.
	var m: Variant = _player.get("movement")
	if m != null and m.has_method("lock_jump_cut"):
		m.lock_jump_cut()


# -----------------------------------------------------------------------------
# Mantle
# -----------------------------------------------------------------------------

func _begin_mantle() -> void:
	_attached = false
	_mantling = true
	_mantle_timer = 0.0
	_mantle_start = _player.global_position

	var into_ladder: Vector3 = -_ladder_normal
	var end: Vector3 = Vector3(_mantle_start.x, _ladder_top_y, _mantle_start.z) \
		+ into_ladder * mantle_forward \
		+ Vector3.UP * (mantle_rise - standoff_distance)
	_mantle_end = end
	_player.velocity = Vector3.ZERO


func _tick_mantle(delta: float) -> void:
	_mantle_timer += delta
	var t: float = clampf(_mantle_timer / mantle_duration, 0.0, 1.0)
	var eased: float = smoothstep(0.0, 1.0, t)
	_player.global_position = _mantle_start.lerp(_mantle_end, eased)
	_player.velocity = Vector3.ZERO
	_player.movement_lockout = mantle_lockout
	if t >= 1.0:
		_finish_mantle()


func _finish_mantle() -> void:
	_mantling = false
	# Small forward nudge so the transition back to locomotion reads clean.
	var fwd: Vector3 = _body_forward_xz()
	_player.velocity.x = fwd.x * 1.0
	_player.velocity.z = fwd.z * 1.0
	_player.velocity.y = 0.0
	_current_step = 0
	_step_settle_timer = 0.0
	_bob_phase = 0.0


# -----------------------------------------------------------------------------
# Camera
# -----------------------------------------------------------------------------

## Adds the climb head bob. Called by player.gd in the visuals block.
func update_camera(delta: float) -> void:
	if not bob_enabled or _player == null:
		return

	var moving: bool = false
	if _attached and not _mantling and _is_facing_ladder():
		moving = _is_up_pressed() or _is_down_pressed()

	if moving:
		_bob_phase += bob_speed * delta
		_bob_offset = sin(_bob_phase) * bob_intensity
	else:
		var t: float = clampf(bob_speed * delta, 0.0, 1.0)
		_bob_offset = lerpf(_bob_offset, 0.0, t)

	_player.add_eye_offset(0.0, _bob_offset, 0.0)


# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

func _is_up_pressed() -> bool:
	if Input.is_action_pressed(climb_up_action):
		return true
	if climb_up_alt_action != "" and Input.is_action_pressed(climb_up_alt_action):
		return true
	return false


func _is_down_pressed() -> bool:
	if Input.is_action_pressed(climb_down_action):
		return true
	if climb_down_alt_action != "" and Input.is_action_pressed(climb_down_alt_action):
		return true
	return false


func _body_forward_xz() -> Vector3:
	if _player == null:
		return Vector3.ZERO
	var fwd: Vector3 = -_player.global_transform.basis.z
	var flat := Vector3(fwd.x, 0.0, fwd.z)
	if flat.length_squared() < 0.0001:
		return Vector3.ZERO
	return flat.normalized()


func _cast_ray(from: Vector3, to: Vector3) -> Dictionary:
	if _sensors == null or _sensors.space == null:
		return {}
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = ladder_mask
	q.exclude = [_player.get_rid()]
	q.collide_with_areas = false
	q.collide_with_bodies = true
	return _sensors.space.intersect_ray(q)
