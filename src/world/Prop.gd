class_name Prop
extends RigidBody3D
## A throwable object (pillow, ball). Simulated on the host only; clients interpolate.
## Grab/throw requests go through Game (req_grab / req_throw) so the host validates them.

const MAX_THROW_FORCE := 9.0
const RESET_BELOW_Y := -3.0

var prop_id: int = -1
var home_position: Vector3 = Vector3.ZERO

# Replicated host -> all
var net_pos: Vector3 = Vector3.ZERO
var net_rot: Quaternion = Quaternion.IDENTITY
var held_by: int = 0

var _sync: MultiplayerSynchronizer


func _ready() -> void:
	add_to_group("props")
	add_to_group("interactable")
	continuous_cd = true
	can_sleep = true
	collision_layer = 2          # props
	collision_mask = 1 | 2 | 4   # room, props, players
	net_pos = global_position
	net_rot = global_transform.basis.get_rotation_quaternion()
	_sync = MultiplayerSynchronizer.new()
	_sync.name = "Sync"
	var cfg := SceneReplicationConfig.new()
	for prop_name in ["net_pos", "net_rot", "held_by"]:
		var path := NodePath(".:" + prop_name)
		cfg.add_property(path)
		cfg.property_set_spawn(path, true)
		cfg.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	_sync.replication_config = cfg
	_sync.replication_interval = 0.05
	add_child(_sync)
	if not Net.is_host():
		freeze = true
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC


func _physics_process(delta: float) -> void:
	if Net.is_host():
		if held_by != 0:
			var main := get_tree().current_scene
			var holder: Node = main.player_node(held_by) if main and main.has_method("player_node") else null
			if holder == null or not is_instance_valid(holder):
				release()
			else:
				freeze = true
				var target: Transform3D = holder.hold_transform()
				global_transform = global_transform.interpolate_with(target, clampf(delta * 18.0, 0.0, 1.0))
		elif global_position.y < RESET_BELOW_Y:
			reset_home()
		net_pos = global_position
		net_rot = global_transform.basis.get_rotation_quaternion()
	else:
		var t := clampf(delta * 14.0, 0.0, 1.0)
		global_position = global_position.lerp(net_pos, t)
		var q := global_transform.basis.get_rotation_quaternion().slerp(net_rot, t)
		global_transform.basis = Basis(q)


# ---------------------------------------------------------------- host API

func grab(peer_id: int) -> bool:
	if not Net.is_host() or held_by != 0:
		return false
	held_by = peer_id
	freeze = true
	return true


func release() -> void:
	if not Net.is_host():
		return
	held_by = 0
	freeze = false
	sleeping = false


func throw(direction: Vector3, force: float) -> void:
	if not Net.is_host():
		return
	release()
	var dir := direction.normalized() if direction.length() > 0.01 else Vector3.FORWARD
	apply_central_impulse(dir * clampf(force, 0.0, MAX_THROW_FORCE) * mass)
	apply_torque_impulse(Vector3(randf_range(-0.2, 0.2), randf_range(-0.2, 0.2), randf_range(-0.2, 0.2)))


func reset_home() -> void:
	if not Net.is_host():
		return
	release()
	global_position = home_position
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
