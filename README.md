# ReparoSistema

Scripts locais para diagnóstico e reparação controlada de computadores Windows e Ubuntu.

## Componentes

- [Documentação Windows](ReparoSistema/Windows/README.md)
- [Documentação Ubuntu](ReparoSistema/Linux/README.md)
- [Script Windows](ReparoSistema/Windows/ReparoSistema-Windows.ps1) — versão `1.1.0`
- [Atalho remoto Windows](windows.ps1) — execução direta pela URL curta
- [Script Ubuntu](ReparoSistema/Linux/reparo-sistema-linux.sh) — versão `1.0.0`
- [Modelo de sudoers](ReparoSistema/Linux/sudoers-reparo-sistema.example)

## Princípios operacionais

- execução local e semanal;
- log Markdown identificado por computador e data/hora;
- sem retenção automática de logs;
- sem limpeza de registro ou exclusão de arquivos de usuário;
- sem reinicialização forçada durante uma sessão interativa;
- códigos de saída adequados para o Agendador de Tarefas e `cron`.

## Status

Os logs usam `OK`, `FALHA`, `ALERTA` e `CORRIGIDO` quando aplicável. O resultado deve ser interpretado pela saída detalhada dos comandos, não apenas pelo código geral.

## Validação realizada

O script Windows foi executado nesta máquina em modo real, incluindo DISM, SFC, Windows Update, otimização e CHKDSK. O resultado foi `OK`, sem falhas e sem reinicialização pendente. A execução levou aproximadamente 36 minutos.

Antes da distribuição, testar primeiro em uma máquina representativa de cada sistema operacional.

## Execução rápida do Windows

Em PowerShell como Administrador:

```powershell
irm https://raw.githubusercontent.com/cidhorta/reparo-sistema/main/windows.ps1 | iex
```

Para validar o acesso remoto sem executar reparos:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/cidhorta/reparo-sistema/main/windows.ps1))) -Simulation
```
