# App macOS do Teleporte — design

Data: 2026-10-24. Status: aprovado no brainstorming.

> **Atualização (2026-10-24):** o app foi renomeado para **Ilusio** (bundle `com.mvtiburcio.ilusio`); o teletransporte virou o primeiro efeito. Os dispositivos próprios passam a se chamar "Ilusio Camera" e "Ilusio Mic". O restante do texto mantém os nomes originais.

## Objetivo

Transformar o script `teleporte.py` num app de Mac que qualquer pessoa usa sem terminal: escolhe câmera e microfone, testa, configura atalhos, segue um checklist até funcionar e, se quiser, doa via Pix. Distribuído como `.dmg` assinado com Developer ID e notarizado, publicado nas Releases do GitHub (fora da App Store).

## Decisões

| Tema | Decisão |
|---|---|
| Interface | SwiftUI, Liquid Glass nativo (`.glassEffect`), macOS 26+, só Apple Silicon |
| Layout | Janela com barra lateral: Início, Câmera e mic, Atalhos, Configuração (n/7), Apoiar |
| Motor | `teleporte.py` congelado com PyInstaller, roda como processo filho do app |
| Câmera virtual | v1 usa OBS Virtual Camera; depois, CoreMediaIO Camera Extension própria ("Teleporte Camera") |
| Microfone virtual | v1 usa BlackHole 2ch; depois, Audio Server Plug-in (HAL) próprio ("Teleporte Mic"), baseado na sample `NullAudio` da Apple |
| Doação | Pix estático (BR Code EMV) gerado no app, sem API, sem servidor, sem confirmação |
| Atalhos | Globais via `RegisterEventHotKey` (Carbon): funcionam com a chamada em foco, sem permissão de Acessibilidade |
| Projeto Xcode | Gerado por XcodeGen a partir de `app/project.yml` (o `.xcodeproj` não é versionado) |

### Por que a doação não usa a API da Orbit

`POST /v2/transactions/` exige `Authorization: Bearer {chave}`, e a mesma Chave de API faz saque (`/v1/pix/cashout/`) e consulta de saldo. Qualquer chave dentro de um app distribuído é extraível, então quem extraísse poderia sacar o saldo. O endpoint também exige `customer` com CPF e endereço, o que mata a doação rápida. O Pix estático usa só a chave Pix (pública por natureza) e aceita valor livre.

A chave Pix configurada deve ser uma **chave aleatória (EVP)** da conta Orbit, nunca CPF ou telefone: ela fica legível no QR e no binário.

## Arquitetura

```
┌──────────────── Teleporte.app (SwiftUI) ────────────────┐
│ AVCaptureSession (câmera escolhida por uniqueID)        │
│        │ BGRA 1280x720                                  │
│        ▼                                                │
│  frames.shm ──slot "in"──▶ motor (PyInstaller, --ipc)   │
│        ▲                     │ MediaPipe + efeito       │
│        └──────slot "out"─────┘ áudio: mic + som → saída │
│        │                       virtual (sounddevice)    │
│        ├─▶ prévia na janela                             │
│        └─▶ câmera virtual (OBS via motor no v1;         │
│            sink stream da Camera Extension depois)      │
│ stdin/stdout: JSON por linha (comandos e eventos)       │
└─────────────────────────────────────────────────────────┘
```

### Por que o app captura a câmera, e não o motor

A ordem dos índices do OpenCV não bate com a lista do AVFoundation, e a câmera virtual entra na lista e muda os índices (é o motivo da sonda com magenta de hoje). Capturando em Swift pelo `uniqueID`, a câmera escolhida na interface é exatamente a usada. A permissão de câmera também fica com o app.

### Memória compartilhada de frames

Um arquivo `frames.shm` em `~/Library/Application Support/Teleporte/`, mapeado com `mmap` pelos dois lados:

- Cabeçalho de 64 bytes: `magic "TLPT"`, `version u32`, `width u32`, `height u32`, `in_seq u64`, `out_seq u64`.
- Slot `in` e slot `out`, cada um com `width*height*4` bytes (BGRA).
- Seqlock por slot: quem escreve incrementa o `seq` para ímpar, copia o frame e incrementa para par. Quem lê descarta o frame se o `seq` for ímpar no início ou tiver mudado no fim da cópia. Frame novo = `seq` par diferente do último lido.
- Leitura por polling (1 ms). `ponytail:` polling simples; trocar por semáforo POSIX se o uso de CPU aparecer no perfil.

### Protocolo stdin/stdout (JSON por linha)

Comandos são `{"cmd": "<nome>", ...}` e eventos `{"event": "<nome>", ...}`.

App → motor:

| Comando | Campos |
|---|---|
| `start` | `shm`, `mic` (nome do dispositivo), `output` (nome da saída virtual; `null` = sem áudio), `gain`, `reach`, `vcam` (bool; envia também pra OBS Virtual Camera até o PR 3) |
| `capture_bg` | `delay_s` |
| `toggle` | dispara o teleporte, igual ao gesto |
| `reappear` | volta na hora, sem efeito |
| `set` | `gain`, `reach` (ajuste ao vivo) |
| `test_sound` | toca o som local e na saída virtual |
| `stop` | encerra limpo |

Motor → app:

| Evento | Campos |
|---|---|
| `ready` | `version` |
| `state` | `hidden`, `bg_ready`, `bg_countdown`, `gesture`, `fps` (no máximo 5 por segundo) |
| `gesture_seen` | primeira vez que o gesto completo foi reconhecido |
| `mic_level` | `rms` (no máximo 10 por segundo, para o medidor) |
| `error` | `code`, `msg` (ex.: `no_output_device`, `mic_failed`) |

Os logs vão para o stderr, que o app grava em `~/Library/Logs/Teleporte/engine.log`. O modo CLI atual (`./teleporte`, com janela do OpenCV e teclas B/R/Q) continua funcionando sem mudança de uso.

### Ciclo de vida do motor

O app sobe o motor ao ligar o teleporte e manda `stop` ao desligar ou sair. Se o motor morrer, o app mostra o erro, guarda o log e oferece "Tentar de novo". Só existe um motor por vez.

## Telas

- **Início:** prévia grande, botão "Ligar teleporte" e "Gravar fundo", status (câmera virtual, áudio, gesto). O botão "Some / Volta" faz o mesmo que o gesto.
- **Câmera e mic:** seletor de câmera (com prévia) e de microfone (com medidor de nível), botão "Testar som", sliders de volume do efeito (`gain`) e sensibilidade do gesto (`reach`).
- **Atalhos:** campo gravador por ação; ao clicar, captura a combinação. Padrões: `⌃⌥T` some/volta, `⌃⌥L` liga/desliga o teleporte, `⌃⌥B` grava o fundo, `⌃⌥R` reaparece. Se o `RegisterEventHotKey` falhar, mostra aviso e mantém o atalho anterior. Salvos em `UserDefaults`.
- **Configuração (checklist):** 7 itens, cada um se confere sozinho e tem um botão que resolve; o item atual abre com instruções.
  1. Permitir câmera — `AVCaptureDevice.authorizationStatus(for: .video)`.
  2. Permitir microfone — `authorizationStatus(for: .audio)`.
  3. Câmera virtual — v1: OBS instalado e dispositivo "OBS Virtual Camera" presente; depois: extensão ativada (`OSSystemExtensionRequest`) e "Teleporte Camera" presente.
  4. Som virtual — dispositivo "BlackHole 2ch" ou "Teleporte Mic" presente na lista do CoreAudio.
  5. Gravar o fundo — evento `state.bg_ready`.
  6. Testar o gesto — evento `gesture_seen`.
  7. Escolher no app de chamada — manual, com abas Meet / Zoom / Teams / WhatsApp mostrando onde clicar.
- **Apoiar:** um QR estático único, sem valor definido (quem paga escolhe o valor no banco), e o botão "Copiar Pix copia-e-cola". Recebedor no QR: "TELEPORTE INSTANTANEO". Depois de copiar, aparece "Obrigado!".

## Pix estático (BR Code)

Payload EMV montado no app: `00` formato "01"; `26` conta (`00` "br.gov.bcb.pix", `01` chave); `52` "0000"; `53` "986"; sem o campo `54` (valor livre); `58` "BR"; `59` nome (até 25, ASCII sem acento); `60` cidade (até 15); `62` (`05` txid "***"); `63` CRC16-CCITT-FALSE (poly 0x1021, init 0xFFFF) sobre tudo até `6304`, inclusive. Chave, nome e cidade vêm de build settings (`PIX_KEY`, `PIX_NAME`, `PIX_CITY`), não do código. QR gerado com `CIQRCodeGenerator` (nível M).

## Sequência de PRs

1. **Motor `--ipc`:** memória compartilhada de frames, protocolo stdin/stdout, entrada de frames pelo slot `in`; mantém pyvirtualcam e BlackHole.
2. **App SwiftUI:** XcodeGen, telas Início, Câmera e mic, Atalhos e Configuração, captura AVFoundation, motor em processo filho (rodando do `.venv` em desenvolvimento).
3. **Camera Extension própria:** substitui o OBS; o app entrega o slot `out` pelo sink stream.
4. **Plug-in HAL próprio:** substitui o BlackHole; o app instala em `/Library/Audio/Plug-Ins/HAL` com senha de admin uma vez e reinicia o `coreaudiod`.
5. **Apoiar (Pix):** gerador BR Code + tela.
6. **Release:** motor congelado (PyInstaller, `--collect-data mediapipe`) dentro do `.app`, hardened runtime, entitlements de câmera e microfone, `codesign` com Developer ID, `.dmg`, `notarytool` + `stapler`, em `scripts/release.sh`, que no fim publica o `.dmg` nas Releases do GitHub (`gh release create vX.Y.Z`). Sem App Store. Requer o certificado "Developer ID Application" no Keychain.

Até o PR 4, o checklist e o motor aceitam tanto os dispositivos próprios quanto OBS e BlackHole.

## Testes

- Motor: `tests/test_ipc.py` com ida e volta de frame pela memória compartilhada (seq, descarte de frame rasgado) e parsing dos comandos. Smoke test: subir `--ipc`, mandar frames sintéticos, receber `ready`/`state`, mandar `stop`.
- Pix: teste XCTest do CRC16 (vetor "123456789" → `29B1`) e do payload de exemplo do manual do BCB (chave `123e4567-e12b-12d1-a456-426655440000`, "Fulano de Tal", "BRASILIA", CRC `1D3D`).
- App: build com `xcodebuild` sem erros; validação manual do checklist numa conta de usuário limpa.
- Extensões: validação manual no Meet (câmera "Teleporte Camera" e microfone "Teleporte Mic").

## Fora do escopo

Intel, macOS anterior ao 26, Windows/Linux, confirmação de doação, atualização automática, câmera e microfone virtuais funcionando sem o app aberto.
