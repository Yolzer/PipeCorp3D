extends Node3D
## DoD for the SISS red zone: both the bare-script zone and SissZone.tscn are clickable on layer 4
var _touches: Array[int] = []
var _passed: int = 0
var _failed: int = 0

func _check(c: bool, label: String) -> void:
	if c:
		_passed += 1
		print("PASS [%s]" % label)
	else:
		_failed += 1
		printerr("FAIL [%s]" % label)

func _make_entity(pos: Vector3) -> PlumberEntity:
	var e: PlumberEntity = PlumberEntity.new()
	var cam: Camera3D = Camera3D.new()
	cam.name = "Camera3D"
	var ray: RayCast3D = RayCast3D.new()
	ray.name = "RayCast3D"
	ray.target_position = Vector3(0.0, 0.0, -3.0)
	ray.collide_with_areas = true
	ray.collision_mask = 1 | 4 | 8
	cam.add_child(ray)
	e.add_child(cam)
	e.position = pos
	add_child(e)
	return e

func _ready() -> void:
	ApiClient.base_url = "http://127.0.0.1:9"
	SignalBus.intent_touch_public_network.connect(func(_p: StringName, t: int) -> void: _touches.append(t))
	var bare: SissZone = SissZone.new()
	bare.ticket_id = 11
	bare.position = Vector3(0.0, 0.0, -2.0)
	add_child(bare)
	var packed: PackedScene = load("res://scenes/SissZone.tscn") as PackedScene
	var from_scene: SissZone = packed.instantiate() as SissZone
	from_scene.ticket_id = 22
	from_scene.position = Vector3(40.0, 0.0, -2.0)
	add_child(from_scene)
	_check(bare.collision_layer == 8 and bare.get_node_or_null(^"RedMesh") != null and bare.get_node_or_null(^"CollisionShape3D") != null,
		"Z01 bare Area3D + script builds collision, red mesh and label on layer 4")
	_check(from_scene.get_node_or_null(^"WarningLabel") != null and from_scene.get_child_count() == 3, "Z02 SissZone.tscn loads without duplicating children")
	var e1: PlumberEntity = _make_entity(Vector3.ZERO)
	var e2: PlumberEntity = _make_entity(Vector3(40.0, 0.0, 0.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	e1.request_interact()
	e2.request_interact()
	_check(_touches == [11, 22], "Z03 clicking either zone emits intent_touch_public_network(ticket)")
	print("\n=== SISS ZONE: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)
