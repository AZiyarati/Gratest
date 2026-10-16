## Wall-run / wall-slide / wall-climb / wall-jump / Q-turn component.
##
## Session 1: horizontal wall run.
## Session 2: wall slide as a fallback when the run window isn't met.
## Session 3: head-on wall slide fallback + camera-independent locked slide.
## Session 4: Ctrl (crouch) cancels any active slide on a fresh press.
## Session 5: vertical wall climb + end-slide transition on climb expiry.
## Session 6: distance caps + slide lateral control (A/D along the wall).
## Session 7: wall jump — Space kicks off any active wall state.
## Session 8: Q-turn — Q rotates the body mid-wall-state; a follow-up
##            Space within turn_grace_time launches along the new
##            look direction (away from the wall).
## Session 9: chain speed-up — each wall jump accumulates a horizontal
##            bonus that applies to the NEXT launch, capped at
##            chain_max_speed. Opt-in (enable_chain default false).
##
## Detects a wall beside the player via SensorHub side-wall sensors.
## While airborne, the component picks between:
##   1. vertical climb   (head-on angle, session-limited, ends in slide)
##   2. horizontal run   (session-limited, locks horizontal speed)
##   3. wall slide       (fallback, preserves horizontal momentum)
## and takes over the player's velocity for its active state.
##
## Head-on walls: when both side sensors miss but the front wall sensor
## fires, slide engages using the front normal. Runs and climbs never
## start from a head-on wall.
##
## Locked slide: once slide begins, the cached wall normal is used every
## frame instead of the camera-relative sensors, so the slide persists
## when the camera rotates away. A single self-owned ray probe refreshes
## the normal or detaches when the wall is lost.
##
## Cancel: a fresh press of the slide cancel action (Ctrl / crouch by
## default) ends any slide — side-adjacent, head-on, locked or not.
##
## Wall jump: Space during any wall state launches the player along the
## wall tangent (or camera forward), away from the face, and up. Reuses
## the cancel-lockout field as the no-reentry gate and sets
## player.movement_lockout for the same window.
##
## Q-turn: Q rotates the body (and optionally pitches the head) over
## turn_duration while the current wall state continues untouched.
## Space within turn_grace_time of a completed turn always launches
## along the current look direction so the player flies away from the
## wall; after the grace window, wall jump behaves as before.
class_name WallRunComponent
extends Node

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------

## Height above the player origin used for the locked-slide wall probe.
const SLIDE_PROBE_HEIGHT: float = 0.9
## How far along -_wall_normal the locked-slide probe reaches before
## declaring the wall lost.
const SLIDE_DETACH_DISTANCE: float = 0.7

# -----------------------------------------------------------------------------
# Exports
# -----------------------------------------------------------------------------

@export_group("Features")
## Master toggle. When false, detect() exits all wall states immediately.
@export var enabled: bool = true
## Allow horizontal wall-running.
@export var horizontal_run: bool = true
## Allow vertical wall-climbing (rise up a wall face).
@export var vertical_climb: bool = true
## Allow wall sliding as a fallback state.
@export var wall_slide_enabled: bool = true
## When a vertical climb session expires, transition into a downward
## wall slide on the same wall. When false, the player is pushed off
## the wall like a horizontal run expiry.
@export var end_slide_enabled: bool = true
## Apply camera FOV / roll while running.
@export var camera_effects: bool = true
## Apply a subtle vertical head bob while running.
@export var bob_enabled: bool = true

@export_group("Input")
## Input action used to boost run speed.
@export var sprint_action: String = "sprint"
## Input action that ends an active slide on a fresh press.
@export var slide_cancel_action: String = "crouch"
## After a Ctrl-cancel from slide, suppress all wall-state re-entry
## for this long (seconds). Prevents a run or climb from stealing
## the body the frame after a slide cancel.
@export var slide_cancel_lockout: float = 0.3

@export_group("Detection")
## Retained for parity with future vertical styles. Not used yet.
@export var min_height_above_ground: float = 0.2

@export_group("Angle Windows")
## Below this angle to the wall direction, treat as vertical climb
## territory — no wall run.
@export var horizontal_min_angle: float = 12.0
## Above this angle, the player is looking away from the wall — no wall run.
@export var horizontal_max_angle: float = 115.0

@export_group("Session")
## Max time a single wall can be run before the player is pushed off.
@export var session_time_max: float = 2.0
## How long the player must be away from any wall before a new session
## can start.
@export var off_wall_reset_time: float = 0.3
## Impulse applied when a session expires.
@export var leave_wall_push: float = 6.0

@export_group("Run")
## Horizontal speed along the wall.
@export var run_speed: float = 12.0
## Constant force pushing the player into the wall so they stay stuck.
@export var stick_force: float = 4.0
## Multiplier applied to run_speed while sprint is held.
@export var sprint_run_multiplier: float = 1.4
## Maximum horizontal distance along the wall per run session
## (metres, measured in XZ from the entry point). 0 disables.
@export var run_max_distance: float = 3.0

@export_group("Vertical Climb")
## Max angle from camera-forward (toward the wall) for vertical
## climb to engage. Below horizontal_min_angle.
@export var vertical_max_angle: float = 35.0
## Upward climb speed (m/s, applied as positive Y).
@export var climb_speed: float = 5.5
## Push into the wall to stay stuck while climbing.
@export var climb_stick_force: float = 2.0
## How fast the player's XZ position snaps onto the climb axis.
## Retained for parity — climb uses stick force, not position snap.
@export var climb_snap_speed: float = 12.0
## Maximum vertical rise per climb session (metres, measured as
## current_y - entry_y). 0 disables.
@export var climb_max_distance: float = 2.0

@export_group("Wall Slide")
## Downward speed while sliding (m/s, applied as negative Y).
@export var slide_speed: float = 2.0
## Push into the wall to stay stuck while sliding.
@export var slide_stick_force: float = 2.0
## Extra downward acceleration per second while sliding.
## 0 = constant slide_speed.
@export var slide_accel: float = 0.0
## Max downward slide speed (only relevant when slide_accel > 0).
@export var slide_max_speed: float = 6.0
## Camera roll scale while sliding, as a fraction of tilt_angle.
## 0 disables.
@export var slide_tilt_scale: float = 0.5
## Max time a single slide can last. 0 = infinite.
@export var slide_max_time: float = 0.0
## Horizontal acceleration applied by WASD input while sliding along
## the wall plane. The wall-normal component of the wish direction is
## removed, so W/S also contribute toward going along the wall.
## 0 disables slide lateral control.
@export var slide_side_control: float = 4.0
## Soft cap on horizontal slide speed produced by input. Entry
## momentum above this cap is preserved — the cap only limits
## additional speed added by slide_side_control.
@export var slide_side_max_speed: float = 6.0

@export_group("Wall Jump")
## Master toggle. When false, Space does nothing during wall states.
@export var enable_wall_jump: bool = true
## Input action used to trigger the wall jump.
@export var jump_action: String = "ui_accept"
## Upward velocity applied by the wall jump.
@export var jump_up_force: float = 7.0
## Forward velocity applied by the wall jump.
@export var jump_forward_force: float = 9.0
## Push directed away from the wall face (added to the launch).
@export var jump_away_force: float = 3.0
## When true, the forward launch uses the wall tangent (the direction
## the player is running along the wall). When false, the player's
## camera forward is used instead.
@export var jump_uses_wall_forward: bool = false
## Seconds after the jump during which wall states cannot re-enter.
## Also sets player.movement_lockout for the same window so movement
## does not lerp over the impulse.
@export var exit_time: float = 0.3
## Minimum time between wall jumps. Prevents Space-spam from
## producing multiple jumps per wall contact.
@export var wall_jump_cooldown: float = 0.6
## Maximum wall jumps that may be performed before the player touches
## the ground again. -1 = unlimited, 0 = none.
@export var max_wall_jumps_per_airtime: int = 3

@export_group("Wall Jump — Variable")
## Master toggle for the variable wall jump. When true, the wall jump
## height scales with how long the jump action is held.
@export var enable_variable_wall_jump: bool = true
## Minimum upward velocity after a wall-jump cut.
@export var wall_jump_min_velocity: float = 2.0
## Fraction of current upward velocity kept when the wall jump is cut.
@export var wall_jump_cut_scale: float = 0.45
## Fraction of the forward impulse kept when the wall jump is cut.
## Matches wall_jump_cut_scale so a quick tap produces a visibly
## smaller launch in BOTH axes, not just height.
@export var wall_jump_forward_cut_scale: float = 0.45
## Seconds the movement lockout is held after a wall jump. Shorter
## than exit_time so gravity can start pulling on the arc once the
## variable-jump cut has landed.
@export var wall_jump_lockout: float = 0.1

@export_group("Chain Speed-Up")
## Master toggle. When false, no bonus is accumulated or applied.
@export var enable_chain: bool = false
## Horizontal speed added per successful wall jump. The bonus is
## applied to the NEXT launch, so the first jump of a chain is always
## at base speed.
@export var chain_speed_gain: float = 3.0
## Hard cap on the accumulated horizontal launch bonus (m/s). Also
## clamps the final composed horizontal launch speed so a chain
## cannot run away.
@export var chain_max_speed: float = 20.0
## Seconds the chain survives after leaving a wall. Reset the moment
## a new wall state (run / slide / climb) is entered. If the player
## does not touch a wall within this window, the accumulated bonus
## is cleared.
@export var chain_timeout: float = 1.5
## When true, entering crouch / prone / slide via MovementComponent
## clears the chain. Safe default; leave on unless testing.
@export var chain_resets_on_stance_change: bool = true

@export_group("Turn — Q-Turn")
## Master toggle. When false, Q does nothing during wall states.
@export var enable_turn_around: bool = true
## Input action that triggers the Q-turn.
@export var turn_action: String = "turn_around"
## Yaw applied by the Q-turn while wall-running (degrees). The sign
## is chosen per wall side so the player always turns away from the
## wall: right wall subtracts, left wall adds. Default -90 = a
## quarter turn to face away from the wall.
@export var horizontal_turn_degrees: float = -90.0
## Yaw applied by the Q-turn while wall-climbing (degrees). Default
## 180 = about-face, so the follow-up wall jump launches off the
## wall face instead of driving the player back into it.
@export var vertical_turn_degrees: float = 180.0
## How long the rotation takes (seconds). 0 = instant snap.
@export var turn_duration: float = 0.25
## Reserved for future polish. The active turn uses a smoothstep
## curve driven by turn_duration.
@export var turn_lerp_speed: float = 10.0
## Seconds after a Q-turn during which Space still launches along the
## new facing. After this window, the wall jump falls back to the
## default direction rules.
@export var turn_grace_time: float = 2.0

@export_group("Camera")
## FOV held while wall-running.
@export var fov_wallrun: float = 90.0
## Camera roll in degrees. Sign flips with the wall side.
@export var tilt_angle: float = -15.0
## Retained for parity. Player applies its own lerp.
@export var camera_lerp: float = 8.0

@export_group("Camera — Bob")
## Vertical bob rate.
@export var bob_speed: float = 14.0
## Vertical bob amplitude (meters).
@export var bob_intensity: float = 0.08
## Retained for parity. Player applies its own lerp.
@export var bob_lerp_speed: float = 10.0

@export_group("Vertical Climb — Camera")
## Vertical bob rate while climbing.
@export var climb_bob_speed: float = 12.0
## Vertical bob amplitude while climbing (metres).
@export var climb_bob_intensity: float = 0.06

@export_group("Wall Slide — Camera")
## Enable a small head bob while sliding down a wall.
@export var slide_bob_enabled: bool = true
## Slide bob rate.
@export var slide_bob_speed: float = 10.0
## Slide bob amplitude (metres).
@export var slide_bob_intensity: float = 0.05

# -----------------------------------------------------------------------------
# Public state
# -----------------------------------------------------------------------------

## True while the component is actively running the player along a wall.
var wall_running: bool = false
## True while the component is actively sliding down a wall.
var wall_sliding: bool = false
## True while the component is actively climbing up a wall face.
var wall_climbing: bool = false

# -----------------------------------------------------------------------------
# Internal state
# -----------------------------------------------------------------------------

var _player: CharacterBody3D
var _sensors: SensorHub

var _session_active: bool = false
var _session_time_left: float = 0.0
var _off_wall_time: float = 999.0
## 1 = right wall, -1 = left wall, 0 = no wall.
var _wall_side: int = 0
var _wall_normal: Vector3 = Vector3.ZERO

var _bob_index: float = 0.0
var _climb_bob_phase: float = 0.0
var _slide_bob_phase: float = 0.0

## Locked-slide state. When true, slide ignores side/front sensors and
## uses a self-owned probe against the cached _wall_normal.
var _slide_locked: bool = false
## Seconds elapsed in the current locked slide. Reset on slide entry.
var _slide_time_elapsed: float = 0.0
## Countdown after a Ctrl-cancel during slide; while > 0, no wall
## state can re-enter. Also armed by the wall jump for the same reason.
var _cancel_lockout: float = 0.0
## World position captured at entry to the active wall state, used
## for the distance caps.
var _state_start_pos: Vector3 = Vector3.ZERO
## Minimum-time-between-wall-jumps gate. Blocks Space-spam from
## producing multiple jumps per wall contact.
var _wall_jump_cooldown_timer: float = 0.0

## Counts wall jumps since the last ground contact. Reset on landing.
var _wall_jumps_this_airtime: int = 0
## True while the wall jump is still eligible for a variable-height cut.
var _wall_jump_cut_pending: bool = false
## Horizontal impulse applied by the last wall jump, cached so the
## variable-cut can shrink the forward arc when Space is released early.
var _wall_jump_h_impulse: Vector3 = Vector3.ZERO
## Vertical impulse applied by the last wall jump (pre-cut).
var _wall_jump_v_impulse: float = 0.0

## True while a Q-turn is animating the body rotation.
var _turning: bool = false
## Counts up while _turning. Ticks the rotation each frame.
var _turn_timer: float = 0.0
## Total duration of the active turn (cached at start).
var _turn_duration_actual: float = 0.0
## Body yaw at the start of the turn. Start of the rotation tween.
var _turn_start_yaw: float = 0.0
## Target yaw for the active turn.
var _turn_target_yaw: float = 0.0
## Grace timer after a successful turn. While > 0, wall jump is
## flagged as "post-turn" and uses the look direction unconditionally.
var _turn_grace_timer: float = 0.0
## True once a Q-turn has fired during the current wall session.
## Reset on session start and on landing. Prevents Q-spam from
## chaining multiple turns per wall contact.
var _turn_used_this_session: bool = false

## Accumulated horizontal launch bonus for the next wall jump.
var _chain_bonus: float = 0.0
## Seconds remaining before the chain resets. Reset to chain_timeout
## every frame a wall state is active; ticks down while airborne
## without wall contact.
var _chain_timeout_timer: float = 0.0

# -----------------------------------------------------------------------------
# Setup
# -----------------------------------------------------------------------------

## Cache the owning player and its SensorHub.
func setup(p: CharacterBody3D) -> void:
	_player = p
	_sensors = p.sensors

# -----------------------------------------------------------------------------
# Public queries
# -----------------------------------------------------------------------------

## True while running, sliding, or climbing.
func is_active() -> bool:
	return wall_running or wall_sliding or wall_climbing

# -----------------------------------------------------------------------------
# Detect
# -----------------------------------------------------------------------------

## Run per-frame wall detection and session bookkeeping. Called by
## player.gd before movement so we can decide whether to take over.
func detect(delta: float) -> void:
	# Variable wall-jump cut must run FIRST, unconditionally. It must
	# NOT be gated by the higher-priority early-outs below
	# (fall_behavior active while airborne, dash active, etc.), or the
	# release edge would be dropped on the frames those systems are
	# active — the wall-jump impulse would then never be cut.
	if _wall_jump_cut_pending:
		_tick_wall_jump_cut()

	# Tick Q-turn grace and advance the active turn. Both run before
	# any early-out so the grace window counts down and the animation
	# lands regardless of which branch detect() takes.
	if _turn_grace_timer > 0.0:
		_turn_grace_timer -= delta
	if _turning:
		_tick_turn(delta)

	# Chain speed-up tick. Runs before any early-out so the timeout
	# counts down regardless of which branch detect() takes this frame
	# (fall_behavior, dash, mid-turn, etc.).
	if _chain_timeout_timer > 0.0:
		_chain_timeout_timer -= delta
	if _chain_timeout_timer <= 0.0 and _chain_bonus > 0.0:
		_chain_bonus = 0.0

	if not enabled or _player == null or _sensors == null:
		_exit_all()
		return

	# Higher-priority states own the body — UNLESS we are mid-turn.
	# A Q-turn must complete; fall behavior / dash cannot kill it.
	if not _turning and (_fall_behavior_active() or _dash_active()):
		_exit_all()
		return

	# While turning, keep the current wall state alive and skip the
	# rest of detect() (side pick, state machine). Physics continue
	# via apply() with the cached _wall_normal.
	if _turning:
		return

	# Reset the wall-jump airtime counter on ground contact. The cut
	# flag is not reset here — _tick_wall_jump_cut() clears it when it
	# sees the player on the floor. Ground contact also clears the
	# chain — the bonus only survives while the player stays airborne
	# and keeps touching walls.
	if _player.is_on_floor():
		_wall_jumps_this_airtime = 0
		_turn_used_this_session = false
		_chain_bonus = 0.0
		_chain_timeout_timer = 0.0

	# Chain survives while on a wall; refresh the timeout each frame.
	if is_active():
		_chain_timeout_timer = chain_timeout

	# Optional defensive reset: crouch / prone / slide set by anything
	# other than the wall states themselves drops the chain.
	if chain_resets_on_stance_change and _player != null:
		var m: Variant = _player.get("movement")
		if m != null:
			var c: Variant = m.get("crouching")
			var p: Variant = m.get("prone")
			var s: Variant = m.get("sliding")
			if c == true or p == true or s == true:
				_chain_bonus = 0.0
				_chain_timeout_timer = 0.0

	if _cancel_lockout > 0.0:
		_cancel_lockout -= delta
	if _wall_jump_cooldown_timer > 0.0:
		_wall_jump_cooldown_timer -= delta

	# Slide cancel: a fresh press of the cancel action ends any active
	# slide. Set a short lockout so a run or climb cannot steal the
	# body the frame after the cancel. While the action is held, all
	# wall-state entry is blocked so the player actually falls free.
	if wall_sliding and Input.is_action_just_pressed(slide_cancel_action):
		_cancel_lockout = slide_cancel_lockout
		# The player is still adjacent to the wall at the moment of
		# cancel; do not count this as time spent off it.
		_off_wall_time = 0.0
		_exit_all()
		return

	# Q-turn: a fresh press while any wall state is active begins a
	# rotation. State detection is skipped for the duration of the
	# turn so the wall side and state stay cached.
	if enable_turn_around \
			and is_active() \
			and not _turning \
			and not _turn_used_this_session \
			and Input.is_action_just_pressed(turn_action):
		_begin_turn()
		return

	var cancel_held: bool = Input.is_action_pressed(slide_cancel_action)
	var entry_blocked: bool = _cancel_lockout > 0.0 or cancel_held

	_off_wall_time += delta

	# Grounded → no wall state.
	if _player.is_on_floor():
		_session_active = false
		_session_time_left = 0.0
		_off_wall_time = off_wall_reset_time
		_exit_all()
		return

	# --- Locked slide path. ---
	# Once a slide has started, its wall reference is cached and the
	# slide is self-sustaining: no side/front sensor reads, one probe
	# against the cached normal. Detach on floor (handled above), wall
	# loss, timeout, or toggle-off.
	if _slide_locked and wall_sliding:
		_tick_locked_slide(delta)
		return

	# --- Pick the wall side. ---
	var side: int = 0
	var side_normal: Vector3 = Vector3.ZERO

	var right_hit: bool = _sensors.wall_right_hit
	var left_hit: bool = _sensors.wall_left_hit
	var cam_fwd: Vector3 = _sensors.cam_forward_xz

	if right_hit and left_hit:
		# Prefer the wall whose normal is most perpendicular to the
		# camera forward — i.e. the wall that's most side-on. Tie → right.
		var r_dot: float = absf(_sensors.wall_right_normal.dot(cam_fwd))
		var l_dot: float = absf(_sensors.wall_left_normal.dot(cam_fwd))
		if r_dot <= l_dot:
			side = 1
			side_normal = _sensors.wall_right_normal
		else:
			side = -1
			side_normal = _sensors.wall_left_normal
	elif right_hit:
		side = 1
		side_normal = _sensors.wall_right_normal
	elif left_hit:
		side = -1
		side_normal = _sensors.wall_left_normal

	# Head-on fallback: side sensors miss a wall directly in front of
	# the player. Use the front wall normal so slide can engage.
	var front_fallback: bool = false
	if side == 0 \
			and _sensors.wall_front_hit \
			and _sensors.wall_front_normal.length_squared() > 0.0001:
		side = 1  # arbitrary — slide camera tilt doesn't care.
		side_normal = _sensors.wall_front_normal
		front_fallback = true

	if side == 0 or side_normal.length_squared() < 0.0001:
		# No usable wall this frame.
		if _off_wall_time >= off_wall_reset_time:
			_session_active = false
		_exit_all()
		return

	# --- Session bookkeeping. ---
	if _off_wall_time >= off_wall_reset_time:
		_session_active = true
		_session_time_left = session_time_max
		_turn_used_this_session = false
	_off_wall_time = 0.0

	# --- Angle window: side-on relative to camera forward. ---
	var side_angle: float = rad_to_deg(cam_fwd.angle_to(-side_normal))

	# --- Above ground check. ---
	var above_ok: bool = _sensors.above_ground

	# --- Session expiry: horizontal run timed out → push off and fall
	# through so slide (or a fresh run on a different wall) can take
	# over the same frame.
	var session_expired: bool = _session_time_left <= 0.0

	# Distance caps: measured from the entry position of the current
	# state. Both feed the same expiry block below as session_time_max.
	var run_dist_exceeded: bool = false
	if wall_running and run_max_distance > 0.0:
		var dx: float = _player.global_position.x - _state_start_pos.x
		var dz: float = _player.global_position.z - _state_start_pos.z
		run_dist_exceeded = (dx * dx + dz * dz) \
			>= run_max_distance * run_max_distance

	var climb_dist_exceeded: bool = false
	if wall_climbing and climb_max_distance > 0.0:
		climb_dist_exceeded = (
			_player.global_position.y - _state_start_pos.y
		) >= climb_max_distance

	if (session_expired or run_dist_exceeded) and wall_running:
		_player.velocity += _wall_normal * leave_wall_push
		_exit_wall_run()
		_session_active = false

	# --- Session expiry: vertical climb timed out → end-slide handoff
	# when enabled, else push off like a horizontal run would.
	if (session_expired or climb_dist_exceeded) and wall_climbing:
		if end_slide_enabled and wall_slide_enabled:
			# Transition directly into the locked slide on the same wall.
			# Cached _wall_normal / _wall_side are reused, so the next
			# frame's _tick_locked_slide keeps the slide alive without
			# re-running the side pick. Session is cleared so a fresh
			# wall contact is required to climb again.
			wall_climbing = false
			wall_sliding = true
			_slide_locked = true
			_slide_time_elapsed = 0.0
			_slide_bob_phase = 0.0
			_climb_bob_phase = 0.0
			_session_active = false
			_state_start_pos = _player.global_position
			_force_stand()
			return
		else:
			_player.velocity += _wall_normal * leave_wall_push
			_exit_all()
			_session_active = false

	# --- Priority 1: vertical climb (checked first). ---
	# front_fallback is intentionally ALLOWED here: the front sensor is
	# the only one that fires when the player looks at a wall (side rays
	# become parallel to the wall face once the neck rotates toward it).
	# The side_angle gate below still prevents climb from stealing the
	# "falling past a wall while looking forward" case — that stays
	# slide. Horizontal run still excludes front_fallback (there is no
	# tangent to run along when the wall is head-on).
	var can_climb: bool = vertical_climb \
		and not entry_blocked \
		and side_angle <= vertical_max_angle \
		and above_ok \
		and _session_active \
		and _session_time_left > 0.0

	if can_climb:
		if not wall_climbing:
			wall_climbing = true
			_climb_bob_phase = 0.0
			_state_start_pos = _player.global_position
			_force_stand()
		_wall_side = side
		_wall_normal = side_normal
		wall_running = false
		wall_sliding = false
		_slide_locked = false
		_session_time_left -= delta
		return

	# --- Priority 2: horizontal run. ---
	# Cannot run a wall you are facing head-on — slide owns that case.
	# Session expiry drops through to slide.
	var angle_ok: bool = side_angle >= horizontal_min_angle \
		and side_angle <= horizontal_max_angle

	var can_run: bool = horizontal_run \
		and not front_fallback \
		and not entry_blocked \
		and angle_ok \
		and above_ok \
		and _session_active \
		and _session_time_left > 0.0

	if can_run:
		if not wall_running:
			wall_running = true
			_bob_index = 0.0
			_state_start_pos = _player.global_position
		_wall_side = side
		_wall_normal = side_normal
		wall_sliding = false
		wall_climbing = false
		_slide_locked = false
		_session_time_left -= delta
		return

	# --- Priority 3: wall slide (fallback). ---
	# Enters whenever a wall is beside or in front of us and we're
	# airborne, regardless of angle or session state. While the cancel
	# action is held or its lockout is active, re-entry is blocked so
	# one press actually ends the slide rather than flickering back on.
	var can_slide: bool = wall_slide_enabled \
		and above_ok \
		and not entry_blocked

	if can_slide:
		if not wall_sliding:
			wall_sliding = true
			_slide_locked = true
			_slide_time_elapsed = 0.0
			_slide_bob_phase = 0.0
			_state_start_pos = _player.global_position
			_force_stand()
		_wall_side = side
		_wall_normal = side_normal
		wall_running = false
		wall_climbing = false
		return

	# --- None. ---
	_exit_all()

# -----------------------------------------------------------------------------
# Locked slide tick
# -----------------------------------------------------------------------------

## Advance the locked slide. One ray against the cached normal; detach on
## wall loss, timeout, or toggle-off. Floor contact is handled at the top
## of detect(). Cancel is handled at the top of detect() as well.
func _tick_locked_slide(delta: float) -> void:
	if not wall_slide_enabled:
		_exit_all()
		return

	var origin: Vector3 = _player.global_position + Vector3.UP * SLIDE_PROBE_HEIGHT
	var end: Vector3 = origin - _wall_normal * SLIDE_DETACH_DISTANCE
	var q := PhysicsRayQueryParameters3D.create(origin, end)
	q.collision_mask = _sensors.mask_wall
	q.exclude = [_player.get_rid()]
	q.collide_with_areas = false
	q.collide_with_bodies = true
	var hit: Dictionary = _sensors.space.intersect_ray(q)

	if hit.is_empty():
		_exit_all()
		return

	# Player is still on the wall — do NOT let locked-slide frames
	# accumulate off-wall time. Otherwise a Ctrl cancel would trip
	# the off_wall_reset_time gate on the next frame and grant a
	# free climb session, producing an infinite-climb loop.
	_off_wall_time = 0.0

	# Refresh cached normal from the new hit (flattened to XZ).
	var n: Vector3 = hit.normal
	var flat := Vector3(n.x, 0.0, n.z)
	if flat.length_squared() > 0.0001:
		_wall_normal = flat.normalized()

	_slide_time_elapsed += delta
	if slide_max_time > 0.0 and _slide_time_elapsed >= slide_max_time:
		_exit_all()
		return

# -----------------------------------------------------------------------------
# Apply
# -----------------------------------------------------------------------------

## Take over the player's velocity for the current state.
func apply(delta: float) -> void:
	if _player == null:
		return
	if _wall_normal.length_squared() < 0.0001:
		return

	# Wall jump takes priority: a fresh Space press on any active wall
	# state launches the player off the wall. player.gd's priority
	# chain already gates apply() on is_active(), so no additional
	# guard is needed here.
	if enable_wall_jump \
			and Input.is_action_just_pressed(jump_action) \
			and _wall_jump_cooldown_timer <= 0.0 \
			and (max_wall_jumps_per_airtime < 0 \
				or _wall_jumps_this_airtime < max_wall_jumps_per_airtime):
		_do_wall_jump()
		return

	# Climb first — a single frame can only be in one state, but this
	# ordering matches the detection priority.
	if wall_climbing:
		_apply_climb(delta)
	elif wall_running:
		_apply_run(delta)
	elif wall_sliding:
		_apply_slide(delta)

func _apply_run(_delta: float) -> void:
	# Wall tangent: normal × up gives a horizontal vector along the wall.
	var wall_forward: Vector3 = _wall_normal.cross(Vector3.UP)
	if wall_forward.length_squared() < 0.0001:
		return
	wall_forward = wall_forward.normalized()

	# Align the tangent with the player's facing so we always go "forward".
	var player_fwd: Vector3 = -_player.global_transform.basis.z
	var to_pos: float = (player_fwd - wall_forward).length_squared()
	var to_neg: float = (player_fwd + wall_forward).length_squared()
	if to_neg < to_pos:
		wall_forward = -wall_forward

	# Run speed (with optional sprint boost).
	var sprinting: bool = Input.is_action_pressed(sprint_action)
	var speed: float = run_speed
	if sprinting:
		speed *= sprint_run_multiplier

	# Compose velocity: tangent speed, then push into the wall so the
	# player stays stuck to it. No vertical component this session.
	var v: Vector3 = _player.velocity
	v.x = wall_forward.x * speed
	v.z = wall_forward.z * speed
	v.y = 0.0
	v -= _wall_normal * stick_force
	_player.velocity = v

func _apply_climb(_delta: float) -> void:
	# Climb straight up: kill the tangent, push into the wall on the XZ
	# plane (negative normal * stick force), and set Y to climb_speed.
	var push: Vector3 = Vector3(_wall_normal.x, 0.0, _wall_normal.z)

	var v: Vector3 = _player.velocity
	v.x = -push.x * climb_stick_force
	v.z = -push.z * climb_stick_force
	v.y = climb_speed
	_player.velocity = v

func _apply_slide(delta: float) -> void:
	var v: Vector3 = _player.velocity

	# Push into the wall on the horizontal plane so we stay stuck.
	# Only apply the XZ portion of the normal so we don't fight gravity
	# or add vertical drift.
	var push: Vector3 = Vector3(_wall_normal.x, 0.0, _wall_normal.z)
	v -= push * slide_stick_force

	# Vertical: constant slide or ramping acceleration.
	if slide_accel > 0.0:
		v.y = maxf(-slide_max_speed, v.y - slide_accel * delta)
	else:
		v.y = -slide_speed

	# Lateral control: project the player's world wish direction onto the
	# wall plane (removing the wall-normal component) and accelerate
	# along it. Entry horizontal momentum is preserved — the soft cap
	# only limits additional input-driven speed.
	if slide_side_control > 0.0:
		var wish: Vector3 = _sensors.wish_dir_world
		wish -= _wall_normal * wish.dot(_wall_normal)
		wish.y = 0.0
		if wish.length_squared() > 0.0001:
			wish = wish.normalized()
			var flat := Vector3(v.x, 0.0, v.z)
			var cur_spd: float = flat.length()
			if slide_side_max_speed <= 0.0 \
					or cur_spd < slide_side_max_speed:
				var new_flat: Vector3 = flat + wish * slide_side_control * delta
				if slide_side_max_speed > 0.0 \
						and new_flat.length() > slide_side_max_speed:
					new_flat = new_flat.normalized() * slide_side_max_speed
				v.x = new_flat.x
				v.z = new_flat.z

	_player.velocity = v

# -----------------------------------------------------------------------------
# Wall jump
# -----------------------------------------------------------------------------

## Launch the player off the current wall and clear all wall state.
## Called from apply() the frame Space is freshly pressed while a wall
## state is active.
func _do_wall_jump() -> void:
	# 1. Wall tangent as a fallback direction.
	var tangent: Vector3 = _wall_normal.cross(Vector3.UP)
	if tangent.length_squared() < 0.0001:
		_exit_all()
		return
	tangent = tangent.normalized()

	var pfwd: Vector3 = -_player.global_transform.basis.z
	pfwd.y = 0.0
	if pfwd.length_squared() > 0.0001:
		pfwd = pfwd.normalized()
		if pfwd.dot(tangent) < 0.0:
			tangent = -tangent

	# 2. Direction. A completed Q-turn forces the look-direction launch
	# unconditionally (the player is now facing away from the wall).
	# Otherwise: look direction by default (matches ladder jump-off);
	# tangent when jump_uses_wall_forward is on. When using the look
	# direction, fall back to the tangent if the player is looking into
	# the wall face (e.g. mid-climb) so the launch never drives them
	# back into the wall.
	var fwd_dir: Vector3 = tangent
	var post_turn: bool = _turn_grace_timer > 0.0
	if post_turn or not jump_uses_wall_forward:
		var cf: Vector3 = _sensors.cam_forward_xz
		if cf.length_squared() > 0.0001:
			cf = cf.normalized()
			if post_turn or cf.dot(_wall_normal) >= 0.0:
				fwd_dir = cf

	# 3. Compose the launch impulse. The chain bonus is added along
	# fwd_dir BEFORE the away vector is mixed in, so the forward
	# component scales with the accumulated speed while the away push
	# stays constant. Cache the horizontal and vertical parts so the
	# variable cut can shrink both if Space is released early.
	var away: Vector3 = _wall_normal  # points from wall toward player

	var fwd_force: float = jump_forward_force
	if enable_chain:
		fwd_force += _chain_bonus

	var h_component: Vector3 = fwd_dir * fwd_force \
		+ away * jump_away_force
	h_component.y = 0.0

	# Hard cap on composed horizontal launch speed. Applies whenever
	# chain_max_speed > 0, even when enable_chain is off, so the cap
	# also protects against odd tuning elsewhere.
	if chain_max_speed > 0.0 \
			and h_component.length() > chain_max_speed:
		h_component = h_component.normalized() * chain_max_speed

	_wall_jump_h_impulse = h_component
	_wall_jump_v_impulse = jump_up_force
	_player.velocity = Vector3(
		h_component.x, jump_up_force, h_component.z
	)

	# 3b. Chain accumulation. Applied to the NEXT jump. Refresh the
	# timeout so the player has chain_timeout to reach the next wall.
	if enable_chain:
		_chain_bonus = minf(
			_chain_bonus + chain_speed_gain, chain_max_speed
		)
		_chain_timeout_timer = chain_timeout

	# 4. Gates, counter, and lockout.
	_cancel_lockout = exit_time
	_wall_jump_cooldown_timer = wall_jump_cooldown
	_wall_jumps_this_airtime += 1
	_player.movement_lockout = wall_jump_lockout

	# 5. Arm the variable-jump cut window.
	_wall_jump_cut_pending = enable_variable_wall_jump

	# 6. Feedback.
	if _player.has_method("play_jump"):
		_player.play_jump()

	# 7. Clear wall state and consume the Q-turn grace window.
	_exit_all()
	_turn_grace_timer = 0.0

## Advance the variable wall jump cut. Fires as soon as Space is
## released while ascending. Shrinks the horizontal impulse too so a
## quick tap produces a visibly shorter launch in both axes.
func _tick_wall_jump_cut() -> void:
	if _player == null:
		_wall_jump_cut_pending = false
		return
	if _player.is_on_floor():
		_wall_jump_cut_pending = false
		return
	if not enable_variable_wall_jump:
		_wall_jump_cut_pending = false
		return
	if _player.velocity.y <= 0.0:
		_wall_jump_cut_pending = false
		return
	if Input.is_action_pressed(jump_action):
		return

	# Vertical cut.
	var v_cut: float = maxf(
		_player.velocity.y * wall_jump_cut_scale,
		wall_jump_min_velocity
	)
	_player.velocity.y = v_cut

	# Horizontal cut: scale the stored forward impulse. Applied to the
	# current horizontal velocity so any drag or wall-slide contribution
	# is preserved proportionally.
	if wall_jump_forward_cut_scale < 1.0:
		var h_now: Vector3 = Vector3(_player.velocity.x, 0.0, _player.velocity.z)
		# Blend between current horizontal and the scaled reference.
		var h_ref_len: float = _wall_jump_h_impulse.length()
		if h_ref_len > 0.0001:
			var h_now_len: float = h_now.length()
			var h_target_len: float = h_now_len * wall_jump_forward_cut_scale
			if h_now_len > 0.0001:
				h_now = h_now.normalized() * h_target_len
			_player.velocity.x = h_now.x
			_player.velocity.z = h_now.z

	_wall_jump_cut_pending = false
	_wall_jump_h_impulse = Vector3.ZERO
	_wall_jump_v_impulse = 0.0

	var m: Variant = _player.get("movement")
	if m != null and m.has_method("lock_jump_cut"):
		m.lock_jump_cut()

# -----------------------------------------------------------------------------
# Q-turn
# -----------------------------------------------------------------------------

## Begin a Q-turn. Rotates the body around Y over turn_duration. The
## angle and sign depend on the current wall state so the rotation
## always points the player away from the wall face:
##   - climbing → +vertical_turn_degrees (default 180, about-face)
##   - running right wall → -horizontal_turn_degrees
##   - running left wall  → +horizontal_turn_degrees
##   - sliding or unknown → +horizontal_turn_degrees (no sign flip)
## The current wall state (run / slide / climb) continues unchanged for
## the duration of the turn.
func _begin_turn() -> void:
	_turn_used_this_session = true
	_turn_start_yaw = _player.rotation.y

	if wall_climbing:
		_turn_target_yaw = _turn_start_yaw \
			+ deg_to_rad(vertical_turn_degrees)
	elif _wall_side == 1:
		_turn_target_yaw = _turn_start_yaw \
			- deg_to_rad(horizontal_turn_degrees)
	elif _wall_side == -1:
		_turn_target_yaw = _turn_start_yaw \
			+ deg_to_rad(horizontal_turn_degrees)
	else:
		_turn_target_yaw = _turn_start_yaw \
			+ deg_to_rad(horizontal_turn_degrees)

	# Reset bob phases so the wall-state bob doesn't stutter on entry.
	_bob_index = 0.0
	_climb_bob_phase = 0.0
	_slide_bob_phase = 0.0

	# A new turn invalidates any grace window from a previous turn.
	_turn_grace_timer = 0.0

	# Instant snap path.
	if turn_duration <= 0.0:
		_player.rotation.y = _turn_target_yaw
		_turning = false
		_turn_timer = 0.0
		_turn_duration_actual = 0.0
		_turn_grace_timer = turn_grace_time
		return

	_turn_duration_actual = turn_duration
	_turn_timer = 0.0
	_turning = true

## Advance an active Q-turn. Called from detect() at the top, so it
## runs regardless of which branch detect() takes afterward.
func _tick_turn(delta: float) -> void:
	_turn_timer += delta
	var t: float = clampf(_turn_timer / _turn_duration_actual, 0.0, 1.0)
	var eased: float = smoothstep(0.0, 1.0, t)

	_player.rotation.y = lerp_angle(
		_turn_start_yaw, _turn_target_yaw, eased
	)

	# Keep MovementComponent out of the way while the body spins.
	_player.movement_lockout = maxf(_player.movement_lockout, 0.05)

	if t >= 1.0:
		_turning = false
		_turn_timer = 0.0
		_turn_grace_timer = turn_grace_time

# -----------------------------------------------------------------------------
# Update camera
# -----------------------------------------------------------------------------

## Push FOV / roll / bob through the Player's accumulator API.
func update_camera(delta: float) -> void:
	if not camera_effects or _player == null:
		return

	# Climb first — defensive, since only one state should be true.
	if wall_climbing:
		var roll_deg_c: float = tilt_angle * float(_wall_side)
		if _player.has_method("hold_camera_roll"):
			_player.hold_camera_roll(deg_to_rad(roll_deg_c), 0.05)
		if _player.has_method("add_eye_offset"):
			_climb_bob_phase += climb_bob_speed * delta
			var bob_c: float = sin(_climb_bob_phase) * climb_bob_intensity
			_player.add_eye_offset(0.0, bob_c, 0.0)
		return

	if wall_running:
		# Roll leans into the wall. Right wall (side=1) leans -tilt; left
		# wall (side=-1) leans +tilt.
		var roll_deg: float = tilt_angle * float(_wall_side)
		if _player.has_method("hold_camera_fov"):
			_player.hold_camera_fov(fov_wallrun, 0.05)
		if _player.has_method("hold_camera_roll"):
			_player.hold_camera_roll(deg_to_rad(roll_deg), 0.05)

		if bob_enabled and _player.has_method("add_eye_offset"):
			_bob_index += bob_speed * delta
			var bob_y: float = sin(_bob_index) * bob_intensity
			_player.add_eye_offset(0.0, bob_y, 0.0)
		return

	if wall_sliding:
		# Optional roll, unchanged from previous sessions.
		if slide_tilt_scale != 0.0:
			var roll_deg_s: float = tilt_angle * float(_wall_side) * slide_tilt_scale
			if _player.has_method("hold_camera_roll"):
				_player.hold_camera_roll(deg_to_rad(roll_deg_s), 0.05)

		# Optional slide bob.
		if slide_bob_enabled and _player.has_method("add_eye_offset"):
			_slide_bob_phase += slide_bob_speed * delta
			var bob_s: float = sin(_slide_bob_phase) * slide_bob_intensity
			_player.add_eye_offset(0.0, bob_s, 0.0)
		return

# -----------------------------------------------------------------------------
# Internal — helpers
# -----------------------------------------------------------------------------

func _exit_wall_run() -> void:
	wall_running = false

func _exit_all() -> void:
	wall_running = false
	wall_sliding = false
	wall_climbing = false
	_wall_side = 0
	_wall_normal = Vector3.ZERO
	_slide_locked = false
	_slide_time_elapsed = 0.0
	_bob_index = 0.0
	_climb_bob_phase = 0.0
	_slide_bob_phase = 0.0
	_wall_jump_h_impulse = Vector3.ZERO
	_wall_jump_v_impulse = 0.0
	# NOTE: do NOT clear _chain_bonus or _chain_timeout_timer here.
	# exit_all() runs every frame the player leaves a wall state, so
	# clearing here would kill the chain on every wall-to-wall jump.
	# Chain state is owned by the tick block at the top of detect().

func _fall_behavior_active() -> bool:
	if _player == null:
		return false
	var fb: Node = _player.get_node_or_null("FallBehaviorComponent")
	if fb != null and fb.has_method("is_active"):
		return fb.is_active()
	return false

func _dash_active() -> bool:
	if _player == null:
		return false
	var d: Variant = _player.get("do_dash")
	if typeof(d) == TYPE_BOOL:
		return d
	return false

func _force_stand() -> void:
	if _player == null:
		return
	var m: Variant = _player.get("movement")
	if m != null and m.has_method("force_stand"):
		m.force_stand()
