# ReparoSistema Windows — versão 1.1.0

## Objetivo

Executar semanalmente diagnóstico e reparações conservadoras no Windows 10/11, gerando um relatório Markdown local.

## Pré-requisitos

- Windows PowerShell 5.1 ou PowerShell 7;
- execução elevada como Administrador;
- espaço suficiente em `C:\ReparoSistema\Logs\`;
- usuário autorizado a executar reparações do sistema;
- recomenda-se janela de manutenção, principalmente para DISM, SFC e CHKDSK.

## O que o script executa

1. inventário de espaço em disco;
2. limpeza de arquivos temporários com mais de sete dias;
3. `DISM /Online /Cleanup-Image /RestoreHealth`;
4. `sfc /scannow`;
5. acionamento de verificação e instalação do Windows Update;
6. otimização de volumes fixos;
7. `chkdsk <unidade>: /scan` em volumes NTFS;
8. verificação dos serviços `wuauserv`, `BITS` e `cryptsvc`;
9. identificação de reinicialização pendente.

O CHKDSK usa somente `/scan`: não desmonta volumes e não agenda reparo offline. Para uma correção com `/f`, abrir uma ação de manutenção separada e aprovada.

## Execução manual

Exemplo de instalação local:

```powershell
New-Item -ItemType Directory -Path 'C:\ReparoSistema\Windows' -Force | Out-Null
Copy-Item '.\ReparoSistema-Windows.ps1' 'C:\ReparoSistema\Windows\ReparoSistema-Windows.ps1'
```

Abra PowerShell como Administrador:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
& 'C:\Caminho\ReparoSistema-Windows.ps1'
```

## Execução direta a partir do GitHub

URL curta recomendada:

```powershell
irm https://raw.githubusercontent.com/cidhorta/reparo-sistema/main/windows.ps1 | iex
```

Forma direta, adequada apenas quando a versão publicada já foi revisada:

```powershell
irm https://raw.githubusercontent.com/cidhorta/reparo-sistema/main/windows.ps1 | iex
```

Esse comando é equivalente a baixar o script e executá-lo imediatamente. Deve ser usado em PowerShell aberto como Administrador.

Forma recomendada, permitindo inspeção antes da execução:

```powershell
$script = Join-Path $env:TEMP 'ReparoSistema-Windows.ps1'
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/cidhorta/reparo-sistema/main/ReparoSistema/Windows/ReparoSistema-Windows.ps1' -OutFile $script
Get-Content -LiteralPath $script
& $script
```

Para uma execução de simulação baixada do GitHub:

```powershell
& $script -Simulation
```

Em ambientes corporativos, prefira validar a versão por commit/hash ou distribuir o arquivo por uma ferramenta de gerenciamento. Não execute `irm | iex` de URLs não revisadas.

Por padrão, o log é gravado em:

```text
C:\ReparoSistema\Logs\NOME_DO_COMPUTADOR_YYYYMMDD-HHMMSS.md
```

Para escolher outro diretório durante teste:

```powershell
& '.\ReparoSistema-Windows.ps1' -LogRoot 'C:\Temp\ReparoSistema-Teste'
```

## Simulação

A simulação percorre todas as etapas, mas não executa os comandos de reparo:

```powershell
& '.\ReparoSistema-Windows.ps1' -Simulation
```

Para simular reinicialização pendente:

```powershell
& '.\ReparoSistema-Windows.ps1' -Simulation -SimulateRebootPending
```

## Agendamento semanal

No Agendador de Tarefas:

1. criar uma tarefa, não uma tarefa básica;
2. selecionar “Executar estando o usuário conectado ou não”;
3. marcar “Executar com privilégios mais altos”;
4. definir disparador semanal;
5. configurar ação `pwsh.exe` ou `powershell.exe`;
6. usar estes argumentos:

```text
-NoProfile -ExecutionPolicy Bypass -File "C:\ReparoSistema\ReparoSistema-Windows.ps1"
```

Se o arquivo foi instalado conforme o exemplo, use:

```text
-NoProfile -ExecutionPolicy Bypass -File "C:\ReparoSistema\Windows\ReparoSistema-Windows.ps1"
```

7. configurar “não iniciar uma nova instância” se a tarefa já estiver em execução.

Se houver usuário conectado e uma reinicialização for necessária, o script mostra aviso e não reinicia. Sem usuário conectado, a reinicialização automática ocorrerá somente depois de o resumo ser gravado.

## Códigos de saída

| Código | Significado |
|---:|---|
| 0 | execução concluída sem falhas e sem reinicialização pendente |
| 1 | uma ou mais etapas falharam |
| 2 | outra execução já está em andamento |
| 10 | reinicialização pendente, sem falha de etapa |

## Leitura do log

O relatório possui cabeçalho, execução detalhada, seção de reinicialização, resumo, problemas resolvidos e problemas a resolver. A saída bruta do DISM, SFC e CHKDSK é preservada, com remoção de caracteres NUL para manter o Markdown analisável.

## Segurança e limitações

- não usar em produção sem testar em uma máquina piloto;
- não incluir `/f`, `/r`, `/x` ou `/offlinescanandfix` no agendamento semanal;
- revisar o log quando houver `FALHA` ou `ALERTA`;
- o código `0` do Windows Update indica que o comando foi aceito, não que uma atualização específica foi instalada;
- o script não faz backup nem rollback de arquivos pessoais.
