-- =====================================================================
-- PipeCorp3D :: 02_triggers.sql
-- Engine-level business rules (SISS law, bankruptcy, capacity, FSM)
-- Custom SQLSTATEs (mapped to HTTP codes in NestJS exception filter):
--   PC001 game over | PC002 not found | PC003 invalid state
--   PC004 insufficient funds | PC005 capacity exceeded | PC006 insufficient XP
--   PC007 immutable record
-- =====================================================================
BEGIN;
SET search_path TO pipecorp;

-- ---------- T1: auto-budget (replaces manual budget phase) ----------
CREATE OR REPLACE FUNCTION trg_ticket_auto_budget() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_labor     money_clp;
    v_avg_pipe  money_clp;
BEGIN
    SELECT labor_rate_per_diff INTO v_labor FROM economy_params WHERE id = 1;
    SELECT COALESCE(AVG(unit_cost), 0) INTO v_avg_pipe FROM items WHERE category = 'PIPE';
    NEW.budget := ROUND(v_labor * NEW.difficulty + v_avg_pipe * NEW.estimated_parts, 2);
    RETURN NEW;
END $$;

CREATE TRIGGER trg_tickets_budget
    BEFORE INSERT ON tickets
    FOR EACH ROW EXECUTE FUNCTION trg_ticket_auto_budget();

-- ---------- T2: ticket finite-state machine + zone legality ----------
CREATE OR REPLACE FUNCTION trg_ticket_fsm() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status = OLD.status THEN
        RETURN NEW;
    END IF;

    IF NOT (
        (OLD.status = 'OPEN'     AND NEW.status IN ('ACCEPTED','EXPIRED','DERIVED','FAILED')) OR
        (OLD.status = 'ACCEPTED' AND NEW.status IN ('COMPLETED','DERIVED','FAILED'))
    ) THEN
        RAISE EXCEPTION 'Illegal ticket transition % -> % (ticket %)', OLD.status, NEW.status, OLD.id
            USING ERRCODE = 'PC003';
    END IF;

    -- SISS law: public network jobs can only be derived, never completed by the player
    IF NEW.status = 'COMPLETED' AND OLD.zone = 'PUBLIC' THEN
        RAISE EXCEPTION 'Ticket % is in a PUBLIC (SISS) zone and cannot be completed', OLD.id
            USING ERRCODE = 'PC003';
    END IF;
    IF NEW.status = 'DERIVED' AND OLD.zone = 'PRIVATE' THEN
        RAISE EXCEPTION 'Ticket % is PRIVATE; derivation only applies to PUBLIC zones', OLD.id
            USING ERRCODE = 'PC003';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_tickets_fsm
    BEFORE UPDATE OF status ON tickets
    FOR EACH ROW EXECUTE FUNCTION trg_ticket_fsm();

-- ---------- T3: ledger applies balance atomically ----------
CREATE OR REPLACE FUNCTION trg_ledger_apply() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE plumber_profiles
       SET money = money + NEW.amount
     WHERE player_id = NEW.player_id
    RETURNING money INTO NEW.balance_after;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Profile % not found', NEW.player_id USING ERRCODE = 'PC002';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_ledger_before_insert
    BEFORE INSERT ON ledger
    FOR EACH ROW EXECUTE FUNCTION trg_ledger_apply();

-- ---------- T4: ledger is append-only ----------
CREATE OR REPLACE FUNCTION trg_ledger_immutable() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'Ledger is append-only (row %)', OLD.id USING ERRCODE = 'PC007';
END $$;

CREATE TRIGGER trg_ledger_no_update_delete
    BEFORE UPDATE OR DELETE ON ledger
    FOR EACH ROW EXECUTE FUNCTION trg_ledger_immutable();

-- ---------- T5: bankruptcy => Game Over (+ updated_at) ----------
CREATE OR REPLACE FUNCTION trg_profile_guard() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := now();
    IF NEW.money < 0 AND NOT NEW.is_game_over THEN
        NEW.is_game_over     := TRUE;
        NEW.game_over_reason := 'BANKRUPTCY';
    END IF;
    -- Game Over is terminal: it can never be reverted by the API
    IF OLD.is_game_over AND NOT NEW.is_game_over THEN
        RAISE EXCEPTION 'Game Over is irreversible for %', OLD.player_id USING ERRCODE = 'PC001';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_profiles_guard
    BEFORE UPDATE ON plumber_profiles
    FOR EACH ROW EXECUTE FUNCTION trg_profile_guard();

-- ---------- T6: mobile inventory capacity (vehicle tier) ----------
CREATE OR REPLACE FUNCTION trg_inventory_capacity() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_capacity  INTEGER;
    v_used      INTEGER;
    v_new_vol   INTEGER;
BEGIN
    -- Row lock on the profile serializes concurrent inventory writes for the
    -- same player, preventing write-skew under READ COMMITTED.
    SELECT vt.inventory_capacity INTO v_capacity
      FROM plumber_profiles p
      JOIN vehicle_tiers vt ON vt.id = p.vehicle_tier_id
     WHERE p.player_id = NEW.player_id
       FOR UPDATE OF p;

    SELECT COALESCE(SUM(i.quantity * it.unit_volume), 0) INTO v_used
      FROM inventory i JOIN items it ON it.id = i.item_id
     WHERE i.player_id = NEW.player_id
       AND i.item_id  <> NEW.item_id;

    SELECT NEW.quantity * unit_volume INTO v_new_vol FROM items WHERE id = NEW.item_id;

    IF v_used + v_new_vol > v_capacity THEN
        RAISE EXCEPTION 'Inventory capacity exceeded: % / % volume units', v_used + v_new_vol, v_capacity
            USING ERRCODE = 'PC005';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_inventory_capacity_check
    BEFORE INSERT OR UPDATE ON inventory
    FOR EACH ROW EXECUTE FUNCTION trg_inventory_capacity();

-- ---------- T7: SISS infraction => fine, ticket FAILED, strike Game Over ----------
CREATE OR REPLACE FUNCTION trg_siss_infraction() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_strikes   INTEGER;
    v_limit     SMALLINT;
BEGIN
    INSERT INTO ledger (player_id, kind, amount, ref_ticket_id)
    VALUES (NEW.player_id, 'FINE', -NEW.fine_amount, NEW.ticket_id);

    UPDATE tickets SET status = 'FAILED'
     WHERE id = NEW.ticket_id AND status IN ('OPEN','ACCEPTED');

    SELECT siss_strikes_game_over INTO v_limit FROM economy_params WHERE id = 1;
    SELECT COUNT(*) INTO v_strikes FROM siss_infractions WHERE player_id = NEW.player_id;

    IF v_strikes >= v_limit THEN
        UPDATE plumber_profiles
           SET is_game_over = TRUE, game_over_reason = 'SISS_TAMPERING'
         WHERE player_id = NEW.player_id AND NOT is_game_over;
    END IF;
    RETURN NULL;
END $$;

CREATE TRIGGER trg_siss_after_insert
    AFTER INSERT ON siss_infractions
    FOR EACH ROW EXECUTE FUNCTION trg_siss_infraction();

COMMIT;