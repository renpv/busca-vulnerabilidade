#!/usr/bin/env bash
# Publica a Task N de um plano como issue pronta para o ator da Rota.
# Uso: automacao/publicar-tarefa.sh docs/superpowers/plans/<plano>.md <N> [ator]
#   ator: quem executa (padrão: cursor)
# O par é aplicado por último: primeiro o ator, depois o verbo `executar` (o verbo é o gatilho).
set -euo pipefail

PLANO="$1"
N="$2"
ATOR="${3:-cursor}"
# A spec vem da linha "**Spec:** `<caminho>`" do cabeçalho do plano.
SPEC="$(grep -m1 -oE '^\*\*Spec:\*\* `[^`]+`' "$PLANO" | grep -oE '`[^`]+`' | tr -d '`')"
[ -n "$SPEC" ] || { echo "Plano sem linha **Spec:**" >&2; exit 1; }
REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"

corpo="$(python3 -I - "$PLANO" "$N" "$SPEC" "$ATOR" <<'PY'
import re, sys
plano, n, spec, ator = sys.argv[1:5]
s = open(plano, encoding="utf-8").read()
total = len(re.findall(r"^### Task \d+:", s, re.M))
m = re.search(rf"^### Task {n}:.*?(?=^---\s*$|^### Task \d+:|\Z)", s, re.S | re.M)
if not m:
    sys.exit(f"Task {n} não encontrada em {plano}")
print(f"**Rota:** executar → {ator} · revisar → claude-renpv · decidir → renpv\n")
print(f"**Plano:** `{plano}` — Task {n} de {total}\n**Spec:** `{spec}`\n\n"
      "Valem as seções *Restrições globais* e *Revisão* do plano e as tasks anteriores já na `main`.\n")
print(m.group(0).strip())
print("\n## Critérios de aceite\n"
      "- [ ] Testes escritos primeiro, vistos falhando e depois passando.\n"
      "- [ ] `automacao/verificar.sh` passa.\n"
      "- [ ] Nada fora do escopo da task e nenhum caminho protegido alterado (veja `CLAUDE.md`).\n"
      "- [ ] PR para `main` com `Closes #<número>` e relato: o que fez, testes com resultado, desvios do plano.")
PY
)"
titulo="$(printf '%s\n' "$corpo" | grep -m1 '^### Task' | sed 's/^### //')"

url="$(gh issue create -R "$REPO" --title "$titulo" --label tarefa --body "$corpo")"
num="${url##*/}"
gh issue edit "$num" -R "$REPO" --add-label "$ATOR"
gh issue edit "$num" -R "$REPO" --add-label executar
echo "$url"
