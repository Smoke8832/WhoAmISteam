extends Node3D
## The living room. Also the lobby. Built procedurally by RoomBuilder on every peer.

var chair_nodes: Array = []
var prop_nodes: Array = []
var _spawns: Array[Transform3D] = []


const TV_SCRIPT := preload("res://src/world/TvScreen.gd")

var tv: Node = null


func _ready() -> void:
	# Afternoon sun from the east windows, high enough to throw short shadows.
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.look_at_from_position(Vector3(5.0, 7.0, 3.0), Vector3(-1.0, 0.0, -1.0), Vector3.UP)
	var built := RoomBuilder.build(self)
	chair_nodes = built.chairs
	prop_nodes = built.props
	_spawns = RoomBuilder.spawn_points()
	var quad := get_node_or_null("Fixtures/TvScreen") as MeshInstance3D
	if quad:
		tv = Node.new()
		tv.name = "Tv"
		tv.set_script(TV_SCRIPT)
		add_child(tv)
		tv.setup(quad)


func spawn_transform(slot: int) -> Transform3D:
	if _spawns.is_empty():
		return Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 3))
	return _spawns[slot % _spawns.size()]


func chairs() -> Array:
	return chair_nodes


func chair(chair_id: int) -> Chair:
	if chair_id < 0 or chair_id >= chair_nodes.size():
		return null
	return chair_nodes[chair_id]


func props() -> Array:
	return prop_nodes


func prop(prop_id: int) -> Prop:
	if prop_id < 0 or prop_id >= prop_nodes.size():
		return null
	return prop_nodes[prop_id]


## Seat order used for the ring assignment: chair ids ascending (clockwise around the table).
func seat_order() -> Array:
	var ids: Array = []
	for c in chair_nodes:
		ids.append(c.chair_id)
	return ids
