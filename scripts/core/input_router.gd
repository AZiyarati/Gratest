## Reads raw input for this tick and exposes a normalized move intent plus discrete actions.
extends Node
class_name InputRouter

var _player: CharacterBody3D
var _move_intent: Vector2 = Vector2.ZERO
var _jump_just_pressed: bool = false
var _warned_missing_move: bool = false
var _warned_missing_jump: bool = false


func setup(player: CharacterBody3D) -> void:
	if player == null:
		push_error("InputRouter: player reference is null.")
		return
	_player = player


func tick(_delta: float) -> void:
	if _player == null:
		return
	_update_move_intent()
	_update_jump_pressed()


func get_move_intent() -> Vector2:
	return _move_intent


func get_jump_just_pressed() -> bool:
	return _jump_just_pressed


func _update_move_intent() -> void:
	if _has_all_move_actions():
		_move_intent = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	else:
		if not _warned_missing_move:
			push_warning("InputRouter: move_left/right/forward/backward missing from InputMap; falling back to ui_left/right/up/down. Add the named actions for production use.")
			_warned_missing_move = true
		_move_intent = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")


func _update_jump_pressed() -> void:
	if InputMap.has_action("jump"):
		_jump_just_pressed = Input.is_action_just_pressed("jump")
	else:
		if not _warned_missing_jump:
			push_warning("InputRouter: 'jump' action missing from InputMap; falling back to ui_accept (Space/Enter). Add the named action for production use.")
			_warned_missing_jump = true
		_jump_just_pressed = Input.is_action_just_pressed("ui_accept")


func _has_all_move_actions() -> bool:
	return InputMap.has_action("move_left") \
		and InputMap.has_action("move_right") \
		and InputMap.has_action("move_forward") \
		and InputMap.has_action("move_backward")
