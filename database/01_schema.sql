-- =====================================================================
-- PipeCorp3D :: 01_schema.sql
-- PostgreSQL 16 | Schema, domains, enums, tables, constraints, indexes
-- Isolation target: READ COMMITTED (PostgreSQL default) + row locks
-- =====================================================================
BEGIN;
SET LOCAL client_min_messages = warning;

DROP SCHEMA IF EXISTS pipecorp CASCADE;
CREATE SCHEMA pipecorp;
SET search_path TO pipecorp;

-- ---------- Domains & enums ----------
CREATE DOMAIN money_clp AS NUMERIC(12,2);
CREATE DOMAIN grade_rank AS CHAR(1) CHECK (VALUE IN ('S','A','B','C','D','F'));

CREATE TYPE zone_type      AS ENUM ('PRIVATE', 'PUBLIC');          -- PUBLIC = red zone (SISS)
CREATE TYPE ticket_status  AS ENUM ('OPEN','ACCEPTED','COMPLETED','EXPIRED','DERIVED','FAILED');
CREATE TYPE item_category  AS ENUM ('PIPE','FITTING','SEALANT');
CREATE TYPE ledger_kind    AS ENUM ('INITIAL','JOB_PAYOUT','FINE','UPKEEP','PURCHASE',
                                    'VEHICLE_UPGRADE','DERIVATION_BONUS');
CREATE TYPE game_over_reason AS ENUM ('BANKRUPTCY','SISS_TAMPERING');

-- ---------- Global economy parameters (singleton row) ----------
CREATE TABLE economy_params (
    id                      SMALLINT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    starting_money          money_clp NOT NULL DEFAULT 50000,
    daily_upkeep            money_clp NOT NULL DEFAULT 8000,
    labor_rate_per_diff     money_clp NOT NULL DEFAULT 6000,   -- budget: labor * difficulty
    siss_fine_amount        money_clp NOT NULL DEFAULT 30000,
    siss_strikes_game_over  SMALLINT  NOT NULL DEFAULT 2 CHECK (siss_strikes_game_over > 0),
    derivation_bonus_money  money_clp NOT NULL DEFAULT 3000,
    derivation_bonus_rep    INTEGER   NOT NULL DEFAULT 10,
    xp_per_difficulty       INTEGER   NOT NULL DEFAULT 20
);

-- ---------- Auth (NestJS owns hashing; DB never sees plaintext) ----------
CREATE TABLE players (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username       VARCHAR(32)  NOT NULL UNIQUE CHECK (username ~ '^[A-Za-z0-9_]{3,32}$'),
    password_hash  VARCHAR(255) NOT NULL,            -- bcrypt/argon2 hash from API
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ---------- Logistics: vehicle progression = inventory capacity ----------
CREATE TABLE vehicle_tiers (
    id                  SMALLINT PRIMARY KEY,
    name                VARCHAR(32) NOT NULL UNIQUE,
    inventory_capacity  INTEGER     NOT NULL CHECK (inventory_capacity > 0),  -- volume units
    price               money_clp   NOT NULL CHECK (price >= 0),
    required_xp         INTEGER     NOT NULL DEFAULT 0 CHECK (required_xp >= 0)
);

-- ---------- Game state (1:1 with player; authoritative, never on disk) ----------
CREATE TABLE plumber_profiles (
    player_id         UUID PRIMARY KEY REFERENCES players(id) ON DELETE CASCADE,
    entity_id         VARCHAR(16) NOT NULL DEFAULT 'Player_1',  -- maps to Godot PlumberEntity.player_id
    money             money_clp   NOT NULL DEFAULT 0,
    xp                INTEGER     NOT NULL DEFAULT 0 CHECK (xp >= 0),
    reputation        INTEGER     NOT NULL DEFAULT 0,
    vehicle_tier_id   SMALLINT    NOT NULL DEFAULT 1 REFERENCES vehicle_tiers(id),
    game_day          INTEGER     NOT NULL DEFAULT 1 CHECK (game_day >= 1),
    is_game_over      BOOLEAN     NOT NULL DEFAULT FALSE,
    game_over_reason  game_over_reason,
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_game_over_reason
        CHECK ((is_game_over AND game_over_reason IS NOT NULL)
            OR (NOT is_game_over AND game_over_reason IS NULL))
);

-- ---------- Catalog ----------
CREATE TABLE items (
    id           SMALLINT PRIMARY KEY,
    code         VARCHAR(32) NOT NULL UNIQUE,     -- matches Godot pipe_type, e.g. 'pvc_90_deg'
    name         VARCHAR(64) NOT NULL,
    category     item_category NOT NULL,
    unit_cost    money_clp   NOT NULL CHECK (unit_cost >= 0),
    unit_volume  INTEGER     NOT NULL CHECK (unit_volume > 0)
);

-- ---------- Mobile inventory (capacity enforced by trigger) ----------
CREATE TABLE inventory (
    player_id  UUID     NOT NULL REFERENCES plumber_profiles(player_id) ON DELETE CASCADE,
    item_id    SMALLINT NOT NULL REFERENCES items(id),
    quantity   INTEGER  NOT NULL CHECK (quantity >= 0),
    PRIMARY KEY (player_id, item_id)
);

-- ---------- Living economy: tickets ----------
CREATE TABLE tickets (
    id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    player_id        UUID          NOT NULL REFERENCES plumber_profiles(player_id) ON DELETE CASCADE,
    zone             zone_type     NOT NULL,
    description      VARCHAR(200)  NOT NULL,
    difficulty       SMALLINT      NOT NULL CHECK (difficulty BETWEEN 1 AND 5),
    estimated_parts  INTEGER       NOT NULL CHECK (estimated_parts > 0),
    target_seconds   INTEGER       NOT NULL CHECK (target_seconds > 0),
    required_xp      INTEGER       NOT NULL DEFAULT 0 CHECK (required_xp >= 0),
    budget           money_clp,                                   -- set by trigger (auto-budget)
    status           ticket_status NOT NULL DEFAULT 'OPEN',
    created_at       TIMESTAMPTZ   NOT NULL DEFAULT now(),
    expires_at       TIMESTAMPTZ   NOT NULL,
    CONSTRAINT chk_expiry_after_creation CHECK (expires_at > created_at)
);
CREATE INDEX idx_tickets_player_status ON tickets (player_id, status);
CREATE INDEX idx_tickets_open_expiry   ON tickets (expires_at) WHERE status = 'OPEN';

-- ---------- Job results (one per completed ticket) ----------
CREATE TABLE jobs (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ticket_id      BIGINT     NOT NULL UNIQUE REFERENCES tickets(id),
    player_id      UUID       NOT NULL REFERENCES plumber_profiles(player_id) ON DELETE CASCADE,
    item_id        SMALLINT   NOT NULL REFERENCES items(id),
    time_seconds   INTEGER    NOT NULL CHECK (time_seconds > 0),
    parts_used     INTEGER    NOT NULL CHECK (parts_used >= 0),
    parts_wasted   INTEGER    NOT NULL CHECK (parts_wasted >= 0),
    grade          grade_rank NOT NULL,
    payout         money_clp  NOT NULL CHECK (payout >= 0),
    xp_gained      INTEGER    NOT NULL CHECK (xp_gained >= 0),
    completed_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------- SISS jurisdiction ----------
CREATE TABLE siss_infractions (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    player_id    UUID      NOT NULL REFERENCES plumber_profiles(player_id) ON DELETE CASCADE,
    ticket_id    BIGINT    NOT NULL REFERENCES tickets(id),
    fine_amount  money_clp NOT NULL CHECK (fine_amount >= 0),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_siss_player ON siss_infractions (player_id);

-- ---------- Financial ledger (append-only audit trail) ----------
CREATE TABLE ledger (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    player_id      UUID        NOT NULL REFERENCES plumber_profiles(player_id) ON DELETE CASCADE,
    kind           ledger_kind NOT NULL,
    amount         money_clp   NOT NULL,              -- signed: + income, - expense
    balance_after  money_clp,                         -- set by trigger
    ref_ticket_id  BIGINT REFERENCES tickets(id),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_ledger_player ON ledger (player_id, created_at);

COMMIT;