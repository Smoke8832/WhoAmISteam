class_name RoomBuilder
extends RefCounted
## Builds the living room deterministically from a layout table, on every peer identically.
## Walls, floor and ceiling are primitives; furniture is the Kenney kit (half scale, so x2).

const MODEL_DIR := "res://assets/models/kenney/"
const KIT_SCALE := 2.0
const ROOM_W := 12.0   # x
const ROOM_D := 10.0   # z
const ROOM_H := 2.7
const WALL_T := 0.2

const COL_FLOOR := Color("c69c6d")
const COL_WALL := Color("f3e9d2")
const COL_WALL_ACCENT := Color("9fc5e8")
const COL_CEILING := Color("dcd5c6")
const COL_TRIM := Color("6b4a2b")

## Seat ring: 8 chairs on an ellipse around the coffee table, all facing the center.
const SEAT_MODELS := ["loungeChair", "chairCushion", "loungeChairRelax", "chair", "loungeChair", "chairModernCushion", "loungeChairRelax", "chairRounded"]
const SEAT_RX := 2.9
const SEAT_RZ := 2.5
## Height of the seat cushion for each seat model (in metres, after scaling).
const SEAT_HEIGHT := {"loungeChair": 0.42, "chairCushion": 0.46, "loungeChairRelax": 0.40, "chair": 0.46, "chairModernCushion": 0.46, "chairRounded": 0.46}

## Decoration: model, position (x, z), rotation degrees, optional scale multiplier, collide flag.
static func decor_layout() -> Array:
	return [
		# north wall: TV
		{"model": "cabinetTelevision", "pos": Vector2(0.0, -4.55), "rot": 0.0},
		{"model": "televisionModern", "pos": Vector2(0.0, -4.55), "rot": 0.0, "y": 0.62, "collide": false},
		{"model": "speaker", "pos": Vector2(-1.6, -4.6), "rot": 0.0},
		{"model": "speaker", "pos": Vector2(1.6, -4.6), "rot": 0.0},
		{"model": "pottedPlant", "pos": Vector2(-2.6, -4.5), "rot": 0.0},
		{"model": "lampRoundFloor", "pos": Vector2(2.7, -4.5), "rot": 0.0},
		# west wall: bookcases + sofa for lounging (not a game seat)
		{"model": "bookcaseClosedWide", "pos": Vector2(-5.6, -2.6), "rot": 90.0},
		{"model": "bookcaseOpen", "pos": Vector2(-5.6, -1.4), "rot": 90.0},
		{"model": "loungeSofa", "pos": Vector2(-5.3, 2.4), "rot": 90.0},
		{"model": "sideTable", "pos": Vector2(-5.5, 4.0), "rot": 90.0},
		{"model": "lampSquareTable", "pos": Vector2(-5.5, 4.0), "rot": 0.0, "y": 0.76, "collide": false},
		# east wall: desk corner + coat rack near the door
		{"model": "desk", "pos": Vector2(5.4, -3.2), "rot": -90.0},
		{"model": "computerScreen", "pos": Vector2(5.4, -3.2), "rot": -90.0, "y": 0.76, "collide": false},
		{"model": "chairModernCushion", "pos": Vector2(4.6, -3.2), "rot": 90.0},
		{"model": "coatRackStanding", "pos": Vector2(5.5, 4.2), "rot": 0.0},
		{"model": "trashcan", "pos": Vector2(5.5, -1.6), "rot": 0.0},
		{"model": "radio", "pos": Vector2(5.5, 1.0), "rot": -90.0, "y": 0.0, "collide": false},
		# south wall: plants by the door, bear on the box
		{"model": "pottedPlant", "pos": Vector2(-1.6, 4.55), "rot": 0.0},
		{"model": "cardboardBoxClosed", "pos": Vector2(3.6, 4.5), "rot": 15.0},
		{"model": "bear", "pos": Vector2(3.6, 4.5), "rot": 200.0, "y": 0.56, "collide": false},
		# center
		{"model": "rugRectangle", "pos": Vector2(0.0, 0.0), "rot": 0.0, "scale": 1.5, "collide": false},
		{"model": "tableCoffee", "pos": Vector2(0.0, 0.0), "rot": 0.0},
		{"model": "books", "pos": Vector2(-0.3, 0.1), "rot": 20.0, "y": 0.46, "collide": false},
		{"model": "plantSmall2", "pos": Vector2(0.4, -0.1), "rot": 0.0, "y": 0.46, "collide": false},
	]


## Throwable props: model (or "ball"), spawn position.
static func prop_layout() -> Array:
	return [
		{"model": "pillow", "pos": Vector3(-5.1, 0.95, 2.0)},
		{"model": "pillowBlue", "pos": Vector3(-5.1, 0.95, 2.8)},
		{"model": "pillowLong", "pos": Vector3(0.0, 0.6, 0.0)},
		{"model": "ball", "pos": Vector3(3.5, 0.4, 3.2)},
	]


static func spawn_points() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	# Players spawn near the south door, facing north into the room.
	var xs := [-2.4, -1.2, 0.0, 1.2, 2.4, -1.8, 0.6, -0.6]
	var zs := [3.6, 3.9, 3.6, 3.9, 3.6, 3.0, 3.0, 4.2]
	for i in 8:
		out.append(Transform3D(Basis(Vector3.UP, 0.0), Vector3(xs[i], 0.05, zs[i])))
	return out


# ------------------------------------------------------------------ build

static func build(root: Node3D) -> Dictionary:
	var chairs: Array = []
	var props: Array = []
	_build_shell(root)
	_build_seats(root, chairs)
	for entry in decor_layout():
		_place_decor(root, entry)
	_build_props(root, props)
	_build_fixtures(root)
	ToonMaterials.convert(root)
	return {"chairs": chairs, "props": props}


static func _mat(color: Color, _roughness: float = 0.9) -> Material:
	return ToonMaterials.make(color)


static func _box(parent: Node3D, name: String, size: Vector3, pos: Vector3, color: Color, collide: bool = true) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = name
	body.position = pos
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = _mat(color)
	body.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		body.add_child(cs)
	body.add_to_group("room")
	parent.add_child(body)
	return body


static func _build_shell(root: Node3D) -> void:
	var shell := Node3D.new()
	shell.name = "Shell"
	root.add_child(shell)
	_box(shell, "Floor", Vector3(ROOM_W, WALL_T, ROOM_D), Vector3(0, -WALL_T / 2.0, 0), COL_FLOOR)
	_box(shell, "Ceiling", Vector3(ROOM_W, WALL_T, ROOM_D), Vector3(0, ROOM_H + WALL_T / 2.0, 0), COL_CEILING)
	_box(shell, "WallN", Vector3(ROOM_W, ROOM_H, WALL_T), Vector3(0, ROOM_H / 2.0, -ROOM_D / 2.0 - WALL_T / 2.0), COL_WALL_ACCENT)
	_box(shell, "WallS", Vector3(ROOM_W, ROOM_H, WALL_T), Vector3(0, ROOM_H / 2.0, ROOM_D / 2.0 + WALL_T / 2.0), COL_WALL)
	_box(shell, "WallE", Vector3(WALL_T, ROOM_H, ROOM_D), Vector3(ROOM_W / 2.0 + WALL_T / 2.0, ROOM_H / 2.0, 0), COL_WALL)
	_box(shell, "WallW", Vector3(WALL_T, ROOM_H, ROOM_D), Vector3(-ROOM_W / 2.0 - WALL_T / 2.0, ROOM_H / 2.0, 0), COL_WALL)
	# Skirting board
	_box(shell, "TrimN", Vector3(ROOM_W, 0.12, 0.04), Vector3(0, 0.06, -ROOM_D / 2.0 + 0.02), COL_TRIM, false)
	_box(shell, "TrimS", Vector3(ROOM_W, 0.12, 0.04), Vector3(0, 0.06, ROOM_D / 2.0 - 0.02), COL_TRIM, false)
	_box(shell, "TrimE", Vector3(0.04, 0.12, ROOM_D), Vector3(ROOM_W / 2.0 - 0.02, 0.06, 0), COL_TRIM, false)
	_box(shell, "TrimW", Vector3(0.04, 0.12, ROOM_D), Vector3(-ROOM_W / 2.0 + 0.02, 0.06, 0), COL_TRIM, false)
	# Windows on the east wall (emissive panes)
	for z in [-2.4, 0.0, 2.4]:
		var pane := _box(shell, "Window%d" % int(z * 10), Vector3(0.06, 1.3, 1.6), Vector3(ROOM_W / 2.0 - 0.06, 1.7, z), Color("dff3ff"), false)
		(pane.get_child(0) as MeshInstance3D).material_override = ToonMaterials.make(Color("dff3ff"), null, Color("cfeaff"), 0.8)
		_box(shell, "WindowFrame%d" % int(z * 10), Vector3(0.08, 1.4, 1.7), Vector3(ROOM_W / 2.0 - 0.1, 1.7, z), Color("f7f4ec"), false)
	# Door on the south wall
	_box(shell, "Door", Vector3(1.1, 2.2, 0.06), Vector3(4.6, 1.1, ROOM_D / 2.0 - 0.04), COL_TRIM, false)


static func _load_model(model: String) -> Node3D:
	var scene: PackedScene = load(MODEL_DIR + model + ".glb")
	if scene == null:
		push_warning("RoomBuilder: missing model %s" % model)
		return null
	return scene.instantiate() as Node3D


## Returns the merged local AABB of a model instance (not yet in tree).
static func model_aabb(inst: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var a := m.transform * m.get_aabb()
		var p := m.get_parent()
		while p != null and p != inst and p is Node3D:
			a = (p as Node3D).transform * a
			p = p.get_parent()
		result = a if first else result.merge(a)
		first = false
	return result


## Wraps a model so its footprint is centred on X/Z and its bottom sits at y=0.
static func _centered_model(model: String, scale: float) -> Dictionary:
	var inst := _load_model(model)
	if inst == null:
		return {}
	var aabb := model_aabb(inst)
	var pivot := Node3D.new()
	pivot.name = model
	inst.scale = Vector3.ONE * scale
	var c := aabb.get_center()
	inst.position = Vector3(-c.x, -aabb.position.y, -c.z) * scale
	pivot.add_child(inst)
	return {"node": pivot, "size": aabb.size * scale}


static func _place_decor(root: Node3D, entry: Dictionary) -> void:
	var scale := KIT_SCALE * float(entry.get("scale", 1.0))
	var built := _centered_model(String(entry.model), scale)
	if built.is_empty():
		return
	var pivot: Node3D = built.node
	var size: Vector3 = built.size
	var collide := bool(entry.get("collide", true))
	var pos := Vector3(entry.pos.x, float(entry.get("y", 0.0)), entry.pos.y)
	var parent: Node3D
	if collide:
		var body := StaticBody3D.new()
		body.name = "Decor_%s_%d" % [entry.model, root.get_child_count()]
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		cs.position = Vector3(0, size.y / 2.0, 0)
		body.add_child(cs)
		body.add_to_group("room")
		parent = body
	else:
		parent = Node3D.new()
		parent.name = "Decor_%s_%d" % [entry.model, root.get_child_count()]
	parent.position = pos
	parent.rotation.y = deg_to_rad(float(entry.get("rot", 0.0)))
	parent.add_child(pivot)
	root.add_child(parent)


static func _build_seats(root: Node3D, chairs: Array) -> void:
	var seats := Node3D.new()
	seats.name = "Seats"
	root.add_child(seats)
	for i in 8:
		var ang := deg_to_rad(i * 45.0 + 180.0)   # seat 0 at the south (near the door)
		var pos := Vector3(SEAT_RX * sin(ang), 0.0, SEAT_RZ * cos(ang))
		var model := String(SEAT_MODELS[i])
		var built := _centered_model(model, KIT_SCALE)
		if built.is_empty():
			continue
		var chair := Chair.new()
		chair.name = "Chair%d" % i
		chair.chair_id = i
		chair.position = pos
		# Kenney chairs face their local +Z; point that at the room center.
		chair.rotation.y = atan2(-pos.x, -pos.z)
		var size: Vector3 = built.size
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		cs.position = Vector3(0, size.y / 2.0, 0)
		chair.add_child(cs)
		chair.add_child(built.node)
		var seat := Marker3D.new()
		seat.name = "Seat"
		seat.position = Vector3(0, float(SEAT_HEIGHT.get(model, 0.45)), 0.05)
		chair.add_child(seat)
		seats.add_child(chair)
		chairs.append(chair)


static func _build_props(root: Node3D, props: Array) -> void:
	var holder := Node3D.new()
	holder.name = "Props"
	root.add_child(holder)
	var i := 0
	for entry in prop_layout():
		var prop := Prop.new()
		prop.name = "Prop%d" % i
		prop.prop_id = i
		var model := String(entry.model)
		if model == "ball":
			var mi := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 0.18
			sphere.height = 0.36
			mi.mesh = sphere
			mi.material_override = _mat(Color("e0523e"), 0.6)
			prop.add_child(mi)
			var cs := CollisionShape3D.new()
			var s := SphereShape3D.new()
			s.radius = 0.18
			cs.shape = s
			prop.add_child(cs)
			prop.mass = 0.6
		else:
			var built := _centered_model(model, KIT_SCALE)
			if built.is_empty():
				continue
			var size: Vector3 = built.size
			(built.node as Node3D).position.y = -size.y / 2.0
			prop.add_child(built.node)
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = size
			cs.shape = box
			prop.add_child(cs)
			prop.mass = 0.4
		prop.position = entry.pos
		prop.home_position = entry.pos
		holder.add_child(prop)
		props.append(prop)
		i += 1


## Fixtures that later milestones fill with content: TV screen, whiteboard, wardrobe mirror.
static func _build_fixtures(root: Node3D) -> void:
	var fx := Node3D.new()
	fx.name = "Fixtures"
	root.add_child(fx)
	# TV screen quad (M3 renders the lobby/TV UI onto it)
	var tv := MeshInstance3D.new()
	tv.name = "TvScreen"
	var quad := QuadMesh.new()
	quad.size = Vector2(1.3, 0.78)
	tv.mesh = quad
	tv.position = Vector3(0.0, 1.07, -4.53)
	tv.material_override = ToonMaterials.make(Color("101418"), null, Color("1c2a3a"), 0.6)
	fx.add_child(tv)
	# Whiteboard on the west wall (M3 draws the rules)
	var wb := StaticBody3D.new()
	wb.name = "Whiteboard"
	wb.position = Vector3(-5.88, 1.6, 0.4)
	wb.rotation.y = PI / 2.0
	var wbm := MeshInstance3D.new()
	var wbq := QuadMesh.new()
	wbq.size = Vector2(2.2, 1.4)
	wbm.mesh = wbq
	wbm.material_override = _mat(Color("fbfbf8"), 0.5)
	wb.add_child(wbm)
	var frame := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(2.3, 1.5, 0.04)
	frame.mesh = fb
	frame.position.z = -0.03
	frame.material_override = _mat(Color("8e8e8e"))
	wb.add_child(frame)
	wb.add_to_group("room")
	# Rules written on the board in marker
	var marker: Font = load("res://assets/fonts/PatrickHand-Regular.ttf")
	var title := Label3D.new()
	title.text = "HOW TO PLAY"
	title.font = marker
	title.font_size = 64
	title.pixel_size = 0.0035
	title.modulate = Color("1c3f8f")
	title.position = Vector3(0, 0.52, 0.01)
	wb.add_child(title)
	var lines := ["1. Write a name for the player on your RIGHT.", "2. It gets stuck on their forehead.", "3. Ask yes/no questions. Everyone votes.", "4. Think you know? Say it! Others judge.", "5. First to guess wins the round."]
	for i in lines.size():
		var l := Label3D.new()
		l.text = lines[i]
		l.font = marker
		l.font_size = 40
		l.pixel_size = 0.0035
		l.modulate = Color("1c1a17") if i % 2 == 0 else Color("b5352c")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.position = Vector3(-1.0, 0.28 - i * 0.2, 0.01)
		l.width = 600
		wb.add_child(l)
	fx.add_child(wb)
	# Wardrobe mirror in the south-west corner (M2 opens the customizer)
	var wardrobe := StaticBody3D.new()
	wardrobe.name = "Wardrobe"
	wardrobe.add_to_group("wardrobe")
	wardrobe.position = Vector3(-4.6, 0.0, 4.6)
	var cabinet := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(1.4, 2.2, 0.6)
	cabinet.mesh = cb
	cabinet.position.y = 1.1
	cabinet.material_override = _mat(COL_TRIM)
	wardrobe.add_child(cabinet)
	var mirror := MeshInstance3D.new()
	var mq := QuadMesh.new()
	mq.size = Vector2(1.0, 1.8)
	mirror.mesh = mq
	mirror.position = Vector3(0, 1.15, 0.31)
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color("cfe6f5")
	mm.roughness = 0.05
	mm.metallic = 0.9
	mirror.material_override = mm
	wardrobe.add_child(mirror)
	var wcs := CollisionShape3D.new()
	var wshape := BoxShape3D.new()
	wshape.size = Vector3(1.4, 2.2, 0.6)
	wcs.shape = wshape
	wcs.position.y = 1.1
	wardrobe.add_child(wcs)
	fx.add_child(wardrobe)
