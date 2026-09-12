extends TestCase


func test_build_ring_forward() -> void:
	var a := RoundManager.build_ring([10, 20, 30, 40], 1)
	# writer i writes for the next player: target(i+1) <- writer(i)
	assert_eq(a[20], 10)
	assert_eq(a[30], 20)
	assert_eq(a[40], 30)
	assert_eq(a[10], 40)
	assert_eq(a.size(), 4)


func test_build_ring_backward() -> void:
	var a := RoundManager.build_ring([10, 20, 30], -1)
	assert_eq(a[10], 20)
	assert_eq(a[20], 30)
	assert_eq(a[30], 10)


func test_ring_nobody_writes_for_themselves() -> void:
	for n in range(2, 9):
		var order: Array = []
		for i in n:
			order.append(100 + i)
		for dir in [1, -1]:
			var a := RoundManager.build_ring(order, dir)
			var writers := {}
			for target in a.keys():
				assert_ne(int(a[target]), int(target), "self-assignment n=%d dir=%d" % [n, dir])
				writers[int(a[target])] = true
			assert_eq(writers.size(), n, "every player writes exactly once n=%d" % n)


func test_two_players_write_for_each_other() -> void:
	var a := RoundManager.build_ring([1, 2], 1)
	assert_eq(a[1], 2)
	assert_eq(a[2], 1)


func test_ring_empty() -> void:
	assert_eq(RoundManager.build_ring([], 1).size(), 0)


func test_famous_names_load() -> void:
	var all := FamousNames.all()
	assert_true(all.size() >= 150, "at least 150 famous names (%d)" % all.size())
	var n := FamousNames.random_name()
	assert_true(n.length() > 1, "random name non-empty")
	for e in all:
		assert_true(e.has("name") and e.has("wiki"), "entry has name and wiki")


func test_rejoin_remap() -> void:
	RoundManager.reset()
	RoundManager.r.order = [1, 5, 9]
	RoundManager.r.turn_order = [1, 5, 9]
	RoundManager.r.assignments = {5: 1, 9: 5, 1: 9}
	RoundManager.r.names = {5: {"name": "x"}, 9: {"name": "y"}, 1: {"name": "z"}}
	RoundManager.r.turns_used = {1: 0, 5: 2, 9: 1}
	# Simulate the host path of the remap without being host: call the private helper logic
	RoundManager._remap(RoundManager.r.order, 5, 12)
	assert_eq(RoundManager.r.order, [1, 12, 9])
	RoundManager.reset()
