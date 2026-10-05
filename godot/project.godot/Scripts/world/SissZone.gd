class_name SissZone
extends Area3D
## Public water network (red zone). Collision layer 4 (SISSZone).
## Touching it is illegal: PlumberEntity emits intent_touch_public_network,
## which (Sprint 2) calls POST /siss/tampering -> sp_report_public_tampering.

@export var ticket_id: int = 0
