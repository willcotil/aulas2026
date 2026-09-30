# Aulas 2026 — Prof. William Paiva · COTIL

Slides e materiais das disciplinas do Prof. William Paiva no COTIL/Unicamp em 2026.

**Acesse:** https://willcotil.github.io/aulas2026/

A página inicial mostra todas as disciplinas em forma de árvore. Clique numa disciplina para abrir o plano de ensino e as aulas de cada semestre.

## Disciplinas

| Sigla | Disciplina | Pasta |
|---|---|---|
| BD | Banco de Dados | [`bd/`](bd/) |
| DAD | Desenvolvimento de Aplicações Desktop | [`dad/`](dad/) |
| FI | Fundamentos de Informática | [`fi/`](fi/) |
| LP | Linguagem de Programação | [`lp/`](lp/) |
| RSSI | Redes e Segurança de Sistemas de Informação | [`rssi/`](rssi/) |
| PI-II | Projeto Integrador II | [`piii/`](piii/) |

## Como usar os slides

- **Navegar:** use `→` ou `Espaço` para avançar e `←` para voltar. Também dá para usar os botões na tela.
- **Apostila:** use `Ctrl+P` (imprimir ou salvar como PDF) para gerar a aula inteira em páginas, com todos os slides visíveis.

## Estrutura do repositório

```
index.html          página inicial (monta o menu a partir de links.json)
links.json          lista de disciplinas e aulas exibidas no menu
palettes.json       paletas de cores usadas nas aulas
<disciplina>/
  plano.html        plano de ensino
  S01/, S02/        aulas do 1º e do 2º semestre
    NN/index.html   slides da aula NN
    NN/exercicios.html   (opcional) lista de exercícios
```

Cada aula é uma página HTML independente. Não há etapa de build. Bibliotecas e fontes vêm de CDN; não há nada para instalar.

## Rodando localmente

Na raiz do repositório:

```bash
python -m http.server 8000
```

Depois abra http://localhost:8000. É preciso usar um servidor, porque abrir o `index.html` direto do disco impede o carregamento do `links.json`.

## Publicando uma aula nova

1. Crie a pasta da aula, por exemplo `bd/S02/09/`, copiando o `index.html` de uma aula recente da mesma disciplina.
2. Use a próxima paleta com `"used": false` em `palettes.json` e marque-a como usada.
3. Adicione a aula ao `links.json`, dentro da disciplina e do semestre corretos:
   ```json
   { "text": "Aula 09: Título da Aula", "link": "./bd/S02/09/" }
   ```
   Para aulas ainda não publicadas, use `"link": "#"`.
4. Faça commit e push. O GitHub Pages atualiza o site em cerca de um minuto.

Imagens (quando usadas) ficam em `NN/img/`. Reduza-as antes do commit (por exemplo, no máximo 1600 px no lado maior) para os slides carregarem rápido.
