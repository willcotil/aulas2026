#!/bin/bash
# ============================================================
# spoofing.sh — IP Spoofing (RSSI Aula 4, ambiente Docker isolado)
# Requisito: containers "vitima" e "atacante" já de pé (setup.sh)
# Uso: ./spoofing.sh — roteiro interativo, aperte ENTER pra avançar cada passo
# Verde = tudo relacionado ao ATACANTE | Amarelo = tudo relacionado à VÍTIMA
# ============================================================
cd "$(dirname "$0")"

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
tab_borda() { printf "%s+-----+-----------------+-----------------+------------+%s\n" "$1" "$RESET"; }
tab_linha() { printf "%s| %-3s | %-15s | %-15s | %-10s |%s\n" "$1" "$2" "$3" "$4" "$5" "$RESET"; }

echo "== IP Spoofing =="

pausa "mostrar quem é o atacante e o que ele vai fazer."
box_topo "$VERDE"
box_linha "$VERDE" "ATACANTE"
box_topo "$VERDE"
box_linha "$VERDE" "IP real:      10.10.10.10"
box_linha "$VERDE" "IP forjado:   10.10.10.99 (não existe na rede)"
box_linha "$VERDE" "Alvo:         10.10.10.20 (vítima)"
box_topo "$VERDE"
echo
printf "%sCabeçalho IP do pacote que vai ser enviado (esperado):%s\n" "$VERDE" "$RESET"
tab_borda "$VERDE"
tab_linha "$VERDE" "#" "IP Origem" "IP Destino" "Protocolo"
tab_borda "$VERDE"
tab_linha "$VERDE" "1" "10.10.10.99" "10.10.10.20" "ICMP"
tab_linha "$VERDE" "2" "10.10.10.99" "10.10.10.20" "ICMP"
tab_linha "$VERDE" "3" "10.10.10.99" "10.10.10.20" "ICMP"
tab_borda "$VERDE"
echo
printf "%sResultado esperado: a vítima vai receber 3 pacotes achando que vieram de\n" "$VERDE"
printf "10.10.10.99 — um IP que nem existe na rede — e não do atacante de verdade.%s\n" "$RESET"

pausa "ligar a captura na vítima e disparar o ataque de verdade."
docker exec vitima sh -c 'rm -f /tmp/spoof.pcap'
docker exec -d vitima timeout 15 tcpdump -U -i eth0 -n icmp -w /tmp/spoof.pcap
sleep 1
printf "%s>> atacante executando: hping3 -1 -a 10.10.10.99 -c 3 10.10.10.20%s\n" "$VERDE" "$RESET"
# -1 = modo ICMP (ping) | -a = forja o IP de origem | -c = quantidade de pacotes a enviar
docker exec atacante hping3 -1 -a 10.10.10.99 -c 3 10.10.10.20
sleep 2

pausa "ver a tabela do que a vítima REALMENTE recebeu."
printf "%sPacotes capturados na interface da VÍTIMA (resultado real):%s\n" "$AMARELO" "$RESET"
tab_borda "$AMARELO"
tab_linha "$AMARELO" "#" "IP Origem" "IP Destino" "Protocolo"
tab_borda "$AMARELO"
i=1
docker exec vitima tcpdump -r /tmp/spoof.pcap -n 2>/dev/null | awk '{gsub(":","",$5); print $3, $5}' | \
while read -r origem destino; do
  tab_linha "$AMARELO" "$i" "$origem" "$destino" "ICMP"
  i=$((i + 1))
done
tab_borda "$AMARELO"
echo
printf "%sConfirmado: a vítima recebeu pacotes com IP de origem 10.10.10.99 — o\n" "$AMARELO"
printf "cabeçalho IP não tem verificação nenhuma de quem realmente mandou o pacote.%s\n" "$RESET"

echo
echo "== Fim =="
