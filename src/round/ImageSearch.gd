class_name ImageSearch
extends Node
## Finds pictures for a name. Wikipedia (no key) first; optional Google Custom Search;
## direct URL fetch with an SSRF guard. Everything runs on the writer's own machine.

const USER_AGENT := "WhoAmIParty/0.1 (+https://github.com/Smoke8832/WhoAmISteam)"
const TIMEOUT_S := 10.0
const MAX_DOWNLOAD := 8 * 1024 * 1024
const MAX_REDIRECTS := 3
const WIKI_LANGS := ["en", "de", "tr", "fr", "es", "it", "nl", "pt"]

signal candidates_ready(results: Array)


## -> [{title, description, thumb_url}]
func search(query: String, lang: String = "en") -> Array:
	var q := query.strip_edges()
	if q.length() < 2:
		return []
	if not (lang in WIKI_LANGS):
		lang = "en"
	var url := "https://%s.wikipedia.org/w/api.php?action=opensearch&search=%s&limit=5&namespace=0&format=json" % [lang, q.uri_encode()]
	var res := await _http_get(url, ["Accept: application/json"])
	if res.is_empty():
		return []
	var parsed = JSON.parse_string(res.get_string_from_utf8())
	if typeof(parsed) != TYPE_ARRAY or parsed.size() < 2 or typeof(parsed[1]) != TYPE_ARRAY:
		return []
	var titles: Array = parsed[1]
	var results: Array = []
	for title in titles:
		var summary := await _summary(String(title), lang)
		if not summary.is_empty():
			results.append(summary)
	return results


func _summary(title: String, lang: String) -> Dictionary:
	var url := "https://%s.wikipedia.org/api/rest_v1/page/summary/%s" % [lang, title.replace(" ", "_").uri_encode()]
	var res := await _http_get(url, ["Accept: application/json"])
	if res.is_empty():
		return {}
	var parsed = JSON.parse_string(res.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var out := {
		"title": String(parsed.get("title", title)),
		"description": String(parsed.get("description", "")),
		"thumb_url": "",
	}
	var thumb: Dictionary = parsed.get("thumbnail", {})
	var original: Dictionary = parsed.get("originalimage", {})
	var src := String(thumb.get("source", ""))
	if src != "":
		# Ask for a larger thumbnail: .../320px-Name.jpg -> .../600px-Name.jpg
		var re := RegEx.new()
		re.compile("/(\\d+)px-")
		var m := re.search(src)
		if m and int(m.get_string(1)) < 600:
			src = src.replace("/%spx-" % m.get_string(1), "/600px-")
	elif original.has("source"):
		src = String(original.source)
	out.thumb_url = src
	return out


## Optional Google Custom Search (player's own key). -> same shape as search().
func search_google(query: String) -> Array:
	var key := String(Settings.get_value("google_api_key", ""))
	var cx := String(Settings.get_value("google_cx", ""))
	if key == "" or cx == "":
		return []
	var url := "https://www.googleapis.com/customsearch/v1?key=%s&cx=%s&searchType=image&num=5&q=%s" % [key.uri_encode(), cx.uri_encode(), query.uri_encode()]
	var res := await _http_get(url, ["Accept: application/json"])
	if res.is_empty():
		return []
	var parsed = JSON.parse_string(res.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	var out: Array = []
	for item in parsed.get("items", []):
		out.append({"title": String(item.get("title", query)), "description": String(item.get("displayLink", "")), "thumb_url": String(item.get("link", ""))})
	return out


## Download a picture from a Wikimedia/Google result URL.
func fetch_image(url: String) -> PackedByteArray:
	if not is_allowed_url(url, false):
		return PackedByteArray()
	return await _http_get(url, ["Accept: image/*"], true)


## Download a picture from a URL the player pasted (stricter: SSRF guard).
func fetch_user_url(url: String) -> PackedByteArray:
	if not is_allowed_url(url, true):
		return PackedByteArray()
	return await _http_get(url, ["Accept: image/*"], true)


# ------------------------------------------------------------------ guards

static func is_allowed_url(url: String, user_supplied: bool) -> bool:
	if not url.begins_with("https://"):
		return false
	var rest := url.substr(8)
	var host := rest.split("/")[0].split("?")[0]
	if ":" in host and not host.begins_with("["):
		host = host.split(":")[0]
	host = host.to_lower().strip_edges()
	if host == "" or host == "localhost" or host.ends_with(".local") or host.ends_with(".internal"):
		return false
	if host.is_valid_ip_address():
		return not is_private_ip(host)
	if user_supplied:
		# Resolve and refuse private ranges (blocking, but only on an explicit user action).
		var ip := IP.resolve_hostname(host, IP.TYPE_ANY)
		if ip == "" or is_private_ip(ip):
			return false
	return true


static func is_private_ip(ip: String) -> bool:
	var s := ip.to_lower()
	if ":" in s:
		# IPv6: loopback, link-local fe80::/10, unique local fc00::/7, v4-mapped
		if s == "::1" or s == "::" or s.begins_with("fe8") or s.begins_with("fe9") or s.begins_with("fea") or s.begins_with("feb") or s.begins_with("fc") or s.begins_with("fd"):
			return true
		if s.begins_with("::ffff:"):
			return is_private_ip(s.substr(7))
		return false
	var parts := s.split(".")
	if parts.size() != 4:
		return true
	var a := int(parts[0])
	var b := int(parts[1])
	if a == 10 or a == 127 or a == 0:
		return true
	if a == 172 and b >= 16 and b <= 31:
		return true
	if a == 192 and b == 168:
		return true
	if a == 169 and b == 254:
		return true
	if a == 100 and b >= 64 and b <= 127:
		return true
	if a >= 224:
		return true
	return false


# ------------------------------------------------------------------- http

func _http_get(url: String, headers: Array, binary: bool = false) -> PackedByteArray:
	var req := HTTPRequest.new()
	req.timeout = TIMEOUT_S
	req.max_redirects = MAX_REDIRECTS
	req.body_size_limit = MAX_DOWNLOAD
	req.use_threads = true
	add_child(req)
	var all_headers := PackedStringArray(["User-Agent: " + USER_AGENT])
	for h in headers:
		all_headers.append(String(h))
	var err := req.request(url, all_headers)
	if err != OK:
		req.queue_free()
		return PackedByteArray()
	var result: Array = await req.request_completed
	req.queue_free()
	var status: int = result[0]
	var code: int = result[1]
	var resp_headers: PackedStringArray = result[2]
	var body: PackedByteArray = result[3]
	if status != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		return PackedByteArray()
	if binary:
		var ok_type := false
		for h in resp_headers:
			var hl := String(h).to_lower()
			if hl.begins_with("content-type:") and "image/" in hl:
				ok_type = true
		if not ok_type and ImageNormalize.detect_format(body) == "":
			return PackedByteArray()
	return body
