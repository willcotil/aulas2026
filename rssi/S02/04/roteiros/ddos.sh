#!/bin/bash
# ============================================================
# ddos.sh — DDoS / SYN Flood (RSSI Aula 4, ambiente Docker isolado)
# Requisito: containers "vitima" e "atacante" já de pé (setup.sh)
# Uso: ./ddos.sh — roteiro interativo, aperte ENTER pra avançar cada passo
# Verde = tudo relacionado ao ATACANTE | Amarelo = tudo relacionado à VÍTIMA
# ============================================================
cd "$(dirname "$0")"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

VERDE=$'\033[0;32m'
AMARELO=$'\033[0;33m'
RESET=$'\033[0m'

pausa() {
  echo
  echo ">> A seguir: $1"
  read -rp "   [pressione ENTER para continuar] " _
  echo
}

box_topo()  { printf "%s+------------------------------------------------------+%s\n" "$1" "$RESET"; }
box_linha() { printf "%s| %-54s |%s\n" "$1" "$2" "$RESET"; }

# Monitora CPU/memoria/rede da vitima por $2 segundos e grava 3 linhas
# (cpu_pico%, mem_pico_bytes, rx_delta_bytes) no arquivo $1.
monitorar() {
  local arq="$1" dur="$2"
  local pico_cpu="0" mem_pico="0" rx_ini rx_fim cpu mem
  rx_ini=$(docker exec vitima cat /sys/class/net/eth0/statistics/rx_bytes 2>/dev/null || echo 0)
  local fim=$((SECONDS + dur))
  while [ $SECONDS -lt $fim ]; do
    cpu=$(docker stats vitima --no-stream --format '{{.CPUPerc}}' 2>/dev/null | tr -d '%')
    mem=$(docker exec vitima cat /sys/fs/cgroup/memory.current 2>/dev/null || echo 0)
    pico_cpu=$(awk -v a="$cpu" -v b="$pico_cpu" 'BEGIN{printf "%.2f", (a+0>b+0)?a+0:b+0}')
    mem_pico=$(awk -v a="$mem" -v b="$mem_pico" 'BEGIN{print (a+0>b+0)?a+0:b+0}')
    sleep 0.5
  done
  rx_fim=$(docker exec vitima cat /sys/class/net/eth0/statistics/rx_bytes 2>/dev/null || echo 0)
  {
    echo "$pico_cpu"
    echo "$mem_pico"
    echo "$((rx_fim - rx_ini))"
  } > "$arq"
}

fmt_mb()  { awk -v b="$1" 'BEGIN{printf "%.1f MB", b/1000000}'; }
fmt_mib() { awk -v b="$1" 'BEGIN{printf "%.1f MiB", b/1048576}'; }

echo "== DDoS / SYN Flood =="

pausa "conferir se a vitima tem um servidor de teste rodando na porta 80 (sobe um se não tiver)."
if ! docker exec vitima sh -c "ss -ltn | grep -q ':80'"; then
  docker exec -d vitima busybox httpd -f -p 80 -h /tmp
  sleep 1
fi
docker exec vitima ss -ltn | grep ':80' && echo "  vitima escutando na porta 80"

pausa "testar um acesso normal, sem nenhum ataque rolando (baseline)."
docker exec atacante curl -s -o /dev/null -w "  HTTP %{http_code} em %{time_total}s\n" http://10.10.10.20/

pausa "FASE 1 — mostrar o ataque que vai rodar, sem defesa nenhuma."
box_topo "$VERDE"
box_linha "$VERDE" "ATACANTE"
box_topo "$VERDE"
box_linha "$VERDE" "IP real:  10.10.10.10"
box_linha "$VERDE" "Alvo:     10.10.10.20:80 (vítima)"
box_linha "$VERDE" "Ataque:   SYN flood (hping3 --flood)"
box_linha "$VERDE" "Nunca fecha o handshake, de propósito"
box_topo "$VERDE"
echo
printf "%s>> atacante executando: hping3 -S --flood -p 80 10.10.10.20%s\n" "$VERDE" "$RESET"
docker exec vitima sh -c "timeout 6 tcpdump -i eth0 -n dst port 80 2>/dev/null | wc -l" > "$TMPDIR/pacotes_sem" &
CAP_PID=$!
monitorar "$TMPDIR/rec_sem" 6 &
MON_PID=$!
sleep 1
# -S = so pacotes com a flag SYN | --flood = dispara o mais rapido possivel | -p = porta de destino
docker exec atacante timeout 5 hping3 -S --flood -p 80 10.10.10.20 >/dev/null 2>&1 || true
wait $CAP_PID $MON_PID
PACOTES_SEM=$(cat "$TMPDIR/pacotes_sem")
CPU_SEM=$(sed -n 1p "$TMPDIR/rec_sem")
MEM_SEM=$(sed -n 2p "$TMPDIR/rec_sem")
RX_SEM=$(sed -n 3p "$TMPDIR/rec_sem")
echo
box_topo "$AMARELO"
box_linha "$AMARELO" "VÍTIMA — resultado real, SEM defesa"
box_topo "$AMARELO"
box_linha "$AMARELO" "Pacotes que chegaram (5s): $PACOTES_SEM"
box_linha "$AMARELO" "CPU pico:                  ${CPU_SEM}%"
box_linha "$AMARELO" "Memória pico:               $(fmt_mib "$MEM_SEM")"
box_linha "$AMARELO" "Rede recebida (RX):         $(fmt_mb "$RX_SEM")"
box_topo "$AMARELO"

pausa "aplicar a defesa: uma regra de rate limiting no iptables da vitima."
docker exec vitima sh -c '
  iptables -C INPUT -p tcp --syn --dport 80 -m limit --limit 5/s --limit-burst 10 -j ACCEPT 2>/dev/null || {
    iptables -A INPUT -p tcp --syn --dport 80 -m limit --limit 5/s --limit-burst 10 -j ACCEPT
    iptables -A INPUT -p tcp --syn --dport 80 -j DROP
  }
'
echo "  regra aplicada."

pausa "FASE 2 — repetir o mesmo ataque, agora COM a defesa ativa."
box_topo "$VERDE"
box_linha "$VERDE" "ATACANTE (repetindo o mesmo ataque)"
box_topo "$VERDE"
box_linha "$VERDE" "IP real:  10.10.10.10"
box_linha "$VERDE" "Alvo:     10.10.10.20:80 (vítima, com defesa)"
box_topo "$VERDE"
echo
printf "%s>> atacante executando: hping3 -S --flood -p 80 10.10.10.20%s\n" "$VERDE" "$RESET"
monitorar "$TMPDIR/rec_com" 6 &
MON_PID=$!
docker exec atacante timeout 5 hping3 -S --flood -p 80 10.10.10.20 >/dev/null 2>&1 || true
wait $MON_PID
CPU_COM=$(sed -n 1p "$TMPDIR/rec_com")
MEM_COM=$(sed -n 2p "$TMPDIR/rec_com")
RX_COM=$(sed -n 3p "$TMPDIR/rec_com")
echo
docker exec vitima iptables -L INPUT -v -n -x --line-numbers > "$TMPDIR/iptables_out"
ACEITOS=$(awk '$1 ~ /^[0-9]+$/ && $4=="ACCEPT"{print $2; exit}' "$TMPDIR/iptables_out")
BLOQUEADOS=$(awk '$1 ~ /^[0-9]+$/ && $4=="DROP"{print $2; exit}' "$TMPDIR/iptables_out")
ACEITOS=${ACEITOS:-0}
BLOQUEADOS=${BLOQUEADOS:-0}
CHEGADA_COM=$((ACEITOS + BLOQUEADOS))
box_topo "$AMARELO"
box_linha "$AMARELO" "VÍTIMA — resultado real, COM defesa"
box_topo "$AMARELO"
box_linha "$AMARELO" "Aceitos (regra ACCEPT):    $ACEITOS"
box_linha "$AMARELO" "Bloqueados (regra DROP):   $BLOQUEADOS"
box_linha "$AMARELO" "CPU pico:                  ${CPU_COM}%"
box_linha "$AMARELO" "Memória pico:               $(fmt_mib "$MEM_COM")"
box_linha "$AMARELO" "Rede recebida (RX):         $(fmt_mb "$RX_COM")"
box_topo "$AMARELO"

pausa "confirmar que o acesso normal ainda funciona, mesmo com o ataque tendo rodado por perto."
docker exec atacante curl -s -o /dev/null -w "  HTTP %{http_code} em %{time_total}s\n" http://10.10.10.20/

pausa "gerar a tabela comparativa final: sem defesa x com defesa."
echo "Nota: a defesa age DEPOIS que o pacote chega — por isso o volume que CHEGA"
echo "na interface de rede é parecido nos dois casos. O que muda é quanto é"
echo "ACEITO/processado. O CPU também pode variar bastante entre execuções,"
echo "já que parte do trabalho do SYN flood acontece no kernel (softirq), fora"
echo "do que o cgroup do container sempre consegue medir."
echo
printf "%s%-34s %-20s %-20s%s\n" "$AMARELO" "Métrica" "Sem defesa" "Com defesa" "$RESET"
printf "%s%-34s %-20s %-20s%s\n" "$AMARELO" "----------------------------------" "--------------------" "--------------------" "$RESET"
printf "%s%-34s %-20s %-20s%s\n" "$AMARELO" "Pacotes que chegaram (~5s)" "$PACOTES_SEM" "$CHEGADA_COM" "$RESET"
printf "%s%-34s %-20s %-20s%s\n" "$AMARELO" "Pacotes aceitos/processados" "$PACOTES_SEM" "$ACEITOS" "$RESET"
printf "%s%-34s %-20s %-20s%s\n" "$AMARELO" "CPU pico (vitima)" "${CPU_SEM}%" "${CPU_COM}%" "$RESET"
printf "%s%-34s %-20s %-20s%s\n" "$AMARELO" "Memória pico (vitima)" "$(fmt_mib "$MEM_SEM")" "$(fmt_mib "$MEM_COM")" "$RESET"
printf "%s%-34s %-20s %-20s%s\n" "$AMARELO" "Rede recebida - RX (~5s)" "$(fmt_mb "$RX_SEM")" "$(fmt_mb "$RX_COM")" "$RESET"
echo
printf "%s  Com defesa: %s aceitos (rate limit) / %s bloqueados (DROP).%s\n" "$AMARELO" "$ACEITOS" "$BLOQUEADOS" "$RESET"
if [ "$PACOTES_SEM" -gt 0 ]; then
  awk -v s="$PACOTES_SEM" -v c="$ACEITOS" -v cor="$AMARELO" -v r="$RESET" 'BEGIN{printf "%s  Redução de pacotes aceitos/processados com a defesa: %.2f%%%s\n", cor, (1-c/s)*100, r}'
fi

echo
echo "== Fim =="
echo "(pra limpar as regras depois: docker exec vitima iptables -F)"
