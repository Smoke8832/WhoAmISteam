class_name TestCase
extends RefCounted
## Minimal unit-test base. Subclasses define test_* methods and use the assert_* helpers.
## Run all tests with tools/run_tests.ps1 (godot --headless tests/TestMain.tscn).

var failures: Array[String] = []
var _current := ""


func _fail(msg: String) -> void:
	failures.append("%s: %s" % [_current, msg])


func assert_true(cond: bool, msg: String = "expected true") -> void:
	if not cond:
		_fail(msg)


func assert_false(cond: bool, msg: String = "expected false") -> void:
	if cond:
		_fail(msg)


func assert_eq(actual, expected, msg: String = "") -> void:
	if actual != expected:
		_fail("%s expected %s got %s" % [msg, str(expected), str(actual)])


func assert_ne(actual, not_expected, msg: String = "") -> void:
	if actual == not_expected:
		_fail("%s did not expect %s" % [msg, str(not_expected)])


func assert_in(value, collection, msg: String = "") -> void:
	if not (value in collection):
		_fail("%s %s not in %s" % [msg, str(value), str(collection)])


func assert_approx(actual: float, expected: float, eps: float = 0.001, msg: String = "") -> void:
	if absf(actual - expected) > eps:
		_fail("%s expected ~%f got %f" % [msg, expected, actual])


## Called by the runner; returns [passed, failed, failure_messages]
func run_all() -> Array:
	var passed := 0
	var failed := 0
	for m in get_method_list():
		var n: String = m.name
		if not n.begins_with("test_"):
			continue
		_current = n
		var before := failures.size()
		call(n)
		if failures.size() == before:
			passed += 1
		else:
			failed += 1
	return [passed, failed, failures]
