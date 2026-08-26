## 中文/英文房间码：IP:端口 <-> 字符码
## IPv4（局域网）：base58（去 0 O I l）英文数字码 10 位
## IPv6（跨网）：4096 常用汉字码 13 字（IPv6 地址 128bit 信息量决定）
## 载荷格式（大端）：1 字节 版本/类型 + 地址字节 + 2 字节端口，转 base-N 编码
class_name RoomCode
extends RefCounted

const ALPHABET_START := 0x4E00  # CJK 常用区起点（思源黑体覆盖）
const ALPHABET_SIZE := 4096     # 12 bit / 字

const IPV4_ALPHABET := "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
const IPV4_LEN := 10
const IPV6_LEN := 13

const TYPE_IPV4 := 0x10  # 高 nibble = 版本 1，低 nibble = 类型 0
const TYPE_IPV6 := 0x11

## 编码 IPv4 地址 + 端口（英文数字码）。地址无效返回空串
static func encode_ipv4(ip: String, port: int) -> String:
	var addr := _parse_ipv4(ip)
	if addr.is_empty():
		return ""
	var payload := PackedByteArray([TYPE_IPV4])
	payload.append_array(addr)
	payload.append((port >> 8) & 0xFF)
	payload.append(port & 0xFF)
	return _encode_with(payload, IPV4_ALPHABET.length(), IPV4_LEN)

## 编码 IPv6 地址 + 端口（中文码）。地址无效返回空串
static func encode_ipv6(ip: String, port: int) -> String:
	var addr := _parse_ipv6(ip)
	if addr.is_empty():
		return ""
	var payload := PackedByteArray([TYPE_IPV6])
	payload.append_array(addr)
	payload.append((port >> 8) & 0xFF)
	payload.append(port & 0xFF)
	return _encode_with(payload, ALPHABET_SIZE, IPV6_LEN)

## 解码房间码 → {"ip": String, "port": int}；无效返回 {}
## 按首字符自动区分：CJK 走中文 IPv6，ASCII 走英文数字 IPv4
static func decode(code: String) -> Dictionary:
	var s := code.strip_edges()
	if s.is_empty():
		return {}
	if s.unicode_at(0) >= ALPHABET_START:
		return _decode_with(s, IPV6_LEN, ALPHABET_SIZE, TYPE_IPV6, 16)
	return _decode_with(s, IPV4_LEN, IPV4_ALPHABET.length(), TYPE_IPV4, 4)

static func _decode_with(s: String, expected_len: int, base: int, type: int, addr_len: int) -> Dictionary:
	if s.length() != expected_len:
		return {}
	var digits: Array = []
	for i in s.length():
		var idx := _char_index(s, i, base)
		if idx < 0:
			return {}
		digits.append(idx)
	var bytes := _base_to_bytes(digits, base, 1 + addr_len + 2)
	if bytes.is_empty() or bytes[0] != type:
		return {}
	var port := (bytes[1 + addr_len] << 8) | bytes[2 + addr_len]
	var ip := ""
	if addr_len == 4:
		ip = "%d.%d.%d.%d" % [bytes[1], bytes[2], bytes[3], bytes[4]]
	else:
		ip = _format_ipv6(bytes.slice(1, 17))
	return {"ip": ip, "port": port}

static func _encode_with(payload: PackedByteArray, base: int, min_len: int) -> String:
	var digits := _bytes_to_base(payload, base, min_len)
	var out := ""
	for d in digits:
		out += _char_at(d, base)
	return out

static func _char_at(d: int, base: int) -> String:
	if base == ALPHABET_SIZE:
		return String.chr(ALPHABET_START + d)
	return IPV4_ALPHABET[d]

static func _char_index(s: String, i: int, base: int) -> int:
	if base == ALPHABET_SIZE:
		var v := s.unicode_at(i) - ALPHABET_START
		return v if (v >= 0 and v < ALPHABET_SIZE) else -1
	return IPV4_ALPHABET.find(s[i])

## 大端字节数组 → base-N 数字（最高位在前，补前导零到 min_len）
static func _bytes_to_base(bytes: PackedByteArray, base: int, min_len: int) -> Array:
	var num: Array = []
	for b in bytes:
		num.append(b)
	var digits: Array = []
	while true:
		var nonzero := false
		for v in num:
			if v != 0:
				nonzero = true
				break
		if not nonzero:
			break
		var rem: int = 0
		for i in num.size():
			var cur: int = rem * 256 + int(num[i])
			num[i] = int(cur / base)
			rem = cur % base
		digits.append(rem)
	digits.reverse()
	while digits.size() < min_len:
		digits.push_front(0)
	return digits

## base-N 数字（最高位在前）→ 大端字节数组（补前导零到 out_len）
static func _base_to_bytes(digits: Array, base: int, out_len: int) -> PackedByteArray:
	var num: Array = []
	for d in digits:
		var carry: int = int(d)
		for i in range(num.size() - 1, -1, -1):
			var cur: int = int(num[i]) * base + carry
			num[i] = cur % 256
			carry = int(cur / 256)
		while carry > 0:
			num.push_front(carry % 256)
			carry = int(carry / 256)
	if num.size() > out_len:
		return PackedByteArray()
	var out := PackedByteArray()
	out.resize(out_len)
	var offset := out_len - num.size()
	for i in num.size():
		out[offset + i] = int(num[i])
	return out

static func _parse_ipv4(ip: String) -> PackedByteArray:
	var parts := ip.split(".")
	if parts.size() != 4:
		return PackedByteArray()
	var out := PackedByteArray()
	for p in parts:
		if not p.is_valid_int():
			return PackedByteArray()
		var v := p.to_int()
		if v < 0 or v > 255:
			return PackedByteArray()
		out.append(v)
	return out

static func _parse_ipv6(ip: String) -> PackedByteArray:
	var s := ip
	var zone := s.find("%")
	if zone != -1:
		s = s.substr(0, zone)
	if s.contains("::"):
		var idx := s.find("::")
		var head_str := s.substr(0, idx)
		var tail_str := s.substr(idx + 2)
		var head: Array = []
		var tail: Array = []
		if not head_str.is_empty():
			head = _ipv6_groups(head_str)
		if not tail_str.is_empty():
			tail = _ipv6_groups(tail_str)
		var missing := 8 - head.size() - tail.size()
		if missing < 0:
			return PackedByteArray()
		var groups: Array = head.duplicate()
		for i in missing:
			groups.append(0)
		groups.append_array(tail)
		return _groups_to_bytes(groups)
	else:
		var groups := _ipv6_groups(s)
		if groups.size() != 8:
			return PackedByteArray()
		return _groups_to_bytes(groups)

static func _ipv6_groups(s: String) -> Array:
	var out: Array = []
	for g in s.split(":"):
		if g.is_empty() or not g.is_valid_hex_number(false):
			return []
		out.append(g.hex_to_int())
	return out

static func _groups_to_bytes(groups: Array) -> PackedByteArray:
	if groups.size() != 8:
		return PackedByteArray()
	var out := PackedByteArray()
	for g in groups:
		out.append((g >> 8) & 0xFF)
		out.append(g & 0xFF)
	return out

static func _format_ipv6(bytes: PackedByteArray) -> String:
	var out := ""
	for i in 8:
		if i > 0:
			out += ":"
		out += "%04x" % ((bytes[i * 2] << 8) | bytes[i * 2 + 1])
	return out
