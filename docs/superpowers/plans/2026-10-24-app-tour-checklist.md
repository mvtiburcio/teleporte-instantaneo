# App: tour de primeiro acesso e checklist da Configuração (PR 2d) — plano

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** quem nunca mexeu com câmera virtual consegue deixar tudo funcionando sozinho: tour na primeira abertura (opção B do brainstorming: janela inteira, ilustração à esquerda, passos à direita) que termina no checklist de 7 itens da spec.

**Spec:** `docs/superpowers/specs/2026-10-24-app-macos-design.md` (tela Configuração); tour pedido pelo usuário em 2026-10-24.

## Global Constraints

- Tour só na primeira abertura (`UserDefaults` `onboarded`); "Rever o tour" em Ajustes.
- Itens que se conferem sozinhos: permissões (`authorizationStatus`), câmera virtual (OBS instalado + "OBS Virtual Camera"/"Teleporte Camera" na descoberta), som virtual ("BlackHole"/"Teleporte Mic"), fundo gravado e gesto reconhecido (eventos do motor, guardados de uma vez). O item do app de chamada é marcado à mão.
- Verificação a cada 2 s e quando o app volta ao primeiro plano; progresso `n/7` como badge na barra lateral.
- Instruções por app de chamada: Meet, Zoom, Teams e WhatsApp.

---

### Task 1: `SetupChecks` + progresso no `AppModel`

- [ ] Teste `SetupTests`: `SetupChecks.doneCount` conta 0 com tudo falso, 7 com tudo verdadeiro, e `firstPending` aponta o primeiro item pendente na ordem do checklist.
- [ ] `SetupChecks` (struct com os 7 booleanos + `current(bg:gesture:callApp:)`), `SetupItem` (enum ordenado); `AppModel.checks`, `refreshChecks()`, flags persistidas `setup.bg`, `setup.gesture`, `setup.callApp`, evento `gesture_seen`.
- [ ] Commit `feat(app): verificação automática dos itens de configuração`.

### Task 2: aba Configuração

- [ ] `SetupView`: barra de progresso, um cartão por item (verde quando pronto), o item atual expandido com o passo a passo e o botão que resolve (pedir permissão / abrir Ajustes do Sistema, baixar ou abrir o OBS, baixar o BlackHole, ir ao Início), abas Meet/Zoom/Teams/WhatsApp no item 7.
- [ ] Badge `n/7` na barra lateral.
- [ ] Commit `feat(app): aba Configuração com checklist guiado`.

### Task 3: tour

- [ ] `OnboardingView`: 4 passos (o que é, como funciona, o gesto, vamos preparar), ilustração com SF Symbol animado à esquerda, texto + lista de passos à direita, Pular/Voltar/Continuar; o último abre a Configuração.
- [ ] `ContentView` mostra o tour enquanto `onboarded` é falso; Ajustes ganha "Rever o tour".
- [ ] Commit `feat(app): tour de primeiro acesso`.
