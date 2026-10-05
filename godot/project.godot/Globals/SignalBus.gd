extends Node

# --- SPRINT 1: SOCKETS & CORE LOOP ---
# The player WANTS to place a pipe (Input)
signal intent_place_pipe(socket_id: String, pipe_type: String)

# The logic controller (Server) CONFIRMS the pipe was placed
signal pipe_placed_successfully(socket_id: String, coordinates: Vector3i)

# --- SPRINT 3: UI & MANAGEMENT ---
signal water_main_shut_off(house_id: String)
signal ticket_accepted(ticket_id: String)
