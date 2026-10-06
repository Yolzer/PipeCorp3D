class_name PlayerProfile
extends RefCounted
## Authoritative player state as returned by the API (GET /profile and every game action)

var username: String = ""
var money: float = 0.0
var xp: int = 0
var reputation: int = 0
var vehicle_tier_id: int = 1
var vehicle_name: String = ""
var inventory_capacity: int = 0
var game_day: int = 1
var is_game_over: bool = false
var game_over_reason: StringName = &""


static func from_dict(d: Dictionary) -> PlayerProfile:
	var p: PlayerProfile = PlayerProfile.new()
	p.username = JsonUtil.get_string(d, "username")
	p.money = JsonUtil.get_float(d, "money")
	p.xp = JsonUtil.get_int(d, "xp")
	p.reputation = JsonUtil.get_int(d, "reputation")
	p.vehicle_tier_id = JsonUtil.get_int(d, "vehicleTierId", 1)
	p.vehicle_name = JsonUtil.get_string(d, "vehicleName")
	p.inventory_capacity = JsonUtil.get_int(d, "inventoryCapacity")
	p.game_day = JsonUtil.get_int(d, "gameDay", 1)
	p.is_game_over = JsonUtil.get_bool(d, "isGameOver")
	p.game_over_reason = StringName(JsonUtil.get_string(d, "gameOverReason"))
	return p
