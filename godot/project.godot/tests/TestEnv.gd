class_name TestEnv
extends RefCounted
## Makes the test suites SAFE to run from the editor (F6):
## - they always talk to the MOCK API (never the real NestJS/PostgreSQL),
## - they use separate save/career files (never your real progress)

const MOCK_URL: String = "http://127.0.0.1:3999"


static func isolate() -> void:
	var env_url: String = OS.get_environment("PIPECORP_API_URL")
	ApiClient.base_url = env_url if env_url != "" else MOCK_URL
	SaveService.save_path = "user://test_session.sav"
	CareerStore.path = "user://test_career.bin"
	SaveService.delete_snapshot()
	CareerStore.reset()


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
