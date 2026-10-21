## Player frame owner.
##
## Owns mouse look, sensor / movement orchestration, the camera
## accumulator API every visual component writes through, and the motion
## helper API (play_jump, play_landing, ...) that movement and
## fall_behavior call. Optional visual/system components are looked up
## with get_node_or_null so the scene runs even when they're absent.
extends CharacterBody3D

# -----------------------------------------------------------------------------
# Exports
# -----------------------------------------------------------------------------

@export_group("Features")
## Master toggle for mouse look. When false, _input returns early.
@export var enable_mouse_look: bool = true

@export_group("Mouse Look")
## Multiplier applied to raw mouse delta.
@export var mouse_sens: float = 0.4
## Reserved for free-look yaw limit (unused until free-look exists).
@export var free_look_yaw_limit_deg: float = 120.0
## Maximum pitch (degrees) applied to head.rotation.x.
@export var head_pitch_limit_deg: float = 89.0

@export_group("Camera")
## Baseline FOV. Camera targets reset to this every frame.
@export var default_fov: float = 75.0
## How quickly cam.fov and roll approach their targets.
@export var camera_lerp_speed: float = 8.0

# -----------------------------------------------------------------------------
# Required refs
# -----------------------------------------------------------------------------

@onready var neck: Node3D = $neck
@onready var head: Node3D = $neck/head
@onready var eyes: Node3D = $neck/head/eyes
@onready var cam: Camera3D = $neck/head/eyes/Camera3D
@onready var sensors: SensorHub = $SensorHub
@onready var movement: MovementComponent = $MovementComponent

# -----------------------------------------------------------------------------
# Optional refs. Nullable — scene must still run when they're missing.
# Typed as Node so the script compiles before those component scripts exist.
# -----------------------------------------------------------------------------

@onready var motion_visual: Node = get_node_or_null("MotionVisualComponent")
@onready var head_bob: Node = get_node_or_null("HeadBobComponent")
@onready var speed_effect: Node = get_node_or_null("SpeedEffectComponent")
@onready var dash: Node = get_node_or_null("DashComponent")
@onready var fall_behavior: Node = get_node_or_null("FallBehaviorComponent")
@onready var wall_run: Node = get_node_or_null("WallRunComponent")
@onready var ladder_climb: Node = get_node_or_null("LadderClimbComponent")
@onready var vault: Node = get_node_or_null("VaultComponent")

# -----------------------------------------------------------------------------
# Shared state mirrors
# -----------------------------------------------------------------------------

var walking: bool = false
var sprinting: bool = false
var jumps_made: int = 0
var crouching: bool = false
var prone: bool = false
var sliding: bool = false
var dash_direction: Vector3 = Vector3.ZERO
var do_dash: bool = false
var current_speed: float = 0.0
var direction: Vector3 = Vector3.ZERO
var last_velocity: Vector3 = Vector3.ZERO
var movement_lockout: float = 0.0

# -----------------------------------------------------------------------------
# Camera accumulators (reset every physics frame)
# -----------------------------------------------------------------------------

var _acc_eye_pos: Vector3 = Vector3.ZERO
var _acc_eye_rot: Vector3 = Vector3.ZERO
var _acc_cam_pos: Vector3 = Vector3.ZERO
var _acc_cam_rot: Vector3 = Vector3.ZERO

# -----------------------------------------------------------------------------
# Camera arbitration
# -----------------------------------------------------------------------------

## Per-frame FOV target. Components may write directly; reset to default
## every frame after the accumulator block.
var camera_fov_target: float = 75.0
## Per-frame roll target. Same rules as camera_fov_target.
var camera_roll_target: float = 0.0

var _current_roll: float = 0.0
var _fov_hold_value: float = 75.0
var _fov_hold_timer: float = 0.0
var _roll_hold_value: float = 0.0
var _roll_hold_timer: float = 0.0

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------

# AFTER
func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	camera_fov_target = default_fov
	_fov_hold_value = default_fov
	cam.fov = default_fov

	sensors.setup(self)
	movement.setup(self)

	if motion_visual != null and motion_visual.has_method("setup"):
		motion_visual.setup(self)
	if head_bob != null and head_bob.has_method("setup"):
		head_bob.setup(self)
	if speed_effect != null and speed_effect.has_method("setup"):
		speed_effect.setup(self)
	if dash != null and dash.has_method("setup"):
		dash.setup(self)
	if fall_behavior != null and fall_behavior.has_method("setup"):
		fall_behavior.setup(self)
	if wall_run != null and wall_run.has_method("setup"):
		wall_run.setup(self)
	if ladder_climb != null and ladder_climb.has_method("setup"):
		ladder_climb.setup(self)
	if vault != null and vault.has_method("setup"):
		vault.setup(self)

func _physics_process(delta: float) -> void:
	# 1. Tick camera hold timers.
	if _fov_hold_timer > 0.0:
		_fov_hold_timer -= delta
	if _roll_hold_timer > 0.0:
		_roll_hold_timer -= delta

	if movement_lockout > 0.0:
		movement_lockout -= delta

	# 2. Sensors first so everything downstream reads fresh data.
	sensors.update()

	# ---------------------------------------------------------------------
	# 3. Priority physics chain.
	#    Traversal components (wall_run, ledge_grab, dual_hooks, vault,
	#    slope_slide) will slot in BEFORE movement.update() once they
	#    exist. The intended final shape is:
	#
	#      if ledge_grab.is_active():
	#          ledge_grab.hold_physics(delta)
	#      elif vault.vaulting:
	#          vault.apply(delta)
	#      elif dual_hooks.is_active():
	#          dual_hooks.apply(delta)
	#      elif wall_run.is_active():
	#          wall_run.apply(delta)
	#      elif slope_slide.is_sliding:
	#          slope_slide.apply(delta)
	#      else:
	#          movement.update(delta)
	#
	#    For now only movement + dash exist. Dash runs after movement so
	#    it can override the horizontal velocity for its duration.
	# ---------------------------------------------------------------------
	# Detection runs before the physics chain so each component has
	# fresh state. Order matters here once more components land.
	if ladder_climb != null and ladder_climb.has_method("detect"):
		ladder_climb.detect(delta)

	if wall_run != null and wall_run.has_method("detect"):
		wall_run.detect(delta)
	if vault != null and vault.has_method("detect"):
		vault.detect(delta)
		
 	# Priority chain. Higher-priority states own the body.
	#if ladder_climb != null and ladder_climb.has_method("is_active") and ladder_climb.is_active():
	if vault != null and vault.has_method("is_active") \
			and vault.is_active():
		vault.apply(delta)
	elif ladder_climb != null and ladder_climb.has_method("is_active") \
			and ladder_climb.is_active():
		ladder_climb.apply(delta)
	elif wall_run != null and wall_run.has_method("is_active") \
			and wall_run.is_active():
		wall_run.apply(delta)
	else:
		movement.update(delta)
	
	if dash != null and dash.has_method("update"):
		dash.update(delta)

	# FallBehaviorComponent drives landings, rolls, and slap pulses. It
	# must run after movement so its landing detection sees the fresh
	# is_on_floor() state for this frame.
	if fall_behavior != null and fall_behavior.has_method("update"):
		fall_behavior.update(delta)

	# 4. Visuals.
	if head_bob != null and head_bob.has_method("update"):
		head_bob.update(delta)
	if motion_visual != null and motion_visual.has_method("update"):
		motion_visual.update(delta)
	if speed_effect != null and speed_effect.has_method("update"):
		speed_effect.update(delta)
	if wall_run != null and wall_run.has_method("update_camera"):
		wall_run.update_camera(delta)
	if vault != null and vault.has_method("update_camera"):
		vault.update_camera(delta)
	if ladder_climb != null and ladder_climb.has_method("update_camera"):
		ladder_climb.update_camera(delta)

	# 5. Camera arbitration.
	# Per-frame asserts win. If nothing asserted this frame, a pending
	# hold value fills in. Otherwise the target falls back to the default.
	if camera_fov_target == default_fov and _fov_hold_timer > 0.0:
		camera_fov_target = _fov_hold_value
	if camera_roll_target == 0.0 and _roll_hold_timer > 0.0:
		camera_roll_target = _roll_hold_value

	var cam_lerp: float = clampf(delta * camera_lerp_speed, 0.0, 1.0)
	cam.fov = lerpf(cam.fov, camera_fov_target, cam_lerp)
	_current_roll = lerpf(_current_roll, camera_roll_target, cam_lerp)

	# Apply accumulators + roll to the eye chain, then clear.
	eyes.position = _acc_eye_pos
	eyes.rotation = _acc_eye_rot
	cam.position = _acc_cam_pos
	cam.rotation = _acc_cam_rot
	eyes.rotation.z += _current_roll

	_acc_eye_pos = Vector3.ZERO
	_acc_eye_rot = Vector3.ZERO
	_acc_cam_pos = Vector3.ZERO
	_acc_cam_rot = Vector3.ZERO

	# Reset per-frame targets for the next frame.
	camera_fov_target = default_fov
	camera_roll_target = 0.0

	# 6. Fold lingering camera-strafe yaw back into the body once bhop
	#    camera strafe is no longer active.
	if movement != null \
			and not movement.is_bhop_camera_strafing() \
			and absf(neck.rotation.y) > 0.0001:
		rotate_y(neck.rotation.y)
		neck.rotation.y = 0.0

	# 7. Move.
	move_and_slide()
	last_velocity = velocity

# -----------------------------------------------------------------------------
# Camera accumulator API
# -----------------------------------------------------------------------------

## Add a position offset to eyes this frame. Cleared at end of frame.
func add_eye_offset(x: float, y: float, z: float) -> void:
	_acc_eye_pos += Vector3(x, y, z)

## Add a rotation offset to eyes this frame. Cleared at end of frame.
func add_eye_rotation(x: float, y: float, z: float) -> void:
	_acc_eye_rot += Vector3(x, y, z)

## Add a position offset to the Camera3D this frame. Cleared at end of frame.
func add_cam_offset(x: float, y: float, z: float) -> void:
	_acc_cam_pos += Vector3(x, y, z)

## Add a rotation offset to the Camera3D this frame. Cleared at end of frame.
func add_cam_rotation(x: float, y: float, z: float) -> void:
	_acc_cam_rot += Vector3(x, y, z)

## Request a held FOV value. Longest timer wins until it expires.
func hold_camera_fov(value: float, duration: float) -> void:
	_fov_hold_value = value
	_fov_hold_timer = maxf(_fov_hold_timer, duration)

## Request a held camera roll value. Longest timer wins until it expires.
func hold_camera_roll(value: float, duration: float) -> void:
	_roll_hold_value = value
	_roll_hold_timer = maxf(_roll_hold_timer, duration)

# -----------------------------------------------------------------------------
# Motion helper API (null-safe)
# -----------------------------------------------------------------------------

## Trigger the jump visual, if the motion visual component is present.
func play_jump() -> void:
	if motion_visual != null and motion_visual.has_method("trigger_jump"):
		motion_visual.trigger_jump()

## Trigger the landing visual.
func play_landing() -> void:
	if motion_visual != null and motion_visual.has_method("trigger_landing"):
		motion_visual.trigger_landing()

## Trigger the hard landing visual.
func play_hard_landing() -> void:
	if motion_visual != null and motion_visual.has_method("trigger_hard_landing"):
		motion_visual.trigger_hard_landing()

## Trigger the roll visual.
func play_roll() -> void:
	if motion_visual != null and motion_visual.has_method("trigger_roll"):
		motion_visual.trigger_roll()

## Trigger the slap visual with an optional duration and intensity.
func play_slap(duration: float = 1.2, intensity: float = 1.0) -> void:
	if motion_visual != null and motion_visual.has_method("trigger_slap"):
		motion_visual.trigger_slap(duration, intensity)

# -----------------------------------------------------------------------------
# Mouse look
# -----------------------------------------------------------------------------

## Enable or disable mouse look. Callable from external systems (e.g. a menu).
func set_mouse_look(on: bool) -> void:
	enable_mouse_look = on
	if on:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _input(event: InputEvent) -> void:
	if not enable_mouse_look:
		return
	if event is InputEventMouseMotion:
		_apply_mouse_look(event)

func _apply_mouse_look(event: InputEventMouseMotion) -> void:
	var rel: Vector2 = event.relative

	if movement != null and movement.is_bhop_camera_strafing():
		# Camera-only yaw: rotate the neck, leave the body alone so the
		# bhop momentum direction isn't interrupted.
		neck.rotate_y(deg_to_rad(-rel.x * mouse_sens))
	else:
		# Body yaw. If a camera-strafe yaw was active last frame, fold
		# it into the body first so the view doesn't snap.
		if absf(neck.rotation.y) > 0.0001:
			rotate_y(neck.rotation.y)
			neck.rotation.y = 0.0
		rotate_y(deg_to_rad(-rel.x * mouse_sens))

	# Pitch: rotate head, clamped.
	head.rotate_x(deg_to_rad(-rel.y * mouse_sens))
	var pitch_limit: float = deg_to_rad(head_pitch_limit_deg)
	head.rotation.x = clampf(head.rotation.x, -pitch_limit, pitch_limit)
