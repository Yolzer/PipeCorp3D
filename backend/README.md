# PipeCorp3D API (NestJS)

## Setup (once)
```bash
cd backend
npm install
npm run keys                 # creates keys/private.pem + keys/public.pem (RS256)
cp .env.example .env         # then edit DB_PASSWORD
```
The database must already be built with `database/01..04_*.sql`.

## Run
```bash
npm run start:dev            # http://localhost:3000/health
```

## Definition of Done
```bash
npm run dod                  # typecheck (strict) + unit tests + e2e tests
```

## Endpoints
| Method | Path | Auth | Description |
|---|---|---|---|
| GET  | /health         | -      | API + DB pool alive |
| POST | /auth/register  | -      | `{username, password}` → profile (calls `sp_register_player`) |
| POST | /auth/login     | -      | `{username, password}` → RS256 access token |
| GET  | /profile        | Bearer | Authoritative game state for the logged-in player |
| GET  | /tickets        | Bearer | Expires stale tickets, tops the board up to 3 (2 private + 1 public pattern) |
| POST | /tickets/:id/accept | Bearer | Accept + auto-buy missing materials (one transaction) |
| POST | /tickets/:id/derive | Bearer | SISS triage on a PUBLIC ticket (+reputation, +bonus) |
| POST | /tickets/:id/tampering | Bearer | Player touched the public network (fine; 2 strikes = Game Over) |
| POST | /jobs/:ticketId/complete | Bearer | `{itemCode, timeSeconds, partsUsed, partsWasted}` → grade S..F + payout |
| GET  | /inventory      | Bearer | Items carried |
| POST | /inventory/purchase | Bearer | `{itemCode, quantity}` (vehicle capacity enforced) |
| POST | /vehicles/upgrade | Bearer | `{tierId}` (XP + money required) |
| POST | /day/end        | Bearer | Daily upkeep (bankruptcy → Game Over) |

## Error contract
Business errors from PostgreSQL come back as `{ statusCode, code, message }`:
PC001 409 Game Over · PC002 404 · PC003 409 · PC004 422 funds · PC005 422 capacity · PC006 403 XP · 23505 409 duplicate.
