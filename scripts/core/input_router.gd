## Reads raw input for this tick and exposes a normalized move intent plus discrete actions.
extends Node
class_name InputRouter

var _player: CharacterBody3D
var _move_intent: Vector2 = Vector2.ZERO
var _jump_just_pressed: bool = false
var _jump_just_released: bool = false
var _crouch_just_pressed: bool = false
var _crouch_held: bool = false
var _prone_just_pressed: bool = false
var _prone_held: bool = false
var _mouse_delta_x: float = 0.0

var _accumulated_mouse_delta_x: float = 0.0

var _prev_crouch_fallback: bool = false
var _prev_prone_fallback: bool = false

var _warned_missing_move: bool = false
var _warned_missing_jump: bool = false
var _warned_missing_crouch: bool = false
var _warned_missing_prone: bool = false


func setup(player: CharacterBody3D) -> void:
	if player == null:
		push_error("InputRouter: player reference is null.")
		return
	_player = player


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_accumulated_mouse_delta_x += event.relative.x


func tick(_delta: float) -> void:
	if _player == null:
		return
	_update_move_intent()
	_update_jump_input()
	_update_crouch_input()
	_update_prone_input()
	_update_mouse_delta()


func get_move_intent() -> Vector2:
	return _move_intent


func get_jump_just_pressed() -> bool:
	return _jump_just_pressed


func get_jump_just_released() -> bool:
	return _jump_just_released


func get_crouch_just_pressed() -> bool:
	return _crouch_just_pressed


func get_crouch_held() -> bool:
	return _crouch_held


func get_prone_just_pressed() -> bool:
	return _prone_just_pressed


func get_prone_held() -> bool:
	return _prone_held


## Horizontal mouse delta accumulated since the previous physics tick, in pixels.
func get_mouse_delta_x() -> float:
	return _mouse_delta_x


func _update_move_intent() -> void:
	if _has_all_move_actions():
		_move_intent = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	else:
		if not _warned_missing_move:
			push_warning("InputRouter: move_left/right/forward/backward missing from InputMap; falling back to ui_left/right/up/down. Add the named actions for production use.")
			_warned_missing_move = true
		_move_intent = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")


func _update_jump_input() -> void:
	if InputMap.has_action("jump"):
		_jump_just_pressed = Input.is_action_just_pressed("jump")
		_jump_just_released = Input.is_action_just_released("jump")
	else:
		if not _warned_missing_jump:
			push_warning("InputRouter: 'jump' action missing from InputMap; falling back to ui_accept (Space/Enter). Add the named action for production use.")
			_warned_missing_jump = true
		_jump_just_pressed = Input.is_action_just_pressed("ui_accept")
		_jump_just_released = Input.is_action_just_released("ui_accept")


func _update_crouch_input() -> void:
	if InputMap.has_action("crouch"):
		_crouch_just_pressed = Input.is_action_just_pressed("crouch")
		_crouch_held = Input.is_action_pressed("crouch")
	else:
		if not _warned_missing_crouch:
			push_warning("InputRouter: 'crouch' action missing from InputMap; falling back to physical Ctrl key. Add the named action (Project Settings → Input Map) for remappable crouch.")
			_warned_missing_crouch = true
		var now_held := Input.is_key_pressed(KEY_CTRL)
		_crouch_just_pressed = now_held and not _prev_crouch_fallback
		_crouch_held = now_held
		_prev_crouch_fallback = now_held


func _update_prone_input() -> void:
	if InputMap.has_action("prone"):
		_prone_just_pressed = Input.is_action_just_pressed("prone")
		_prone_held = Input.is_action_pressed("prone")
	else:
		if not _warned_missing_prone:
			push_warning("InputRouter: 'prone' action missing from InputMap; falling back to physical Z key. Add the named action (Project Settings → Input Map) for remappable prone.")
			_warned_missing_prone = true
		var now_held := Input.is_key_pressed(KEY_Z)
		_prone_just_pressed = now_held and not _prev_prone_fallback
		_prone_held = now_held
		_prev_prone_fallback = now_held


func _update_mouse_delta() -> void:
	_mouse_delta_x = _accumulated_mouse_delta_x
	_accumulated_mouse_delta_x = 0.0


func _has_all_move_actions() -> bool:
	return InputMap.has_action("move_left") \
		and InputMap.has_action("move_right") \
		and InputMap.has_action("move_forward") \
		and InputMap.has_action("move_backward")
