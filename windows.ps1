[CmdletBinding()]
param(
    [string]$LogRoot = 'C:\ReparoSistema\Logs',
    [int]$TempFileAgeDays = 7,
    [switch]$Simulation,
    [switch]$SimulateRebootPending
)

$ErrorActionPreference = 'Stop'
$scriptUri = 'https://raw.githubusercontent.com/cidhorta/reparo-sistema/main/ReparoSistema/Windows/ReparoSistema-Windows.ps1'
$downloadedScript = (Invoke-WebRequest -Uri $scriptUri -UseBasicParsing).Content
if ([string]::IsNullOrWhiteSpace($downloadedScript)) {
    throw 'Não foi possível baixar o script principal de reparo.'
}

$scriptBlock = [scriptblock]::Create($downloadedScript)
& $scriptBlock -LogRoot $LogRoot -TempFileAgeDays $TempFileAgeDays -Simulation:$Simulation -SimulateRebootPending:$SimulateRebootPending
exit $LASTEXITCODE
