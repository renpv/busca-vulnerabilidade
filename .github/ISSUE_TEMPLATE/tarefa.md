---
name: Tarefa
about: Uma task de um plano, com a rota de quem executa, revisa e decide
title: "Task N: <título da task>"
---

<!--
Normalmente a issue é criada por automacao/publicar-tarefa.sh, que preenche tudo.
O par verbo + ator é aplicado só quando a task estiver pronta: primeiro o ator, o verbo por último.
-->

**Rota:** executar → cursor · revisar → claude-renpv · decidir → renpv

**Plano:** `docs/superpowers/plans/AAAA-MM-DD-<plano>.md`, task <N>
**Spec:** `docs/superpowers/specs/AAAA-MM-DD-<assunto>-design.md`

## Task
Texto da task do plano.

## Critérios de aceite
- [ ] Testes escritos primeiro, vistos falhando e depois passando.
- [ ] `automacao/verificar.sh` passa.
- [ ] Nada fora do escopo da task e nenhum caminho protegido alterado.
- [ ] PR para `main` com `Closes #<número>` e relato.
