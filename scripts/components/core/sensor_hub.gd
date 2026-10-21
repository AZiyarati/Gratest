# res://scripts/components/core/sensor_hub.gd
## Centralized sensor hub. The only component that casts rays.
##
## Every other component reads its state from here. Fields are refreshed
## exactly once per physics frame via [method update]. Do not cache results
## beyond one frame; do not cast your own rays from other components.
class_name SensorHub
extends Node

# -----------------------------------------------------------------------------
# Exports
# -----------------------------------------------------------------------------

@export_group("Detection — Masks")
## Collision mask used for slope detection rays.
@export_flags_3d_physics var mask_slope: int = 32
## Collision mask used for ground detection rays.
@export_flags_3d_physics var mask_ground: int = 1
## Collision mask used for ceiling detection rays.
@export_flags_3d_physics var mask_ceiling: int = 1
## Collision mask used for wall detection rays.
@export_flags_3d_physics var mask_wall: int = 128
## Collision mask used for ledge detection rays.
@export_flags_3d_physics var mask_ledge: int = 8
## Collision mask used for grapple anchor detection.
@export_flags_3d_physics var mask_hook: int = 2
## Collision mask used for vaultable obstacles.
@export_flags_3d_physics var mask_vault: int = 4

@export_group("Detection — Shapes")
## How far above the player the slope probe starts.
@export var slope_probe_up: float = 1.5
## How far down the slope probe travels.
@export var slope_probe_down: float = 3.0
## How far down the ground short-probe travels.
@export var ground_probe_down: float = 0.2
## How far up the ceiling probe travels.
@export var ceiling_probe_up: float = 2.0
## Forward reach of wall rays.
@export var wall_reach: float = 1.0
## Origin offset behind the player for wall rays.
@export var wall_back_offset: float = 0.35
## Vertical heights used for the 3-ray wall sweep fallback.
@export var wall_probe_heights: PackedFloat32Array = [0.4, 1.0, 1.6]
## Height above the feet for side wall rays.
@export var side_probe_height: float = 0.9
## Range of the hook anchor ray.
@export var hook_range: float = 30.0

@export_group("Detection — Wall Shape Cast")
## When true, use a ShapeCast3D for front wall detection instead of rays.
@export var wall_use_shape_cast: bool = true
## Size of the box used for the wall shape cast.
@export var wall_probe_size: Vector3 = Vector3(0.5, 1.4, 0.15)
## Forward reach of the wall shape cast.
@export var wall_probe_reach: float = 0.8
## Vertical center of the wall shape cast, relative to player origin.
@export var wall_probe_center_y: float = 0.9

# -----------------------------------------------------------------------------
# Cached refs
# -----------------------------------------------------------------------------

## The owning player body. Cached in setup().
var player: CharacterBody3D
## Physics space state from the player's world.
var space: PhysicsDirectSpaceState3D
## Wall-detection shape cast, created in setup() when enabled.
var _wall_cast: ShapeCast3D

# -----------------------------------------------------------------------------
# Public sensor fields (refreshed once per physics frame via update())
# -----------------------------------------------------------------------------

## Raw WASD input. x = left/right, y = forward(-)/backward(+).
var input_dir: Vector2 = Vector2.ZERO
## Input direction mapped into world space (normalized).
var wish_dir_world: Vector3 = Vector3.ZERO
## Camera forward in 3D.
var cam_forward: Vector3 = Vector3.FORWARD
## Camera forward flattened to the XZ plane (normalized).
var cam_forward_xz: Vector3 = Vector3.FORWARD
## Player right vector on the XZ plane (normalized).
var player_right: Vector3 = Vector3.RIGHT
## Current gravity vector (from the player).
var gravity: Vector3 = Vector3.DOWN

## True when the slope ray hit a surface.
var floor_hit: bool = false
## Normal of the detected floor.
var floor_normal: Vector3 = Vector3.UP
## World Y of the floor contact (or player Y on miss).
var floor_hit_y: float = 0.0
## Angle in degrees between floor_normal and UP.
var floor_angle_deg: float = 0.0
## True when the short ground probe finds nothing below the feet.
var above_ground: bool = false

## True when the ceiling ray hit a surface.
var ceiling_hit: bool = false
## World position of the ceiling hit (ZERO when no hit).
var ceiling_point: Vector3 = Vector3.ZERO

## True when the front shape cast / ray sweep found a wall.
var wall_front_hit: bool = false
## Flattened (XZ) normal of the front wall.
var wall_front_normal: Vector3 = Vector3.ZERO
## World position of the front wall hit.
var wall_front_point: Vector3 = Vector3.ZERO
## All front wall contacts this frame. Each dict: { point, normal }.
var wall_front_samples: Array[Dictionary] = []
## True when the left side ray hit a wall.
var wall_left_hit: bool = false
## Flattened (XZ) normal of the left wall.
var wall_left_normal: Vector3 = Vector3.ZERO
## True when the right side ray hit a wall.
var wall_right_hit: bool = false
## Flattened (XZ) normal of the right wall.
var wall_right_normal: Vector3 = Vector3.ZERO

## True when the front shape cast / ray sweep found a ledge surface.
var ledge_front_hit: bool = false
## Flattened (XZ) normal of the front ledge.
var ledge_front_normal: Vector3 = Vector3.ZERO
## World position of the front ledge hit.
var ledge_front_point: Vector3 = Vector3.ZERO

## Ray result dictionary for the hook anchor (empty when no hit).
var hook_hit: Dictionary = {}

# -----------------------------------------------------------------------------
# Internal
# -----------------------------------------------------------------------------

var _last_physics_frame: int = -1

# -----------------------------------------------------------------------------
# Setup
# -----------------------------------------------------------------------------

## Cache references and (optionally) build the wall shape cast.
func setup(p: CharacterBody3D) -> void:
	player = p
	space = player.get_world_3d().direct_space_state
	if wall_use_shape_cast and _wall_cast == null:
		_create_wall_shape_cast()


func _create_wall_shape_cast() -> void:
	_wall_cast = ShapeCast3D.new()
	var box := BoxShape3D.new()
	box.size = wall_probe_size
	_wall_cast.shape = box
	_wall_cast.target_position = Vector3(0.0, 0.0, -wall_probe_reach)
	_wall_cast.collision_mask = mask_wall | mask_ledge
	_wall_cast.max_results = 16
	_wall_cast.enabled = false
	_wall_cast.exclude_parent = true
	_wall_cast.collide_with_areas = false
	_wall_cast.collide_with_bodies = true
	player.add_child(_wall_cast)
	_wall_cast.add_exception(player)

# -----------------------------------------------------------------------------
# Update
# -----------------------------------------------------------------------------

## Refresh every sensor field. Safe to call multiple times per frame.
func update() -> void:
	if player == null:
		return
	var frame := Engine.get_physics_frames()
	if frame == _last_physics_frame:
		return
	_last_physics_frame = frame

	_sample_cheap_reads()
	_sample_floor()
	_sample_ceiling()
	_sample_walls()
	_sample_hook()


func _sample_cheap_reads() -> void:
	input_dir = Input.get_vector("left", "right", "forward", "backward")
	gravity = player.get_gravity()

	var cam_node: Node3D = player.cam
	cam_forward = -cam_node.global_transform.basis.z

	cam_forward_xz = Vector3(cam_forward.x, 0.0, cam_forward.z)
	if cam_forward_xz.length_squared() > 0.0001:
		cam_forward_xz = cam_forward_xz.normalized()
	else:
		var neck_node: Node3D = player.neck
		var fb: Vector3 = -neck_node.global_transform.basis.z
		var fb_xz := Vector3(fb.x, 0.0, fb.z)
		if fb_xz.length_squared() > 0.0001:
			cam_forward_xz = fb_xz.normalized()
		else:
			cam_forward_xz = Vector3.FORWARD

	var neck_node2: Node3D = player.neck
	var n_right: Vector3 = neck_node2.global_transform.basis.x
	player_right = Vector3(n_right.x, 0.0, n_right.z)
	if player_right.length_squared() > 0.0001:
		player_right = player_right.normalized()
	else:
		player_right = Vector3.RIGHT

	var raw := Vector3(input_dir.x, 0.0, input_dir.y)
	var neck_node3: Node3D = player.neck
	var world: Vector3 = neck_node3.global_transform.basis * raw
	if world.length_squared() > 0.0001:
		wish_dir_world = world.normalized()
	else:
		wish_dir_world = Vector3.ZERO


func _sample_floor() -> void:
	# Long slope probe.
	var up := Vector3.UP
	var origin := player.global_position + up * slope_probe_up
	var q := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * slope_probe_down)
	q.collision_mask = mask_slope
	q.exclude = [player.get_rid()]
	q.collide_with_areas = false
	q.collide_with_bodies = true
	var hit := space.intersect_ray(q)

	if hit.is_empty():
		floor_hit = false
		if player.is_on_floor():
			floor_normal = player.get_floor_normal()
		else:
			floor_normal = Vector3.UP
		floor_hit_y = player.global_position.y
	else:
		floor_hit = true
		floor_normal = hit.normal
		floor_hit_y = hit.position.y

	floor_angle_deg = rad_to_deg(floor_normal.angle_to(Vector3.UP))

	# Short above-ground probe. Starts slightly above the feet because
	# Godot rays that begin exactly on a surface may miss.
	var ag_origin := player.global_position + up * 0.1
	var ag_q := PhysicsRayQueryParameters3D.create(
		ag_origin,
		ag_origin + Vector3.DOWN * (ground_probe_down + 0.1)
	)
	ag_q.collision_mask = mask_ground
	ag_q.exclude = [player.get_rid()]
	ag_q.collide_with_areas = false
	ag_q.collide_with_bodies = true
	var ag_hit := space.intersect_ray(ag_q)
	above_ground = ag_hit.is_empty()


func _sample_ceiling() -> void:
	var origin := player.global_position + Vector3.UP * 0.1
	var q := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.UP * ceiling_probe_up)
	q.collision_mask = mask_ceiling
	q.exclude = [player.get_rid()]
	q.collide_with_areas = false
	q.collide_with_bodies = true
	var hit := space.intersect_ray(q)

	if hit.is_empty():
		ceiling_hit = false
		ceiling_point = Vector3.ZERO
	else:
		ceiling_hit = true
		ceiling_point = hit.position


func _sample_walls() -> void:
	wall_front_hit = false
	wall_front_normal = Vector3.ZERO
	wall_front_point = Vector3.ZERO
	wall_front_samples.clear()
	wall_left_hit = false
	wall_left_normal = Vector3.ZERO
	wall_right_hit = false
	wall_right_normal = Vector3.ZERO
	ledge_front_hit = false
	ledge_front_normal = Vector3.ZERO
	ledge_front_point = Vector3.ZERO

	if wall_use_shape_cast and _wall_cast != null:
		_sample_front_wall_shape()
	else:
		_sample_front_wall_rays()

	_sample_side_walls()


func _sample_front_wall_shape() -> void:
	var box := _wall_cast.shape as BoxShape3D
	if box != null and box.size != wall_probe_size:
		box.size = wall_probe_size
	_wall_cast.target_position = Vector3(0.0, 0.0, -wall_probe_reach)
	_wall_cast.collision_mask = mask_wall | mask_ledge

	var neck_node: Node3D = player.neck
	var cast_basis := Basis(Vector3.UP, neck_node.global_rotation.y)
	var cast_origin := player.global_position + Vector3.UP * wall_probe_center_y
	_wall_cast.global_transform = Transform3D(cast_basis, cast_origin)
	_wall_cast.force_shapecast_update()

	var count := _wall_cast.get_collision_count()
	for i in count:
		var collider := _wall_cast.get_collider(i)
		var normal: Vector3 = _wall_cast.get_collision_normal(i)
		var point: Vector3 = _wall_cast.get_collision_point(i)

		var flat := Vector3(normal.x, 0.0, normal.z)
		if flat.length_squared() > 0.0001:
			flat = flat.normalized()

		var layer := 0
		if collider is CollisionObject3D:
			layer = (collider as CollisionObject3D).collision_layer

		var is_ledge := (layer & mask_ledge) != 0
		var is_wall := (layer & mask_wall) != 0

		if is_ledge and not ledge_front_hit:
			ledge_front_hit = true
			ledge_front_normal = flat
			ledge_front_point = point

		if is_wall and absf(normal.y) < 0.5 and not wall_front_hit:
			wall_front_hit = true
			wall_front_normal = flat
			wall_front_point = point

		wall_front_samples.append({"point": point, "normal": flat})


func _sample_front_wall_rays() -> void:
	var neck_node: Node3D = player.neck
	var forward: Vector3 = -neck_node.global_transform.basis.z
	var forward_xz := Vector3(forward.x, 0.0, forward.z)
	if forward_xz.length_squared() > 0.0001:
		forward = forward_xz.normalized()
	else:
		forward = Vector3.FORWARD

	var reach := wall_reach + wall_back_offset
	for h in wall_probe_heights:
		var origin: Vector3 = player.global_position + Vector3.UP * h - forward * wall_back_offset
		var end: Vector3 = origin + forward * reach
		var q := PhysicsRayQueryParameters3D.create(origin, end)
		q.collision_mask = mask_wall | mask_ledge
		q.exclude = [player.get_rid()]
		q.collide_with_areas = false
		q.collide_with_bodies = true
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue

		var normal: Vector3 = hit.normal
		var flat := Vector3(normal.x, 0.0, normal.z)
		if flat.length_squared() > 0.0001:
			flat = flat.normalized()
		var point: Vector3 = hit.position
		var collider = hit.collider
		var layer := 0
		if collider is CollisionObject3D:
			layer = (collider as CollisionObject3D).collision_layer

		var is_ledge := (layer & mask_ledge) != 0
		var is_wall := (layer & mask_wall) != 0

		if is_ledge and not ledge_front_hit:
			ledge_front_hit = true
			ledge_front_normal = flat
			ledge_front_point = point

		if is_wall and absf(normal.y) < 0.5 and not wall_front_hit:
			wall_front_hit = true
			wall_front_normal = flat
			wall_front_point = point

		wall_front_samples.append({"point": point, "normal": flat})


func _sample_side_walls() -> void:
	var origin := player.global_position + Vector3.UP * side_probe_height
	var right_dir := player_right
	if right_dir.length_squared() < 0.0001:
		right_dir = Vector3.RIGHT

	# Right side.
	var rq := PhysicsRayQueryParameters3D.create(origin, origin + right_dir * wall_reach)
	rq.collision_mask = mask_wall
	rq.exclude = [player.get_rid()]
	rq.collide_with_areas = false
	rq.collide_with_bodies = true
	var rh := space.intersect_ray(rq)
	if not rh.is_empty():
		wall_right_hit = true
		var rn: Vector3 = rh.normal
		var rf := Vector3(rn.x, 0.0, rn.z)
		wall_right_normal = rf.normalized() if rf.length_squared() > 0.0001 else Vector3.ZERO

	# Left side.
	var lq := PhysicsRayQueryParameters3D.create(origin, origin - right_dir * wall_reach)
	lq.collision_mask = mask_wall
	lq.exclude = [player.get_rid()]
	lq.collide_with_areas = false
	lq.collide_with_bodies = true
	var lh := space.intersect_ray(lq)
	if not lh.is_empty():
		wall_left_hit = true
		var ln: Vector3 = lh.normal
		var lf := Vector3(ln.x, 0.0, ln.z)
		wall_left_normal = lf.normalized() if lf.length_squared() > 0.0001 else Vector3.ZERO


func _sample_hook() -> void:
	var cam_node: Node3D = player.cam
	if cam_node == null:
		hook_hit = {}
		return
	var origin: Vector3 = cam_node.global_position
	var dir := cam_forward
	if dir.length_squared() < 0.0001:
		hook_hit = {}
		return
	dir = dir.normalized()
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * hook_range)
	q.collision_mask = mask_hook
	q.exclude = [player.get_rid()]
	q.collide_with_areas = false
	q.collide_with_bodies = true
	hook_hit = space.intersect_ray(q)

# -----------------------------------------------------------------------------
# Public queries
# -----------------------------------------------------------------------------

## True when the hook ray found a valid anchor this frame.
func can_grapple() -> bool:
	return not hook_hit.is_empty()
