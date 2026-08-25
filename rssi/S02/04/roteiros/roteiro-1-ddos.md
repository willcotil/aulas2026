# Roteiro 1 — DDoS / SYN Flood

Vídeo demonstrativo para a Aula 4 de RSSI (Laboratório Prático). Ambiente
100% isolado em Docker — nada aqui sai da sua máquina.

**Antes de gravar**, abra **dois terminais lado a lado**:
- **Terminal 1** — onde você dispara o ataque (`docker exec` no `atacante`)
- **Terminal 2** — no seu computador, fora de qualquer container — onde
  você tenta acessar a vítima como se fosse um usuário comum

⚠️ **Aviso a repetir em voz alta no início do vídeo:** este laboratório roda
numa rede Docker isolada, sem saída pra internet nem pra rede real. Essas
técnicas só podem ser usadas contra máquinas suas, criadas por você, com
essa finalidade — nunca contra redes ou dispositivos de terceiros (no
Brasil, isso é crime pela Lei 12.737/2012).

---

## Parte 1 — Preparando o ambiente

Pule esta parte se as VMs já estão de pé (rodou `setup.sh` ou já gravou
outro roteiro hoje).

```bash
cd roteiros/          # pasta onde está o Dockerfile.rssi-lab
docker build -t rssi-lab:kali -f Dockerfile.rssi-lab .
docker network create --driver bridge --subnet 10.10.10.0/24 rssi-labnet
docker run -dit --name vitima   --network rssi-labnet --ip 10.10.10.20 --cap-add=NET_ADMIN --cap-add=NET_RAW --sysctl net.ipv4.tcp_syncookies=0 rssi-lab:kali
docker run -dit --name atacante --network rssi-labnet --ip 10.10.10.10 --cap-add=NET_ADMIN --cap-add=NET_RAW rssi-lab:kali
docker exec vitima ping -c 2 10.10.10.10
```

🎬 **Fale:** "Temos duas máquinas leves na mesma rede isolada: a vítima,
em 10.10.10.20, e o atacante, em 10.10.10.10."

---

## Parte 2 — Subindo um "servidor" na vítima

**Terminal 2 (vitima):**
```bash
docker exec -d vitima busybox httpd -f -p 80 -h /tmp
docker exec vitima ss -ltn
```

🎬 **Fale:** "A vítima está rodando um servidor simples na porta 80,
como se fosse um site qualquer."

⚠️ **Confira antes de seguir:** a saída do `ss -ltn` precisa mostrar uma
linha `LISTEN` com `*:80`.

**Teste de linha de base — direto do seu computador (fora de qualquer container):**
```bash
curl -s -o /dev/null -w "HTTP %{http_code} em %{time_total}s\n" http://10.10.10.20/
```
Isso deve responder rapidinho (`HTTP 404` já serve — o que importa aqui é
o servidor responder, não o conteúdo). Anote esse tempo de resposta
normal, é o "antes" da comparação.

📌 **Por que testar do seu computador, e não de dentro de um container:**
no Linux, com Docker, sua máquina já enxerga o IP dos containers direto
(rede `rssi-labnet`) — isso deixa o teste mais parecido com "um usuário
comum tentando acessar o site", em vez de outro processo dentro da
própria rede de teste.

**Se o `curl` do host não alcançar `10.10.10.20`** (aconteceu, teste
antes de gravar), use este fallback rodando dentro do próprio
`atacante`, numa segunda janela/sessão — não atrapalha o ataque, que
roda em outra sessão do mesmo container:
```bash
docker exec atacante sh -c 'while true; do curl -s -o /dev/null -w "HTTP %{http_code} em %{time_total}s\n" --max-time 2 http://10.10.10.20/ || echo "FALHOU (timeout)"; sleep 1; done'
```

---

## Parte 3 — Disparando o SYN flood

🎬 **Fale:** "Do atacante, vamos inundar a vítima com pacotes SYN, sem
nunca completar o aperto de mão de três vias (3-way handshake) do TCP —
exatamente o mecanismo que vimos na Aula 3. O efeito que interessa não é
um número dentro do servidor, e sim isto: um usuário comum tentando
acessar o site NÃO CONSEGUE MAIS — é isso que 'ataque à Disponibilidade'
quer dizer, na prática."

**Terminal 1 (atacante) — dispara o ataque por 20 segundos e para sozinho:**
```bash
docker exec atacante timeout 20 hping3 -S --flood -p 80 10.10.10.20
```

**Enquanto isso, no Terminal 2 (seu computador, fora do container — ou o fallback da Parte 2 se o host não alcançar a vítima) — tente acessar repetidamente:**
```bash
while true; do curl -s -o /dev/null -w "HTTP %{http_code} em %{time_total}s\n" --max-time 2 http://10.10.10.20/ || echo "FALHOU (timeout)"; sleep 1; done
```

🎬 **Fale, apontando pro Terminal 2:** "Reparem: enquanto o ataque está
ativo, as tentativas de acesso começam a falhar ou demorar muito mais
que o normal — o servidor está tão ocupado processando SYNs falsos que
não sobra capacidade pra atender quem realmente quer entrar."

Quando o ataque do Terminal 1 acabar sozinho (`timeout` de 20s),
interrompa o loop do Terminal 2 com `Ctrl+C` — repare que as respostas
voltam ao normal.

---

## Parte 3.5 — Visualizando o ataque e o esforço do servidor (opcional, mais didático)

Três formas simples de MOSTRAR o flood acontecendo e o servidor
"sofrendo", em vez de só ver o sintoma (timeout do usuário). Grave cada
uma em uma tomada separada — repita o ataque da Parte 3 quantas vezes
precisar, ele não deixa nenhum efeito permanente.

**① O custo real fica no kernel, não no processo (explica por que `docker stats` mostra ~0%):**

Se você testou `docker stats vitima`, deve ter reparado que o `CPU %`
mal se mexe durante o ataque — e isso é, em si, um ótimo ponto didático:
o `busybox httpd` (o processo da aplicação) nunca chega a ser
incomodado, porque os pacotes SYN são descartados/processados pelo
**kernel do sistema**, na camada de rede, antes de qualquer coisa chegar
na aplicação. Esse trabalho de kernel não é contado nas estatísticas de
CPU do container.

Pra ver ONDE esse custo aparece de verdade, rode isto no seu computador
(host), fora de qualquer container, antes de disparar o ataque:
```bash
top
```
Fique de olho na linha `%Cpu(s):`, especificamente no valor de `si`
(software interrupts — processamento de rede em baixo nível). Dispare o
ataque (Terminal 1) e observe esse número subir.

🎬 **Fale:** "Reparem: o processo do servidor nem percebe o ataque — quem
sente o peso é o próprio kernel, processando essa avalanche de pacotes
na camada de rede, antes mesmo de chegar em qualquer aplicação. É por
isso que defesas como rate limiting e SYN cookies também vivem no
kernel, e não dentro do programa do servidor."

**② A inundação em si, pacote por pacote (mostra o volume do ataque):**

Num terminal separado, ANTES de disparar o ataque:
```bash
docker exec vitima timeout 20 tcpdump -i eth0 -n dst port 80
```
Dispare o ataque (Terminal 1) logo em seguida — a tela vai encher de
linhas `S` (SYN) rolando rápido demais pra ler, uma atrás da outra.

🎬 **Fale:** "Essa parede de linhas passando é o próprio ataque chegando
na vítima, pacote por pacote — cada uma dessas linhas é um pedido de
conexão que nunca vai ser completado."

**③ Um número concreto de pacotes por segundo (bom pra legenda/gráfico no vídeo):**

Com o ataque já rodando, num terceiro terminal:
```bash
docker exec vitima sh -c "timeout 3 tcpdump -i eth0 -n dst port 80 2>/dev/null | wc -l"
```
Isso conta quantos pacotes chegaram na porta 80 em 3 segundos — divida
por 3 pra ter um "pacotes por segundo" pra mostrar na tela.

🎬 **Fale:** "Só nesses 3 segundos, chegaram X mil pacotes na porta 80 —
e lembrem, isso é só o meu notebook fazendo esse ataque de brincadeira;
uma botnet de verdade, como vimos na Aula 3, multiplica isso por
milhares de máquinas."

---

## Parte 4 — Aplicando a mitigação (rate limiting)

🎬 **Fale:** "Agora vamos aplicar a defesa que vimos na Aula 3: limitar
quantas conexões novas por segundo o servidor aceita, e ver se isso
protege o acesso dos usuários legítimos mesmo com o ataque ativo."

**Terminal 2 (vitima):**
```bash
docker exec vitima iptables -A INPUT -p tcp --syn --dport 80 -m limit --limit 5/s --limit-burst 10 -j ACCEPT
docker exec vitima iptables -A INPUT -p tcp --syn --dport 80 -j DROP
```

**Terminal 1 (atacante) — repete o mesmo ataque:**
```bash
docker exec atacante timeout 20 hping3 -S --flood -p 80 10.10.10.20
```

**Terminal 2 (seu computador) — repete o mesmo teste de acesso:**
```bash
while true; do curl -s -o /dev/null -w "HTTP %{http_code} em %{time_total}s\n" --max-time 2 http://10.10.10.20/ || echo "FALHOU (timeout)"; sleep 1; done
```

🎬 **Fale:** "Com o rate limiting ativo, uma fatia das conexões novas
continua sendo aceita mesmo durante o ataque — o site não fica
100% fora do ar. Numa rede real, essa defesa é combinada com as outras
que vimos na Aula 3 (WAF, serviços de mitigação, redundância), porque
sozinha ela não resolve um ataque em grande escala — só reduz o dano."

---

## Limpeza (só quando terminar TODAS as gravações do dia)

```bash
docker exec vitima iptables -F   # remove as regras de firewall de teste
docker rm -f vitima atacante
docker network rm rssi-labnet
```
