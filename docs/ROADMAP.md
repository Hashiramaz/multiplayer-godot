# Roadmap

Legenda: [x] feito · [~] em andamento · [ ] pendente

## Fase 0 — Scaffolding  [x]
- [x] Estrutura de pastas (autoload/scenes/scripts/docs)
- [x] Autoloads registrados (GameManager, PlayerManager)
- [x] Docs (CLAUDE.md, GDD, ARCHITECTURE, ROADMAP)
- [x] Cena principal = Arena de teste

## Fase 1 — Movimento + câmera  [x] (aguardando validação no Play)
- [x] `PlayerInput` por dispositivo (teclado + gamepad, modo DEBUG_ANY)
- [x] `Player` (CharacterBody3D): movimento relativo à câmera, gira p/ encarar, gravidade, colisão
- [x] `CameraRig`: câmera compartilhada que segue o grupo "players"
- [x] Arena com chão, obstáculo, spawns; spawna 1 jogador debug
- [ ] **VALIDAR:** abrir na Godot, apertar Play, andar com controle e teclado

## Fase 2 — Câmera compartilhada com vários players  [x] (aguardando validação de feel)
- [x] Arena spawna N jogadores (`debug_player_count`); slot 0 dirigível, resto parado (DEVICE_NONE) como referência
- [x] Câmera com enquadramento por FOV (distância = raio/tan(fov/2) * margem)
- [x] Ângulo desacoplado (pitch/yaw em graus) da distância (zoom)
- [x] Suavização separada de posição (follow_speed) e zoom (zoom_speed)
- [ ] **VALIDAR:** andar com o azul e sentir a câmera abrir/fechar; ajustar constantes

## Fase 3 — Join local + spawn por device  [ ]
- [ ] Detectar "aperte para entrar" por controle/teclado (`_unhandled_input`)
- [ ] PlayerManager registra device → slot → cor e spawna
- [ ] Remover o atalho DEBUG_ANY

## Fase 4 — Pegar / carregar / interagir  [ ]
- [ ] `Interactable` base + itens pegáveis (reparent p/ "mão")
- [ ] Estação de interação (Area3D) e soltar/entregar

## Fase 5 — Menu → Lobby → Jogo + pause  [ ]
- [ ] Menu principal navegável por controle
- [ ] Transições de cena via GameManager; pause

## Fase 6 — Vertical slice temática  [ ]
- [ ] Escolher temática (ver GDD) e montar 1 mini-desafio jogável

---
### Status atual
Fase 0 e 1 implementadas. **Próximo passo:** o usuário roda na Godot para validar
o movimento/câmera e dá feedback (feel, velocidade, ângulo). Depois, Fase 2/3.
