#!/usr/bin/env bash
# Cria (ou atualiza) as etiquetas do fluxo no repositório atual. Idempotente.
# Uso: automacao/criar-etiquetas.sh
set -euo pipefail

criar() { gh label create "$1" --color "$2" --description "$3" --force >/dev/null; echo "ok: $1"; }

criar tarefa          0E8A16 "Uma task de um plano"
criar executar        1D76DB "Verbo: implementar a task e abrir o PR"
criar revisar         5319E7 "Verbo: revisar o PR"
criar corrigir        D93F0B "Verbo: aplicar os comentários da revisão"
criar decidir         FBCA04 "Verbo: uma pessoa precisa decidir"
criar cursor          C5DEF5 "Ator: Cursor, agente de codificação"
criar claude-renpv    BFD4F2 "Ator: Claude do renpv"
criar renpv           D4C5F9 "Ator: renpv, dono do repositório"
criar em-andamento    EDEDED "O ator começou este passo"
criar melhoria        EDEDED "Backlog: nenhum ator pega"
