class_name SissZone
extends Area3D
## Public water network (red zone / public meter). Collision layer 4 (SISSZone).
## Clicking it with the wrench is ILLEGAL: PlumberEntity emits intent_touch_public_network,
## ApiClient calls POST /tickets/:id/tampering and PostgreSQL applies the fine
## (2 strikes = Game Over). The legal path is "Derivar SISS" on the phone.
##
## Rookie-proof: if the node has no children, it builds its own collision box,
## red translucent mesh and warning label at runtime. Just add an Area3D + this script.

const SISS_LAYER_BIT: int = 1 << 3   # layer 4 "SISSZone"

@export var ticket_id: int = 0                    ## 0 = fine the first OPEN public ticket
@export var zone_size: Vector3 = Vector3(1.5, 1.2, 1.5)
@export var warning_text: String = "RED PÚBLICA — SISS\nNO INTERVENIR\nDeriva el problema desde el teléfono [T]"


func _ready() -> void:
	collision_layer = SISS_LAYER_BIT
	collision_mask = 0
	monitoring = false
	if get_node_or_null(^"CollisionShape3D") == null:
		_build_collision()
	if get_node_or_null(^"RedMesh") == null:
		_build_mesh()
	if get_node_or_null(^"WarningLabel") == null:
		_build_label()


func _build_collision() -> void:
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box: BoxShape3D = BoxShape3D.new()
	box.size = zone_size
	shape.shape = box
	add_child(shape)


func _build_mesh() -> void:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.9, 0.08, 0.08, 0.45)
	material.emission_enabled = true
	material.emission = Color(0.7, 0.0, 0.0)
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = zone_size
	mesh.material = material
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = "RedMesh"
	instance.mesh = mesh
	add_child(instance)


func _build_label() -> void:
	var label: Label3D = Label3D.new()
	label.name = "WarningLabel"
	label.text = warning_text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.modulate = Color(1.0, 0.85, 0.85)
	label.outline_size = 8
	label.position = Vector3(0.0, zone_size.y * 0.5 + 0.6, 0.0)
	add_child(label)
