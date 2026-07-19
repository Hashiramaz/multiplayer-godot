extends Node
## Global game state + high-level scene flow (autoload / singleton, like a Unity
## manager). Flow: MainMenu -> Lobby -> Arena, with in-match pause.

enum State { BOOT, MENU, ONLINE, LOBBY, LEVEL_SELECT, EDITOR, PLAYING, PAUSED, RESULT }

const MAIN_MENU_SCENE: String = "res://scenes/menu/MainMenu.tscn"
const ONLINE_MENU_SCENE: String = "res://scenes/menu/OnlineMenu.tscn"
const ONLINE_LOBBY_SCENE: String = "res://scenes/menu/OnlineLobby.tscn"
const LOBBY_SCENE: String = "res://scenes/lobby/Lobby.tscn"
const LEVEL_SELECT_SCENE: String = "res://scenes/levels/LevelSelect.tscn"
const EDITOR_SCENE: String = "res://scenes/editor/LevelEditor.tscn"
const LEVEL_MANIFEST_SCENE: String = "res://scenes/menu/LevelManifest.tscn"
const ARENA_SCENE: String = "res://scenes/arena/Arena.tscn"

var state: State = State.BOOT

## The level the Arena will build. Set by the level-select screen / editor before
## start_match(); null means "use the default island" (see arena.gd fallback).
var selected_level: LevelData = null

func set_state(new_state: State) -> void:
	state = new_state

func go_to_main_menu() -> void:
	set_state(State.MENU)
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)

func go_to_online() -> void:
	set_state(State.ONLINE)
	get_tree().change_scene_to_file(ONLINE_MENU_SCENE)

## The connected online lobby (roster + colors). Entered automatically when we host
## or join (incl. accepting a Steam invite).
func go_to_online_lobby() -> void:
	set_state(State.ONLINE)
	get_tree().change_scene_to_file(ONLINE_LOBBY_SCENE)

func go_to_lobby() -> void:
	# Guarantee a clean offline state: a leftover online session would send the couch
	# Arena down the networked-spawn path (1 player instead of N).
	NetworkManager.leave()
	# Fresh lobby each time: clear who joined last session.
	PlayerManager.clear()
	set_state(State.LOBBY)
	get_tree().change_scene_to_file(LOBBY_SCENE)

func go_to_level_select() -> void:
	set_state(State.LEVEL_SELECT)
	get_tree().change_scene_to_file(LEVEL_SELECT_SCENE)

func go_to_editor() -> void:
	set_state(State.EDITOR)
	get_tree().change_scene_to_file(EDITOR_SCENE)

## Dev-only screen to curate which levels ship in the build and in what order.
func go_to_level_manifest() -> void:
	set_state(State.EDITOR)
	get_tree().change_scene_to_file(LEVEL_MANIFEST_SCENE)

func start_match() -> void:
	set_state(State.PLAYING)
	get_tree().change_scene_to_file(ARENA_SCENE)

## Build version for the UI. Written into res://version.txt at build time -- by CI
## ("build-N (sha)") or publish_itch.ps1 ("local (sha)"). Absent in the editor, where
## it reads "dev". Cached after first read.
var _version_cache: String = ""

func get_version() -> String:
	if _version_cache != "":
		return _version_cache
	_version_cache = "dev"
	if FileAccess.file_exists("res://version.txt"):
		var f := FileAccess.open("res://version.txt", FileAccess.READ)
		if f != null:
			var t := f.get_as_text().strip_edges()
			if t != "":
				_version_cache = t
	return _version_cache
