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

## Candidatas de temática (decidir quando a mecânica estiver gostosa)
1. **Oficina de reparo espacial** 🚀 — consertar vazamentos/energia numa nave em pane;
   perigos dinâmicos (fogo, descompressão).
2. **Ateliê de poções / alquimia** 🧪 — colher ingredientes, usar caldeirões, entregar poções.
3. **Fábrica de robôs / linha de montagem** 🤖 — montar/encaixar peças numa esteira.
4. **Abrigo de bichos caótico** 🐾 — carregar animais que fogem sozinhos até os cercados.

## Fora de escopo por agora
- Online/rede (previsto, não travado — ver ARCHITECTURE).
- Progressão, UI polida, áudio, arte final, temática fechada.
