-- =====================================================================
-- PipeCorp3D :: 05_tests.sql — DoD unit tests (run with ON_ERROR_STOP=1)
-- Every block either prints PASS or aborts the whole run.
-- =====================================================================
SET search_path TO pipecorp;
SET client_min_messages TO notice;
\pset tuples_only on
\pset format unaligned

-- Helper: runs SQL and asserts it fails with the expected SQLSTATE
CREATE OR REPLACE FUNCTION pg_temp.expect_error(p_sql TEXT, p_state TEXT, p_label TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = p_state THEN
            RAISE NOTICE 'PASS [%] -> % (%)', p_label, SQLSTATE, SQLERRM;
            RETURN;
        END IF;
        RAISE EXCEPTION 'FAIL [%]: expected %, got % (%)', p_label, p_state, SQLSTATE, SQLERRM;
    END;
    RAISE EXCEPTION 'FAIL [%]: expected SQLSTATE %, statement succeeded', p_label, p_state;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.pid(p_user TEXT) RETURNS UUID LANGUAGE sql AS
$$ SELECT id FROM pipecorp.players WHERE username = p_user $$;

-- T01 registration + initial ledger
DO $$
DECLARE p plumber_profiles;
BEGIN
    p := sp_register_player('tester_01', '$argon2id$dummyhash');
    ASSERT p.money = 50000, 'T01 starting money';
    ASSERT p.vehicle_tier_id = 1 AND p.entity_id = 'Player_1', 'T01 defaults';
    ASSERT (SELECT balance_after FROM ledger WHERE player_id = p.player_id AND kind = 'INITIAL') = 50000, 'T01 ledger';
    RAISE NOTICE 'PASS [T01 register player]';
END $$;

-- T02 auto-budget trigger: 6000*2 + avg(1500,1200)*4 = 17400
DO $$
DECLARE t tickets;
BEGIN
    t := sp_generate_ticket(pg_temp.pid('tester_01'), 'PRIVATE', 'Fuga en lavaplatos', 2::smallint, 4, 120, 600);
    ASSERT t.budget = 17400, format('T02 expected 17400, got %s', t.budget);
    RAISE NOTICE 'PASS [T02 auto budget = %]', t.budget;
END $$;

-- T03 grading (pure function, 2 variables)
DO $$
BEGIN
    ASSERT fn_calc_grade(100, 120, 0, 4) = 'S', 'T03 fast, no waste';
    ASSERT fn_calc_grade(180, 120, 0, 4) = 'B', 'T03 50% over time';
    ASSERT fn_calc_grade(180, 120, 1, 4) = 'D', 'T03 slow + waste';
    ASSERT fn_calc_grade(600, 120, 4, 4) = 'F', 'T03 disaster';
    RAISE NOTICE 'PASS [T03 grading S..F]';
END $$;

-- T04 inventory capacity (tier 1 = 10 volume units)
SELECT pg_temp.expect_error(
    $q$ SELECT pipecorp.sp_purchase_item(pg_temp.pid('tester_01'), 'pvc_straight', 6) $q$,  -- 12 > 10
    'PC005', 'T04 capacity exceeded on foot');
DO $$
DECLARE inv inventory;
BEGIN
    inv := sp_purchase_item(pg_temp.pid('tester_01'), 'pvc_90_deg', 8);   -- 8 vol, cost 9600
    ASSERT inv.quantity = 8, 'T04 qty';
    ASSERT (SELECT money FROM plumber_profiles WHERE player_id = pg_temp.pid('tester_01')) = 40400, 'T04 money';
    RAISE NOTICE 'PASS [T04 purchase within capacity]';
END $$;

-- T05 FSM: cannot complete a non-accepted ticket
SELECT pg_temp.expect_error(
    $q$ SELECT pipecorp.sp_complete_job(pg_temp.pid('tester_01'),
          (SELECT id FROM pipecorp.tickets WHERE description = 'Fuga en lavaplatos'), 'pvc_90_deg', 100, 4, 0) $q$,
    'PC003', 'T05 complete OPEN ticket rejected');

-- T06 full core loop: accept -> complete -> grade S -> payout 1.5x
DO $$
DECLARE v UUID := pg_temp.pid('tester_01'); tid BIGINT; j jobs; p plumber_profiles;
BEGIN
    SELECT id INTO tid FROM tickets WHERE description = 'Fuga en lavaplatos';
    PERFORM sp_accept_ticket(v, tid);
    j := sp_complete_job(v, tid, 'pvc_90_deg', 100, 4, 0);
    SELECT * INTO p FROM plumber_profiles WHERE player_id = v;
    ASSERT j.grade = 'S' AND j.payout = 26100, format('T06 grade/payout %s/%s', j.grade, j.payout);
    ASSERT p.money = 40400 + 26100, 'T06 money credited';
    ASSERT p.xp = 60, format('T06 xp %s', p.xp);
    ASSERT (SELECT quantity FROM inventory WHERE player_id = v AND item_id = 2) = 4, 'T06 stock consumed';
    ASSERT (SELECT status FROM tickets WHERE id = tid) = 'COMPLETED', 'T06 status';
    RAISE NOTICE 'PASS [T06 core loop: grade %, payout %]', j.grade, j.payout;
END $$;

-- T07 expiry: competition takes the job
DO $$
DECLARE v UUID := pg_temp.pid('tester_01'); t tickets; n INTEGER;
BEGIN
    t := sp_generate_ticket(v, 'PRIVATE', 'Ticket que expira', 1::smallint, 1, 60, 1);
    UPDATE tickets SET created_at = now() - interval '1 hour', expires_at = now() - interval '1 second' WHERE id = t.id;
    n := sp_expire_tickets(v);
    ASSERT n = 1 AND (SELECT status FROM tickets WHERE id = t.id) = 'EXPIRED', 'T07 expired';
    RAISE NOTICE 'PASS [T07 lazy expiry]';
END $$;

-- T08 SISS: public tickets cannot be completed; private cannot be derived
DO $$
DECLARE v UUID := pg_temp.pid('tester_01');
BEGIN
    PERFORM sp_generate_ticket(v, 'PUBLIC', 'Medidor publico A', 1::smallint, 1, 60, 600);
    PERFORM sp_generate_ticket(v, 'PUBLIC', 'Medidor publico B', 1::smallint, 1, 60, 600);
    PERFORM sp_generate_ticket(v, 'PUBLIC', 'Medidor publico C', 1::smallint, 1, 60, 600);
    PERFORM sp_generate_ticket(v, 'PRIVATE', 'Privado no derivable', 1::smallint, 1, 60, 600);
    PERFORM sp_accept_ticket(v, (SELECT id FROM tickets WHERE description = 'Medidor publico A'));
END $$;
SELECT pg_temp.expect_error(
    $q$ SELECT pipecorp.sp_complete_job(pg_temp.pid('tester_01'),
          (SELECT id FROM pipecorp.tickets WHERE description = 'Medidor publico A'), 'pvc_90_deg', 50, 1, 0) $q$,
    'PC003', 'T08 PUBLIC ticket cannot be completed');
SELECT pg_temp.expect_error(
    $q$ SELECT pipecorp.sp_derive_ticket(pg_temp.pid('tester_01'),
          (SELECT id FROM pipecorp.tickets WHERE description = 'Privado no derivable')) $q$,
    'PC003', 'T08 PRIVATE ticket cannot be derived');

-- T09 Triage: derivation bonus (+rep, +money)
DO $$
DECLARE v UUID := pg_temp.pid('tester_01'); before plumber_profiles; after plumber_profiles;
BEGIN
    SELECT * INTO before FROM plumber_profiles WHERE player_id = v;
    after := sp_derive_ticket(v, (SELECT id FROM tickets WHERE description = 'Medidor publico A'));
    ASSERT after.reputation = before.reputation + 10, 'T09 reputation';
    ASSERT after.money = before.money + 3000, 'T09 bonus money';
    RAISE NOTICE 'PASS [T09 derivation bonus]';
END $$;

-- T10 SISS tampering: strike 1 = fine, strike 2 = Game Over
DO $$
DECLARE v UUID := pg_temp.pid('tester_01'); p plumber_profiles; m0 NUMERIC;
BEGIN
    SELECT money INTO m0 FROM plumber_profiles WHERE player_id = v;
    p := sp_report_public_tampering(v, (SELECT id FROM tickets WHERE description = 'Medidor publico B'));
    ASSERT p.money = m0 - 30000 AND NOT p.is_game_over, 'T10 strike 1';
    ASSERT (SELECT status FROM tickets WHERE description = 'Medidor publico B') = 'FAILED', 'T10 ticket failed';
    p := sp_report_public_tampering(v, (SELECT id FROM tickets WHERE description = 'Medidor publico C'));
    ASSERT p.is_game_over AND p.game_over_reason = 'SISS_TAMPERING', 'T10 strike 2 game over';
    RAISE NOTICE 'PASS [T10 SISS fines + Game Over]';
END $$;

-- T11 Game Over is terminal: every action rejected, flag irreversible
SELECT pg_temp.expect_error(
    $q$ SELECT pipecorp.sp_purchase_item(pg_temp.pid('tester_01'), 'pvc_90_deg', 1) $q$,
    'PC001', 'T11 action after Game Over');
SELECT pg_temp.expect_error(
    $q$ UPDATE pipecorp.plumber_profiles SET is_game_over = false, game_over_reason = NULL
        WHERE player_id = pg_temp.pid('tester_01') $q$,
    'PC001', 'T11 Game Over cannot be reverted');

-- T12 Ledger append-only + balance consistency
SELECT pg_temp.expect_error(
    $q$ DELETE FROM pipecorp.ledger WHERE player_id = pg_temp.pid('tester_01') $q$,
    'PC007', 'T12 ledger delete blocked');
DO $$
DECLARE v UUID := pg_temp.pid('tester_01');
BEGIN
    ASSERT (SELECT SUM(amount) FROM ledger WHERE player_id = v)
         = (SELECT money FROM plumber_profiles WHERE player_id = v), 'T12 SUM(ledger) = money';
    RAISE NOTICE 'PASS [T12 ledger reconciles with balance]';
END $$;

-- T13 Bankruptcy via daily upkeep
DO $$
DECLARE v UUID; p plumber_profiles; i INTEGER := 0;
BEGIN
    p := sp_register_player('tester_02', '$argon2id$dummyhash');
    v := p.player_id;
    WHILE NOT p.is_game_over AND i < 20 LOOP
        p := sp_apply_daily_upkeep(v);
        i := i + 1;
    END LOOP;
    ASSERT p.is_game_over AND p.game_over_reason = 'BANKRUPTCY', 'T13 bankruptcy';
    ASSERT i = 7, format('T13 expected bankruptcy on day 7 (50000/8000), got %s', i);
    RAISE NOTICE 'PASS [T13 bankruptcy after % days]', i;
END $$;

-- T14 Vehicle upgrade requires XP; upgraded tier raises capacity
DO $$
DECLARE p plumber_profiles;
BEGIN
    p := sp_register_player('tester_03', '$argon2id$dummyhash');
END $$;
SELECT pg_temp.expect_error(
    $q$ SELECT pipecorp.sp_upgrade_vehicle(pg_temp.pid('tester_03'), 2::smallint) $q$,
    'PC006', 'T14 upgrade blocked without XP');
DO $$
DECLARE v UUID := pg_temp.pid('tester_03'); p plumber_profiles; inv inventory;
BEGIN
    UPDATE plumber_profiles SET xp = 60 WHERE player_id = v;   -- simulate earned XP
    p := sp_upgrade_vehicle(v, 2::smallint);
    ASSERT p.vehicle_tier_id = 2 AND p.money = 25000, 'T14 upgrade + charge';
    inv := sp_purchase_item(v, 'pvc_straight', 9);              -- 18 vol <= 20
    ASSERT inv.quantity = 9, 'T14 bigger capacity';
    RAISE NOTICE 'PASS [T14 vehicle progression -> capacity]';
END $$;

\echo '=== ALL SQL UNIT TESTS PASSED ==='