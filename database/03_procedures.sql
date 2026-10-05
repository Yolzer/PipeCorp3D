-- =====================================================================
-- PipeCorp3D :: 03_procedures.sql
-- Business stored procedures. Implemented as PL/pgSQL FUNCTIONS so that
-- NestJS (TypeORM QueryRunner) can `SELECT * FROM sp_x(...)` and receive
-- typed rows. All run inside the caller's READ COMMITTED transaction and
-- lock the player's profile row first (per-player serialization).
-- =====================================================================
BEGIN;
SET search_path TO pipecorp;

-- ---------- Helpers ----------
CREATE OR REPLACE FUNCTION fn_lock_alive_profile(p_player UUID)
RETURNS plumber_profiles LANGUAGE plpgsql AS $$
DECLARE v plumber_profiles;
BEGIN
    SELECT * INTO v FROM plumber_profiles WHERE player_id = p_player FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Profile % not found', p_player USING ERRCODE = 'PC002';
    END IF;
    IF v.is_game_over THEN
        RAISE EXCEPTION 'Game Over (%): action rejected', v.game_over_reason USING ERRCODE = 'PC001';
    END IF;
    RETURN v;
END $$;

CREATE OR REPLACE FUNCTION fn_lock_ticket(p_player UUID, p_ticket BIGINT)
RETURNS tickets LANGUAGE plpgsql AS $$
DECLARE v tickets;
BEGIN
    SELECT * INTO v FROM tickets WHERE id = p_ticket AND player_id = p_player FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Ticket % not found for player', p_ticket USING ERRCODE = 'PC002';
    END IF;
    RETURN v;
END $$;

-- Grade S..F from two variables only (time, wasted parts) — per MVP doc
CREATE OR REPLACE FUNCTION fn_calc_grade(p_time INTEGER, p_target INTEGER,
                                         p_wasted INTEGER, p_estimated INTEGER)
RETURNS grade_rank LANGUAGE sql IMMUTABLE STRICT AS $$
    WITH s AS (
        SELECT 100
             - LEAST(60, GREATEST(0, (p_time::numeric / p_target - 1) * 50))
             - LEAST(60, p_wasted::numeric / GREATEST(p_estimated, 1) * 100)
          AS score
    )
    SELECT (CASE WHEN score >= 95 THEN 'S' WHEN score >= 85 THEN 'A'
                 WHEN score >= 70 THEN 'B' WHEN score >= 55 THEN 'C'
                 WHEN score >= 40 THEN 'D' ELSE 'F' END)::grade_rank
      FROM s;
$$;

CREATE OR REPLACE FUNCTION fn_grade_multiplier(p_grade grade_rank)
RETURNS NUMERIC LANGUAGE sql IMMUTABLE STRICT AS $$
    SELECT CASE p_grade WHEN 'S' THEN 1.50 WHEN 'A' THEN 1.25 WHEN 'B' THEN 1.00
                        WHEN 'C' THEN 0.80 WHEN 'D' THEN 0.50 ELSE 0.00 END;
$$;

-- ---------- Registration (called by NestJS after hashing password) ----------
CREATE OR REPLACE FUNCTION sp_register_player(p_username VARCHAR, p_password_hash VARCHAR)
RETURNS plumber_profiles LANGUAGE plpgsql AS $$
DECLARE
    v_id UUID;
    v_start money_clp;
    v plumber_profiles;
BEGIN
    INSERT INTO players (username, password_hash) VALUES (p_username, p_password_hash)
    RETURNING id INTO v_id;
    INSERT INTO plumber_profiles (player_id) VALUES (v_id);
    SELECT starting_money INTO v_start FROM economy_params WHERE id = 1;
    INSERT INTO ledger (player_id, kind, amount) VALUES (v_id, 'INITIAL', v_start);
    SELECT * INTO v FROM plumber_profiles WHERE player_id = v_id;
    RETURN v;
END $$;

-- ---------- Tickets ----------
CREATE OR REPLACE FUNCTION sp_generate_ticket(p_player UUID, p_zone zone_type, p_description VARCHAR,
        p_difficulty SMALLINT, p_estimated_parts INTEGER, p_target_seconds INTEGER,
        p_ttl_seconds INTEGER, p_required_xp INTEGER DEFAULT 0)
RETURNS tickets LANGUAGE plpgsql AS $$
DECLARE v tickets;
BEGIN
    PERFORM fn_lock_alive_profile(p_player);
    INSERT INTO tickets (player_id, zone, description, difficulty, estimated_parts,
                         target_seconds, required_xp, expires_at)
    VALUES (p_player, p_zone, p_description, p_difficulty, p_estimated_parts,
            p_target_seconds, p_required_xp, now() + make_interval(secs => p_ttl_seconds))
    RETURNING * INTO v;
    RETURN v;
END $$;

-- Lazy expiry: called on GET /tickets ("the competition took the job")
CREATE OR REPLACE FUNCTION sp_expire_tickets(p_player UUID)
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE v_count INTEGER;
BEGIN
    UPDATE tickets SET status = 'EXPIRED'
     WHERE player_id = p_player AND status = 'OPEN' AND expires_at <= now();
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END $$;

CREATE OR REPLACE FUNCTION sp_accept_ticket(p_player UUID, p_ticket BIGINT)
RETURNS tickets LANGUAGE plpgsql AS $$
DECLARE
    p plumber_profiles;
    t tickets;
BEGIN
    p := fn_lock_alive_profile(p_player);
    t := fn_lock_ticket(p_player, p_ticket);

    IF t.status = 'OPEN' AND t.expires_at <= now() THEN
        UPDATE tickets SET status = 'EXPIRED' WHERE id = t.id;
        RAISE EXCEPTION 'Ticket % expired', t.id USING ERRCODE = 'PC003';
    END IF;
    IF p.xp < t.required_xp THEN
        RAISE EXCEPTION 'Requires % XP (has %)', t.required_xp, p.xp USING ERRCODE = 'PC006';
    END IF;

    UPDATE tickets SET status = 'ACCEPTED' WHERE id = t.id RETURNING * INTO t;  -- FSM trigger validates
    RETURN t;
END $$;

-- ---------- Core loop close: job completion, grading, payout ----------
CREATE OR REPLACE FUNCTION sp_complete_job(p_player UUID, p_ticket BIGINT, p_item_code VARCHAR,
        p_time_seconds INTEGER, p_parts_used INTEGER, p_parts_wasted INTEGER)
RETURNS jobs LANGUAGE plpgsql AS $$
DECLARE
    t        tickets;
    v_item   SMALLINT;
    v_stock  INTEGER;
    v_need   INTEGER := p_parts_used + p_parts_wasted;
    v_grade  grade_rank;
    v_payout money_clp;
    v_xp     INTEGER;
    v_xp_rate INTEGER;
    j        jobs;
BEGIN
    PERFORM fn_lock_alive_profile(p_player);
    t := fn_lock_ticket(p_player, p_ticket);

    IF t.status <> 'ACCEPTED' THEN
        RAISE EXCEPTION 'Ticket % must be ACCEPTED (is %)', t.id, t.status USING ERRCODE = 'PC003';
    END IF;

    SELECT id INTO v_item FROM items WHERE code = p_item_code;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Item % not found', p_item_code USING ERRCODE = 'PC002';
    END IF;

    SELECT quantity INTO v_stock FROM inventory
     WHERE player_id = p_player AND item_id = v_item FOR UPDATE;
    IF COALESCE(v_stock, 0) < v_need THEN
        RAISE EXCEPTION 'Insufficient stock of %: need %, have %', p_item_code, v_need, COALESCE(v_stock,0)
            USING ERRCODE = 'PC003';
    END IF;
    UPDATE inventory SET quantity = quantity - v_need
     WHERE player_id = p_player AND item_id = v_item;

    v_grade  := fn_calc_grade(p_time_seconds, t.target_seconds, p_parts_wasted, t.estimated_parts);
    v_payout := ROUND(t.budget * fn_grade_multiplier(v_grade), 2);
    SELECT xp_per_difficulty INTO v_xp_rate FROM economy_params WHERE id = 1;
    v_xp     := FLOOR(v_xp_rate * t.difficulty * GREATEST(fn_grade_multiplier(v_grade), 0.25));

    INSERT INTO jobs (ticket_id, player_id, item_id, time_seconds, parts_used, parts_wasted,
                      grade, payout, xp_gained)
    VALUES (t.id, p_player, v_item, p_time_seconds, p_parts_used, p_parts_wasted,
            v_grade, v_payout, v_xp)
    RETURNING * INTO j;

    UPDATE tickets SET status = 'COMPLETED' WHERE id = t.id;   -- FSM blocks PUBLIC zones
    UPDATE plumber_profiles SET xp = xp + v_xp WHERE player_id = p_player;
    IF v_payout > 0 THEN
        INSERT INTO ledger (player_id, kind, amount, ref_ticket_id)
        VALUES (p_player, 'JOB_PAYOUT', v_payout, t.id);
    END IF;
    RETURN j;
END $$;

-- ---------- SISS: triage (derive) vs tampering ----------
CREATE OR REPLACE FUNCTION sp_derive_ticket(p_player UUID, p_ticket BIGINT)
RETURNS plumber_profiles LANGUAGE plpgsql AS $$
DECLARE
    t tickets;
    e economy_params;
    p plumber_profiles;
BEGIN
    PERFORM fn_lock_alive_profile(p_player);
    t := fn_lock_ticket(p_player, p_ticket);
    SELECT * INTO e FROM economy_params WHERE id = 1;

    UPDATE tickets SET status = 'DERIVED' WHERE id = t.id;     -- FSM enforces PUBLIC only
    UPDATE plumber_profiles SET reputation = reputation + e.derivation_bonus_rep
     WHERE player_id = p_player;
    INSERT INTO ledger (player_id, kind, amount, ref_ticket_id)
    VALUES (p_player, 'DERIVATION_BONUS', e.derivation_bonus_money, t.id);

    SELECT * INTO p FROM plumber_profiles WHERE player_id = p_player;
    RETURN p;
END $$;

-- Called by Godot (via API) when the player physically interacts with a red-zone socket
CREATE OR REPLACE FUNCTION sp_report_public_tampering(p_player UUID, p_ticket BIGINT)
RETURNS plumber_profiles LANGUAGE plpgsql AS $$
DECLARE
    t tickets;
    v_fine money_clp;
    p plumber_profiles;
BEGIN
    PERFORM fn_lock_alive_profile(p_player);
    t := fn_lock_ticket(p_player, p_ticket);
    IF t.zone <> 'PUBLIC' THEN
        RAISE EXCEPTION 'Ticket % is not a PUBLIC zone', t.id USING ERRCODE = 'PC003';
    END IF;
    SELECT siss_fine_amount INTO v_fine FROM economy_params WHERE id = 1;
    INSERT INTO siss_infractions (player_id, ticket_id, fine_amount)
    VALUES (p_player, t.id, v_fine);                           -- trigger: fine + strikes
    SELECT * INTO p FROM plumber_profiles WHERE player_id = p_player;
    RETURN p;
END $$;

-- ---------- Survival: daily upkeep ----------
CREATE OR REPLACE FUNCTION sp_apply_daily_upkeep(p_player UUID)
RETURNS plumber_profiles LANGUAGE plpgsql AS $$
DECLARE
    v_upkeep money_clp;
    p plumber_profiles;
BEGIN
    PERFORM fn_lock_alive_profile(p_player);
    SELECT daily_upkeep INTO v_upkeep FROM economy_params WHERE id = 1;
    UPDATE plumber_profiles SET game_day = game_day + 1 WHERE player_id = p_player;
    INSERT INTO ledger (player_id, kind, amount) VALUES (p_player, 'UPKEEP', -v_upkeep);
    SELECT * INTO p FROM plumber_profiles WHERE player_id = p_player;  -- may now be BANKRUPTCY
    RETURN p;
END $$;

-- ---------- Logistics: purchases & vehicle upgrades ----------
CREATE OR REPLACE FUNCTION sp_purchase_item(p_player UUID, p_item_code VARCHAR, p_qty INTEGER)
RETURNS inventory LANGUAGE plpgsql AS $$
DECLARE
    p      plumber_profiles;
    it     items;
    v_cost money_clp;
    inv    inventory;
BEGIN
    IF p_qty <= 0 THEN
        RAISE EXCEPTION 'Quantity must be positive' USING ERRCODE = 'PC003';
    END IF;
    p := fn_lock_alive_profile(p_player);
    SELECT * INTO it FROM items WHERE code = p_item_code;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Item % not found', p_item_code USING ERRCODE = 'PC002';
    END IF;
    v_cost := it.unit_cost * p_qty;
    IF p.money < v_cost THEN
        RAISE EXCEPTION 'Insufficient funds: need %, have %', v_cost, p.money USING ERRCODE = 'PC004';
    END IF;

    INSERT INTO inventory (player_id, item_id, quantity) VALUES (p_player, it.id, p_qty)
    ON CONFLICT (player_id, item_id) DO UPDATE SET quantity = inventory.quantity + EXCLUDED.quantity
    RETURNING * INTO inv;                                      -- capacity trigger fires here

    INSERT INTO ledger (player_id, kind, amount) VALUES (p_player, 'PURCHASE', -v_cost);
    RETURN inv;
END $$;

CREATE OR REPLACE FUNCTION sp_upgrade_vehicle(p_player UUID, p_tier SMALLINT)
RETURNS plumber_profiles LANGUAGE plpgsql AS $$
DECLARE
    p  plumber_profiles;
    vt vehicle_tiers;
BEGIN
    p := fn_lock_alive_profile(p_player);
    SELECT * INTO vt FROM vehicle_tiers WHERE id = p_tier;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Vehicle tier % not found', p_tier USING ERRCODE = 'PC002';
    END IF;
    IF p_tier <= p.vehicle_tier_id THEN
        RAISE EXCEPTION 'Tier % is not an upgrade (current %)', p_tier, p.vehicle_tier_id USING ERRCODE = 'PC003';
    END IF;
    IF p.xp < vt.required_xp THEN
        RAISE EXCEPTION 'Requires % XP (has %)', vt.required_xp, p.xp USING ERRCODE = 'PC006';
    END IF;
    IF p.money < vt.price THEN
        RAISE EXCEPTION 'Insufficient funds: need %, have %', vt.price, p.money USING ERRCODE = 'PC004';
    END IF;

    UPDATE plumber_profiles SET vehicle_tier_id = p_tier WHERE player_id = p_player;
    INSERT INTO ledger (player_id, kind, amount) VALUES (p_player, 'VEHICLE_UPGRADE', -vt.price);
    SELECT * INTO p FROM plumber_profiles WHERE player_id = p_player;
    RETURN p;
END $$;

-- ---------- Hardening: pin search_path on every routine ----------
-- Makes functions independent of the caller's session search_path (TypeORM
-- connections default to "public") and blocks search_path hijacking.
DO $$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT p.oid::regprocedure AS sig
               FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname = 'pipecorp'
    LOOP
        EXECUTE format('ALTER FUNCTION %s SET search_path = pipecorp, pg_catalog', r.sig);
    END LOOP;
END $$;

COMMIT;