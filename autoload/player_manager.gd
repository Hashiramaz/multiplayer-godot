extends Node
## Tracks which input devices have joined and hands out per-player slots/colors.
##
## Phase 1 does NOT register anyone here yet -- the test arena spawns a single
## debug player directly. Phase 3 moves the local join screen and spawning into
## this manager (one slot per device), which is also the seam a future online
## layer would plug into.

const PLAYER_COLORS: Array[Color] = [
	Color(0.20, 0.55, 1.00), # blue
	Color(1.00, 0.35, 0.30), # red
	Color(0.35, 0.85, 0.40), # green
	Color(1.00, 0.80, 0.25), # yellow
]

## Device ids that have joined, in join order. Index == player slot.
var registered_devices: Array[int] = []

func color_for_slot(slot: int) -> Color:
	return PLAYER_COLORS[slot % PLAYER_COLORS.size()]

func slot_count() -> int:
	return registered_devices.size()
