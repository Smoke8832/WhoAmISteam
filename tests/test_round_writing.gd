extends TestCase


func test_normalize_name() -> void:
	assert_eq(RoundManager.normalize_name("  Michael  Jackson! "), "michaeljackson")
	assert_eq(RoundManager.normalize_name("michael-jackson"), "michaeljackson")
	assert_eq(RoundManager.normalize_name("Beyoncé"), "beyoncé")
	assert_eq(RoundManager.normalize_name(""), "")


func test_sanitize_written_name() -> void:
	var s := RoundManager.sanitize_written_name("  HelloWorld\n ")
	assert_eq(s, "HelloWorld")
	var long := RoundManager.sanitize_written_name("x".repeat(100))
	assert_eq(long.length(), RoundManager.MAX_WRITTEN_NAME)


func test_postit_view_hidden_outside_round() -> void:
	RoundManager.reset()
	var v := RoundManager.postit_view(1)
	assert_false(v.visible)
	assert_true(v.blank)
