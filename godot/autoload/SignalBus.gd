extends Node
## Global event bus (Autoload "SignalBus").
## Every signal here is a future network boundary: in multiplayer, "intent_*"
## signals become client->host RPCs and confirmations become host->client RPCs.
## Rule: gameplay and UI nodes never call each other directly; they talk through here.

@warning_ignore_start("unused_signal")

# --- Gameplay intents (client -> authority). Emitted by PlumberEntity. ---
signal intent_place_pipe(player_id: StringName, socket_id: StringName, item_code: StringName)
signal intent_touch_public_network(player_id: StringName, ticket_id: int)

# --- Authority results (authority -> world / UI). Emitted by GridManager. ---
signal pipe_placed(player_id: StringName, socket_id: StringName, cell: Vector3i, item_code: StringName)
signal pipe_rejected(player_id: StringName, socket_id: StringName, reason: StringName)

# --- UI -> logic intents (emitted by Gemini's UI scenes) ---
signal intent_register(username: String, password: String)
signal intent_login(username: String, password: String)
signal intent_refresh_tickets()
signal intent_accept_ticket(ticket_id: int)
signal intent_derive_ticket(ticket_id: int)
signal intent_finish_job()
signal intent_purchase(item_code: StringName, quantity: int)
signal intent_upgrade_vehicle(tier_id: int)
signal intent_end_day()
signal intent_new_career()                    # Game Over screen: start a fresh career
signal intent_switch_plumber()                 # [C]: cycle local control between plumbers

# --- Logic -> UI (emitted by ApiClient / JobSession) ---
signal login_succeeded(profile: PlayerProfile)
signal auth_failed(message: String)
signal profile_updated(profile: PlayerProfile)
signal tickets_updated(tickets: Array[TicketData])
signal job_started(ticket: TicketData)
signal job_graded(result: JobResult)
signal game_over(reason: StringName)
signal api_error(code: String, message: String)
signal control_switched(player_id: StringName)

# --- World & economy ---
signal water_main_shut_off(house_id: StringName)
signal ticket_accepted(ticket_id: int)
signal job_completed(ticket_id: int, time_seconds: int, item_code: StringName, parts_used: int, parts_wasted: int)

@warning_ignore_restore("unused_signal")
