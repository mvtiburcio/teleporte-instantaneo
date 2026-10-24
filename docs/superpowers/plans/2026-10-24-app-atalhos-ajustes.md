# App: atalhos globais e Ajustes com tema (PR 2c) — plano

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** atalhos de teclado globais configuráveis (funcionam com a chamada em primeiro plano) e aba Ajustes com tema Sistema/Claro/Escuro.

**Spec:** `docs/superpowers/specs/2026-10-24-app-macos-design.md` (tela Atalhos); tema pedido pelo usuário em 2026-10-24.

## Global Constraints

- `RegisterEventHotKey` (Carbon) com assinatura `TLPT`: global, sem permissão de Acessibilidade.
- Padrões: `⌃⌥T` some/volta, `⌃⌥L` liga/desliga, `⌃⌥B` grava o fundo, `⌃⌥R` reaparece.
- Combinação precisa ter ⌃ ou ⌘ (o macOS 15+ não entrega atalho global só com ⌥/⇧); a mesma combinação não pode estar em duas ações.
- Falha no registro → aviso na linha do atalho e o anterior continua.
- Persistência em `UserDefaults` (`hotkey.<ação>` em JSON; `theme`).
- Tema aplicado via `NSApp.appearance` (nil = sistema), que volta para o sistema sem reiniciar.

---

### Task 1: `Shortcuts.swift` — `KeyCombo`, `ShortcutAction`, `HotKeyCenter`

**Produces:** `KeyCombo {keyCode, modifiers (Carbon), key}` Codable com `description` ("⌃⌥T") e `init?(event: NSEvent)` (nil sem ⌃/⌘); `ShortcutAction: CaseIterable` (`toggle`, `power`, `background`, `reappear`) com `title` e `defaultCombo`; `ShortcutAction.conflict(for:with:in:)`; `HotKeyCenter.shared.register(_:combo:action:) -> Bool`.

- [ ] Testes (`ShortcutsTests`): descrição na ordem ⌃⌥⇧⌘; conversão de modificadores do NSEvent; ida e volta JSON; conflito detectado entre ações e ignorado na própria; padrões sem conflito entre si.
- [ ] Implementação; commit `feat(app): atalhos globais com RegisterEventHotKey`.

### Task 2: aba Atalhos + ligação no `AppModel`

**Produces:** `AppModel.shortcuts`, `shortcutFailures`, `setShortcut(_:_:) -> String?` (erro para a interface), `registerShortcuts()` chamado no `init`; `ShortcutsView` com `KeyRecorder` (clique → "Pressione a combinação…", Esc cancela) e "Restaurar padrões".

- [ ] Implementação + testes passando; commit `feat(app): aba Atalhos com gravador de combinação`.

### Task 3: aba Ajustes (tema)

**Produces:** `AppTheme` (`system`, `light`, `dark`) com `appearance: NSAppearance?`; `SettingsView` (tema segmentado, abrir pasta de logs, versão); aplicado no `onAppear` e ao trocar.

- [ ] Implementação + smoke manual (atalho com o Meet em foco; troca de tema ao vivo); commit `feat(app): aba Ajustes com tema do app`.
