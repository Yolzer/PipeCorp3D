class_name ItemCodes
extends RefCounted
## Item codes shared with PostgreSQL (pipecorp.items.code). One source of truth:
## if you add an item to 04_seed.sql, add it here too.

const PVC_STRAIGHT: StringName = &"pvc_straight"
const PVC_90_DEG: StringName = &"pvc_90_deg"
const PVC_TEE: StringName = &"pvc_tee"
const TEFLON_TAPE: StringName = &"teflon_tape"

const PLACEABLE: Array[StringName] = [PVC_STRAIGHT, PVC_90_DEG, PVC_TEE]


static func is_placeable(code: StringName) -> bool:
	return PLACEABLE.has(code)
