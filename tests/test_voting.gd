extends TestCase


func test_answer_majority_yes() -> void:
	assert_eq(RoundManager.resolve_answer({2: 1, 3: 1, 4: -1}), "YES")


func test_answer_majority_no() -> void:
	assert_eq(RoundManager.resolve_answer({2: -1, 3: -1, 4: 1}), "NO")


func test_answer_tie_is_no() -> void:
	assert_eq(RoundManager.resolve_answer({2: 1, 3: -1}), "NO")


func test_answer_shrugs_do_not_count() -> void:
	assert_eq(RoundManager.resolve_answer({2: 0, 3: 0, 4: 1}), "YES")
	assert_eq(RoundManager.resolve_answer({2: 0, 3: 0}), "NONE")
	assert_eq(RoundManager.resolve_answer({}), "NONE")


func test_guess_writer_weighs_double() -> void:
	# writer (id 9) says correct, two others say wrong: 2 vs 2 -> tie -> wrong
	assert_false(RoundManager.resolve_guess({9: true, 2: false, 3: false}, 9))
	# writer correct, one other wrong: 2 vs 1 -> correct
	assert_true(RoundManager.resolve_guess({9: true, 2: false}, 9))
	# writer wrong, two others correct: 2 vs 2 -> wrong
	assert_false(RoundManager.resolve_guess({9: false, 2: true, 3: true}, 9))
	# writer wrong, three others correct: 3 vs 2 -> correct
	assert_true(RoundManager.resolve_guess({9: false, 2: true, 3: true, 4: true}, 9))


func test_guess_no_votes_is_wrong() -> void:
	assert_false(RoundManager.resolve_guess({}, 9))


func test_two_players_writer_decides() -> void:
	assert_true(RoundManager.resolve_guess({9: true}, 9))
	assert_false(RoundManager.resolve_guess({9: false}, 9))


func test_score_for_rank() -> void:
	assert_eq(RoundManager.score_for_rank(1), 5)
	assert_eq(RoundManager.score_for_rank(2), 4)
	assert_eq(RoundManager.score_for_rank(5), 1)
	assert_eq(RoundManager.score_for_rank(8), 1)
