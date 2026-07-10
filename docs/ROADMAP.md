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

## Fase 3 — Join local + spawn por device  [x] (aguardando validação)
- [x] Lobby (cena principal): join por device em `_input` (A/B/Start · Enter/Esc/Espaço)
- [x] PlayerManager registra device → slot → cor (sinais join/left, persiste)
- [x] GameManager.start_match troca Lobby → Arena; Arena spawna por device
- [x] Removido o DEBUG_ANY; fallback de teclado ao abrir a Arena direto
- [ ] **VALIDAR:** entrar com teclado e controle(s), começar, e cada um mover o seu boneco

## Fase 4 — Pegar / carregar / interagir  [x] (aguardando validação)
- [x] Ação `interact` por device (edge): gamepad A, teclado E/Espaço
- [x] `Carriable` (tora, Area3D grupo "carriable"); pegar = reparent p/ HoldPoint
- [x] `Player` com InteractionArea (esfera): pega o mais próximo, entrega ou solta
- [x] `BoatStation` (Area3D grupo "station"): entrega revela pranchas, Label3D "Barco N/4"
- [x] Arena povoada com 5 toras + o barco
- [ ] **VALIDAR:** pegar tora, levar ao barco, ver as pranchas subindo até "BARCO PRONTO!"

## Fase 5 — Menu → Lobby → Jogo + pause  [x] (aguardando validação)
- [x] MainMenu (cena principal): Jogar / Sair, navegável por controle e teclado
- [x] GameManager: go_to_main_menu / go_to_lobby (limpa roster) / start_match
- [x] PauseMenu (CanvasLayer ALWAYS) na Arena: Start/Esc; Continuar/Lobby/Menu
- [ ] **VALIDAR:** navegar Menu→Lobby→Jogo por controle; pausar e usar cada opção

## Fase 6 — Core loop: relógio + vitória/derrota  [x] (aguardando validação)
- [x] MatchUI (CanvasLayer PAUSABLE): relógio regressivo no HUD (o pause congela junto)
- [x] Vitória ao completar o barco a tempo; derrota quando o tempo zera
- [x] Tela de resultado (Jogar de novo / Menu principal), com a ponte do A do controle
- [x] Estado RESULT no GameManager; pause fica silencioso durante o resultado
- [ ] **VALIDAR:** ganhar (barco a tempo) e perder (deixar o tempo acabar)

## Fase 7 — Primeiro passe visual  [~] (aguardando validação)
- [x] Personagem: pinguim FBX no lugar da cápsula (colisão/gameplay intactos)
- [x] Iluminação: sol quente + sombra suave + SSAO + ajuste de contraste/saturação
- [x] Pós-processo: shader outline + posterização + paleta + dithering (quad da câmera)
- [ ] **VALIDAR/AFINAR:** escala e rotação do pinguim; parâmetros do shader; paleta
- [ ] (depois) cor por jogador no pinguim; mais assets/estações temáticas

## Fase 8 — Tempero: terreno encolhendo (adiado)  [ ]
- [ ] Área jogável (maré/lava) que diminui com o tempo, empurrando os jogadores
- [ ] Sinergia com a câmera compartilhada (grupo forçado a se aproximar)

---
### Status atual
Fases 0–6 implementadas: core loop jogável de ponta a ponta — Menu → Lobby → Jogo
(pegar toras, construir o barco contra o relógio) → vitória/derrota → resultado.
**Próximo passo:** validar ganhar/perder no F5; afinar `match_duration`. Depois,
Fase 7 (terreno encolhendo) e polish (áudio, arte, feedback).
