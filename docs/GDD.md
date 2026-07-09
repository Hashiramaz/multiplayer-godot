# GDD — multiplayer-project (rascunho vivo)

## Visão
Jogo cooperativo local para **1–4 jogadores** na mesma tela, no espírito do
**Overcooked**: caos coordenado, comunicação, pressão de tempo. Personagens 3D
simples numa visão de câmera alta (meio isométrica).

## Core loop
Pegar objeto → transportar → usar/combinar numa estação → entregar um resultado
antes do tempo acabar. Obstáculos e o próprio layout forçam coordenação entre os
jogadores. Loop agnóstico de temática — prototipado com primitivas.

## Jogadores e controle
- Até 4 jogadores locais, cada um em **um dispositivo** (controle; teclado serve
  como jogador de teste).
- Entrada na partida por **join** ("aperte para entrar"); não exige lobby cheio.
- Movimento com o analógico/WASD, relativo à câmera. Ações: pegar/soltar, interagir.

## Câmera
Uma câmera compartilhada que enquadra todos. Aproxima quando juntos, afasta quando
se espalham. Ninguém sai da tela — isso incentiva o grupo a andar junto.

## Temática — direção escolhida: "Escape the Island" 🏝️
> Direção definida pelo desenvolvedor; **mecânicas ainda NÃO desenhadas** e o plano
> técnico atual (protótipo com primitivas) segue inalterado. Isto é só o norte
> criativo para, mais adiante, desenharmos mecânicas coerentes com ele.

**Premissa:** 1–4 jogadores presos numa ilha precisam **cooperar para escapar**
antes que uma ameaça crescente os alcance. A ideia central é **coletar recursos e
construir uma embarcação** (ex.: uma jangada/barco) sob pressão de tempo.

**Ameaça / relógio (a decidir — ainda em aberto):**
- **Vulcão** entrando em erupção (lava avançando, tremores, queda de detritos), ou
- **Ilha alagando** (maré/água subindo que reduz a área jogável).
Ambas dão o "timer com tensão crescente" que combina com o core loop cooperativo.

**Ganchos que a temática abre (para pensarmos em mecânicas depois, não agora):**
- Recursos espalhados (madeira, corda, velas...) → transportar até um ponto de construção.
- Uma "estação" central = o barco em construção, que evolui por etapas.
- Perigos dinâmicos do ambiente (lava/água) forçando rotas e coordenação.
- Possível terreno que muda com o tempo (área encolhendo), reforçando a câmera compartilhada.

### Alternativas consideradas (arquivadas)
- Oficina de reparo espacial 🚀 · Ateliê de poções 🧪 · Fábrica de robôs 🤖 · Abrigo de bichos 🐾

## Fora de escopo por agora
- Online/rede (previsto, não travado — ver ARCHITECTURE).
- Progressão, UI polida, áudio, arte final, temática fechada.
