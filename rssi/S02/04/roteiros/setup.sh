#!/bin/bash
# =====================================================================
# SETUP — ambiente isolado para os 3 roteiros de vídeo (RSSI Aula 4)
# =====================================================================
#
# Cria três "VMs" leves (containers Docker com Kali Linux (rolling)) numa rede
# Docker isolada (não afeta a rede real nem outros serviços):
#   - vitima   -> 10.10.10.20 (DNS = 1.1.1.1, DE PROPÓSITO: só ela resolve
#                 www.google.com de verdade, pra depois o mitm.sh forjar isso)
#   - atacante -> 10.10.10.10
#   - servico  -> 10.10.10.53 (site falso usado no mitm.sh, alvo da 2ª parte do ataque)
#
# NOTA DE ISOLAMENTO: a rede rssi-labnet TEM saída pra internet (é uma rede
# bridge comum do Docker) -- de propósito, só pra vitima conseguir pingar o
# www.google.com de verdade no mitm.sh. As ferramentas de ataque (arpspoof,
# dnsspoof, hping3) só enxergam e só afetam essa rede isolada (ARP não
# atravessa rede nenhuma); a única coisa que realmente sai daqui é um ping
# comum, sem ataque nenhum envolvido.
#
# Rode este script UMA VEZ, antes de gravar qualquer um dos 3 roteiros.
# Se já rodou hoje e as VMs continuam de pé, pode pular (cada roteiro
# também sabe pular esta parte se detectar que já existe).
#
# Requisito: Docker instalado e rodando (docker.com/get-started).
# Uso: cd nesta pasta e rode `bash setup.sh`

set -e
cd "$(dirname "$0")"

echo "==> Build da imagem de teste (Kali Linux + ferramentas de rede)"
docker build -t rssi-lab:kali -f Dockerfile.rssi-lab .

echo "==> Criando rede isolada rssi-labnet (10.10.10.0/24)"
docker network create --driver bridge --subnet 10.10.10.0/24 rssi-labnet 2>/dev/null \
  && echo "Rede criada." \
  || echo "Rede rssi-labnet já existe, seguindo em frente."

echo "==> Subindo o servico (10.10.10.53) — site falso pro mitm.sh"
docker run -dit --name servico --network rssi-labnet --ip 10.10.10.53 \
  rssi-lab:kali 2>/dev/null \
  && echo "servico criado." \
  || echo "Container servico já existe, seguindo em frente."

echo "==> Subindo a VM vitima (10.10.10.20)"
docker run -dit --name vitima --network rssi-labnet --ip 10.10.10.20 --dns 1.1.1.1 \
  --cap-add=NET_ADMIN --cap-add=NET_RAW \
  --sysctl net.ipv4.tcp_syncookies=0 \
  --sysctl net.ipv4.conf.all.arp_accept=1 \
  --sysctl net.ipv4.conf.default.arp_accept=1 \
  rssi-lab:kali 2>/dev/null \
  && echo "vitima criada." \
  || echo "Container vitima já existe, seguindo em frente."

echo "==> Subindo a VM atacante (10.10.10.10)"
# ip_forward=0 é de propósito: sem isso, o atacante roteia a consulta DNS real
# da vitima pro servico verdadeiro por baixo dos panos, e a resposta REAL
# vence a corrida contra a resposta falsa do dnsspoof (mitm.sh não funciona).
docker run -dit --name atacante --network rssi-labnet --ip 10.10.10.10 \
  --cap-add=NET_ADMIN --cap-add=NET_RAW \
  --sysctl net.ipv4.tcp_syncookies=0 \
  --sysctl net.ipv4.ip_forward=0 \
  rssi-lab:kali 2>/dev/null \
  && echo "atacante criado." \
  || echo "Container atacante já existe, seguindo em frente."

echo "==> Ligando o site falso no servico"
docker exec servico sh -c "ss -ltn | grep -q ':80'" \
  || docker exec -d servico busybox httpd -f -p 80 -h /tmp
sleep 1

echo "==> Testando conectividade entre as VMs"
docker exec vitima ping -c 2 10.10.10.10
echo "==> Testando o DNS real (vitima resolvendo www.google.com de verdade)"
docker exec vitima ping -c 1 www.google.com

echo
echo "Ambiente pronto. Os ataques ficam confinados à rede isolada rssi-labnet"
echo "(ARP/DNS/SYN flood não atravessam pra fora dela); a vitima tem saída"
echo "real pra internet só pra pingar o www.google.com de verdade no mitm.sh."
echo
echo "Pra gravar um dos ataques, siga o roteiro correspondente:"
echo "  roteiro-1-ddos.md"
echo "  roteiro-2-mitm.md"
echo "  roteiro-3-spoofing.md"
echo
echo "Quando terminar TODAS as gravações do dia, derrube o ambiente com:"
echo "  docker rm -f vitima atacante servico && docker network rm rssi-labnet"
