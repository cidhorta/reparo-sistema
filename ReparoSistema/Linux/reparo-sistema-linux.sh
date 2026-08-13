#!/usr/bin/env bash
set -u

VERSION='1.0.0'
LOG_ROOT='/var/log/reparo-sistema'
SIMULATION=0
SIMULATE_REBOOT=0
for arg in "$@"; do
  case "$arg" in
    --simulate) SIMULATION=1 ;;
    --simulate-reboot) SIMULATION=1; SIMULATE_REBOOT=1 ;;
    --log-root=*) LOG_ROOT="${arg#*=}" ;;
    *) echo "Uso: $0 [--simulate] [--simulate-reboot] [--log-root=DIR]"; exit 64 ;;
  esac
done
HOST="$(hostname 2>/dev/null | tr -d '\r\n' | sed 's/[^A-Za-z0-9_.-]/_/g')"
[[ -z "$HOST" ]] && HOST='linux-host'
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="${LOG_ROOT}/${HOST}_${STAMP}.md"
LOCK="${TMPDIR:-/tmp}/reparo-sistema.lock"
FAILED=0
REBOOT=0

if ! mkdir -p "$LOG_ROOT" 2>/dev/null || [[ ! -w "$LOG_ROOT" ]]; then
  echo "ReparoSistema: diretório de log não existe ou não é gravável: $LOG_ROOT"; exit 1
fi
if ! ( set -o noclobber; echo "$$" > "$LOCK" ) 2>/dev/null; then
  echo 'ReparoSistema: outra execução já está em andamento.'; exit 2
fi
trap 'rm -f "$LOCK"' EXIT

log() { printf '%s\n' "$1" >> "$LOG"; }
step() {
  local name="$1"; shift
  log "- **EM_EXECUCAO** - ${name}"
  if [[ "$SIMULATION" -eq 1 ]]; then
    log '- **OK** - ação simulada; comando real não executado.'
    return
  fi
  local rc=0
  "$@" >>"$LOG" 2>&1 || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    log "- **OK** - ${name}"
  else
    FAILED=$((FAILED+1)); log "- **FALHA** - ${name} (código ${rc})"
  fi
}
priv_step() {
  local name="$1"; shift
  log "- **EM_EXECUCAO** - ${name}"
  if [[ "$SIMULATION" -eq 1 ]]; then
    log '- **OK** - ação privilegiada simulada; sudo não executado.'
    return
  fi
  local rc=0
  sudo -n "$@" >>"$LOG" 2>&1 || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    log "- **OK** - ${name}"
  else
    FAILED=$((FAILED+1)); log "- **FALHA** - ${name}: sudo não autorizado ou comando falhou"
  fi
}

START="$(date --iso-8601=seconds)"
log '# ReparoSistema Linux'
log ''
log '## Cabeçalho'
log "- Computador: ${HOST}"
log "- Sistema: $(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-desconhecido}")"
log "- Kernel: $(uname -r)"
log "- Usuário executor: $(id -un)"
log "- Versão do script: ${VERSION}"
log "- Início: ${START}"
[[ "$SIMULATION" -eq 1 ]] && log '- Modo: SIMULAÇÃO'
log ''
log '## Execução'

step 'Inventário de espaço em disco' df -h
step 'Verificação de memória' free -h
priv_step 'Atualização da lista de pacotes' apt-get update
priv_step 'Atualização dos pacotes' apt-get -y upgrade
priv_step 'Correção de dependências' dpkg --configure -a
priv_step 'Correção de pacotes quebrados' apt-get -f install -y
priv_step 'Limpeza segura de pacotes' apt-get autoremove -y
priv_step 'Limpeza de cache de pacotes' apt-get clean
step 'Verificação de serviços com falha' systemctl --failed --no-pager
step 'Resumo recente do journal' journalctl -p err..alert -b --no-pager -n 100

if [[ "$SIMULATE_REBOOT" -eq 1 || -f /var/run/reboot-required ]]; then
  REBOOT=1
fi
log ''
log '## Reinicialização'
if [[ "$REBOOT" -eq 1 ]]; then
  log '- **ALERTA** - Reinicialização necessária em até 24 horas.'
  if [[ "$SIMULATION" -eq 1 ]]; then
    log '- Simulação: nenhuma reinicialização foi executada.'
  elif who | grep -q .; then
    command -v notify-send >/dev/null 2>&1 && notify-send 'ReparoSistema' 'OK - reinicialização necessária em até 24 horas.' || true
    echo 'OK - Reinicialização necessária em até 24 horas.'
  else
    log '- Usuário não conectado; reinicialização automática será executada após o resumo.'
    RESTART_REQUESTED=1
  fi
else
  log '- **OK** - Nenhuma reinicialização pendente identificada.'
fi

RESULT='OK'
[[ "$FAILED" -gt 0 ]] && RESULT='FALHA'
[[ "$FAILED" -eq 0 && "$REBOOT" -eq 1 ]] && RESULT='ALERTA'
log ''
log '## Resumo'
log "- Resultado geral: **${RESULT}**"
log "- Falhas: ${FAILED}"
log "- Fim: $(date --iso-8601=seconds)"
log ''
log '## Problemas resolvidos'
log '- O log registra as ações executadas com sucesso; a confirmação técnica depende da saída de cada comando.'
log ''
log '## Problemas a resolver'
if [[ "$FAILED" -gt 0 ]]; then
  log "- Existem ${FAILED} etapa(s) com falha; consultar os detalhes acima."
elif [[ "$REBOOT" -eq 1 ]]; then
  log '- Reinicialização pendente dentro do prazo de 24 horas.'
else
  log '- Nenhum problema pendente identificado pelo script.'
fi
if [[ "${RESTART_REQUESTED:-0}" -eq 1 ]]; then
  sudo -n systemctl reboot >>"$LOG" 2>&1 || { FAILED=$((FAILED+1)); log '- **FALHA** - Não foi possível reiniciar automaticamente.'; }
fi
[[ "$FAILED" -gt 0 ]] && exit 1
[[ "$REBOOT" -eq 1 ]] && exit 10
exit 0
