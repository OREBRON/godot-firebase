@tool
extends EditorPlugin

const AUTOLOAD := "Firebase"
const IOSExportPlugin := preload("res://addons/godot_firebase/export/firebase_ios_export_plugin.gd")

var _export_plugin: EditorExportPlugin


func _enable_plugin() -> void:
	add_autoload_singleton(AUTOLOAD, "res://addons/godot_firebase/core/firebase.gd")


func _disable_plugin() -> void:
	remove_autoload_singleton(AUTOLOAD)


func _enter_tree() -> void:
	_export_plugin = IOSExportPlugin.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null
