# Ilusio para Windows — design

Data: 2026-10-24. Status: aprovado pelo usuário ("seguir tudo como fizemos no Mac").

## Objetivo

Levar o Ilusio para o Windows com a mesma experiência do app de Mac: baixar um instalador, abrir e seguir o tour e o checklist até o efeito funcionar na chamada (Meet, Zoom, Teams, WhatsApp). Sem assinatura de código, por decisão do usuário.

## Decisões

| Tema | Decisão |
|---|---|
| Interface | Python + PySide6 (Qt 6), tema próprio no estilo Fluent do Windows 11, claro/escuro seguindo o sistema; sem bibliotecas GPL |
| Processo | Um processo só: a interface importa o motor (`teleporte.py`) como módulo; sem memória compartilhada nem JSON entre processos |
| Sistema | Windows 11 x64 (câmera própria); Windows 10 x64 funciona com a OBS Virtual Camera como alternativa |
| Câmera virtual | **Ilusio Camera** própria: DLL C++ (media source do Media Foundation) registrada como COM e criada com `MFCreateVirtualCamera`; o app entrega os frames por um mapeamento de memória nomeado. Sem driver, sem assinatura obrigatória |
| Microfone virtual | **VB-Cable** (gratuito, instalado à parte, guiado pelo checklist). Microfone próprio exige driver de kernel assinado pela Microsoft (certificado EV + atestação no Partner Center): fica no roadmap, condicionado ao certificado |
| Som local | `winsound` (stdlib) no lugar do `afplay` |
| Atalhos globais | `RegisterHotKey` da API do Windows (via `ctypes`), padrões **Ctrl+Alt+Shift+T/L/B/R**: Ctrl+Alt sozinho é o AltGr do teclado ABNT2 (roubaria caracteres) e Ctrl+Shift+T é "reabrir aba" nos navegadores |
| Distribuição | Instalador `Ilusio-Setup-<versão>.exe` (Inno Setup), sem assinatura: instala, registra a Ilusio Camera (UAC uma vez), cria atalho no menu Iniciar. Um `.exe` de arquivo único foi descartado: descompactaria ~250 MB a cada abertura |
| Build | GitHub Actions `windows-latest`: testes do motor, DLL da câmera (MSVC), app (PyInstaller `--onedir`), instalador; anexado à mesma release do `.dmg` |
| Teste real | PC com Windows do usuário |

### SmartScreen

Sem assinatura, o Windows mostra "O Windows protegeu o computador" no primeiro uso do instalador. O README e a página de release explicam: **Mais informações → Executar assim mesmo**. A reputação do SmartScreen melhora com downloads; a solução definitiva é assinar (fora do escopo).

## Paridade com o Mac

| Mac | Windows |
|---|---|
| Tour de 4 passos (opção B) | Igual |
| Checklist de 7 itens | Igual; item 3 = Ilusio Camera (Win 11) ou OBS (Win 10); item 4 = VB-Cable ("CABLE Input/Output") |
| Abas Início, Câmera e mic, Configuração, Atalhos, Apoiar, Ajustes | Iguais |
| Câmera padrão do computador, iPhone/USB só por escolha | Câmera integrada como padrão; USB por escolha |
| fps 15/30/60 com aviso do limite da câmera | Igual |
| Pix estático (BR Code) e QR | Igual (mesmo payload, `…63048C40`) |
| Atualização da câmera própria na abertura | Igual (re-registro quando a versão da DLL muda) |

## Arquitetura

```
Ilusio.exe (PySide6)
 ├─ captura: OpenCV/MSMF pela câmera escolhida (índice resolvido pelo nome via enumeração do DirectShow/MSMF)
 ├─ motor: Engine(teleporte) em thread própria: gesto, efeito, mixer de áudio → VB-Cable
 ├─ prévia: QImage a ~15 fps
 └─ saída de vídeo:
     ├─ Windows 11: mapeamento nomeado "Global\IlusioCameraFrames" (mesmo layout/seqlock do frames.shm)
     │                ← criado pela IlusioCamera.dll, que roda no Frame Server (LOCAL SERVICE, sessão 0)
     │                → chamada
     └─ Windows 10: pyvirtualcam (OBS)
```

**Mapeamento dos frames:** a DLL roda no Frame Server, numa sessão diferente da do app, então `Local\` não serve. Quem cria o `Global\IlusioCameraFrames` é a DLL (o serviço tem `SeCreateGlobalPrivilege`; um usuário comum não), com DACL de leitura e escrita para usuários interativos. O app só abre o mapeamento e, se a câmera ainda não existir, tenta de novo a cada segundo. Sem frames novos há mais de 0,5 s, a DLL mostra o placeholder "Abra o Ilusio".

**Câmeras virtuais fora da captura:** "Ilusio Camera" e "OBS Virtual Camera" aparecem na lista do Media Foundation/DirectShow, mas nunca são oferecidas como fonte nem viram padrão (o mesmo cuidado do `Devices.virtualNames` do Mac), para o app não realimentar a própria saída.

O motor ganha a classe `Engine` (start/stop/comandos/eventos por callback), reaproveitada pelo `run_ipc` do Mac, sem mudar o protocolo `--ipc`.

## Sequência de PRs

1. **Motor portável + CI Windows:** `winsound` no lugar do `afplay`, `preparar_som.py` com ffmpeg quando não houver `afconvert`, saídas virtuais incluindo VB-Cable, workflow `windows.yml` rodando os testes do motor no Windows.
2. **App PySide6 — base:** janela, tema Fluent, Início com prévia e controles, captura, motor em thread, câmera escolhida.
3. **App PySide6 — abas:** Câmera e mic, Atalhos (`RegisterHotKey`), Apoiar (Pix), Ajustes (tema), tour e checklist.
4. **Instalador + release no CI:** PyInstaller `--onedir`, Inno Setup, upload na release.
5. **Ilusio Camera para Windows 11:** DLL C++ (media source), registro, `MFCreateVirtualCamera`, frames pelo mapeamento nomeado, placeholder "Abra o Ilusio".

Antes do PR 2, mockup do visual para aprovação do usuário.

## Testes

- Motor: a mesma suíte (`unittest`) no `windows-latest`.
- App: testes de unidade das partes puras (Pix, escolha de câmera/fps, atalhos, checklist) com `unittest` + PySide6 offscreen no CI.
- Câmera: teste no CI que registra a DLL, cria a câmera e confere que o Media Foundation a lista; validação final no PC do usuário (Meet e WhatsApp).

## Fora do escopo

Assinatura de código, microfone próprio (até haver certificado EV), Windows ARM, Windows anterior ao 10, loja da Microsoft, atualização automática.
