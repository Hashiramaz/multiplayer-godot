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

## Fase 8 — Profundidade de gameplay (encadeamento)  [~]
Backlog completo de ideias no GDD (`docs/GDD.md`). Primeira fatia:
- [x] **Serraria**: tora → (processa) → tábua; barco só aceita tábua (loop encadeado)
- [x] Estações com interface `accepts(kind)`/`submit(item)`; item tem `kind` (log/plank)
- [x] Câmera solo afastada (`min_distance` 9 → 13)
- [ ] **VALIDAR:** levar tora à serraria, pegar a tábua que sai, entregar no barco
- [ ] (próximos) 2º recurso/zona · arremessar/carga a dois · placar

## Fase 9 — Tempero: terreno encolhendo (adiado)  [ ]
- [ ] Área jogável (maré/lava) que diminui com o tempo, empurrando os jogadores
- [ ] Sinergia com a câmera compartilhada (grupo forçado a se aproximar)

## Fase 10 — Fases data-driven + editor de níveis  [x] (aguardando validação)
Produzir fases em vez de uma arena fixa. Detalhes em `docs/ARCHITECTURE.md`.
- [x] **A**: `LevelData`/`PlacedObject`/`ObjectDef` + autoload `LevelCatalog`; Arena
  constrói a fase a partir de `selected_level` (arena atual vira a ilha padrão)
- [x] **B**: `LevelSelect` entre Lobby e Arena (varre `res://levels` + ilha embutida)
- [x] **C**: `LevelEditor` — câmera de editor + pincel de terreno (heightmap) +
  salvar/abrir/testar + anel-Decal de raio/força
- [x] **D**: editor de objetos — paleta do catálogo, colocar/mover/girar/apagar,
  inspector de `props`, spawns; cenário Kenney (palmeira/pedra) com cor+colisão
- [x] **E**: painel de propriedades (tempo, água, cores) + validação (spawn + barco)
- [ ] **VALIDAR:** montar uma fase do zero, salvar, e jogá-la pela LevelSelect
- [ ] (depois) mais elementos no catálogo; thumbnails; salvar em `user://` no build

## Fase 11 — Multiplayer online (Steam)  [x] (testado a 2 máquinas)
Detalhes em `docs/ARCHITECTURE.md` ("Multiplayer online").
- [x] **O1**: GodotSteam v4.20 + `SteamManager`/`NetworkManager`; hospedar/entrar por
  lobby, browser por tag, convite (overlay + `inviteUserToLobby` + `+connect_lobby`)
- [x] **O2**: jogadores replicados; movimento client-authoritative + interpolação;
  autoridade pelo nome do nó (peer_id)
- [x] **O3**: mundo host-authoritative — pegar/soltar/entregar por RPC, serraria só no
  host, relógio + vitória/derrota em rede, pause online = menu local
- [x] **Lobby online** (`OnlineLobby`): roster, cor por jogador, expulsar, escolher fase
  (sincronizada), convidar; fim de partida volta ao lobby
- [x] **Spawn robusto por-peer** (retry + catch-up + idempotente) — corrige "nenhum
  pinguim spawnou"

## Fase 12 — Água: afogamento e respawn  [x]
- [x] Afoga com meio corpo submerso; larga item no spawn; marcador "Afogou! N";
  respawn em 5s. Host-authoritative no online; local no couch.

## Fase 13 — Curadoria de fases + editor dev-only  [x]
- [x] Editor de níveis e "Fases na Build" só rodando do editor Godot (some na build)
- [x] Manifesto (`res://levels/manifest.tres`) cura quais fases entram e a ordem;
  `shared_levels()` alimenta LevelSelect + lobby online

## Fase 14 — Tesouro: objetivo secundário + estrelas  [~] (aguardando validação)
Detalhes em `docs/ARCHITECTURE.md` ("Tesouro"). 
- [x] Pá (`carriable` kind "shovel") e marca de X (`dig_spot`, prop `dig_duration`) no catálogo
- [x] Cavar segurando o botão, com barra 3D; sorteio de UMA marca certa (host no online)
- [x] X errado = buraco + fumaça placeholder; X certo = baú (placeholder) que vai ao barco
- [x] Estrelas no resultado: 3 com tesouro, 2 sem, 0 na derrota
- [ ] **VALIDAR:** montar fase com pá + 3 Xs, cavar errado e certo, entregar o baú a tempo
- [ ] (depois) arte de pá/baú/fumaça de verdade; regra da 1 estrela; som/feedback

## Infra — Build/CI/distribuição  [x]
- [x] Versão no MainMenu (`version.txt`, `build-N (sha)`)
- [x] CI: push na `main` → build Windows → GitHub Release + `butler push` pro itch

---
### Status atual
Core couch loop (Fases 0–6) + fases data-driven/editor (Fase 10) + **online co-op via
Steam** (lobby, mundo em rede, água) + curadoria de fases + **tesouro/estrelas** (Fase 14),
tudo shipando por CI (build-13+). **Próximos candidatos (a decidir):** Fase 9 (terreno
encolhendo — "tempero"), mais profundidade de gameplay, ou um passe visual nos menus/lobby.
