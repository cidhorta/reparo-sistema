# ReparoSistema Ubuntu — versão 1.0.0

## Objetivo

Executar semanalmente manutenção controlada em Ubuntu, com log Markdown local e uso de `sudo` somente nas ações autorizadas.

## Pré-requisitos

- Ubuntu com Bash;
- usuário de manutenção autorizado;
- `sudo` configurado sem senha apenas para os comandos aprovados;
- diretório `/var/log/reparo-sistema/` gravável pelo script ou execução com preparação administrativa;
- janela de manutenção para atualizações de pacotes.

## O que o script executa

1. inventário de espaço em disco;
2. resumo de memória;
3. `apt-get update`;
4. `apt-get -y upgrade`;
5. `dpkg --configure -a`;
6. `apt-get -f install -y`;
7. `apt-get autoremove -y`;
8. `apt-get clean`;
9. serviços com falha;
10. erros recentes do journal;
11. verificação de reinicialização pendente.

O script não executa verificação offline de sistema de arquivos. Para isso, usar uma janela separada com a unidade desmontada ou o modo de recuperação.

## Configuração segura do sudo

1. revisar o arquivo [sudoers-reparo-sistema.example](sudoers-reparo-sistema.example);
2. confirmar os caminhos dos binários com `command -v`;
3. criar o grupo de manutenção;
4. instalar a regra em `/etc/sudoers.d/reparo-sistema`;
5. validar com `sudo visudo -f /etc/sudoers.d/reparo-sistema`.

Exemplo:

```bash
sudo groupadd --system reparo  # se ainda não existir
sudo usermod -aG reparo usuario-manut
sudo install -o root -g root -m 0440 sudoers-reparo-sistema.example /etc/sudoers.d/reparo-sistema
sudo visudo -cf /etc/sudoers.d/reparo-sistema
```

Não liberar `sudo bash`, `sudo sh`, `sudo python`, `sudo find` ou binários inteiros com argumentos livres.

## Execução manual

```bash
sudo install -d -m 0750 -o usuario-manut -g usuario-manut /var/log/reparo-sistema
chmod 0750 ./reparo-sistema-linux.sh
./reparo-sistema-linux.sh
```

O uso de `sudo` no comando de criação/preparação não significa executar o script inteiro como root. O script chama `sudo -n` somente nas etapas autorizadas.

## Simulação

```bash
./reparo-sistema-linux.sh --simulate --log-root=/tmp/reparo-sistema-teste
./reparo-sistema-linux.sh --simulate --simulate-reboot --log-root=/tmp/reparo-sistema-teste
```

## Agendamento semanal com cron

Para agendar no domingo às 03:00, por exemplo:

```cron
0 3 * * 0 /opt/reparo-sistema/reparo-sistema-linux.sh >> /var/log/reparo-sistema/cron-wrapper.log 2>&1
```

O `cron` deve pertencer ao usuário de manutenção. A regra de `sudoers` precisa permitir `sudo -n`; se exigir senha, as etapas privilegiadas serão registradas como falha.

## Códigos de saída

| Código | Significado |
|---:|---|
| 0 | execução concluída sem falhas e sem reinicialização pendente |
| 1 | uma ou mais etapas falharam |
| 2 | outra execução já está em andamento |
| 10 | reinicialização pendente, sem falha de etapa |
| 64 | argumento inválido |

## Leitura do log

Os logs ficam em `/var/log/reparo-sistema/` com o formato `HOST_YYYYMMDD-HHMMSS.md`. Cada relatório contém cabeçalho, ações, reinicialização, resumo e problemas resolvidos/pendentes.

## Segurança e limitações

- testar primeiro em uma máquina piloto;
- revisar atualizações antes de distribuir para todos os computadores;
- não liberar comandos administrativos adicionais sem análise;
- não executar o script simultaneamente com outra rotina de `apt`;
- retenção e remoção dos logs são manuais;
- a reinicialização só ocorre automaticamente quando não há usuário conectado e o comando autorizado foi aceito pelo `sudo`.
