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
(`GameManager.start_match`) → `Arena.tscn`, que lê `PlayerManager.registered_devices`
e spawna um jogador por device. Abrir a Arena direto (sem ninguém registrado) cai num
fallback de 1 jogador de teclado.

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
- `GameManager` — estado global (enum BOOT/MENU/LOBBY/PLAYING/PAUSED) + flow de
  cena (`start_match`, `return_to_lobby`).
- `PlayerManager` — **fonte da verdade** do roster: `registered_devices`
  (device→slot em ordem de join), cores por slot, `join/leave` + sinais
  `player_joined/player_left`. Persiste na troca de cena.

## Preparado para online (sem implementar agora)
- Input isolado por device → trocável por input de rede.
- Spawn centralizado (Fase 3) → ponto único para autoridade/replicação.
- Estado em autoloads, não espalhado nos nós.
Quando/se formos para rede: Godot tem `MultiplayerAPI` +
`MultiplayerSynchronizer`/`MultiplayerSpawner` nativos.

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
