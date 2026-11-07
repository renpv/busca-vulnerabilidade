# Fluxo de trabalho

Quem faz o quê, em que ordem e como avisar o próximo. Vale para agentes de IA e para pessoas. As regras curtas ficam em `CLAUDE.md`. O desenho segue o do `renpv/top-tenis`.

```
spec → plano → issue (uma por task) → PR (um por task) → main
```

Cada issue e cada PR tem, no máximo, **um par de etiquetas: um verbo e um ator**. O par diz **quem age agora**. O ator procura o seu par, faz o passo e passa o bastão trocando o par.

## Atores
| Etiqueta | Quem é |
| --- | --- |
| `renpv` | Pessoa: dono do repositório. Decide. |
| `claude-agencia` | Claude da agência (conta `jcmagenciamkt`). Executa e corrige. |
| `claude-renpv` | Claude do renpv. Revisa e mergeia. |

Rota padrão das issues: `**Rota:** executar → claude-agencia · revisar → claude-renpv · decidir → renpv`. Cada lado usa só a própria conta do GitHub.

## Verbos
| Verbo | Vai em | Significa |
| --- | --- | --- |
| `executar` | issue | Implementar a task e abrir o PR. |
| `revisar` | PR | Revisar contra a spec e o plano; aprovar e mergear, ou devolver. |
| `corrigir` | PR | Aplicar os comentários da revisão. |
| `decidir` | issue ou PR | Travou: uma pessoa precisa decidir. |

## Mecânica
- **Achar o trabalho:** `gh issue list --label executar --label <ator>`; `gh pr list --label revisar --label <ator>` (idem `corrigir`, `decidir`).
- **Trava `em-andamento`:** se o item já tem, outro ator está nele. Ao começar, adicione; ao terminar, tire junto com a troca de par.
- **Trocar o par, nesta ordem (o verbo é o gatilho):** tire o par antigo; adicione o ator novo; adicione o verbo novo por último. Se o `gh issue edit` falhar, use `gh api -X DELETE|POST repos/<repo>/issues/<n>/labels`.
- **Gatilhos:** `.github/workflows/agencia-gatilho.yml` avisa o `claude-agencia` quando o item recebe `executar` (issue) ou `corrigir` (PR). `.github/workflows/renpv-gatilho.yml` avisa o `claude-renpv` quando o PR recebe `revisar`. O aviso só diz repositório, tipo, número, verbo e URL; o ator relê o item pelo `gh` e confere o par e o autor antes de agir. Segredos: `AGENCIA_WEBHOOK_URL`, `AGENCIA_WEBHOOK_TOKEN`, `RENPV_WEBHOOK_URL`, `RENPV_WEBHOOK_TOKEN`.

## O que fazer em cada verbo

### `executar` (issue)
1. Confira o seu ator e `executar`, e que não há `em-andamento`. Adicione `em-andamento`.
2. Leia a spec e o plano indicados, **inteiros**: "Global Constraints", "Revisão" e as tasks anteriores, já na `main`.
3. Crie a branch `tarefa-<issue>` a partir da `origin/main` atual.
4. Implemente só a task da issue: teste, veja falhar, implemente, veja passar. Use os nomes do plano.
5. Rode `automacao/verificar.sh`.
6. Abra um PR para `main`: título da issue; corpo começando com `Closes #<n>`, seguido do relato (o que fez, testes com resultado, desvios do plano com o motivo).
7. Passe o bastão: no PR, aplique o ator de `revisar` da Rota e, por último, `revisar`. Tire o `em-andamento` da issue. A issue fecha no merge, pelo `Closes`.

### `revisar` (PR)
1. Confira o seu ator e `revisar`, e que não há `em-andamento`. Adicione `em-andamento`.
2. Confira a base: o branch parte da `origin/main` atual e está sem conflito. Se não, devolva pedindo rebase, sem revisar o mérito.
3. Leia o relato, a issue, o diff, a spec e o plano. Rode `automacao/verificar.sh` e confira o CI.
4. Aprove só se: os testes passam e os da task existem com as asserções do plano; nomes e assinaturas batem com o plano; as restrições globais são respeitadas; nada fora do escopo, nenhum segredo, nenhum caminho protegido alterado sem a task pedir; erros não somem em silêncio; a pergunta de arquitetura fecha (faltou prática que o problema pedia, ou sobrou especulação?).
5. **Aprovou:** comente o resumo, mergeie (nunca com CI vermelho), confirme `MERGED`, tire o par e o `em-andamento`, e publique a próxima task com `automacao/publicar-tarefa.sh`.
6. **Reprovou:** comente **uma** lista numerada e objetiva (arquivo, problema, o que o plano exige) e passe o par para `corrigir` + o ator de `executar` da Rota. Não corrija o código você mesmo.

### `corrigir` (PR)
1. Confira o seu ator e `corrigir`. Adicione `em-andamento`.
2. Leia **todos** os comentários da revisão. Corrija no mesmo branch, rode `automacao/verificar.sh` e faça o push. Não apague nem enfraqueça testes.
3. Comente um relato curto, item por item. Passe o par para `revisar` + o ator de `revisar` da Rota. Tire o `em-andamento`.

### `decidir` (issue ou PR)
1. Antes, tente a escolha mais simples que respeite a spec e explique no relato. Só pare se estiver realmente bloqueado.
2. Comente o motivo, as opções e a que você recomenda. Passe o par para `decidir` + `renpv`. Tire o `em-andamento`.
3. A pessoa responde no comentário e devolve o item: aplica o par de quem continua, com o verbo por último.

## Limites conhecidos
A proteção é por convenção e por revisão, não por barreira técnica: o plano grátis do GitHub não protege branch em repositório privado. Siga as regras como se o CI bloqueasse e não contorne uma guarda que falhou.
