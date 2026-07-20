# Arquitetura técnica

Engine: **Godot 4.7**, Forward+, física **Jolt**. Linguagem: **GDScript** (TAB).

## Mapa mental Unity → Godot
| Unity | Godot |
|-------|-------|
| GameObject + Components | Node (a árvore JÁ é a composição) |
| Prefab | Scene (`.tscn`, texto legível) |
| MonoBehaviour | script anexado a um Node (`extends <TipoDoNode>`) |
| Singleton/Manager | **Autoload** (registrado em `project.godot`) |
| CharacterController | `CharacterBody3D` + `move_and_slide()` |
| Update / FixedUpdate | `_process(delta)` / `_physics_process(delta)` |
| ScriptableObject | `Resource` (`.tres`) |
| Tags/Layers | Grupos (`add_to_group`) e collision layers |

## Fluxo de cenas
`MainMenu.tscn` (cena principal) → **Jogar** (`GameManager.go_to_lobby`, que limpa
o roster) → `Lobby.tscn` (join por device) → **Start**
(`GameManager.go_to_level_select`) → `LevelSelect.tscn` (escolhe a fase, grava em
`GameManager.selected_level`) → **A/Enter** (`GameManager.start_match`) → `Arena.tscn`,
que **constrói a fase** (ver abaixo) e spawna um jogador por device
(`PlayerManager.registered_devices`). Abrir a Arena direto (sem nível/roster) cai num
fallback de 1 jogador de teclado + ilha padrão. `MainMenu` também abre o
**editor de níveis** (`GameManager.go_to_editor` → `LevelEditor.tscn`).

## Fases como dados (LevelData)
A Arena deixou de ter conteúdo fixo: uma fase é um **`Resource`** (o análogo do
ScriptableObject) — `LevelData` (`scripts/levels/level_data.gd`) com terreno
(heightmap `PackedFloat32Array` + tamanho/resolução/cores/nível da água), lista de
`PlacedObject` (type_id + transform + `props`) e `spawn_points`. `arena.gd`:
1. `Island/Terrain.build_from(level)` reconstrói o terreno (mesh + colisão);
2. cada `PlacedObject` é instanciado via **`LevelCatalog`** (autoload que mapeia
   `type_id → ObjectDef{cena, categoria, props editáveis}`), com transform + `props`
   aplicados antes do `add_child` (pro `_ready` já ver os valores);
3. cria `Marker3D` por spawn; 4. `MatchUI.configure(level)` liga o relógio e a
   vitória — chamado **depois** de montar a fase, pois o `_ready` do MatchUI roda antes
   do `_ready` da Arena (filhos inicializam antes dos pais).
Adicionar um elemento novo ao jogo = uma cena + uma entrada no `LevelCatalog`.
> ⚠️ `PackedFloat32Array` é copy-on-write: `island.heights` diverge de
> `level.heights` ao esculpir. O editor re-sincroniza o terreno vivo de volta ao
> `LevelData` no Salvar/Testar (`_sync_level_from_scene`).

## Editor de níveis (LevelEditor)
Ferramenta in-game **mouse+teclado** (`scripts/editor/level_editor.gd`), distinta do
couch co-op. Câmera própria (`editor_camera.gd`: botão direito orbita, meio faz pan,
roda dá zoom). Três modos: **Terreno** (pincel subir/descer/suavizar/nivelar sobre o
heightmap, com anel-`Decal` projetado mostrando raio/força/modo; raycast contra o
heightmap em `island.raycast`), **Objetos** (paleta do catálogo; colocar/selecionar/
arrastar/girar Q-E/apagar Del; inspector das `props`; spawns), **Propriedades**
> Modo Objetos tem **encaixe na grade** opcional (ajuda de autoria estilo Overcooked,
> pra layout/balanceamento): um toggle + tamanho de célula quantizam X/Z ao centro da
> célula (Y segue o heightmap), com overlay de grade via `Decal` projetado e leitura da
> célula `(cx, cz)` no inspector. É **estado só do editor** — nada disso vai pro
> `LevelData`; o objeto continua guardando um `Transform3D` comum (`_snap_xz`).
(tempo, nível da água, cores). A árvore `$Objects` é o estado de trabalho, sincronizada
para o `LevelData` no Salvar (`ResourceSaver` → `res://levels/*.tres`) / Testar.
Validação exige ≥1 spawn e ≥1 barco. Cenário (Kenney nature kit) usa `scenery_prop.gd`
para reaplicar o atlas `colormap.png` e gerar colisão trimesh.

Menus (MainMenu/Pause) usam `Button` + o sistema de foco da Godot: navegáveis por
teclado e D-pad. O `ui_accept` padrão não estava disparando com o **A** do controle
aqui, então os scripts de menu fazem a ponte: no `_input`, `JOY_BUTTON_A` emite
`pressed` no botão em foco (`gui_get_focus_owner`). No pause isso só vale enquanto
pausado, pra não colidir com o A do gameplay.

## Pause
`PauseMenu.tscn` é um `CanvasLayer` com `process_mode = ALWAYS`, instanciado dentro da
Arena. Ele segue recebendo input enquanto `get_tree().paused = true` congela o resto da
árvore (players são PAUSABLE). Toggle: **Start** (gamepad) / **Esc** (teclado). Opções:
Continuar (unpause), Voltar ao Lobby, Menu principal — sempre despausando antes de trocar
de cena.

## Árvore de cena — Lobby
```
Lobby (Control, lobby.gd)
├─ Bg (ColorRect)
└─ VBox
   ├─ Title / Instructions (Label)
   └─ Slots (HBoxContainer)   # 4 painéis de slot criados por código
```
Join lido em `_input` por device: gamepad A/B/Start, teclado Enter/Esc/Espaço.

## Árvore de cena — Arena
```
Arena (Node3D, arena.gd)
├─ WorldEnvironment        # céu procedural + luz ambiente
├─ Sun (DirectionalLight3D)
├─ Floor (StaticBody3D)    # chão 40x40 com colisão
├─ Obstacle (StaticBody3D) # caixa para testar colisão/profundidade
├─ SpawnPoints (Node3D)    # 4 Marker3D
├─ Players (Node3D)        # container onde os jogadores são instanciados
└─ CameraRig (Node3D, camera_rig.gd)
   └─ Camera3D             # perspectiva, fov 45, ângulo alto
```

## Modelo de input (a peça mais importante do couch co-op)
O singleton `Input` da Godot **mistura todos os controles**. Para N jogadores
independentes na mesma máquina, cada jogador possui um `PlayerInput`
(`scripts/input/player_input.gd`) amarrado a **um device**:
- `device >= 0` → aquele gamepad (lê eixos via `Input.get_joy_axis(device, ...)`).
- `device == -1` → teclado.
- `device == -99` (**NONE**) → não lê nada (placeholder / ainda sem device).

(O antigo `DEBUG_ANY` foi removido na Fase 3, quando o join real passou a existir.)

`get_move()` devolve `Vector2` (x = direita, y negativo = "pra cima"), unificando
teclado e analógico. **Toda entrada do jogador passa por aqui** — é também a
costura por onde uma futura camada online injetaria input remoto sem reescrever o
Player.

## Movimento (player.gd)
`CharacterBody3D`. O input 2D é convertido para direção no mundo **relativa à
câmera ativa** (empurrar "pra cima" = para dentro da tela, sempre). Aceleração via
`move_toward`, gravidade simples, `move_and_slide()`. O mesh (`Pivot`) gira suave
(`slerp`) para encarar a direção; o "nariz" fica no -Z do Pivot.

## Câmera compartilhada (camera_rig.gd)
Roda em `_process`. Calcula o **centroide** dos nós do grupo `"players"`, mede o
**espalhamento** (maior distância ao centro) e define a distância da câmera
(`base_distance + spread * spread_factor`, com clamp). Posiciona-se em
`centro + view_offset.normalized() * distância` e faz `look_at(centro)`, tudo com
`lerp` para suavizar. Um jogador → segue; vários → enquadra todos.

## Interação: pegar / carregar / entregar (Fase 4)
Modelo por **grupos + Area3D**, sem herança pesada:
- **Carriable** (`carriable.gd`, grupo `"carriable"`) — a tora. É um `Area3D`;
  enquanto carregado fica `monitorable=false` (some da detecção).
- **BoatStation** (`boat_station.gd`, grupo `"station"`) — o barco. `Area3D` com
  N pranchas escondidas; `deliver()` revela uma e atualiza o `Label3D`; ao chegar
  em `required` emite `completed`.
- **Player** tem um `HoldPoint` (sob o Pivot, à frente) e um `InteractionArea`
  (esfera). Ao apertar `interact`: sem carregar → pega o `"carriable"` mais
  próximo (reparent p/ HoldPoint); carregando → se há `"station"` que aceita,
  entrega (consome a tora); senão, solta à frente no chão.
- Input da ação: `PlayerInput.interact_just_pressed()` (edge por device — gamepad
  A, teclado E/Espaço).

## Partida: relógio + vitória/derrota (Fase 6)
`MatchUI.tscn` (`CanvasLayer`, `match_ui.gd`, process **PAUSABLE**) na Arena:
- Relógio regressivo (`match_duration`, `@export`) no HUD; por ser PAUSABLE, o pause
  congela o relógio junto.
- **Vitória**: escuta `BoatStation.completed`. **Derrota**: relógio chega a zero.
- Ao terminar: `GameManager.state = RESULT`, desabilita os players
  (`process_mode = DISABLED`) — em vez de `get_tree().paused`, pra tela de resultado
  seguir respondendo — e mostra "Jogar de novo / Menu principal". O `PauseMenu`
  ignora input enquanto o estado é `RESULT`.

## Autoloads
- `GameManager` — estado global (enum BOOT/MENU/ONLINE/LOBBY/LEVEL_SELECT/EDITOR/
  PLAYING/PAUSED/RESULT) + flow de cena (`go_to_lobby`, `go_to_online`,
  `go_to_online_lobby`, `go_to_level_select`, `go_to_editor`, `go_to_level_manifest`,
  `start_match`) + `selected_level: LevelData` (fase offline) + `get_version()`.
- `LevelCatalog` — registro de objetos colocáveis (`type_id → ObjectDef`); a Arena
  e o editor instanciam conteúdo de fase por aqui. Novo elemento = 1 entrada.
- `PlayerManager` — **fonte da verdade** do roster couch: `registered_devices`
  (device→slot em ordem de join), cores por slot, `join/leave` + sinais
  `player_joined/player_left`. Persiste na troca de cena.
- `SteamManager` — inicializa a Steam (GodotSteam) e bombeia `run_callbacks` todo
  frame; **único a tocar no singleton `Steam`**. Roda offline sem o addon
  (`available`). `process_mode = ALWAYS`.
- `NetworkManager` — fachada da sessão online (ver seção abaixo). `process_mode = ALWAYS`.

## Multiplayer online (Steam)
O couch local continua intacto; o online é uma camada por cima, plugada nas costuras
que já existiam (input por device, spawn centralizado, estado nos autoloads).

**Transporte:** GodotSteam **v4.20** (GDExtension em `addons/godotsteam/`) — já traz o
próprio `SteamMultiplayerPeer` embutido (`create_host`/`create_client`). `steam_appid.txt`
= 480 (Spacewar, appid de teste). O `SteamManager` inicializa; o `NetworkManager` cria o
peer (via `ClassDB`, pra não travar o boot sem o addon) e o resto do jogo só fala com o
`multiplayer` nativo + a fachada — peer trocável.

**Fluxo:** MainMenu → **Online** (`OnlineMenu`: hospedar / procurar partidas por tag /
entrar por ID) → ao hospedar/entrar/aceitar convite Steam cai numa **tela de lobby**
(`OnlineLobby`): roster com cor por jogador, escolher cor (host concede se livre),
expulsar (host), escolher a **fase** (host, sincronizada), convidar amigos. **Iniciar**
(host) manda todos pra Arena; no fim (vitória/derrota) **volta pro lobby** mantendo a
sessão/roster/cores. Convite Steam: `join_requested` (jogo rodando) + `+connect_lobby`
na linha de comando (cold start) — ambos levam ao lobby.

**Roster host-authoritative:** `NetworkManager.members` (peer_id → {name, color}) é do
host, que faz broadcast do dict inteiro (`_sync_members`) a cada mudança; clientes só
exibem e mandam pedidos de volta (registrar nome ao conectar, pedir cor).

**Autoridade:** movimento **client-authoritative** — o dono do pinguim simula e envia
`_remote_state` (posição/giro/velocidade, unreliable) todo frame; remotos **interpolam**
(lerp) rumo ao último estado (mata a trepidação). O **mundo é host-authoritative**:
cliente manda intenção, host decide e transmite. `is_multiplayer_authority()` é true pra
todos offline, então o mesmo código roda no couch — ver `player.gd::_controls_self()`
(offline OU autoridade), desacoplado do id do peer.

**Spawn robusto (por-peer):** cada peer, ao carregar a Arena, faz ping "pronto" ao host
(`_net_client_ready`); o host spawna aquele pinguim em **todos os já presentes** e faz
catch-up dos anteriores pro novo — **sem espera tudo-ou-nada** (o modelo antigo travava:
um ping perdido deixava a partida vazia). Ping perdido/precoce é reenviado a cada 0.5s
(no `_process` do cliente) até o pinguim existir; `_net_spawn_player` é idempotente. O nó
é nomeado com o peer_id → define a autoridade em `player.gd::_ready`. Cor vem do lobby
(`NetworkManager.color_for_peer`).

**Interações em rede:** objetos de fase ganham nome determinístico (`obj_N`) + um registro
`nome→nó` na Arena (`_net_items` — dicionário, não `get_node`, porque item carregado sai
do `$Interactables` pro `HoldPoint`). Pegar/soltar/entregar: cliente manda intenção
(`player._req_interact` → host), host decide na própria cópia (posições sincronizadas) e
transmite `_net_pickup`/`_net_drop`/`_net_deliver`. Progresso do barco sincroniza de graça
(`submit()` é determinístico e roda em todos via `_net_deliver`). Serraria: só o host roda
o timer e faz `host_spawn_item` (prancha com posição decidida pelo host — o jitter era
aleatório); clientes recebem o display (label/barra) via `_net_apply_state`.

**Relógio/fim (`match_ui.gd`):** host roda a contagem e envia `_net_time` (1 msg/s);
vitória (barco completo) e derrota (tempo zera) são decididas pelo host e transmitidas por
`_net_end` (call_local → todos). Clientes só exibem.

**Pause online:** vira **menu local** — NÃO congela a árvore (isso pararia o mundo dos
outros e o poll da Steam); só desabilita o próprio pinguim (`pause_menu.gd`). Por isso os
autoloads de Steam são `process_mode = ALWAYS`.

## Água: afogamento e respawn (player.gd)
Quem controla o pinguim checa a cada frame se o **centro do corpo** passou abaixo da linha
d'água (`global_position.y < water_level - DROWN_DEPTH`, ~meio corpo). Afogou: larga o que
carregava em terra segura (o ponto de spawn), teleporta escondido pro spawn, mostra um
`Label3D` billboard "Afogou! N" (⚠️ **não** `fixed_size` — vira gigante fixo na tela) e
**respawna após `respawn_delay` (5s, `@export`)**. Offline o próprio player cronometra;
online é **host-authoritative** (dono chama `Arena.report_drown` → host valida que é o dono
daquele pinguim, larga o item no spawn, e faz `_net_die`/`_net_respawn`, timer no host). A
Arena passa `player.set_spawn_info(spawn, water_level)` nos dois caminhos de spawn.

## Tesouro: pá, marcas de X e estrelas (objetivo secundário)
O barco continua sendo o objetivo direto; o tesouro é o **secundário opcional**, e é o
que separa 2 de 3 estrelas.

- **Pá** (`Shovel.tscn`) — reusa `carriable.gd` com `kind = "shovel"`. Ocupa as mãos como
  qualquer item: quem está com a pá não carrega tábua. Colocável no editor.
- **Marca de X** (`DigSpot.tscn`, `dig_spot.gd`, grupo `"dig_spot"`) — `Area3D` com prop
  editável `dig_duration` (5s). Coloque **quantas quiser**; a Arena sorteia **uma** como a
  certa no `_ready` (`_setup_treasure`). Estados: intacto → cavado (buraco + `GPUParticles3D`
  de fumaça placeholder se era a errada); cavada, sai da detecção (`monitorable = false`).
- **Cavar = SEGURAR** — `PlayerInput.interact_down()` (estado bruto, sem edge) além do
  `interact_just_pressed()` de sempre. Em `player.gd::_update_interaction`, estar com a pá
  em cima de um X intacto faz o botão **cavar** em vez de pegar/soltar; soltar o botão, sair
  de cima ou afogar **cancela e zera** o progresso. Longe de um X, o interact é o de antes.
  Animação: o FBX não tem clipe de escavação, então `eat` roda **em loop** como placeholder
  (`_set_dig_anim`, que devolve o clipe pra one-shot ao terminar).
- **Quem cronometra** — a Arena, nunca o `DigSpot` (mesma razão da serraria). Offline, esta
  máquina; online, o **host**: o dono manda intenção (`report_dig` → `_req_dig`), o host
  mantém as sessões em `_digs` (player → {spot, t}), transmite a barra (`_net_dig_progress`,
  unreliable) e o resultado (`_net_dig_result`, reliable). **Só o host sabe qual X é o certo**
  — o segredo nunca trafega, então não dá pra ler a resposta na rede.
- **Baú** (`Chest.tscn`) — não está no catálogo (não é colocável); nasce ao cavar o X certo.
  Online vem por `host_spawn_item`, que dá nome determinístico e registra em `_net_items` —
  com isso pegar/carregar/entregar em rede funciona de graça, e afogar carregando o baú cai
  no mesmo caminho de "larga no spawn".
- **Entrega e estrelas** — `boat_station.gd` aceita `kind == "treasure"` sem contar como
  prancha (`treasure_stowed`). ⚠️ Como a **última prancha encerra a partida na hora**, o baú
  precisa chegar **antes** dela — é a tensão de ordem da fase. No fim, `match_ui.gd` conta:
  **3** estrelas (escapou com o baú), **2** (escapou sem), **0** na derrota. Online quem conta
  é o host, e as estrelas viajam junto do `_net_end`. Fase sem nenhum X = sem secundário,
  então fases antigas seguem valendo 2 estrelas.

## Fases: seleção e manifesto de build
As fases (`LevelData` .tres) vivem em `res://levels/`, autoradas no **editor de níveis**
— agora **só disponível rodando do editor Godot** (botão escondido na build via
`OS.has_feature("editor")`; idem "Fases na Build"). O que entra na build e **em que ordem**
é curado por um **manifesto** (`res://levels/manifest.tres`, `LevelManifest`: `order` +
`disabled`), editado na tela dev-only **"Fases na Build"** (`level_manifest_editor.gd`:
checklist + Subir/Descer + Salvar). `LevelData.shared_levels()` devolve só as habilitadas,
em ordem, e alimenta tanto o `LevelSelect` (couch) quanto o seletor de fase do `OnlineLobby`
(sincronizado por caminho `res://`, que toda build compartilha). Sem manifesto, tudo aparece
habilitado (comportamento antigo).

## Distribuição e CI/CD
Versão no canto do MainMenu vem de `res://version.txt` (`GameManager.get_version()`;
`dev` no editor, `build-N (sha)` no build; empacotado via `include_filter` no preset).
`.github/workflows/release.yml`: cada push na `main` builda no **windows-latest**
(`chickensoft-games/setup-godot` + templates), grava o `version.txt`, cria **GitHub
Release** `build-<run_number>` e faz **`butler push`** pro **itch** (segredo
`BUTLER_API_KEY`; upload diferencial, experiência "tipo Steam"). Fallback manual:
`publish.bat` / `tools/publish_itch.ps1` (feche o editor antes — DLLs travam).

## Visual / renderização
- **Personagem:** modelo FBX de pinguim (Kenney-style, `Assets/Visual/Characters/Penguim/`)
  instanciado sob `Player/Pivot/Model`. A cápsula de colisão, `HoldPoint` e
  `InteractionArea` seguem iguais — só o visual mudou. Escala/rotação do `Model`
  são ajustadas no editor (FBX costuma precisar). Cor por jogador está **adiada**
  (`set_color` só guarda `player_color` por enquanto).
- **Iluminação:** sol quente com sombra suave (`light_angular_distance`), ambiente
  com **SSAO** e leve ajuste de contraste/saturação. Alimenta o pós-processo abaixo.
- **Pós-processo (estilização):** `Assets/Shaders/posterize_outline.gdshader`
  (spatial `unshaded`, lê depth/normal/screen — exige **Forward+**). Aplicado num
  `QuadMesh` de tela cheia (`flip_faces`, `extra_cull_margin` alto) filho do
  `Camera3D` (`CameraRig/Camera3D/PostProcess`). Faz outline (Sobel em depth+normal),
  posterização, mapeamento pra paleta de 8 cores e dithering — tudo em uniforms
  ajustáveis no material. Fonte: godotshaders.com.
  ⚠️ Usa `render_mode ... depth_draw_never` — sem isso o quad escreve profundidade e
  **oculta os `Label3D`** (texto "Serraria"/"Barco") desenhados no passe transparente.

## Decisões e pendências
- Câmera **perspectiva** (não ortográfica) — mais natural/Overcooked. Trocável.
- `DEBUG_ANY` é temporário; sai quando o join real entrar (Fase 3).
