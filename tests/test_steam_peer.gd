extends TestCase


func test_peer_id_is_positive_and_not_reserved() -> void:
	for sid in [76561198119601147, 76561197960265728, 76561197960265729, 1, 0, 0x80000000]:
		var id := SteamPeer.peer_id_for(sid)
		assert_true(id > 1, "peer id for %d is > 1 (%d)" % [sid, id])
		assert_true(id <= 0x7FFFFFFF, "fits int32")


func test_data_roundtrip() -> void:
	var payload := PackedByteArray([9, 8, 7, 6, 5])
	var bytes := SteamPeer.encode_data(3, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, payload)
	var d := SteamPeer.decode_data(bytes)
	assert_eq(d.channel, 3)
	assert_eq(d.mode, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE)
	assert_eq(d.data, payload)


func test_ctrl_roundtrip() -> void:
	var bytes := SteamPeer.encode_ctrl(SteamPeer.CTRL_WELCOME, 123456789)
	var c := SteamPeer.decode_ctrl(bytes)
	assert_eq(c.type, SteamPeer.CTRL_WELCOME)
	assert_eq(c.peer_id, 123456789)


func test_malformed_packets_rejected() -> void:
	assert_true(SteamPeer.decode_data(PackedByteArray([1])).is_empty())
	assert_true(SteamPeer.decode_ctrl(PackedByteArray([1, 2, 3])).is_empty())


func test_connect_lobby_arg_parsing() -> void:
	assert_eq(SteamService.connect_lobby_from_args(), 0, "no +connect_lobby in tests")
