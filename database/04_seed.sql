-- =====================================================================
-- PipeCorp3D :: 04_seed.sql  — static catalog for the MVP
-- =====================================================================
BEGIN;
SET search_path TO pipecorp;

INSERT INTO economy_params (id) VALUES (1);

INSERT INTO vehicle_tiers (id, name, inventory_capacity, price, required_xp) VALUES
    (1, 'A pie',      10,      0,   0),
    (2, 'Bicicleta',  20,  25000,  60),
    (3, 'Hatchback',  45,  90000, 200),
    (4, 'Furgón',    100, 250000, 500);

-- item codes match Godot pipe_type strings (SignalBus.intent_place_pipe)
INSERT INTO items (id, code, name, category, unit_cost, unit_volume) VALUES
    (1, 'pvc_straight', 'Tubo PVC recto 1m',   'PIPE',    1500, 2),
    (2, 'pvc_90_deg',   'Codo PVC 90°',        'PIPE',    1200, 1),
    (3, 'pvc_tee',      'Tee PVC',             'FITTING', 1400, 1),
    (4, 'teflon_tape',  'Cinta teflón',        'SEALANT',  800, 1);

COMMIT;