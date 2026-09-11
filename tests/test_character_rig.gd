extends TestCase


func test_every_hair_facial_and_accessory_builds() -> void:
	var rig := CharacterRig.new()
	for hair in Customization.OPTIONS.hair:
		for acc in Customization.OPTIONS.accessory:
			var c := Customization.defaults()
			c.hair = hair
			c.accessory = acc
			c.facial_hair = (hair + acc) % Customization.OPTIONS.facial_hair
			c.head = (hair + acc) % Customization.OPTIONS.head
			c.pattern = acc % Customization.OPTIONS.pattern
			rig.apply(c)
			var meshes := rig.find_children("*", "MeshInstance3D", true, false)
			assert_true(meshes.size() >= 10, "hair %d acc %d has meshes (%d)" % [hair, acc, meshes.size()])
			assert_true(rig.postit != null, "post-it exists")
			assert_true(rig.head_node() != null, "head exists")
	rig.free()


func test_animations_and_emotes_run() -> void:
	var rig := CharacterRig.new()
	rig.apply(Customization.randomized())
	for anim in [CharacterRig.Anim.IDLE, CharacterRig.Anim.WALK, CharacterRig.Anim.JUMP, CharacterRig.Anim.CROUCH, CharacterRig.Anim.SIT]:
		for i in 10:
			rig.set_anim(anim, 0.05)
	for e in 3:
		rig.play_emote(e)
		for i in 60:
			rig.set_anim(CharacterRig.Anim.IDLE, 0.05)
	rig.set_talking(1.0)
	for i in 10:
		rig.set_anim(CharacterRig.Anim.IDLE, 0.05)
	assert_true(true)
	rig.free()


func test_toon_materials() -> void:
	var m := ToonMaterials.make(Color.RED)
	assert_true(m is ShaderMaterial and m.shader != null, "toon material has shader")
	assert_eq(ToonMaterials.pattern_texture(0, Color.RED), null, "plain has no texture")
	var t := ToonMaterials.pattern_texture(1, Color.RED)
	assert_eq(t.get_width(), 64)
	assert_true(ToonMaterials.pattern_texture(2, Color.BLUE) != null)
