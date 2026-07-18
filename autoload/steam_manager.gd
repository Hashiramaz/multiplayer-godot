extends Node
## Boots the Steam client integration and pumps its callbacks. This is the ONLY
## place in the game that touches the raw GodotSteam `Steam` singleton, so the rest
## of the code stays transport-agnostic.
##
## Safe to run WITHOUT the GodotSteam addon installed: it detects the singleton and
## no-ops (offline) if it's missing -- that's what lets us build the netcode in
## parallel with the addon install (see docs: online phase O1).

signal steam_ready(steam_id: int, persona: String)

## Spacewar -- Valve's public test appid. Swap for our own once we have one.
const TEST_APP_ID: int = 480

var available: bool = false ## True only when the Steam client initialized OK.
var steam_id: int = 0
var persona: String = ""

## The raw GodotSteam singleton, or null when the addon isn't installed / init failed.
var _steam: Object = null

func _ready() -> void:
	if not Engine.has_singleton("Steam"):
		push_warning("SteamManager: GodotSteam não instalado (addons/). Rodando offline.")
		return
	_steam = Engine.get_singleton("Steam")
	# App id via env vars + steam_appid.txt (na raiz e ao lado do .exe no build).
	# Setar o ambiente aqui deixa a init robusta mesmo quando o cwd não tem o .txt.
	OS.set_environment("SteamAppId", str(TEST_APP_ID))
	OS.set_environment("SteamGameId", str(TEST_APP_ID))
	# GodotSteam 4.x: steamInitEx() sem args lê o app id acima e devolve
	# { "status": int, "verbal": String }; status 0 == OK. Chamado sem argumentos
	# de propósito -- a assinatura com args mudou entre versões.
	var result: Dictionary = _steam.steamInitEx()
	if int(result.get("status", -1)) != 0:
		push_warning("SteamManager: falha ao iniciar Steam -> %s" % result.get("verbal", result))
		_steam = null
		return
	# ==========================================================================
	available = true
	steam_id = _steam.getSteamID()
	persona = _steam.getPersonaName()
	print("SteamManager: pronto como '%s' (%s)" % [persona, steam_id])
	steam_ready.emit(steam_id, persona)

func _process(_delta: float) -> void:
	# Steam callbacks must be pumped every frame while the client is up.
	if _steam != null:
		_steam.run_callbacks()

## Raw GodotSteam singleton for the NetworkManager (null when offline).
func api() -> Object:
	return _steam
