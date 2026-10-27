## Player root: the single CharacterBody3D. Drives physics lifecycle and wires Core services + required modules.
extends CharacterBody3D
class_name Player

@onready var standing_collision_shape: CollisionShape3D = $StandingCollisionShape
@onready var neck: Node3D = $Neck
@onready var head: Node3D = $Neck/Head
@onready var eyes: Node3D = $Neck/Head/Eyes
@onready var camera: Camera3D = $Neck/Head/Eyes/Camera3D

@onready var input_router: InputRouter = $Core/InputRouter
@onready var state_machine: StateMachine = $Core/StateMachine
@onready var movement_authority: MovementAuthority = $Core/MovementAuthority

@onready var module_host: Node = $ModuleHost
@onready var basic_locomotion: BasicLocomotion = $ModuleHost/BasicLocomotion


func _ready() -> void:
	_validate_structure()
	_setup_core()
	_setup_modules()
	_wire_collaborators()


## The single physics lifecycle for the whole character.
## Order is explicit and documented here — not implicit scene-tree order.
func _physics_process(delta: float) -> void:
	if input_router == null or state_machine == null \
		or basic_locomotion == null or movement_authority == null:
		return
	input_router.tick(delta)
	state_machine.tick(delta)
	basic_locomotion.tick(delta)
	movement_authority.tick(delta)


func _validate_structure() -> void:
	var required := {
		"StandingCollisionShape": standing_collision_shape,
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
