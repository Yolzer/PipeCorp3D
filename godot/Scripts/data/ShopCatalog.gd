class_name ShopCatalog
extends RefCounted
## Catálogo de la Tienda: espejo de database/04_seed.sql (tablas items y vehicle_tiers).
## Solo sirve para MOSTRAR precios en la interfaz: el dinero, la XP y la capacidad
## los valida PostgreSQL al comprar (sp_purchase_item, sp_upgrade_vehicle, trigger T6).
## Si cambias 04_seed.sql, actualiza también esta lista.

const ITEMS: Array[Dictionary] = [
	{"code": ItemCodes.PVC_STRAIGHT, "name": "Tubo PVC recto 1m", "category": "Tubería", "cost": 1500, "volume": 2},
	{"code": ItemCodes.PVC_90_DEG, "name": "Codo PVC 90°", "category": "Tubería", "cost": 1200, "volume": 1},
	{"code": ItemCodes.PVC_TEE, "name": "Tee PVC", "category": "Conexión", "cost": 1400, "volume": 1},
	{"code": ItemCodes.TEFLON_TAPE, "name": "Cinta teflón", "category": "Sellante", "cost": 800, "volume": 1},
]

const VEHICLES: Array[Dictionary] = [
	{"id": 1, "name": "A pie", "capacity": 10, "price": 0, "required_xp": 0},
	{"id": 2, "name": "Bicicleta", "capacity": 20, "price": 25000, "required_xp": 60},
	{"id": 3, "name": "Hatchback", "capacity": 45, "price": 90000, "required_xp": 200},
	{"id": 4, "name": "Furgón", "capacity": 100, "price": 250000, "required_xp": 500},
]


static func item(code: StringName) -> Dictionary:
	for entry: Dictionary in ITEMS:
		if entry["code"] == code:
			return entry
	return {}


static func item_name(code: StringName) -> String:
	var entry: Dictionary = item(code)
	return String(entry.get("name", String(code)))


## Volumen ocupado en el vehículo (cantidad × volumen unitario), igual que el trigger T6.
static func used_volume(stock: Dictionary[StringName, int]) -> int:
	var total: int = 0
	for code: StringName in stock:
		var entry: Dictionary = item(code)
		total += stock[code] * int(entry.get("volume", 1))
	return total


## Pesos chilenos con separador de miles: 25000 -> "$25.000".
static func clp(value: float) -> String:
	var digits: String = str(absi(roundi(value)))
	var out: String = ""
	while digits.length() > 3:
		out = "." + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-$" if value < 0.0 else "$") + digits + out
