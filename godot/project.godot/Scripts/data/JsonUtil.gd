class_name JsonUtil
extends RefCounted
## Strict-typed readers for JSON dictionaries. JSON numbers arrive as float and
## null as Variant NIL; these helpers convert safely without unsafe casts


static func get_float(d: Dictionary, key: String, fallback: float = 0.0) -> float:
	var v: Variant = d.get(key, fallback)
	if v is float or v is int:
		var out: float = v
		return out
	return fallback


static func get_int(d: Dictionary, key: String, fallback: int = 0) -> int:
	var v: Variant = d.get(key, fallback)
	if v is float or v is int:
		var out: float = v
		return roundi(out)
	return fallback


static func get_string(d: Dictionary, key: String, fallback: String = "") -> String:
	var v: Variant = d.get(key, fallback)
	if v is String:
		var out: String = v
		return out
	return fallback


static func get_bool(d: Dictionary, key: String, fallback: bool = false) -> bool:
	var v: Variant = d.get(key, fallback)
	if v is bool:
		var out: bool = v
		return out
	return fallback


static func get_dict(d: Dictionary, key: String) -> Dictionary:
	var v: Variant = d.get(key, {})
	if v is Dictionary:
		var out: Dictionary = v
		return out
	return {}


static func get_array(d: Dictionary, key: String) -> Array:
	var v: Variant = d.get(key, [])
	if v is Array:
		var out: Array = v
		return out
	return []
