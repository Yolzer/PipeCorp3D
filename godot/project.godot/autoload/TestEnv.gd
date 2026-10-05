class_name TestEnv
extends RefCounted
## Makes the test suites SAFE to run from the editor (F6):
## - they always talk to the MOCK API (never the real NestJS/PostgreSQL),
## - they use separate save/career files (never your real progress).
## If an autoload is an OLD version, the tests STOP instead of touching real data.

const MOCK_URL: String = "http://127.0.0.1:3999"


## Returns false (and explains why) if isolation is impossible.
static func isolate(node: Node) -> bool:
	var save_service: Node = node.get_tree().root.get_node_or_null(^"SaveService")
	if save_service == null or not ("save_path" in save_service):
		var where: String = "(not loaded)"
		if save_service != null:
			var raw: Variant = save_service.get_script()
			if raw is Script:
				var script: Script = raw
				where = script.resource_path
		printerr("\n✘ SaveService is an OLD version: %s" % where)
		printerr("  Replace THAT file's content with the new SaveService.gd (it must contain 'var save_path').")
		printerr("  Project Settings → Globals shows which file the SaveService autoload really uses.")
		printerr("  Tests stopped to protect your real save file.\n")
		return false
	var env_url: String = OS.get_environment("PIPECORP_API_URL")
	ApiClient.base_url = env_url if env_url != "" else MOCK_URL
	save_service.set("save_path", "user://test_session.sav")
	CareerStore.path = "user://test_career.bin"
	SaveService.delete_snapshot()
	CareerStore.reset()
	return true


## True if the mock answers. Prints how to start it otherwise.
static func mock_is_up(node: Node) -> bool:
	var res: ApiClient.ApiResponse = await ApiClient._request(HTTPClient.METHOD_GET, "/__log")
	if res.ok:
		return true
	printerr("\n✘ MOCK API NOT RUNNING at %s" % ApiClient.base_url)
	printerr("  Start it in another terminal:  python godot/tests/mock_api.py")
	printerr("  (These tests never use the real API, so your game data stays safe.)\n")
	node.get_tree().quit(1)
	return false
