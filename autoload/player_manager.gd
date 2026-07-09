extends Node
## Source of truth for local couch co-op: which input devices have joined, in what
## slot, and their color. Populated by the Lobby (Phase 3) and read by the Arena
## when spawning. Being an autoload, it PERSISTS across scene changes -- and it's
## the seam a future online layer would plug player identity into.

signal player_joined(slot: int, device: int)
signal player_left(slot: int, device: int)

const MAX_PLAYERS: int = 4

const PLAYER_COLORS: Array[Color] = [
	Color(0.20, 0.55, 1.00), # blue
	Color(1.00, 0.35, 0.30), # red
	Color(0.35, 0.85, 0.40), # green
	Color(1.00, 0.80, 0.25), # yellow
]

## Device ids in join order. Index == player slot. (-1 = keyboard, >=0 = gamepad.)
var registered_devices: Array[int] = []

## Registers a device if free and there's room. Returns the slot, or -1 on failure.
func join(device: int) -> int:
	if device in registered_devices:
		return -1
	if registered_devices.size() >= MAX_PLAYERS:
		return -1
	registered_devices.append(device)
	var slot := registered_devices.size() - 1
	player_joined.emit(slot, device)
	return slot

func leave(device: int) -> void:
	var idx := registered_devices.find(device)
	if idx == -1:
		return
	registered_devices.remove_at(idx)
	player_left.emit(idx, device)

func is_registered(device: int) -> bool:
	return device in registered_devices

func slot_count() -> int:
	return registered_devices.size()

func color_for_slot(slot: int) -> Color:
	return PLAYER_COLORS[slot % PLAYER_COLORS.size()]

func clear() -> void:
	registered_devices.clear()
