"""Minimal mock of the PipeCorp3D NestJS API (same JSON shapes) for headless Godot integration tests."""
import json, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ITEMS = {"pvc_straight": (1500, 2), "pvc_90_deg": (1200, 1), "pvc_tee": (1400, 1), "teflon_tape": (800, 1)}
TIERS = {1: ("A pie", 10, 0, 0), 2: ("Bicicleta", 20, 25000, 60), 3: ("Hatchback", 45, 90000, 200), 4: ("Furgón", 100, 250000, 500)}
STATE = {"users": {}, "log": [], "money": 50000.0, "xp": 0, "day": 1, "game_over": False, "reason": None, "tier": 1, "inventory": {},
         "tickets": [
             {"id": 101, "zone": "PRIVATE", "description": "Fuga bajo el lavaplatos", "difficulty": 1, "estimatedParts": 2, "targetSeconds": 75, "requiredXp": 0, "budget": 8700, "status": "OPEN"},
             {"id": 102, "zone": "PRIVATE", "description": "Cambio de sifón", "difficulty": 2, "estimatedParts": 3, "targetSeconds": 105, "requiredXp": 0, "budget": 16050, "status": "OPEN"},
             {"id": 103, "zone": "PUBLIC", "description": "Fuga en medidor", "difficulty": 2, "estimatedParts": 2, "targetSeconds": 105, "requiredXp": 0, "budget": 14700, "status": "OPEN"}]}

def profile(user):
    return {"playerId": "uuid-1", "username": user, "entityId": "Player_1", "money": STATE["money"], "xp": STATE["xp"],
            "reputation": 0, "vehicleTierId": STATE["tier"], "vehicleName": TIERS[STATE["tier"]][0], "inventoryCapacity": TIERS[STATE["tier"]][1], "gameDay": STATE["day"],
            "isGameOver": STATE["game_over"], "gameOverReason": STATE["reason"]}

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, code, obj):
        data = json.dumps(obj).encode(); self.send_response(code)
        self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(data)))
        self.end_headers(); self.wfile.write(data)
    def handle_any(self, method):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n).decode() if n else ""
        body = json.loads(raw) if raw else {}
        auth = self.headers.get("Authorization", "")
        path = self.path
        if path != "/__log":
            STATE["log"].append({"method": method, "path": path, "auth": auth.startswith("Bearer tok-"), "body": body})
        user = auth.replace("Bearer tok-", "") if auth.startswith("Bearer tok-") else None
        if path == "/__log": return self.send(200, {"requests": STATE["log"]})
        if path == "/auth/login":
            if body.get("username") in STATE["users"] and STATE["users"][body["username"]] == body.get("password"):
                return self.send(200, {"access_token": "tok-" + body["username"], "token_type": "Bearer", "expires_in": 7200})
            return self.send(401, {"statusCode": 401, "message": "Invalid credentials"})
        if path == "/auth/register":
            if body.get("username") in STATE["users"]: return self.send(409, {"statusCode": 409, "code": "23505", "message": "Resource already exists"})
            STATE["users"][body["username"]] = body.get("password")
            STATE.update(money=50000.0, xp=0, day=1, game_over=False, reason=None, tier=1, inventory={})
            for t in STATE["tickets"]: t["status"] = "OPEN"
            return self.send(201, profile(body["username"]))
        if user is None: return self.send(401, {"statusCode": 401, "message": "Missing bearer token"})
        if STATE["game_over"] and method == "POST": return self.send(409, {"statusCode": 409, "code": "PC001", "message": "Game Over (SISS_TAMPERING): action rejected"})
        if path == "/profile": return self.send(200, profile(user))
        if path == "/tickets":
            return self.send(200, {"tickets": [dict(t, expiresAtUnix=int(time.time()) + 300) for t in STATE["tickets"] if t["status"] in ("OPEN", "ACCEPTED")]})
        parts = path.strip("/").split("/")
        if parts[0] == "tickets" and parts[2] == "accept":
            t = next(t for t in STATE["tickets"] if t["id"] == int(parts[1])); t["status"] = "ACCEPTED"; STATE["money"] -= 4800
            return self.send(200, {"ticket": dict(t, expiresAtUnix=0), "profile": profile(user)})
        if parts[0] == "jobs":
            t = next(t for t in STATE["tickets"] if t["id"] == int(parts[1])); t["status"] = "COMPLETED"
            STATE["money"] += 10875; STATE["xp"] += 25
            return self.send(200, {"result": {"ticketId": t["id"], "grade": "A", "payout": 10875, "xpGained": 25}, "profile": profile(user)})
        if parts[0] == "tickets" and parts[2] == "tampering":
            STATE["game_over"] = True; STATE["reason"] = "SISS_TAMPERING"; STATE["money"] -= 30000
            return self.send(200, {"profile": profile(user)})
        if path == "/__grant_xp":   # test helper only
            STATE["xp"] += int(body.get("xp", 0)); return self.send(200, {"profile": profile(user)})
        if path == "/inventory" and method == "GET":
            return self.send(200, {"items": [{"itemCode": c, "quantity": q} for c, q in STATE["inventory"].items() if q > 0]})
        if path == "/inventory/purchase":
            code, qty = body.get("itemCode"), int(body.get("quantity", 0))
            if code not in ITEMS: return self.send(404, {"statusCode": 404, "code": "PC002", "message": "Item not found"})
            cost = ITEMS[code][0] * qty
            if STATE["money"] < cost: return self.send(422, {"statusCode": 422, "code": "PC004", "message": "Insufficient funds"})
            used = sum(q * ITEMS[c][1] for c, q in STATE["inventory"].items())
            if used + qty * ITEMS[code][1] > TIERS[STATE["tier"]][1]:
                return self.send(422, {"statusCode": 422, "code": "PC005", "message": "Inventory capacity exceeded"})
            STATE["money"] -= cost; STATE["inventory"][code] = STATE["inventory"].get(code, 0) + qty
            return self.send(200, {"inventory": {"itemCode": code, "quantity": STATE["inventory"][code]}, "profile": profile(user)})
        if path == "/vehicles/upgrade":
            tier = int(body.get("tierId", 0))
            if tier <= STATE["tier"]: return self.send(409, {"statusCode": 409, "code": "PC003", "message": "Not an upgrade"})
            if STATE["xp"] < TIERS[tier][3]: return self.send(403, {"statusCode": 403, "code": "PC006", "message": "Requires XP"})
            if STATE["money"] < TIERS[tier][2]: return self.send(422, {"statusCode": 422, "code": "PC004", "message": "Insufficient funds"})
            STATE["money"] -= TIERS[tier][2]; STATE["tier"] = tier
            return self.send(200, {"profile": profile(user)})
        if path == "/day/end":
            STATE["day"] += 1; STATE["money"] -= 8000; return self.send(200, {"profile": profile(user)})
        return self.send(404, {"statusCode": 404, "message": "not found"})
    def do_GET(self): self.handle_any("GET")
    def do_POST(self): self.handle_any("POST")

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 3999
print(f"PipeCorp3D MOCK API listening on http://127.0.0.1:{PORT}  (Ctrl+C to stop)")
ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
