extends RefCounted
## Frozen Rust sim_core::agents::facility::facility_offset_position.
## Original hash is std::collections::hash_map::DefaultHasher::new(),
## i.e. SipHash-1-3 with key (0,0) of Rust Hash for str: UTF-8 followed
## by the prefix-free 0xff sentinel, then unsigned hash % 360.
## This is DIFFERENT from N43 facility_orbit_initial_angle(location)'s
## FNV hash and MUST NOT be silently substituted by FNV or by UI pixels.
const FACILITY_ORBIT_RADIUS: float = 0.55

static func _rot(value: int, amount: int) -> int:
    # GDScript integers are signed 64-bit. Mask the arithmetic
    # right-shift's sign-extension so this is true u64 rotate-left.
    return (value << amount) | ((value >> (64 - amount)) & (
        (1 << amount) - 1))

static func _round(v: Array) -> void:
    v[0] = int(v[0]) + int(v[1])
    v[1] = _rot(int(v[1]), 13) ^ int(v[0])
    v[0] = _rot(int(v[0]), 32)
    v[2] = int(v[2]) + int(v[3])
    v[3] = _rot(int(v[3]), 16) ^ int(v[2])
    v[0] = int(v[0]) + int(v[3])
    v[3] = _rot(int(v[3]), 21) ^ int(v[0])
    v[2] = int(v[2]) + int(v[1])
    v[1] = _rot(int(v[1]), 17) ^ int(v[2])
    v[2] = _rot(int(v[2]), 32)

static func _siphash13_string(agent_id: String) -> int:
    var bytes: PackedByteArray = agent_id.to_utf8_buffer()
    bytes.append(255) # Rust Hash for str's required terminator.
    var v: Array = [
        0x736f6d6570736575, 0x646f72616e646f6d,
        0x6c7967656e657261, 0x7465646279746573
    ]
    var complete: int = int(bytes.size() / 8)
    for chunk in range(complete):
        var message: int = 0
        for i in range(8):
            message |= int(bytes[chunk * 8 + i]) << (8 * i)
        v[3] = int(v[3]) ^ message
        _round(v)
        v[0] = int(v[0]) ^ message
    var final_word: int = (bytes.size() & 255) << 56
    for j in range(bytes.size() - complete * 8):
        final_word |= int(bytes[complete * 8 + j]) << (8 * j)
    v[3] = int(v[3]) ^ final_word
    _round(v)
    v[0] = int(v[0]) ^ final_word
    v[2] = int(v[2]) ^ 255
    for _i in range(3):
        _round(v)
    return int(v[0]) ^ int(v[1]) ^ int(v[2]) ^ int(v[3])

static func facility_angle(agent_id: String) -> int:
    if agent_id.is_empty():
        return -1
    var signed_hash: int = _siphash13_string(agent_id)
    # Hash values >=2^63 are negative as signed Godot integers.
    # Reduce the original UNSIGNED u64 modulo 360, with 2^32 %360=256.
    var low: int = signed_hash & 0xffffffff
    var high: int = (signed_hash >> 32) & 0xffffffff
    return int(((high % 360) * 256 + (low % 360)) % 360)

static func position(body_center: Vector2, agent_id: String) -> Array:
    if agent_id.is_empty() or not is_finite(body_center.x) or not is_finite(
            body_center.y):
        return []
    var angle: int = facility_angle(agent_id)
    if angle < 0:
        return []
    var theta: float = deg_to_rad(float(angle))
    # Rust BodyOrbit gives the source body universe_position; its
    # facility_offset_position applies a fixed per-agent-id 0.55 orbit.
    return [body_center.x + FACILITY_ORBIT_RADIUS * cos(theta),
        body_center.y + FACILITY_ORBIT_RADIUS * sin(theta)]
