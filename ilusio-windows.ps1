[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$AppArgs
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Python = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
$Sound = Join-Path $ProjectRoot "sons\teleport.wav"

if (-not (Test-Path -LiteralPath $Python) -or -not (Test-Path -LiteralPath $Sound)) {
    throw "Ambiente incompleto. Rode .\setup-windows.ps1 primeiro."
}

$OldPythonPath = $env:PYTHONPATH
$env:PYTHONPATH = "$ProjectRoot;$ProjectRoot\windows"
try {
    & $Python -m ilusio_win @AppArgs
    exit $LASTEXITCODE
}
finally {
    $env:PYTHONPATH = $OldPythonPath
}
