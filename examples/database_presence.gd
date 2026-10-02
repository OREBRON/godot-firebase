extends Node
## Connection presence example. The game chooses the path and database rules.
## This tracks the Firebase connection, not whether this scene is visible.
## No Auth dependency, global player-online flag, or automatic registration replay.

@export var connections_path := "presence/connections"

var _database: FirebaseDatabase
var _listener_id := 0
var _connection_generation := 0


func _ready() -> void:
	var firebase := get_node_or_null("/root/Firebase")
	if firebase == null:
		push_warning("Presence needs the Firebase autoload")
		return
	_database = firebase.get("database")
	if _database == null or not firebase.call("is_available", "database"):
		push_warning("Presence needs an available Database backend")
		return
	_listener_id = _database.listen_value(".info/connected", _on_connection)


func _exit_tree() -> void:
	_connection_generation += 1
	if _database and _listener_id != 0:
		_database.remove_listener(_listener_id)


func _on_connection(result: FirebaseResult) -> void:
	_connection_generation += 1
	if not result.ok or result.value.value != true:
		return
	var generation := _connection_generation
	# A separate key for each connection prevents one device from clearing another.
	var connection_key := Crypto.new().generate_random_bytes(16).hex_encode()
	var path := connections_path + "/" + connection_key
	var registered := await _database.on_disconnect_remove_value(path).wait()
	if not registered.ok:
		push_warning("Presence registration failed: " + registered.error_message)
		return
	if generation != _connection_generation or not is_inside_tree():
		return
	# Only publish online after the server has acknowledged this connection's cleanup.
	# Registration is one-shot; the next connected event registers a new key.
	var written := await _database.set_value(path, true).wait()
	if not written.ok:
		push_warning("Presence write failed: " + written.error_message)
