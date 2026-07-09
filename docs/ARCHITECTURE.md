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

## Árvore de cena (atual)
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
- `device == -2` (**DEBUG_ANY**) → teclado + todos os pads juntos; só para
  prototipar solo antes da tela de join (Fase 3). É o modo usado hoje na Arena.

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

## Autoloads
- `GameManager` — estado global (enum BOOT/MENU/LOBBY/PLAYING/PAUSED). Esqueleto.
- `PlayerManager` — devices registrados + cores por slot. Esqueleto; recebe a
  lógica de join/spawn na Fase 3.

## Preparado para online (sem implementar agora)
- Input isolado por device → trocável por input de rede.
- Spawn centralizado (Fase 3) → ponto único para autoridade/replicação.
- Estado em autoloads, não espalhado nos nós.
Quando/se formos para rede: Godot tem `MultiplayerAPI` +
`MultiplayerSynchronizer`/`MultiplayerSpawner` nativos.

## Decisões e pendências
- Câmera **perspectiva** (não ortográfica) — mais natural/Overcooked. Trocável.
- `DEBUG_ANY` é temporário; sai quando o join real entrar (Fase 3).
