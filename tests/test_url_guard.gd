extends TestCase


func test_private_ips() -> void:
	for ip in ["127.0.0.1", "10.1.2.3", "172.16.0.1", "172.31.255.255", "192.168.1.1", "169.254.10.10", "0.0.0.0", "100.64.0.1", "224.0.0.1", "::1", "fe80::1", "fd00::5", "::ffff:192.168.0.1"]:
		assert_true(ImageSearch.is_private_ip(ip), "%s is private" % ip)


func test_public_ips() -> void:
	for ip in ["8.8.8.8", "1.1.1.1", "172.32.0.1", "172.15.0.1", "208.80.154.224", "2001:4860:4860::8888", "::ffff:8.8.8.8"]:
		assert_false(ImageSearch.is_private_ip(ip), "%s is public" % ip)


func test_url_scheme_and_hosts() -> void:
	assert_false(ImageSearch.is_allowed_url("http://upload.wikimedia.org/x.jpg", false), "http refused")
	assert_false(ImageSearch.is_allowed_url("file:///C:/Windows/system32", false), "file refused")
	assert_false(ImageSearch.is_allowed_url("https://localhost/x.jpg", false), "localhost refused")
	assert_false(ImageSearch.is_allowed_url("https://127.0.0.1/x.jpg", false), "loopback ip refused")
	assert_false(ImageSearch.is_allowed_url("https://192.168.0.10:8080/x.jpg", true), "lan ip refused")
	assert_false(ImageSearch.is_allowed_url("https://printer.local/x.jpg", true), ".local refused")
	assert_true(ImageSearch.is_allowed_url("https://upload.wikimedia.org/wikipedia/commons/a.jpg", false), "wikimedia ok")
	assert_true(ImageSearch.is_allowed_url("https://8.8.8.8/pic.png", true), "public ip ok")
