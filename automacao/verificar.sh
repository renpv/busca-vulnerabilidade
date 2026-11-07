#!/usr/bin/env bash
# Mesma verificação do CI. Rode antes de abrir ou atualizar um PR.
set -euo pipefail
cd "$(dirname "$0")/.."

uv run pytest -q
uv run lint-imports
uv run ruff check
