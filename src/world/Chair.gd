class_name Chair
extends StaticBody3D
## A seat in the ring. Occupancy is decided by the host and lives in Game.players[peer].seat.

var chair_id: int = -1


func _ready() -> void:
	add_to_group("chairs")
	add_to_group("interactable")


func seat_transform() -> Transform3D:
	var seat := get_node_or_null("Seat") as Node3D
	return seat.global_transform if seat else global_transform


## Where a player stands up to (in front of the chair). The chair's front is its local +Z.
func stand_transform() -> Transform3D:
	var t := global_transform
	var front := t.basis.z.normalized()
	return Transform3D(Basis(Vector3.UP, facing_yaw()), Vector3(t.origin.x, 0.05, t.origin.z) + front * 0.75)


## Yaw a player should have to look the same way the chair faces (Godot forward is -Z).
func facing_yaw() -> float:
	return rotation.y + PI


func occupant() -> int:
	for id in Game.players.keys():
		if int(Game.players[id].get("seat", -1)) == chair_id:
			return id
	return 0


func is_free() -> bool:
	return occupant() == 0
