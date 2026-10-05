extends Node
## Global event bus (Autoload "SignalBus").
## Every signal here is a future network boundary: in multiplayer, "intent_*"
## signals become client->host RPCs and confirmations become host->client RPCs.
## Rule: gameplay nodes never call each other directly; they talk through here.

@warning_ignore_start("unused_signal")

# --- Intents (client -> authority). Emitted by PlumberEntity. ---
signal intent_place_pipe(player_id: StringName, socket_id: StringName, item_code: StringName)
signal intent_touch_public_network(player_id: StringName, ticket_id: int)

# --- Authority results (authority -> world / UI). Emitted by GridManager. ---
signal pipe_placed(player_id: StringName, socket_id: StringName, cell: Vector3i, item_code: StringName)
signal pipe_rejected(player_id: StringName, socket_id: StringName, reason: StringName)

# --- World & economy (Sprint 2/3) ---
signal water_main_shut_off(house_id: StringName)
signal ticket_accepted(ticket_id: int)
signal job_completed(ticket_id: int, time_seconds: int, item_code: StringName, parts_used: int, parts_wasted: int)

@warning_ignore_restore("unused_signal")
