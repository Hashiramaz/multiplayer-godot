# multiplayer-project

Jogo cooperativo local **até 4 jogadores**, split-couch (mesma máquina, controles),
inspirado no **Overcooked**: personagens 3D em visão isométrica/perspectiva alta que
pegam objetos e interagem com estações sob pressão de tempo. A temática ainda não
está fechada (candidatas no GDD); o foco atual é o protótipo de mecânicas.

> O desenvolvedor é senior technical artist vindo de **Unity** e está aprendendo Godot.
> Ao explicar, vale conectar conceitos Godot ↔ Unity.

## Decisões-chave (travadas)
- **Engine:** Godot **4.7**, renderer Forward+, física **Jolt**.
- **Linguagem:** **GDScript** (indentação com TAB, não espaços).
- **Câmera:** **uma câmera compartilhada** (Overcooked real), perspectiva em ângulo
  alto (~50°), com zoom/pan dinâmico. NÃO é split-screen em quadrantes.
- **Multiplayer:** **couch co-op local** agora; código estruturado para **não travar**
  uma futura camada online (input isolado por dispositivo é a costura).
- **Fluxo de teste:** eu edito `.tscn`/`.gd` no disco; o usuário aperta Play na Godot.
  Sem MCP por enquanto (reavaliar depois).

## Como rodar
Abrir o projeto na Godot 4.7 e apertar Play (F5). Cena principal atual:
`scenes/arena/Arena.tscn` — spawna 1 jogador "debug" controlável por **teclado
(WASD/setas) e/ou qualquer controle**, para testar movimento solo.

## Estrutura
```
autoload/   game_manager.gd, player_manager.gd   (singletons globais)
scenes/     arena/Arena.tscn, player/Player.tscn
scripts/    player/, camera/, arena/, input/       (lógica separada das cenas)
docs/       GDD.md, ARCHITECTURE.md, ROADMAP.md
```

## Convenções
- Nós de cena em PascalCase; arquivos de script em snake_case.
- Lógica em scripts sob `scripts/`; cenas montam a hierarquia visual.
- Jogadores entram no grupo `"players"`; a câmera enquadra esse grupo.
- `PlayerInput` (`scripts/input/`) é a ÚNICA porta de entrada de input do jogador.

## Onde ler mais
- Design/temática/controles → `docs/GDD.md`
- Arquitetura técnica e o "porquê" → `docs/ARCHITECTURE.md`
- Status e próximos passos → `docs/ROADMAP.md`
