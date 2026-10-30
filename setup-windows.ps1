[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Python = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
$Sound = Join-Path $ProjectRoot "sons\teleport.wav"

Push-Location $ProjectRoot
try {
    if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
        throw "Python Launcher nao encontrado. Instale o Python 3.12 com: winget install -e --id Python.Python.3.12"
    }

    & py -3.12 -c "import sys; print(sys.version)"
    if ($LASTEXITCODE -ne 0) {
        throw "Python 3.12 nao encontrado. Instale com: winget install -e --id Python.Python.3.12"
    }

    if (Test-Path -LiteralPath $Python) {
        & $Python -c "import sys; raise SystemExit(0 if sys.version_info[:2] == (3, 12) else 1)"
        if ($LASTEXITCODE -ne 0) {
            throw "O ambiente .venv existente nao usa Python 3.12. Renomeie ou remova a pasta .venv e rode este setup novamente."
        }
    }
    else {
        & py -3.12 -m venv .venv
        if ($LASTEXITCODE -ne 0) { throw "Nao foi possivel criar o ambiente .venv." }
    }

    & $Python -m pip install --upgrade pip
    if ($LASTEXITCODE -ne 0) { throw "Falha ao atualizar o pip." }
    & $Python -m pip install -r requirements.txt -r windows\requirements.txt
    if ($LASTEXITCODE -ne 0) { throw "Falha ao instalar as dependencias." }

    if (-not (Test-Path -LiteralPath $Sound)) {
        if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
            throw "FFmpeg nao encontrado. Instale com 'winget install -e --id Gyan.FFmpeg', abra outro PowerShell e rode este setup novamente."
        }
        & $Python tools\preparar_som.py
        if ($LASTEXITCODE -ne 0) { throw "Falha ao preparar o som do efeito." }
    }

    Write-Host ""
    Write-Host "Ilusio pronto para desenvolvimento no Windows." -ForegroundColor Green
    Write-Host "Execute: .\ilusio-windows.ps1"
    Write-Host "O checklist do app orienta a instalacao do OBS Virtual Camera e do VB-Cable."
}
finally {
    Pop-Location
}
