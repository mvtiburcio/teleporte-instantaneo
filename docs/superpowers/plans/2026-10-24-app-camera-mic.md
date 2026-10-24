# App: câmera escolhida, aba Câmera e mic e Início redesenhado (PR 2b) — plano

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** a câmera usada passa a ser escolha do usuário (padrão: a embutida do Mac, nunca o iPhone por Continuidade sozinho), com lista atualizada ao conectar/desconectar; aba "Câmera e mic" com microfone, nível, teste de som e ajustes finos; Início no layout A (status sobre a prévia).

**Spec:** `docs/superpowers/specs/2026-10-24-app-macos-design.md` (telas Início e Câmera e mic). Feedback do usuário em 2026-10-24: câmera trocava sozinha para o iPhone, indicadores feios, fps mal posicionado, janela pequena.

## Global Constraints

- Tudo do plano `2026-10-24-app-base.md` continua valendo.
- Dispositivos virtuais ("OBS Virtual Camera", "Teleporte Camera", "BlackHole", "Teleporte Mic") nunca aparecem como fonte.
- Escolhas persistem em `UserDefaults`: `cameraID`, `micName`, `gain` (0…1,5, padrão 0,8), `reach` (1,0…2,5, padrão 1,5).
- O microfone vai para o motor pelo nome (`start.mic`), que é o mesmo nome do CoreAudio que o PortAudio usa.

---

### Task 1: `Devices` (descoberta + escolha padrão)

**Files:** Create `app/Teleporte/Devices.swift`, `app/TeleporteTests/DevicesTests.swift`; Modify `app/Teleporte/CameraCapture.swift` (remove `cameras()`/`virtualNames`; `start` troca de câmera com a sessão rodando).

**Produces:** `Devices.Item {id, name, builtIn}`, `Devices.cameras()`, `Devices.microphones()`, `Devices.isVirtual(_:)`, `Devices.pick(_:saved:) -> Item?` (salva conectada → embutida → primeira).

- [ ] Testes: `pick` prefere a salva; sem salva, prefere a embutida mesmo com o iPhone primeiro na lista; salva desconectada cai na embutida; lista vazia → nil; `isVirtual` para os quatro nomes virtuais e falso para "FaceTime HD Camera".
- [ ] Implementação; `CameraCapture.start` remove entradas/saídas antigas antes de adicionar.
- [ ] Commit `feat(app): câmera padrão do Mac e descoberta de câmeras e microfones reais`.

### Task 2: `AppModel` com dispositivos e ajustes

**Files:** Modify `app/Teleporte/AppModel.swift`.

**Produces:** `cameras`, `microphones`, `cameraID`, `micName`, `gain`, `reach`, `micLevel`; `selectCamera(_:)` (troca ao vivo), `selectMic(_:) async` (religa o motor), observação de `AVCaptureDevice.wasConnected/wasDisconnectedNotification` (câmera em uso desconectada → volta para a padrão com aviso). `start` manda `mic`, `gain`, `reach`; `gain`/`reach` mandam `set` ao vivo; `mic_level` alimenta `micLevel`.

- [ ] Implementação + build + testes existentes passando.
- [ ] Commit `feat(app): escolha de câmera e microfone persistida e trocada ao vivo`.

### Task 3: Início layout A + aba Câmera e mic + janela

**Files:** Modify `app/Teleporte/HomeView.swift`, `app/Teleporte/ContentView.swift`, `app/Teleporte/TeleporteApp.swift`; Create `app/Teleporte/DevicesView.swift`.

- [ ] Prévia com cápsulas de vidro no canto superior esquerdo ("Ao vivo"/"Desligado", "Fundo pronto"/"Sem fundo"), fps discreto no superior direito, menu de câmera no inferior esquerdo, borda verde brilhante enquanto o gesto é reconhecido; sem a linha de status antiga.
- [ ] Aba "Câmera e mic" (`Form` agrupado): câmera, microfone ("Padrão do sistema" + reais), medidor de nível, "Testar som", sliders "Volume do efeito" e "Sensibilidade do gesto" (Exigente ↔ Fácil).
- [ ] Janela: `defaultSize` 1040×720, mínimo 900×620.
- [ ] Smoke manual com o usuário: iPhone ligado por perto não é escolhido sozinho; trocar câmera com o teleporte ligado; mic e nível; sliders.
- [ ] Commit `feat(app): Início com status sobre a prévia e aba Câmera e mic`.
