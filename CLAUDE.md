# busca-vulnerabilidade — instruções para agentes

Scanner de vulnerabilidades de repositório (Python, `uv`). Orquestra Semgrep, Gitleaks, OSV-Scanner, Bandit e `npm audit` e entrega um relatório unificado e um prompt para agentes de IA.

## Comece aqui
1. Leia a spec em `docs/superpowers/specs/` e o plano em `docs/superpowers/plans/`.
2. Para saber **o que fazer, quem age e como passar o trabalho adiante**, leia `docs/fluxo.md`.
3. Quando você trabalha por etiqueta, o seu trabalho é a issue ou o PR que tem **o seu ator e um verbo**. Se uma pessoa lhe pediu algo direto, faça o pedido, seguindo as regras abaixo.

## Regras invioláveis
- O scanner só **lê** o repositório analisado: nunca grava dentro dele.
- Camadas (contratos em `pyproject.toml`, checados por `import-linter`): `cli` → `geradores`, `nucleo`, `adaptadores` → `modelos`. O `nucleo` não importa `adaptadores` nem `geradores`.
- Cada ferramenta externa é um adaptador e cada formato é um gerador, registrados em catálogo. Acrescentar um é criar um módulo, sem mexer no núcleo.
- Segredo encontrado nunca aparece inteiro no relatório, no prompt nem em log: só os 4 primeiros caracteres e `****`.
- Segredos do projeto só em variável de ambiente. Nunca commitar `.env`.
- Mensagens e textos de saída em português do Brasil.
- Nunca apagar nem enfraquecer testes para fazê-los passar.
- Nunca push direto na `main`. Nunca merge com CI vermelho.
- Não contorne uma guarda que falhou (CI, teste, contrato de importação): comente o motivo e passe o item para `decidir`.

## Verificação
`automacao/verificar.sh` é a mesma verificação do CI. Rode antes de abrir ou atualizar um PR.

## Processo
Spec → plano → uma issue por task → um PR por task → `main`.

### GitLab Flow
- A `main` é a branch de integração e está sempre verde. O trabalho sai de uma branch curta a partir da `main` e volta por PR.
- Este projeto é uma ferramenta de linha de comando, sem deploy: não há branches de ambiente. Se um dia houver (por exemplo, publicação de pacote), elas ficam abaixo da `main` e só recebem por promoção, no sentido `main` → ambiente.
- Correção urgente entra primeiro na `main` (*upstream first*) e depois desce para os ambientes, se existirem.
- Releases se marcam com tag na `main`.
- Branch `tarefa-<issue>` a partir da `origin/main` atual; rebase antes do merge.
- PR para `main` com `Closes #<n>` e relato: o que fez, testes com resultado, desvios do plano.
- Commits em português, Conventional Commits, no imperativo.

## Etiquetas: verbo + ator
Cada issue ou PR tem no máximo um par: um verbo e um ator. O par diz quem age agora.
- Verbos: `executar` (issue) · `revisar` (PR) · `corrigir` (PR) · `decidir`
- Atores: `cursor` (executa e corrige) · `claude-renpv` (revisa) · `renpv` (decide)
- `em-andamento`: o ator começou. Se o item já tem, não comece. Tire ao terminar o passo.

Rota no topo da issue: `**Rota:** executar → <ator> · revisar → <ator> · decidir → <ator>`.
Ao trocar: tire o par antigo, adicione o ator e, por último, o verbo (o verbo é o gatilho).
Revisar o próprio trabalho só com agent separado, de contexto limpo, e CI verde.
O passo a passo de cada verbo está em `docs/fluxo.md`.

## Quando travar
Task impossível ou contraditória, spec ambígua ou decisão que não é sua: primeiro faça a escolha mais simples que respeite a spec e explique no relato. Se estiver realmente bloqueado, comente o motivo e as opções e passe o item para `decidir` + `renpv`.

## Caminhos protegidos
`.github/`, `automacao/`, `CLAUDE.md`, `docs/fluxo.md`, `pyproject.toml` (a seção `importlinter`). Não altere esses caminhos num PR de task, a não ser que a task peça; se pedir, diga no relato quais mudam e por quê.
