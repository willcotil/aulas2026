#!/bin/bash
# ============================================================
# mitm_vitima.sh — Terminal da VÍTIMA pro ataque MITM (RSSI Aula 4)
# Abre um shell DENTRO do container vitima, pra você mesmo digitar os
# comandos ao vivo, no momento que o mitm.sh (rodando no OUTRO terminal,
# no papel do atacante) pedir.
#
# Comandos pra usar aqui dentro, quando o mitm.sh pedir:
#   ping -c 2 www.google.com
#   curl "http://10.10.10.53/login?usuario=aluno&senha=SenhaSecreta123"
#
# Uso: ./mitm_vitima.sh   (Ctrl+D ou "exit" sai do container)
# ============================================================
cd "$(dirname "$0")"

AMARELO=$'\033[0;33m'
RESET=$'\033[0m'

if ! docker ps --format '{{.Names}}' | grep -q '^vitima$'; then
  echo "Container 'vitima' não está rodando. Rode o setup.sh primeiro."
  exit 1
fi

echo "${AMARELO}== Terminal da VÍTIMA (MITM) ==${RESET}"
echo
echo "Você está entrando no container da vítima. Quando o mitm.sh (no outro"
echo "terminal) pedir, digite aqui:"
echo
echo "  ping -c 2 www.google.com"
echo "  curl \"http://10.10.10.53/login?usuario=aluno&senha=SenhaSecreta123\""
echo
echo "(Ctrl+D ou 'exit' sai do container)"
echo

PS1_AMARELO=$(printf '\\[\\033[0;33m\\]vitima\\$\\[\\033[0m\\] ')
docker exec -it -e PS1="$PS1_AMARELO" vitima bash --norc
