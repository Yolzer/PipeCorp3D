extends Node
## Shop test (v1.0.4): store + vehicle upgrade against the MOCK API.
##   Terminal 1: python godot/tests/mock_api.py   (restart it before each run)
##   Terminal 2: open res://tests/TestShop.tscn and press F6

var _passed: int = 0
var _failed: int = 0
var _profile: PlayerProfile = null
var _stock: Dictionary[StringName, int] = {}
var _purchases: int = 0
var _upgrades: Array[int] = []


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("PASS [%s]" % label)
	else:
		_failed += 1
		printerr("FAIL [%s]" % label)


func _until(condition: Callable, timeout_s: float = 6.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var done: bool = condition.call()
		if done:
			return true
		await get_tree().process_frame
	return false


func _ready() -> void:
	TestEnv.isolate()
	if not await TestEnv.mock_is_up(self):
		return
	SignalBus.profile_updated.connect(func(p: PlayerProfile) -> void: _profile = p)
	SignalBus.inventory_updated.connect(func(s: Dictionary[StringName, int]) -> void: _stock = s)
	SignalBus.purchase_succeeded.connect(func(_c: StringName, _q: int) -> void: _purchases += 1)
	SignalBus.vehicle_upgraded.connect(func(t: int) -> void: _upgrades.append(t))

	_check(ShopCatalog.ITEMS.size() == 4 and ShopCatalog.VEHICLES.size() == 4, "S01 catalog mirrors 04_seed.sql (4 items, 4 vehicles)")
	_check(ShopCatalog.clp(250000.0) == "$250.000" and ShopCatalog.clp(800.0) == "$800", "S02 CLP format with thousands separator")

	var shop: ShopMenu = ShopMenu.new()
	add_child(shop)
	await get_tree().process_frame
	shop.open_shop()
	_check(not shop.is_open(), "S03 shop stays closed before login")

	SignalBus.intent_login.emit("Player_1", "mvp_password_123")
	_check(await _until(func() -> bool: return _profile != null), "S04 login ok")
	SignalBus.intent_open_shop.emit()
	_check(shop.is_open(), "S05 intent_open_shop opens the shop")
	_check(await _until(func() -> bool: return shop.find_child("InfoLabel", true, false).text.contains("Bodega: 0 / 10")),
		"S06 header shows money, vehicle and cargo 0/10")

	var money_before: float = _profile.money
	var elbow_row: Node = shop.find_child(String(ItemCodes.PVC_90_DEG), true, false)
	(elbow_row.get_node(^"Quantity") as SpinBox).value = 3
	(elbow_row.get_node(^"BuyBtn") as Button).pressed.emit()
	_check(await _until(func() -> bool: return _stock.get(ItemCodes.PVC_90_DEG, 0) == 3), "S07 buying 3 elbows -> inventory 3")
	_check(is_equal_approx(_profile.money, money_before - 3600.0), "S08 money charged by the server (3 × $1.200)")
	_check(_purchases == 1 and shop.find_child("StatusLabel", true, false).text.contains("Compraste"), "S09 success message shown")

	var straight_row: Node = shop.find_child(String(ItemCodes.PVC_STRAIGHT), true, false)
	(straight_row.get_node(^"Quantity") as SpinBox).value = 5
	(straight_row.get_node(^"BuyBtn") as Button).pressed.emit()
	_check(await _until(func() -> bool: return shop.find_child("StatusLabel", true, false).text.contains("bodega")),
		"S10 over capacity -> PC005 shown in Spanish")

	var bike_btn: Button = shop.find_child("Tier2", true, false).get_node(^"UpgradeBtn") as Button
	_check(bike_btn.disabled and bike_btn.text.contains("Bloqueado"), "S11 bike locked without 60 XP")
	await ApiClient._request(HTTPClient.METHOD_POST, "/__grant_xp", {"xp": 60})
	shop._upgrade(4)   # bypasses the locked button on purpose: the SERVER must still refuse
	_check(await _until(func() -> bool: return shop.find_child("StatusLabel", true, false).text.contains("XP")),
		"S12 server rejects the van without XP (PC006)")
	await ApiClient._fetch_profile()
	await get_tree().process_frame
	bike_btn = shop.find_child("Tier2", true, false).get_node(^"UpgradeBtn") as Button
	_check(not bike_btn.disabled, "S13 bike unlocked at 60 XP")
	bike_btn.pressed.emit()
	_check(await _until(func() -> bool: return _upgrades.has(2) and _profile.vehicle_tier_id == 2), "S14 upgrade to Bicicleta")
	_check(await _until(func() -> bool: return shop.find_child("InfoLabel", true, false).text.contains("/ 20")),
		"S15 cargo capacity now 20")
	(shop.find_child("CloseBtn", true, false) as Button).pressed.emit()
	_check(not shop.is_open(), "S16 Cerrar closes the shop")

	print("\n=== SHOP DoD: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
