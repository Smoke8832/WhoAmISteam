extends Node3D
## The living room. Also the lobby. Exposes spawn points and (from M1) chairs and props.

@onready var spawn_points: Node3D = $SpawnPoints


func spawn_transform(slot: int) -> Transform3D:
	var points := spawn_points.get_children()
	if points.is_empty():
		return Transform3D(Basis.IDENTITY, Vector3(0, 1, 0))
	var m: Node3D = points[slot % points.size()]
	return m.global_transform


func chairs() -> Array:
	return get_tree().get_nodes_in_group("chairs")
