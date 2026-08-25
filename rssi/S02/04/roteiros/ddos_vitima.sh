#!/bin/bash
# ============================================================
# ddos_vitima.sh — sobe a vitima e fica monitorando CPU/memoria/rede dela
# ao vivo (docker stats). Roda num SEGUNDO terminal, ao lado do ddos.sh.
# Uso: ./ddos_vitima.sh   (Ctrl+C pra sair)
# ============================================================
cd "$(dirname "$0")"

echo "== Painel da Vitima (CPU / Memoria / Rede) =="
echo

echo "Conferindo se a vitima esta de pe..."
if ! docker ps --format '{{.Names}}' | grep -q '^vitima$'; then
  echo "Container 'vitima' parado. Subindo..."
  if ! docker start vitima >/dev/null 2>&1; then
    echo "Nao encontrei o container 'vitima'. Rode o setup.sh primeiro."
    exit 1
  fi
  sleep 1
fi
echo "vitima de pe."
echo
echo "Nota: o CPU% aqui reflete só o processo da aplicação (busybox httpd)."
echo "O processamento do SYN flood em si acontece no kernel (softirq), então"
echo "o CPU% pode ficar baixo mesmo com o ataque pesado — o NET I/O (RX) é"
echo "quem mostra o volume real do ataque chegando."
echo
echo "Deixe essa janela visível enquanto roda o ddos.sh no outro terminal."
echo "(Ctrl+C pra sair)"
sleep 2
echo

docker stats vitima
