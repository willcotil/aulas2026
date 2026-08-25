# Roteiro 3 — IP Spoofing (forjando o remetente do pacote)

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
atacante em 10.10.10.10. Hoje vamos ver como o atacante consegue mentir
sobre o próprio endereço IP."

---

## Parte 2 — Capturando o que chega na vítima

**Terminal 2 (vitima) — inicia a captura em segundo plano:**
```bash
docker exec -d vitima tcpdump -i eth0 -n icmp -w /tmp/spoof.pcap
```

🎬 **Fale:** "A vítima está capturando tudo que chega nela, pra
mostrarmos exatamente o que aparece como remetente de cada pacote."

---

## Parte 3 — Enviando um pacote com IP de origem forjado

🎬 **Fale:** "Do atacante — que é 10.10.10.10 de verdade — vamos mandar
um ping pra vítima, mas mentindo o IP de origem no cabeçalho do pacote:
vamos fingir que somos 10.10.10.99, um IP que não existe de verdade
nessa rede."

**Terminal 1 (atacante):**
```bash
docker exec atacante hping3 -1 -a 10.10.10.99 -c 3 10.10.10.20
```
*(`-1` = modo ICMP/ping, `-a`/`--spoof` = IP de origem forjado, `-c 3` = manda 3 pacotes)*

---

## Parte 4 — Revelando o forjamento

**Terminal 2 (vitima) — para a captura e mostra o resultado:**
```bash
docker exec vitima pkill tcpdump
docker exec vitima tcpdump -r /tmp/spoof.pcap -n
```

🎬 **Fale, apontando pra saída:** "Reparem: os pacotes chegaram dizendo
que vieram de 10.10.10.99 — mas quem mandou de verdade foi o atacante,
10.10.10.10. É exatamente o que vimos na Aula 3: o cabeçalho IP nunca
verificou se o campo de origem é verdadeiro, então qualquer máquina com
acesso de baixo nível à rede pode escrever o remetente que quiser."

🎬 **Fale (fechamento):** "É essa mesma falha que vimos possibilitar os
ataques de amplificação/reflexão dentro do DDoS — o atacante manda uma
pergunta pequena forjando o IP da vítima, e a resposta grande cai em
cima dela. Numa rede real, a defesa não é do lado da vítima: é o
provedor de internet filtrando na borda da rede (BCP38), barrando
pacotes que saem com um IP de origem que não bate com a rede de onde
vieram."

---

## Limpeza (só quando terminar TODAS as gravações do dia)

```bash
docker rm -f vitima atacante
docker network rm rssi-labnet
```
