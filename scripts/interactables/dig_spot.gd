extends Area3D
## Uma marca de "X" no chão -- possível esconderijo do tesouro. Uma fase pode ter
## quantas o autor quiser, mas só UMA é a certa: a Arena sorteia no início da partida
## (online quem sorteia é o host, senão cada máquina acharia um tesouro diferente).
##
## Quem estiver carregando uma pá e segurar o botão de interação em cima da marca
## cava por `dig_duration` segundos, com barra flutuante mostrando o progresso.
##
## Este nó não decide nada sozinho: quem cronometra e resolve é a Arena (offline ou
## host), pelo mesmo motivo da serraria -- timer rodando em cada máquina diverge.

@export var dig_duration: float = 5.0

var is_treasure: bool = false ## Sorteado pela Arena; nunca definido aqui.
var dug: bool = false

@onready var _mark: Node3D = $Mark
@onready var _hole: Node3D = $Hole
@onready var _smoke: GPUParticles3D = $Smoke
@onready var _bar: Node3D = $ProgressBar
@onready var _fill: Node3D = $ProgressBar/Fill

func _ready() -> void:
	add_to_group("dig_spot")
	_hole.visible = false
	_bar.visible = false

func can_dig() -> bool:
	return not dug

## Progresso 0..1, empurrado pela Arena (o host transmite pros clientes).
func set_progress(p: float) -> void:
	if dug:
		return
	_bar.visible = p > 0.0
	_fill.scale.x = clampf(p, 0.02, 1.0)

## Resultado da escavação, aplicado em TODAS as máquinas. O baú em si é spawnado
## pela Arena (é item de mundo: precisa de nome determinístico pra rede).
func resolve(found: bool) -> void:
	if dug:
		return
	dug = true
	_bar.visible = false
	_mark.visible = false
	_hole.visible = true
	if not found:
		_smoke.emitting = true # placeholder: fumacinha de "aqui não era"
	# Sai da detecção do jogador -- buraco cavado não se cava de novo.
	monitorable = false
