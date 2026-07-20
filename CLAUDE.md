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
- **Multiplayer:** **couch co-op local** + **online co-op via Steam** (implementado —
  GodotSteam v4.20, appid de teste 480). Input isolado por dispositivo foi a costura por
  onde a rede entrou. Detalhes em `docs/ARCHITECTURE.md` (seção "Multiplayer online").
- **Fluxo de teste:** eu edito `.tscn`/`.gd` no disco; o usuário aperta Play na Godot.
  Sem MCP por enquanto (reavaliar depois).

## Como rodar
Abrir o projeto na Godot 4.7 e apertar Play (F5). Fluxo:
`MainMenu` → **Jogar** → `Lobby` (join local: **A/Enter** entra, **B/Esc** sai,
**Start/Espaço** começa) → `LevelSelect` (escolher a fase) → `Arena` (spawna 1
jogador por device; movimento com analógico/WASD, **A/E** pega/entrega tora no barco).
Objetivo secundário: com a **pá** na mão, **segurar A/E** em cima de um **X** cava (5s);
uma das marcas esconde o **baú**, que entregue no barco antes da última prancha vale a
**3ª estrela**. Ver `docs/ARCHITECTURE.md` (seção "Tesouro").
Na Arena, **Start/Esc** = pause (Continuar / Voltar ao Lobby / Menu principal). Menus
navegáveis por controle e teclado. Abrir a Arena direto cai num fallback de 1 jogador
de teclado + ilha padrão.

`MainMenu` → **Online** → `OnlineMenu` (hospedar / procurar partidas / entrar por ID) →
`OnlineLobby` (roster, cor por jogador, expulsar, host escolhe a fase, convidar) →
**Iniciar** → `Arena` em rede; no fim volta ao lobby. Precisa da **Steam aberta**. Ver
`docs/ARCHITECTURE.md` (seções "Multiplayer online" e "Água").

`MainMenu` → **Editor de Níveis** / **Fases na Build** — botões **só aparecem rodando do
editor Godot** (dev), não na build. O `LevelEditor` (mouse+teclado) esculpe terreno,
posiciona objetos/spawns e salva em `res://levels/`. "Fases na Build" cura quais `.tres`
entram na build e em que ordem (manifesto). As fases habilitadas aparecem na `LevelSelect`
e no lobby online. Detalhes em `docs/ARCHITECTURE.md`.

## Como gerar build (Windows)
Preset `export_presets.cfg` → **Windows Desktop**, saída em `build/windows/EscapeTheIsland.exe`
(pasta `build/` é gitignored). Requer os **export templates da 4.7 instalados**
(Editor → Gerenciar Modelos de Exportação). Pelo editor: Projeto → Exportar →
Exportar Projeto. Ou via CLI headless (com o editor fechado):
`Godot_..._console.exe --headless --path <projeto> --export-release "Windows Desktop" build/windows/EscapeTheIsland.exe`.

## Estrutura
```
autoload/   game_manager.gd, player_manager.gd, level_catalog.gd,
            steam_manager.gd, network_manager.gd  (singletons globais)
scenes/     arena/, player/, lobby/, menu/, levels/ (LevelSelect), editor/ (LevelEditor), props/
scripts/    player/, camera/, arena/, input/, ui/, levels/ (LevelData/PlacedObject/ObjectDef),
            editor/ (level_editor, editor_camera), props/ (scenery)
levels/     fases salvas (.tres) — carregadas pela LevelSelect
docs/       GDD.md, ARCHITECTURE.md, ROADMAP.md
```
As fases são **dados** (`LevelData`, um `Resource`): a Arena constrói terreno + objetos
a partir do nível selecionado, em vez de conteúdo fixo. Ver `docs/ARCHITECTURE.md`.

## Convenções
- Nós de cena em PascalCase; arquivos de script em snake_case.
- Lógica em scripts sob `scripts/`; cenas montam a hierarquia visual.
- Jogadores entram no grupo `"players"`; a câmera enquadra esse grupo.
- `PlayerInput` (`scripts/input/`) é a ÚNICA porta de entrada de input do jogador.

## Onde ler mais
- Design/temática/controles → `docs/GDD.md`
- Arquitetura técnica e o "porquê" → `docs/ARCHITECTURE.md`
- Status e próximos passos → `docs/ROADMAP.md`
