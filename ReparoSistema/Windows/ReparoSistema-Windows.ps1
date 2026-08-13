[CmdletBinding()]
param(
    [string]$LogRoot = 'C:\ReparoSistema\Logs',
    [int]$TempFileAgeDays = 7,
    [switch]$Simulation,
    [switch]$SimulateRebootPending
)

$ErrorActionPreference = 'Continue'
$scriptVersion = '1.1.0'
$started = Get-Date
$computer = $env:COMPUTERNAME
$stamp = $started.ToString('yyyyMMdd-HHmmss')
New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
$logPath = Join-Path $LogRoot ("{0}_{1}.md" -f $computer,$stamp)
$lockPath = Join-Path $LogRoot ("{0}.lock" -f $computer)

try {
    $lock = [System.IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
} catch {
    Write-Host 'ReparoSistema: outra execução já está em andamento. Encerrando.'
    exit 2
}

$results = [System.Collections.Generic.List[object]]::new()
function Write-Log([string]$Text) {
    # Alguns binários nativos podem retornar texto com NULs embutidos no PowerShell 7.
    # Removê-los mantém o Markdown legível e preserva o conteúdo textual do diagnóstico.
    $cleanText = if ($null -eq $Text) { '' } else { $Text -replace "`0", '' }
    Add-Content -LiteralPath $logPath -Value $cleanText -Encoding UTF8
}
function Invoke-Step([string]$Name,[scriptblock]$Action) {
    $t = Get-Date
    try {
        if ($Simulation) {
            Write-Log '    SIMULAÇÃO: ação real não executada.'
            $results.Add([pscustomobject]@{Name=$Name;Status='OK';ExitCode=0;Time=(Get-Date)-$t})
            Write-Log "- **OK** - $Name (simulação)"
            return
        }
        $global:LASTEXITCODE = 0
        & $Action 2>&1 | ForEach-Object { Write-Log ("    " + $_.ToString()) }
        $code = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
        $status = if ($code -eq 0) { 'OK' } else { 'FALHA' }
        $results.Add([pscustomobject]@{Name=$Name;Status=$status;ExitCode=$code;Time=(Get-Date)-$t})
        Write-Log "- **$status** - $Name (código $code)"
    } catch {
        $results.Add([pscustomobject]@{Name=$Name;Status='FALHA';ExitCode=1;Time=(Get-Date)-$t})
        Write-Log "- **FALHA** - ${Name}: $($_.Exception.Message)"
    }
}
function Test-RebootPending {
    return ((Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
        (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
        ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations))
}

Write-Log "# ReparoSistema Windows"
Write-Log ""
Write-Log "## Cabeçalho"
Write-Log "- Computador: $computer"
Write-Log "- Sistema: $((Get-CimInstance Win32_OperatingSystem).Caption)"
Write-Log "- Versão: $((Get-CimInstance Win32_OperatingSystem).Version)"
Write-Log "- Usuário executor: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Log "- Versão do script: $scriptVersion"
Write-Log "- Início: $started"
Write-Log "- Modo: $(if ($Simulation) {'SIMULAÇÃO'} else {'PRODUÇÃO'})"
Write-Log ""
Write-Log "## Execução"

Invoke-Step 'Inventário de espaço em disco' {
    Get-PSDrive -PSProvider FileSystem | Where-Object {$_.Used -ne $null} | ForEach-Object {
        Write-Output ("$($_.Name): livre {0:N2} GB" -f ($_.Free/1GB))
    }
}
Invoke-Step 'Limpeza segura de temporários antigos' {
    $cutoff = (Get-Date).AddDays(-$TempFileAgeDays)
    @($env:TEMP, "$env:WINDIR\Temp") | ForEach-Object {
        if (Test-Path $_) { Get-ChildItem -LiteralPath $_ -Force -File -ErrorAction SilentlyContinue | Where-Object LastWriteTime -lt $cutoff | Remove-Item -Force -ErrorAction SilentlyContinue }
    }
}
Invoke-Step 'DISM RestoreHealth' { DISM.exe /Online /Cleanup-Image /RestoreHealth }
Invoke-Step 'SFC Scannow' { sfc.exe /scannow }
Invoke-Step 'Windows Update - iniciar verificação' { & "$env:WINDIR\System32\UsoClient.exe" StartScan }
Invoke-Step 'Windows Update - iniciar instalação' { & "$env:WINDIR\System32\UsoClient.exe" StartInstall }
Invoke-Step 'Otimização das unidades' { Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter } | ForEach-Object { Optimize-Volume -DriveLetter $_.DriveLetter -Verbose } }
Invoke-Step 'CHKDSK - verificação online dos volumes NTFS' {
    $chkdskFailures = [System.Collections.Generic.List[string]]::new()
    Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter -and $_.FileSystem -eq 'NTFS' } | ForEach-Object {
        Write-Output ("Volume {0}:" -f $_.DriveLetter)
        & chkdsk.exe ("{0}:" -f $_.DriveLetter) /scan
        if ($LASTEXITCODE -ne 0) {
            Write-Output ("CHKDSK retornou código {0}; verificar necessidade de reparo offline." -f $LASTEXITCODE)
            $chkdskFailures.Add(("{0}: (código {1})" -f $_.DriveLetter,$LASTEXITCODE))
        }
    }
    if ($chkdskFailures.Count -gt 0) {
        throw ("Falha na verificação CHKDSK: " + ($chkdskFailures -join ', '))
    }
}
Invoke-Step 'Verificação de serviços essenciais' {
    Get-Service -Name wuauserv,BITS,cryptsvc -ErrorAction SilentlyContinue | ForEach-Object { Write-Output ("{0}: {1}" -f $_.Name,$_.Status) }
}

$reboot = if ($Simulation) { [bool]$SimulateRebootPending } else { Test-RebootPending }
$interactive = [bool](Get-CimInstance Win32_ComputerSystem).UserName
$restartRequested = $false
Write-Log ""
Write-Log "## Reinicialização"
if ($reboot) {
    Write-Log '- **ALERTA** - Reinicialização necessária em até 24 horas.'
    if ($Simulation) {
        Write-Log '- Simulação: nenhuma reinicialização foi executada.'
    } elseif ($interactive) {
        try { msg.exe * 'OK - Este computador precisa ser reiniciado em até 24 horas.' | Out-Null } catch {}
        Write-Host 'OK - Reinicialização necessária em até 24 horas.'
    } else {
        Write-Log '- Usuário não conectado; reinicialização automática será executada após a gravação do resumo.'
        $restartRequested = $true
    }
} else { Write-Log '- **OK** - Nenhuma reinicialização pendente identificada.' }

$failed = @($results | Where-Object Status -eq 'FALHA').Count
$corrected = @($results | Where-Object Status -eq 'CORRIGIDO').Count
$overall = if ($failed -gt 0) {'FALHA'} elseif ($reboot) {'ALERTA'} else {'OK'}
Write-Log ""
Write-Log "## Resumo"
Write-Log "- Resultado geral: **$overall**"
Write-Log "- Itens executados: $($results.Count)"
Write-Log "- Falhas: $failed"
Write-Log "- Corrigidos: $corrected"
Write-Log "- Fim: $(Get-Date)"
Write-Log ""
Write-Log "## Problemas resolvidos"
Write-Log '- O log registra as ações executadas com sucesso; a confirmação técnica depende da saída de cada comando.'
Write-Log ""
Write-Log "## Problemas a resolver"
if ($failed -gt 0) {
    Write-Log "- Existem $failed etapa(s) com falha; consultar os detalhes acima."
} elseif ($reboot) {
    Write-Log '- Reinicialização pendente dentro do prazo de 24 horas.'
} else {
    Write-Log '- Nenhum problema pendente identificado pelo script.'
}

$lock.Close(); $lock.Dispose(); Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
if ($restartRequested) { Restart-Computer -Force }
if ($failed -gt 0) { exit 1 } elseif ($reboot) { exit 10 } else { exit 0 }
