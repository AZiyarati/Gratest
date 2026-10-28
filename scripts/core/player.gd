## Player root: the single CharacterBody3D. Owns collision shapes, camera pivots, and drives the single physics lifecycle.
extends CharacterBody3D
class_name Player

enum Stance {
	STANDING,
	CROUCHING,
	PRONE,
}

@onready var standing_collision_shape: CollisionShape3D = $StandingCollisionShape
@onready var crouching_collision_shape: CollisionShape3D = $CrouchingCollisionShape
@onready var prone_collision_shape: CollisionShape3D = $ProneCollisionShape
@onready var neck: Node3D = $Neck
@onready var head: Node3D = $Neck/Head
@onready var eyes: Node3D = $Neck/Head/Eyes
@onready var camera: Camera3D = $Neck/Head/Eyes/Camera3D

@onready var input_router: InputRouter = $Core/InputRouter
@onready var state_machine: StateMachine = $Core/StateMachine
@onready var movement_authority: MovementAuthority = $Core/MovementAuthority

@onready var module_host: Node = $ModuleHost
@onready var basic_locomotion: BasicLocomotion = $ModuleHost/BasicLocomotion

## Eye height (Neck y-offset) when standing, in meters above the Player root.
@export var standing_eye_height: float = 1.6

## Eye height when crouched, in meters above the Player root.
@export var crouch_eye_height: float = 0.9

## Eye height when prone, in meters above the Player root.
@export var prone_eye_height: float = 0.3

## Lerp rate for camera height transitions (per second).
@export var eye_height_lerp_speed: float = 12.0

## Collision mask used for the headroom query when trying to stand/crouch.
@export_flags_3d_physics var headroom_check_mask: int = 1

## When true, logs stance transitions to the output panel. Use to diagnose stance bugs.
@export var debug_stance: bool = false

var _stance: int = Stance.STANDING
var _target_eye_height: float = 1.6


func _ready() -> void:
	_validate_structure()
	_setup_core()
	_setup_modules()
	_wire_collaborators()
	_init_stance()


func _physics_process(delta: float) -> void:
	if input_router == null or state_machine == null \
		or basic_locomotion == null or movement_authority == null:
		return
	input_router.tick(delta)
	state_machine.tick(delta)
	basic_locomotion.tick(delta)
	movement_authority.tick(delta)
	_smooth_eye_height(delta)


# --- Stance API (called by BasicLocomotion) ---

## Enter crouching from standing. No-op if already crouched or prone.
func crouch() -> void:
	if _stance != Stance.STANDING:
		return
	_set_stance(Stance.CROUCHING)


## Try to stand. Returns true on success.
## From CROUCHING: requires standing headroom.
## From PRONE: refused — use try_unprone().
func try_stand() -> bool:
	if _stance == Stance.STANDING:
		return true
	if _stance == Stance.PRONE:
		return false
	if not _has_headroom_for(Stance.STANDING):
		return false
	_set_stance(Stance.STANDING)
	return true


## Enter prone from any stance. Always succeeds (smallest shape).
func prone() -> void:
	if _stance == Stance.PRONE:
		return
	_set_stance(Stance.PRONE)


## Try to leave prone. Goes to CROUCHING if that fits. Crouch logic handles the
## remaining climb to STANDING on subsequent ticks via try_stand(). Returns true
## if at least the crouch transition succeeded.
func try_unprone() -> bool:
	if _stance != Stance.PRONE:
		return true
	if _has_headroom_for(Stance.CROUCHING):
		_set_stance(Stance.CROUCHING)
		return true
	return false


func is_crouched() -> bool:
	return _stance == Stance.CROUCHING


func is_prone() -> bool:
	return _stance == Stance.PRONE


func is_standing() -> bool:
	return _stance == Stance.STANDING


func get_stance() -> int:
	return _stance


func _init_stance() -> void:
	_stance = Stance.STANDING
	standing_collision_shape.disabled = false
	crouching_collision_shape.disabled = true
	prone_collision_shape.disabled = true
	_target_eye_height = standing_eye_height
	neck.position.y = standing_eye_height


func _set_stance(new_stance: int) -> void:
	var old := _stance
	_stance = new_stance
	standing_collision_shape.disabled = (new_stance != Stance.STANDING)
	crouching_collision_shape.disabled = (new_stance != Stance.CROUCHING)
	prone_collision_shape.disabled = (new_stance != Stance.PRONE)
	match new_stance:
		Stance.STANDING:
			_target_eye_height = standing_eye_height
		Stance.CROUCHING:
			_target_eye_height = crouch_eye_height
		Stance.PRONE:
			_target_eye_height = prone_eye_height
	if debug_stance:
		print("[stance] %s → %s" % [_stance_name(old), _stance_name(new_stance)])


func _stance_name(s: int) -> String:
	match s:
		Stance.STANDING: return "STANDING"
		Stance.CROUCHING: return "CROUCHING"
		Stance.PRONE: return "PRONE"
		_: return "UNKNOWN(%d)" % s


func _has_headroom_for(stance: int) -> bool:
	var shape_node: CollisionShape3D
	match stance:
		Stance.STANDING:
			shape_node = standing_collision_shape
		Stance.CROUCHING:
			shape_node = crouching_collision_shape
		Stance.PRONE:
			shape_node = prone_collision_shape
		_:
			return true
	if shape_node == null or shape_node.shape == null:
		return true
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape_node.shape
	query.transform = global_transform * shape_node.transform
	query.collision_mask = headroom_check_mask
	query.exclude = [get_rid()]
	var hits := space_state.intersect_shape(query, 1)
	return hits.is_empty()


func _smooth_eye_height(delta: float) -> void:
	var t := clampf(eye_height_lerp_speed * delta, 0.0, 1.0)
	neck.position.y = lerp(neck.position.y, _target_eye_height, t)


func _validate_structure() -> void:
	var required := {
		"StandingCollisionShape": standing_collision_shape,
		"CrouchingCollisionShape": crouching_collision_shape,
		"ProneCollisionShape": prone_collision_shape,
		"Neck": neck,
		"Head": head,
		"Eyes": eyes,
		"Camera3D": camera,
		"Core/InputRouter": input_router,
		"Core/StateMachine": state_machine,
		"Core/MovementAuthority": movement_authority,
		"ModuleHost": module_host,
		"ModuleHost/BasicLocomotion": basic_locomotion,
	}
	for _name in required:
		if required[_name] == null:
			push_error("Player: required node '%s' missing." % _name)
	if standing_collision_shape and not standing_collision_shape.shape is CapsuleShape3D:
		push_error("Player: StandingCollisionShape must hold a CapsuleShape3D.")
	if crouching_collision_shape and not crouching_collision_shape.shape is CapsuleShape3D:
		push_error("Player: CrouchingCollisionShape must hold a CapsuleShape3D.")
	if prone_collision_shape and prone_collision_shape.shape == null:
		push_error("Player: ProneCollisionShape has no shape assigned.")


func _setup_core() -> void:
	if input_router:
		input_router.setup(self)
	if state_machine:
		state_machine.setup(self)
	if movement_authority:
		movement_authority.setup(self)


func _setup_modules() -> void:
	if basic_locomotion == null:
		push_error("Player: BasicLocomotion is required but missing.")
		return
	basic_locomotion.setup(self)
	if not basic_locomotion.validate_dependencies():
		push_error("Player: BasicLocomotion failed dependency validation; not activating.")
		return
	basic_locomotion.activate()


func _wire_collaborators() -> void:
	if basic_locomotion and input_router and movement_authority:
		basic_locomotion.set_collaborators(input_router, movement_authority)
