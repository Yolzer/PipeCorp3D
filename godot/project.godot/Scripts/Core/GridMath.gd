class_name GridMath
extends RefCounted
## Pure, stateless grid math. Deterministic: the same world position always
## maps to the same integer cell on every machine (safe to send over a network

const CELL_SIZE: float = 1.0


static func world_to_cell(world_position: Vector3) -> Vector3i:
	return Vector3i(
		roundi(world_position.x / CELL_SIZE),
		roundi(world_position.y / CELL_SIZE),
		roundi(world_position.z / CELL_SIZE)
	)


static func cell_to_world(cell: Vector3i) -> Vector3:
	return Vector3(cell) * CELL_SIZE
