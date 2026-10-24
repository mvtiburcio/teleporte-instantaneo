# Teletransporte Instantâneo ⚡

<p>
  <img src="https://img.shields.io/badge/macOS-13%2B-000000?logo=apple&logoColor=white" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Python-3.12-3776AB?logo=python&logoColor=white" alt="Python 3.12">
  <img src="https://img.shields.io/badge/MediaPipe-0.10.14-0097A7" alt="MediaPipe 0.10.14">
  <img src="https://img.shields.io/badge/licen%C3%A7a-MIT-green" alt="Licença MIT">
</p>

Faça o **Teletransporte Instantâneo do Goku** numa videochamada de verdade: coloque **dois dedos na testa**, ouça o *"vuush"* e **suma da câmera** — com os riscos verticais clássicos do anime. Faça o gesto de novo e você **reaparece**, de onde estiver.

Testado no **Google Meet**. Deve funcionar também no **WhatsApp (app do Mac), Zoom, Teams** e em qualquer app que deixe escolher câmera e microfone.

<p align="center">
  <img src="docs/img/efeito.gif" alt="Demonstração: a pessoa é coberta por riscos verticais, pisca e some, ficando só o fundo; depois reaparece" width="640">
</p>

## Início rápido

```bash
git clone https://github.com/mvtiburcio/teleporte-instantaneo.git
cd teleporte-instantaneo
./setup.sh      # instala tudo (uma vez)
./teleporte     # roda
```

Na chamada: câmera **OBS Virtual Camera**, microfone **BlackHole 2ch**. Na janela *teleporte*: **B** grava o fundo, **dois dedos na testa** some e volta.
Primeira vez? Siga também a [configuração única do OBS](#configuração-única-do-obs).

---

## Sumário

- [Início rápido](#início-rápido)
- [Como funciona](#como-funciona)
- [Requisitos](#requisitos)
- [Instalação](#instalação)
- [Configuração única do OBS](#configuração-única-do-obs)
- [Usando numa chamada](#usando-numa-chamada)
- [O gesto](#o-gesto)
- [As etapas do efeito](#as-etapas-do-efeito)
- [Atalhos](#atalhos)
- [Ajustes finos](#ajustes-finos)
- [Trocar o som](#trocar-o-som)
- [Solução de problemas](#solução-de-problemas)
- [Por dentro: problemas resolvidos](#por-dentro-problemas-resolvidos)
- [Estrutura do repositório](#estrutura-do-repositório)
- [Créditos e licença](#créditos-e-licença)

---

## Como funciona

<p align="center">
  <img src="docs/img/arquitetura.svg" alt="Diagrama: webcam e microfone entram no teleporte.py; o vídeo sai pela OBS Virtual Camera e o áudio pelo BlackHole 2ch, ambos indo para o Meet/WhatsApp" width="900">
</p>

1. **Vídeo** — o `teleporte.py` lê a sua webcam, procura o gesto com o **MediaPipe** (mão + rosto) e, quando dispara, recorta a sua silhueta e aplica o efeito. O resultado sai pela **OBS Virtual Camera**, que o Meet/WhatsApp enxerga como uma câmera normal.
2. **Áudio** — o Meet e o WhatsApp **cortam** o que sai do alto-falante (cancelamento de eco), então tocar o som no Mac não basta. O script vira o seu microfone: mistura o microfone de verdade com o som do teletransporte e manda tudo para o **BlackHole 2ch**, uma placa de som virtual que a chamada usa como microfone.
3. **Sumir** — enquanto você está "teleportado", a chamada recebe a **foto do fundo** que você gravou antes, então não sobra sombra nem contorno.

## Requisitos

| Item | Por quê |
|---|---|
| **macOS** (Apple Silicon ou Intel) | Câmera virtual do OBS e `afplay`/`afconvert` são do Mac |
| [**Homebrew**](https://brew.sh) | Instala o resto automaticamente |
| **Python 3.12** | O MediaPipe ainda não tem pacote para 3.13/3.14 (o `setup.sh` instala) |
| **OBS Studio** 30+ | Fornece a câmera virtual (o `setup.sh` instala) |
| **BlackHole 2ch** | Leva o som do teletransporte para a chamada (o `setup.sh` instala) |
| Webcam + microfone | Os do próprio Mac servem |

## Instalação

```bash
git clone https://github.com/mvtiburcio/teleporte-instantaneo.git
cd teleporte-instantaneo
./setup.sh
```

O `setup.sh` faz, nesta ordem:

1. Instala o **Python 3.12**, o **OBS** e o **BlackHole 2ch** via Homebrew (o BlackHole pede a sua senha de administrador).
2. Reinicia o serviço de áudio do Mac (`sudo killall coreaudiod`) para o BlackHole aparecer na lista de dispositivos — o som corta por ~2 segundos.
3. Cria o ambiente Python em `.venv/` e instala as dependências do `requirements.txt`.
4. Prepara o som: converte `sons/goku-teleport.mp3` em `sons/teleport.wav` cortando o silêncio do começo.

> **Atalho opcional:** para rodar de qualquer pasta digitando só `teleporte`, adicione um alias ao seu shell:
> ```bash
> echo "alias teleporte=\"$PWD/teleporte\"" >> ~/.zshrc && source ~/.zshrc
> ```

## Configuração única do OBS

Só precisa ser feita **uma vez**, para o macOS liberar a câmera virtual:

1. Abra o **OBS**. Se perguntar sobre fontes de vídeo vazias, clique em **Sim** — o script é quem manda a imagem, o OBS não precisa de cena.
2. Clique em **Iniciar câmera virtual**.
3. O macOS avisa que a extensão foi bloqueada. Vá em **Ajustes do Sistema → Geral → Itens de Início e Extensões → Extensões de Câmera** (ⓘ) e ative o **OBS Studio**. Digite sua senha.
4. Volte ao OBS: o botão vira **Interromper câmera virtual** — funcionou. Clique nele e **feche o OBS (⌘Q)**.

> O OBS precisa estar **fechado** quando você usa o teletransporte: só um programa pode alimentar a câmera virtual por vez.

Na primeira execução do `./teleporte`, o macOS também pede permissão de **Câmera** e **Microfone** para o Terminal. Permita. Se a permissão não aparecer, ative em **Ajustes do Sistema → Privacidade e Segurança → Câmera / Microfone → Terminal**.

## Usando numa chamada

### 1. Rodar

```bash
./teleporte
```

Deixe o Terminal aberto durante a chamada. Você deve ver:

```
Microfone 'AirPods Pro' + teleporte -> BlackHole. Na chamada, escolha o microfone 'BlackHole 2ch'.
Na chamada, escolha a câmera 'OBS Virtual Camera'.
Com a janela "teleporte" em foco, aperte B e, em 5 s, saia do quadro e da frente da luz (grava o fundo).
Dois dedos na testa = some / volta. R = voltar na hora, Q = sair.
```

Uma janela chamada **teleporte** abre com a prévia (espelhada, como um espelho).

### 2. Configurar a chamada

**Google Meet** — `⋮ → Configurações`:

| Aba | Opção | Valor |
|---|---|---|
| Vídeo | Câmera | **OBS Virtual Camera** |
| Vídeo | Resolução de envio | **Alta definição (720p)** |
| Áudio | Microfone | **BlackHole 2ch** |
| Áudio | Cancelamento de ruído | **Desligado** (senão o Meet pode cortar o som) |
| `⋮ → Aplicar efeitos visuais` | — | **Sem efeito** (o desfoque do Meet borra a imagem quando você some) |

**WhatsApp (app do Mac)** — na chamada de vídeo, no menu de câmera/microfone (`⋯` ou setinha ao lado do botão da câmera): câmera **OBS Virtual Camera**, microfone **BlackHole 2ch**.
Se o app não deixar escolher o microfone: **Ajustes do Sistema → Som → Entrada → BlackHole 2ch** *antes* de rodar o `./teleporte` — o script detecta isso e usa o primeiro microfone de verdade da lista. Depois da chamada, volte a entrada para o microfone normal.

> No **WhatsApp do celular não funciona**: a câmera é a do telefone, o script não tem acesso a ela.

**Zoom / Teams / outros** — mesmo esquema: câmera **OBS Virtual Camera**, microfone **BlackHole 2ch**, efeitos de fundo e supressão de ruído desligados.

### 3. Gravar o fundo

1. Clique na janela **teleporte** e aperte **B**.
2. Começa uma contagem de **5 segundos**. Saia do quadro **e da frente da luz** — se a sua sombra estiver na parede, ela entra na foto e fica lá quando você sumir.
3. Grave de novo (**B**) sempre que a luz do ambiente mudar.

### 4. Teleportar

- **Dois dedos na testa** por um instante (~0,25 s) → som + riscos → você some.
- **Dois dedos na testa de novo** → você reaparece com o mesmo efeito ao contrário. Pode ser de outro lugar do quarto, em pé, longe da câmera.

### 5. Depois da chamada

Aperte **Q** e volte o microfone da chamada para o normal — com o script fechado, o BlackHole fica mudo.

## O gesto

<p align="center">
  <img src="docs/img/gesto.svg" alt="Diagrama do gesto: dois dedos (indicador e médio) juntos tocando a testa; a área aceita é um círculo centrado na testa com raio proporcional à distância entre os olhos" width="720">
</p>

- A posição da testa é calculada a partir dos **olhos**: meio dos olhos, subindo 0,6× a distância entre eles.
- A tolerância também é proporcional a essa distância, então o gesto funciona **perto ou longe** da câmera.
- Se a mão esconder parte do rosto, o script usa a última posição do rosto vista por até 1 segundo.
- A **bolinha verde** no canto da janela *teleporte* mostra que o gesto foi reconhecido (ela não aparece na chamada).
- Depois de disparar, é preciso **tirar a mão** antes de disparar de novo — segurar o gesto não fica alternando.

## As etapas do efeito

<p align="center">
  <img src="docs/img/etapas.jpg" alt="Quatro quadros: 1 normal; 2 riscos verticais brancos e pretos com borrão vertical; 3 a pessoa piscando, quase transparente; 4 só o fundo" width="900">
</p>

O efeito dura **0,9 s** e acompanha o som:

1. **Normal** — a câmera passa direto.
2. **Riscos + borrão** — a sua silhueta (MediaPipe Selfie Segmentation) é esticada na vertical e coberta por riscos brancos e pretos, como no anime.
3. **Piscando** — você fica cada vez mais transparente, piscando entre o fundo e a sua imagem.
4. **Sumiu** — a chamada recebe só a foto do fundo, até você fazer o gesto de novo.

## Atalhos

Com a janela **teleporte** em foco:

| Tecla | Ação |
|---|---|
| `B` | Grava o fundo (com contagem de 5 s) |
| `R` | Reaparece na hora, sem efeito |
| `Q` | Fecha |

## Ajustes finos

Todos no começo do `teleporte.py`:

| Constante | Padrão | O que faz |
|---|---|---|
| `REACH` | `1.5` | Tolerância dos dedos até a testa. **Suba** (ex.: `2.0`) se o gesto não for reconhecido. |
| `HOLD_S` | `0.25` | Quanto tempo segurar o gesto para disparar. |
| `FX_S` | `0.9` | Duração do efeito. Combine com a duração do seu som. |
| `SOUND_LEAD` | `0.1` | Atraso entre o disparo e o começo do efeito (o *pré-roll* do som). |
| `GROW_PX` | `31` | Quanto a máscara cresce além do seu contorno. **Suba** se sobrar borda. |
| `BG_DELAY_S` | `5` | Contagem entre apertar **B** e gravar o fundo. |
| `SFX_GAIN` | `0.8` | Volume do som na chamada, em relação ao microfone. |

## Trocar o som

Qualquer áudio que o macOS abre (mp3, m4a, wav, aiff…):

```bash
.venv/bin/python tools/preparar_som.py ~/Downloads/meu-som.mp3
```

O script converte para `sons/teleport.wav`, **corta o silêncio do começo** (deixando 0,1 s, que casa com `SOUND_LEAD`) e o fim. Ajuste `FX_S` para a duração da parte mais forte do som.

## Solução de problemas

| Sintoma | Causa | Solução |
|---|---|---|
| A chamada mostra o **logo do OBS** com uma câmera riscada | Nada está alimentando a câmera virtual | Rode `./teleporte`. Se já estiver rodando, troque de câmera na chamada e volte. |
| `Câmera virtual indisponível` | O OBS está aberto usando a câmera virtual | Feche o OBS (⌘Q) e rode de novo. |
| `Webcam não encontrada` / `not authorized to capture video` | Sem permissão de câmera | Ajustes do Sistema → Privacidade e Segurança → Câmera → ative o Terminal. Feche e abra o Terminal. |
| `A câmera virtual não está instalada` (no OBS) | Extensão não aprovada | Veja [Configuração única do OBS](#configuração-única-do-obs). |
| Fica uma **sombra** quando você some | A sua sombra estava na parede quando o fundo foi gravado | Aperte **B** e saia também da frente da luz. |
| Sobra um **contorno** em volta de você no efeito | Máscara apertada | Suba `GROW_PX` (41, 51…). |
| O gesto **não é reconhecido** | Tolerância baixa, mão longe ou rosto escondido | Suba `REACH`; deixe os olhos visíveis; confira a bolinha verde. |
| Imagem **borrada** na chamada | Desfoque de fundo da própria chamada | Desligue os efeitos visuais do Meet/Zoom/Teams. |
| A chamada **não ouve** o som | Microfone errado ou supressão de ruído | Microfone **BlackHole 2ch**; desligue o cancelamento de ruído. |
| `BlackHole não instalado` mesmo após instalar | O CoreAudio não recarregou | `sudo killall coreaudiod` ou reinicie o Mac. |
| `PaMacCore ... err='-50'` no Terminal | Aviso do driver ao abrir o BlackHole | Pode ignorar — o áudio passa certo (o `./teleporte` já esconde). |

## Por dentro: problemas resolvidos

Coisas não óbvias que apareceram no caminho e já estão tratadas no código:

- **A câmera virtual "rouba" o índice 0.** Quando a OBS Virtual Camera está ativa, ela entra na lista de câmeras do OpenCV e a webcam muda de índice. O `open_webcam()` manda uma imagem magenta para a câmera virtual e fica com a primeira câmera que devolve **outra** coisa.
- **Microfone + BlackHole num fluxo só devolve lixo (`NaN`).** São dois dispositivos com relógios diferentes. A solução foram dois fluxos (`InputStream` do microfone e `OutputStream` do BlackHole) ligados por uma fila curta, que descarta blocos antigos para o atraso não crescer.
- **BlackHole a 48 kHz.** Com outra taxa, o CoreAudio reclama; o som é reamostrado para 48 kHz ao carregar.
- **Desempenho.** Mão + rosto custam ~25 ms por frame no M2; a detecção roda a cada 2 frames para manter 30 fps. A segmentação da silhueta só roda durante o efeito.
- **Sumir = imagem inteira do fundo.** Trocar só a área da pessoa deixava sombra e diferença de exposição; enquanto você está sumido, sai a foto do fundo inteira.
- **Silêncio no começo do MP3.** O som original tem 0,7 s de silêncio; o `preparar_som.py` corta, e o efeito sai praticamente junto com o gesto.

## App para Mac (em desenvolvimento)

Interface em SwiftUI que substitui o terminal (spec em `docs/superpowers/specs/2026-10-24-app-macos-design.md`). Para rodar a partir do código (macOS 26+, Xcode e `brew install xcodegen`):

```bash
./setup.sh                      # o app usa o .venv do motor
cd app && xcodegen generate && open Teleporte.xcodeproj
```

Opcional: crie `app/Local.xcconfig` com `CODE_SIGN_IDENTITY` e `DEVELOPMENT_TEAM` da sua conta Apple, para o macOS lembrar a permissão de câmera entre builds.

## Estrutura do repositório

```
teleporte-instantaneo/
├── teleporte.py           # o programa: gesto, efeito, câmera virtual e mixer de áudio (--ipc = modo app)
├── ipc.py                 # ponte com o app: frames em memória compartilhada + comandos JSON
├── app/                   # app SwiftUI (gera o projeto com xcodegen)
├── tests/                 # unittest: .venv/bin/python -m unittest discover -s tests
├── teleporte              # lançador (esconde os logs internos do MediaPipe/CoreAudio)
├── setup.sh               # instala tudo
├── requirements.txt       # dependências Python fixadas
├── sons/
│   └── goku-teleport.mp3  # som original (o teleport.wav é gerado a partir dele)
├── tools/
│   ├── preparar_som.py    # converte qualquer áudio e corta o silêncio
│   └── gerar_demo.py      # gera o GIF e as imagens deste README (com o rosto pixelado)
└── docs/img/              # imagens do README
```

Para regenerar as imagens do README com a sua webcam (o rosto é pixelado antes de salvar):

```bash
.venv/bin/python tools/gerar_demo.py
```

## Créditos e licença

- Código sob a [licença MIT](LICENSE).
- Feito com [MediaPipe](https://github.com/google-ai-edge/mediapipe), [OpenCV](https://opencv.org), [pyvirtualcam](https://github.com/letmaik/pyvirtualcam), [python-sounddevice](https://github.com/spatialaudio/python-sounddevice), [OBS Studio](https://obsproject.com) e [BlackHole](https://github.com/ExistentialAudio/BlackHole).
- *Dragon Ball* e o efeito sonoro do Teletransporte Instantâneo pertencem aos seus detentores (Akira Toriyama / Toei Animation). Este é um projeto de fã, sem fins lucrativos e sem afiliação. O áudio **não** está coberto pela licença MIT — se você é detentor dos direitos e quer a remoção, abra uma issue.
