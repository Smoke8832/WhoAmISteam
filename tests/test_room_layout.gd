extends TestCase
## Sanity checks on the procedural room so a layout typo cannot break the seat ring.


func test_eight_seats_and_spawns() -> void:
	assert_eq(RoomBuilder.SEAT_MODELS.size(), 8, "eight seat models")
	assert_eq(RoomBuilder.spawn_points().size(), 8, "eight spawn points")
	for m in RoomBuilder.SEAT_MODELS:
		assert_true(RoomBuilder.SEAT_HEIGHT.has(m), "seat height for %s" % m)
		assert_true(ResourceLoader.exists(RoomBuilder.MODEL_DIR + m + ".glb"), "model exists %s" % m)


func test_decor_models_exist_and_fit_in_room() -> void:
	for e in RoomBuilder.decor_layout():
		assert_true(ResourceLoader.exists(RoomBuilder.MODEL_DIR + String(e.model) + ".glb"), "decor model %s" % e.model)
		var p: Vector2 = e.pos
		assert_true(absf(p.x) <= RoomBuilder.ROOM_W / 2.0 and absf(p.y) <= RoomBuilder.ROOM_D / 2.0, "decor %s inside room" % e.model)


func test_props_have_homes_inside_room() -> void:
	var layout := RoomBuilder.prop_layout()
	assert_true(layout.size() >= 3, "at least three props")
	for e in layout:
		var p: Vector3 = e.pos
		assert_true(absf(p.x) <= RoomBuilder.ROOM_W / 2.0 and absf(p.z) <= RoomBuilder.ROOM_D / 2.0 and p.y > 0.0, "prop %s inside room" % e.model)


func test_room_builds_with_eight_chairs_and_props() -> void:
	var root := Node3D.new()
	var built := RoomBuilder.build(root)
	assert_eq(built.chairs.size(), 8, "eight chairs built")
	assert_eq(built.props.size(), RoomBuilder.prop_layout().size(), "all props built")
	var ids := {}
	for c in built.chairs:
		ids[c.chair_id] = true
		assert_true(c.has_node("Seat"), "chair %d has a seat marker" % c.chair_id)
	assert_eq(ids.size(), 8, "chair ids unique")
	root.free()
