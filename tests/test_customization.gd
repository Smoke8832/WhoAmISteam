extends TestCase


func test_defaults_have_every_key() -> void:
	var d := Customization.defaults()
	for key in Customization.OPTIONS.keys():
		assert_true(d.has(key), "default has %s" % key)


func test_sanitize_clamps_and_drops() -> void:
	var s := Customization.sanitize({"skin": 99, "hair": -4, "shirt": 3, "bogus": 1, "eyes": "two"})
	assert_eq(s.skin, Customization.OPTIONS.skin - 1, "skin clamped high")
	assert_eq(s.hair, 0, "hair clamped low")
	assert_eq(s.shirt, 3, "valid kept")
	assert_false(s.has("bogus"), "unknown dropped")
	assert_eq(s.eyes, 0, "string ignored")


func test_sanitize_non_dictionary() -> void:
	var s := Customization.sanitize("nope")
	assert_eq(s, Customization.defaults())


func test_randomized_is_valid() -> void:
	for i in 50:
		var r := Customization.randomized()
		var s := Customization.sanitize(r)
		for key in Customization.OPTIONS.keys():
			assert_eq(s[key], r[key], "random %s already in range" % key)


func test_color_tables_match_option_counts() -> void:
	assert_eq(Customization.SKIN_COLORS.size(), Customization.OPTIONS.skin)
	assert_eq(Customization.HAIR_COLORS.size(), Customization.OPTIONS.hair_color)
	assert_eq(Customization.SHIRT_COLORS.size(), Customization.OPTIONS.shirt)
	assert_eq(Customization.PANTS_COLORS.size(), Customization.OPTIONS.pants)
	assert_eq(Customization.SHOE_COLORS.size(), Customization.OPTIONS.shoes)
