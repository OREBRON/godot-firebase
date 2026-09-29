@tool
extends EditorPlugin

const AUTOLOAD := "Firebase"
const IOSExportPlugin := preload("res://addons/godot_firebase/export/firebase_ios_export_plugin.gd")
const AndroidExportPlugin := preload("res://addons/godot_firebase/export/firebase_android_export_plugin.gd")

var _ios_export_plugin: EditorExportPlugin
var _android_export_plugin: EditorExportPlugin


func _enable_plugin() -> void:
	add_autoload_singleton(AUTOLOAD, "res://addons/godot_firebase/core/firebase.gd")


func _disable_plugin() -> void:
	remove_autoload_singleton(AUTOLOAD)


func _enter_tree() -> void:
	_ios_export_plugin = IOSExportPlugin.new()
	_android_export_plugin = AndroidExportPlugin.new()
	add_export_plugin(_ios_export_plugin)
	add_export_plugin(_android_export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(_android_export_plugin)
	remove_export_plugin(_ios_export_plugin)
	_android_export_plugin = null
	_ios_export_plugin = null
