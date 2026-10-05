#!/usr/bin/env bash
# PipeCorp3D :: DB DoD runner — builds schema from scratch, runs unit + concurrency tests.
# Usage: PGHOST=localhost PGPORT=5432 PGUSER=postgres PGDATABASE=pipecorp3d ./run_tests.sh
set -euo pipefail
cd "$(dirname "$0")"
PSQL="psql -v ON_ERROR_STOP=1 -X -q"

echo ">> Building schema"
for f in 01_schema.sql 02_triggers.sql 03_procedures.sql 04_seed.sql; do
  $PSQL -f "$f"
done

echo ">> Unit tests"
$PSQL -f 05_tests.sql 2>&1 | sed 's/^psql:[^:]*:[0-9]*: //' | grep -v '^$'
[[ ${PIPESTATUS[0]} -eq 0 ]] || { echo "FAIL: unit tests aborted"; exit 1; }

echo ">> Concurrency test (READ COMMITTED, 2 parallel purchases exceeding capacity)"
$PSQL -c "SELECT pipecorp.sp_register_player('tester_cc','\$argon2id\$x')" >/dev/null
BUY="BEGIN ISOLATION LEVEL READ COMMITTED;
     SELECT pipecorp.sp_purchase_item((SELECT id FROM pipecorp.players WHERE username='tester_cc'),'pvc_straight',4);
     SELECT pg_sleep(1);
     COMMIT;"
( $PSQL -c "$BUY" >/dev/null 2>/tmp/pc_cc_a.err && echo OK || echo FAIL ) > /tmp/pc_cc_a.out &
( $PSQL -c "$BUY" >/dev/null 2>/tmp/pc_cc_b.err && echo OK || echo FAIL ) > /tmp/pc_cc_b.out &
wait
RESULTS="$(cat /tmp/pc_cc_a.out /tmp/pc_cc_b.out | sort | tr '\n' ' ')"
QTY="$($PSQL -tA -c "SELECT COALESCE(SUM(quantity),0) FROM pipecorp.inventory i JOIN pipecorp.players p ON p.id=i.player_id WHERE p.username='tester_cc'")"
if [[ "$RESULTS" == "FAIL OK " && "$QTY" == "4" ]] && grep -q "capacity exceeded" /tmp/pc_cc_*.err; then
  echo "PASS [T15 concurrent writes serialized: one commit, one PC005, final qty=$QTY]"
else
  echo "FAIL [T15] results=$RESULTS qty=$QTY"; cat /tmp/pc_cc_*.err; exit 1
fi
echo "=== DATABASE DoD: ALL TESTS PASSED ==="