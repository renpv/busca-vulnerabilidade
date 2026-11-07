# Scanner de repositório — Plano de implementação

> **Para agentes:** SUB-SKILL OBRIGATÓRIA: use superpowers:subagent-driven-development (recomendado) ou superpowers:executing-plans para executar este plano task a task. Os passos usam checkbox (`- [ ]`).

**Objetivo:** um comando `buscavuln` que varre um repositório (qualquer linguagem) com ferramentas de segurança de código aberto e entrega um relatório unificado (HTML, Markdown, JSON) mais um prompt para agentes de IA corrigirem os achados.

**Arquitetura:** núcleo que não conhece nenhuma ferramenta nem formato. Cada ferramenta é um **adaptador** (Adapter) e cada formato de saída é um **gerador** (Strategy), ambos com contrato único e registrados em catálogos; acrescentar um é criar um módulo. O tipo de alvo é uma fronteira própria, para o scanner de URL futuro reaproveitar achado, relatório e geradores.

**Stack:** Python (versão fixada em `.python-version`), `uv`, `pytest`, `import-linter`, `ruff`. Ferramentas externas: Semgrep, Bandit (via `uv`), Gitleaks, OSV-Scanner (binários), `npm` (já na máquina). Só biblioteca padrão no código de produção (`argparse`, `subprocess`, `json`, `html`).

**Spec:** `docs/superpowers/specs/2026-11-06-scanner-repositorio-design.md`

## Restrições globais
- Roda em WSL/Linux. Sem Docker.
- O scanner **só lê** o repositório analisado e **nunca grava dentro dele**.
- Saída padrão: `./relatorios/<nome-do-repo>-<AAAA-MM-DD>/`, configurável.
- Pastas ignoradas na detecção: `node_modules`, `.venv`, `venv`, `vendor`, `target`, `build`, `dist`, `.git`.
- Severidades internas: `BAIXA < MEDIA < ALTA < CRITICA`. Padrão de `--falhar-em`: `ALTA`.
- Código de saída: `0` sem achados no limiar, `1` com achados, `2` para erro de uso (caminho inexistente etc.).
- Segredos: relatório e prompt mostram só os 4 primeiros caracteres seguidos de `****`. O prompt manda **trocar** o segredo.
- Métricas do Semgrep desligadas (`--metrics=off`); regras empacotadas no projeto, sem baixar nada no uso.
- Rede: só OSV-Scanner e `npm audit`, enviando nomes e versões de dependências; o relatório traz um aviso fixo sobre isso.
- Prompt para agentes: no máximo 40 achados por arquivo (`prompt-agente-1.md`, `-2.md`…), mais graves primeiro, agrupados por arquivo.
- Ferramenta ausente ou que falha vira `nao_rodou` com o motivo, nunca derruba o scan.
- Camadas (import-linter, dependência num sentido só): `cli` → `geradores`, `nucleo`, `adaptadores` → `modelos`. `nucleo` não importa `adaptadores` nem `geradores`.
- Flags e saídas de cada ferramenta externa mudam entre versões: o implementador confere na versão instalada (`<cli> --version`, `--help`) e fixa essa versão no setup.
- Commits em português, Conventional Commits, assinados, em branch `tarefa-<número da issue>` (nunca na `main`). `git add` por caminho.

## Revisão: pontos que o plano pina com teste
1. Repositório vazio ou sem nenhum projeto detectável → relatório vazio, código 0 (Task 4, 12).
2. Caminho inexistente ou que é arquivo → código 2 com mensagem clara (Task 12).
3. Ferramenta não instalada → `nao_rodou` no relatório, scan segue (Task 3, 12).
4. Repositório sem `.git` → Gitleaks ainda roda no diretório; sem erro (Task 6).
5. Saída JSON inválida ou vazia de uma ferramenta → `nao_rodou` com motivo, sem exceção (Task 3).
6. Segredo nunca aparece inteiro em nenhum gerador (Task 4, 9, 10, 11).
7. `--saida` dentro do repositório analisado é recusada com código 2 (Task 12).
8. Caminho com espaço ou acento no nome (Task 12).

## Estrutura de arquivos

```
pyproject.toml            # uv, pytest, ruff, import-linter (contratos de camadas)
.python-version
src/buscavuln/
  modelos.py              # Severidade, Achado, StatusFerramenta, ResultadoFerramenta, Relatorio
  alvo.py                 # AlvoRepositorio, Projeto
  deteccao.py             # detectar_projetos
  execucao.py             # rodar_comando (subprocess com timeout)
  nucleo/
    normalizacao.py       # mascarar_segredo, deduplicar, ordenar
    scanner.py            # executar_scan
  adaptadores/
    base.py               # Protocolo Adaptador
    catalogo.py           # registrar_adaptador, adaptadores_registrados
    semgrep.py  gitleaks.py  osv.py  bandit.py  npm_audit.py  configuracao.py
    regras/               # regras Semgrep customizadas (*.yml)
  geradores/
    base.py               # Protocolo Gerador
    catalogo.py           # registrar_gerador, geradores_registrados
    json_.py  markdown.py  html.py  prompt_agente.py
  cli.py                  # main(argv) -> int
  verificar.py            # comando `verificar` (o que falta instalar)
scripts/setup.sh          # idempotente, versões e checksums fixados
tests/                    # espelha src/; fixtures/ com repositórios de exemplo
```

---

### Task 1: Esqueleto do projeto e modelos

**Files:**
- Create: `pyproject.toml`, `.python-version`, `src/buscavuln/__init__.py`, `src/buscavuln/modelos.py`, `tests/test_modelos.py`
- Create: `.importlinter` contratos dentro do `pyproject.toml`

**Interfaces:**
- Produces (`modelos.py`):
  - `class Severidade(IntEnum): BAIXA=1; MEDIA=2; ALTA=3; CRITICA=4`
  - `@dataclass(frozen=True) class Achado: ferramenta: str; regra: str; severidade: Severidade; arquivo: str; linha: int | None; descricao: str; correcao: str; segredo: str | None = None` (`arquivo` relativo à raiz do alvo)
  - `class StatusFerramenta(str, Enum): OK="ok"; NAO_RODOU="nao_rodou"`
  - `@dataclass class ResultadoFerramenta: ferramenta: str; status: StatusFerramenta; achados: list[Achado]; motivo: str | None = None; usa_rede: bool = False`
  - `@dataclass class Relatorio: alvo: str; gerado_em: str; resultados: list[ResultadoFerramenta]; achados: list[Achado]` (achados já deduplicados e ordenados)

- [ ] **Step 1: Teste que falha** — `test_severidade_ordena` (`Severidade.CRITICA > Severidade.ALTA`), `test_achado_e_imutavel` (atribuir a campo levanta `FrozenInstanceError`).
- [ ] **Step 2: Rodar `uv run pytest tests/test_modelos.py -v`** — esperado: FAIL (módulo inexistente).
- [ ] **Step 3: Criar o projeto com `uv init --package`**, pacote `buscavuln` em `src/`, script de entrada `buscavuln = "buscavuln.cli:main"`; implementar `modelos.py` com as assinaturas acima. No `pyproject.toml`, adicionar contratos do `import-linter` pelas camadas das restrições globais, e `ruff`.
- [ ] **Step 4: Rodar `uv run pytest -v && uv run lint-imports && uv run ruff check`** — esperado: tudo verde.
- [ ] **Step 5: Commit** `feat: esqueleto do projeto e modelos de achado`

### Task 2: Detecção de projetos

**Files:**
- Create: `src/buscavuln/alvo.py`, `src/buscavuln/deteccao.py`, `tests/test_deteccao.py`

**Interfaces:**
- Consumes: nada.
- Produces:
  - `@dataclass(frozen=True) class Projeto: caminho: Path; ecossistema: str` — `ecossistema` ∈ `python`, `node`, `php`, `java`, `go`, `outro`
  - `@dataclass(frozen=True) class AlvoRepositorio: raiz: Path` com propriedade `nome: str`
  - `detectar_projetos(raiz: Path) -> list[Projeto]` — recursiva, ignora as pastas das restrições globais

Marcadores: `pyproject.toml`/`requirements*.txt` → python; `package.json` → node; `composer.json` → php; `pom.xml`/`build.gradle*` → java; `go.mod` → go.

- [ ] **Step 1: Testes que falham** (usando `tmp_path`): `test_detecta_monorepo` (`backend/pyproject.toml` + `frontend/package.json` → dois projetos), `test_ignora_node_modules` (`package.json` dentro de `node_modules/x/` não conta), `test_repositorio_vazio` (devolve `[]`), `test_caminho_com_espaco_e_acento` (`pasta com ç/composer.json`).
- [ ] **Step 2: Rodar** `uv run pytest tests/test_deteccao.py -v` — esperado: FAIL.
- [ ] **Step 3: Implementar** `detectar_projetos` com `os.walk` podando as pastas ignoradas.
- [ ] **Step 4: Rodar** os mesmos testes — esperado: PASS.
- [ ] **Step 5: Commit** `feat: detecção recursiva de projetos`

### Task 3: Contrato do adaptador, catálogo e execução de comandos

**Files:**
- Create: `src/buscavuln/execucao.py`, `src/buscavuln/adaptadores/{__init__,base,catalogo}.py`, `tests/test_execucao.py`, `tests/test_catalogo_adaptadores.py`

**Interfaces:**
- Consumes: `Achado`, `ResultadoFerramenta`, `StatusFerramenta`, `AlvoRepositorio`, `Projeto`.
- Produces:
  - `execucao.py`: `@dataclass class SaidaComando: codigo: int; stdout: str; stderr: str` e `rodar_comando(argv: list[str], cwd: Path, timeout: int = 600) -> SaidaComando`. Levanta `FerramentaAusente(nome)` se o binário não existe e `TempoEsgotado` no timeout.
  - `base.py`: `class Adaptador(Protocol): nome: str; usa_rede: bool; def aplica(self, alvo: AlvoRepositorio, projetos: list[Projeto]) -> bool; def executar(self, alvo: AlvoRepositorio, projetos: list[Projeto]) -> ResultadoFerramenta`
  - `catalogo.py`: `registrar_adaptador(adaptador: Adaptador) -> None`, `adaptadores_registrados() -> list[Adaptador]`, `limpar_catalogo() -> None` (para testes)
  - `base.py` também expõe `executar_com_protecao(adaptador, alvo, projetos) -> ResultadoFerramenta`: captura `FerramentaAusente`, `TempoEsgotado`, `json.JSONDecodeError` e qualquer exceção do adaptador e devolve `NAO_RODOU` com o motivo.

- [ ] **Step 1: Testes que falham:** `test_ferramenta_ausente_levanta` (`rodar_comando(["binario-que-nao-existe"], tmp_path)`), `test_timeout`, `test_protecao_converte_ausente_em_nao_rodou`, `test_protecao_converte_json_invalido_em_nao_rodou` (adaptador falso que faz `json.loads("")`), `test_catalogo_registra_e_lista`.
- [ ] **Step 2: Rodar** — esperado: FAIL.
- [ ] **Step 3: Implementar** com `subprocess.run(capture_output=True, text=True, timeout=..., shell=False)`.
- [ ] **Step 4: Rodar** — esperado: PASS, mais `uv run lint-imports`.
- [ ] **Step 5: Commit** `feat: contrato de adaptador, catálogo e execução protegida`

### Task 4: Núcleo — normalização e `executar_scan`

**Files:**
- Create: `src/buscavuln/nucleo/{__init__,normalizacao,scanner}.py`, `tests/nucleo/test_normalizacao.py`, `tests/nucleo/test_scanner.py`

**Interfaces:**
- Consumes: modelos, `detectar_projetos`, `executar_com_protecao`.
- Produces:
  - `mascarar_segredo(valor: str) -> str` — 4 primeiros caracteres + `****`; valor com 4 ou menos caracteres vira `****`.
  - `deduplicar(achados: list[Achado]) -> list[Achado]` — iguais em `(arquivo, linha, regra)` colapsam, mantendo a maior severidade.
  - `ordenar(achados: list[Achado]) -> list[Achado]` — severidade decrescente, depois `arquivo`, depois `linha`.
  - `executar_scan(alvo: AlvoRepositorio, adaptadores: list[Adaptador]) -> Relatorio` — detecta projetos, roda só os adaptadores com `aplica(...)` verdadeiro (os demais entram como `NAO_RODOU` com motivo `"não se aplica"`), junta, deduplica, ordena.

- [ ] **Step 1: Testes que falham:** `test_mascara_nunca_devolve_valor_inteiro`, `test_deduplica_mantem_maior_severidade`, `test_ordena_por_severidade`, `test_scan_repositorio_vazio_devolve_relatorio_sem_achados`, `test_scan_nao_importa_adaptador_concreto` (usa adaptadores falsos), `test_adaptador_que_nao_se_aplica_aparece_como_nao_rodou`.
- [ ] **Step 2: Rodar** — esperado: FAIL.
- [ ] **Step 3: Implementar.** `gerado_em` em ISO 8601 UTC.
- [ ] **Step 4: Rodar** testes e `uv run lint-imports` (o contrato proíbe `nucleo` → `adaptadores`) — esperado: PASS.
- [ ] **Step 5: Commit** `feat: núcleo de normalização e orquestração do scan`

### Task 5: Adaptador Semgrep (análise de código)

**Files:**
- Create: `src/buscavuln/adaptadores/semgrep.py`, `tests/adaptadores/test_semgrep.py`, `tests/fixtures/semgrep_saida.json`

**Interfaces:**
- Consumes: `rodar_comando`, `Adaptador`, `registrar_adaptador`.
- Produces: `class AdaptadorSemgrep` (`nome="semgrep"`, `usa_rede=False`), registrado ao importar o módulo. `aplica` é verdadeiro se há ao menos um projeto detectado. Função pura `converter_saida_semgrep(saida_json: str, raiz: Path) -> list[Achado]` (testável sem a ferramenta).

Mapeamento de severidade: `ERROR`→`ALTA`, `WARNING`→`MEDIA`, `INFO`→`BAIXA`. Comando: Semgrep com `--json --metrics=off` e `--config` apontando para um pacote de regras de segurança multi-linguagem **empacotado** em `src/buscavuln/adaptadores/regras/` (o implementador vendoriza as regras de segurança do registro oficial do Semgrep na versão fixada, com a licença conferida antes). Caminho em `arquivo` relativo à raiz.

- [ ] **Step 1: Testes que falham:** `test_converte_saida_real` (fixture com um resultado `ERROR`: asserts em `regra`, `arquivo` relativo, `linha`, `severidade == ALTA`), `test_saida_vazia_sem_resultados`, `test_comando_desliga_metricas` (o argv contém `--metrics=off`).
- [ ] **Step 2: Rodar** — esperado: FAIL.
- [ ] **Step 3: Implementar** `converter_saida_semgrep` e `AdaptadorSemgrep.executar`; código de saída `1` do Semgrep com achados não é erro.
- [ ] **Step 4: Rodar** — esperado: PASS. Se o Semgrep está instalado, rodar uma vez contra `tests/fixtures/repo_vulneravel/` (criado na Task 13) fica para lá.
- [ ] **Step 5: Commit** `feat: adaptador semgrep`

### Task 6: Adaptador Gitleaks (segredos)

**Files:**
- Create: `src/buscavuln/adaptadores/gitleaks.py`, `tests/adaptadores/test_gitleaks.py`, `tests/fixtures/gitleaks_saida.json`

**Interfaces:**
- Produces: `class AdaptadorGitleaks` (`nome="gitleaks"`, `usa_rede=False`); `converter_saida_gitleaks(saida_json: str) -> list[Achado]`. Cada achado tem `severidade=CRITICA`, `segredo=mascarar_segredo(Secret)` (o valor bruto nunca fica no `Achado`) e `correcao` dizendo para remover e **trocar** o segredo, citando que o histórico do git também precisa ser tratado.

`aplica` sempre verdadeiro. Se não há `.git`, roda na modalidade de diretório da ferramenta (sem histórico), sem erro. Relatório lido de arquivo temporário **fora do repositório analisado**.

- [ ] **Step 1: Testes que falham:** `test_converte_e_mascara` (a fixture traz um `Secret` de 20 caracteres; assert que o valor completo não aparece em `repr(achado)`), `test_sem_git_usa_modo_diretorio` (argv sem a modalidade de histórico quando `tmp_path` não tem `.git`), `test_saida_vazia_lista_vazia`.
- [ ] **Step 2: Rodar** — esperado: FAIL.
- [ ] **Step 3: Implementar.** Código de saída da ferramenta com vazamentos encontrados não é erro.
- [ ] **Step 4: Rodar** — esperado: PASS.
- [ ] **Step 5: Commit** `feat: adaptador gitleaks`

### Task 7: Adaptador OSV-Scanner (dependências, todas as linguagens)

**Files:**
- Create: `src/buscavuln/adaptadores/osv.py`, `tests/adaptadores/test_osv.py`, `tests/fixtures/osv_saida.json`

**Interfaces:**
- Produces: `class AdaptadorOsv` (`nome="osv-scanner"`, `usa_rede=True`); `converter_saida_osv(saida_json: str, raiz: Path) -> list[Achado]`. `arquivo` é o lockfile; `regra` é o id do aviso (GHSA/CVE); `descricao` traz pacote e versão afetada; `correcao` traz a versão corrigida quando a saída informa, senão "atualizar para versão sem o aviso". Severidade pela pontuação CVSS quando existe (≥9 `CRITICA`, ≥7 `ALTA`, ≥4 `MEDIA`, senão `BAIXA`); sem pontuação, `MEDIA`.

`aplica` é verdadeiro se algum projeto tem lockfile reconhecido (a ferramenta decide; o adaptador só confere que há `projetos`).

- [ ] **Step 1: Testes que falham:** `test_converte_aviso_com_cvss_alto` (assert `ALTA` e a versão corrigida em `correcao`), `test_aviso_sem_cvss_vira_media`, `test_marca_usa_rede`.
- [ ] **Step 2: Rodar** — esperado: FAIL.
- [ ] **Step 3: Implementar.** Código de saída com achados não é erro.
- [ ] **Step 4: Rodar** — esperado: PASS.
- [ ] **Step 5: Commit** `feat: adaptador osv-scanner`

### Task 8: Adaptadores Bandit e npm audit

**Files:**
- Create: `src/buscavuln/adaptadores/{bandit,npm_audit}.py`, `tests/adaptadores/test_bandit.py`, `tests/adaptadores/test_npm_audit.py`, fixtures JSON de cada um

**Interfaces:**
- Produces:
  - `class AdaptadorBandit` (`nome="bandit"`, `usa_rede=False`), `aplica` só com projeto `python`; `converter_saida_bandit(saida_json: str, raiz: Path) -> list[Achado]`. Severidade: `HIGH`→`ALTA`, `MEDIUM`→`MEDIA`, `LOW`→`BAIXA`.
  - `class AdaptadorNpmAudit` (`nome="npm-audit"`, `usa_rede=True`), `aplica` só com projeto `node` que tenha `package-lock.json`; roda dentro de cada projeto node; `converter_saida_npm_audit(saida_json: str, caminho_projeto: str) -> list[Achado]`. Severidade: `critical`→`CRITICA`, `high`→`ALTA`, `moderate`→`MEDIA`, `low`→`BAIXA`.

- [ ] **Step 1: Testes que falham:** `test_bandit_converte_high`, `test_bandit_nao_se_aplica_sem_python`, `test_npm_converte_critical`, `test_npm_nao_se_aplica_sem_lockfile`.
- [ ] **Step 2: Rodar** — esperado: FAIL.
- [ ] **Step 3: Implementar.**
- [ ] **Step 4: Rodar** — esperado: PASS.
- [ ] **Step 5: Commit** `feat: adaptadores bandit e npm audit`

### Task 9: Checagens de configuração (regras Semgrep customizadas)

**Files:**
- Create: `src/buscavuln/adaptadores/configuracao.py`, `src/buscavuln/adaptadores/regras/configuracao/{django,php,spring,node}.yml`, `tests/adaptadores/test_configuracao.py`, `tests/fixtures/config/` (um arquivo vulnerável por stack e um seguro)

**Interfaces:**
- Produces: `class AdaptadorConfiguracao` (`nome="configuracao"`, `usa_rede=False`) que roda o Semgrep **só** com as regras de `regras/configuracao/` e converte pela mesma `converter_saida_semgrep` (reuso, sem copiar). `aplica` verdadeiro se há projeto.

Regras da primeira versão (cada uma com mensagem em português e `correcao` nos metadados da regra):
- Django: `DEBUG = True`; `ALLOWED_HOSTS = ["*"]`; `SECRET_KEY` literal em `settings`; `CORS_ALLOW_ALL_ORIGINS = True`; `SESSION_COOKIE_SECURE`/`CSRF_COOKIE_SECURE = False`.
- PHP/Laravel: `APP_DEBUG=true` em `.env*`; `display_errors = On` em `php.ini`.
- Spring: `management.endpoints.web.exposure.include=*`; `spring.h2.console.enabled=true` em `application.properties`/`.yml`.
- Node/Express: `cors()` sem opções; cookie de sessão com `secure: false`.

- [ ] **Step 1: Testes que falham** (rodam o Semgrep de verdade; `pytest.mark.skipif` se não instalado): para cada stack, o arquivo vulnerável gera o achado esperado com `arquivo` e `linha` corretos, e o arquivo seguro gera zero.
- [ ] **Step 2: Rodar** — esperado: FAIL.
- [ ] **Step 3: Escrever as regras e o adaptador.** Passa a `correcao` da regra para `Achado.correcao`.
- [ ] **Step 4: Rodar** — esperado: PASS.
- [ ] **Step 5: Commit** `feat: checagens de configuração insegura`

### Task 10: Contrato do gerador, catálogo, JSON e Markdown

**Files:**
- Create: `src/buscavuln/geradores/{__init__,base,catalogo,json_,markdown}.py`, `tests/geradores/test_json.py`, `tests/geradores/test_markdown.py`

**Interfaces:**
- Consumes: `Relatorio`.
- Produces:
  - `base.py`: `class Gerador(Protocol): nome: str; def gerar(self, relatorio: Relatorio) -> dict[str, str]` — nome do arquivo → conteúdo.
  - `catalogo.py`: `registrar_gerador`, `geradores_registrados() -> dict[str, Gerador]` (chave é `nome`), `limpar_catalogo()`.
  - `json_.py`: `GeradorJson` (`nome="json"`) → `{"relatorio.json": ...}`.
  - `markdown.py`: `GeradorMarkdown` (`nome="markdown"`) → `{"relatorio.md": ...}`.
- Todo gerador inclui: resumo por severidade; lista de ferramentas com status (`nao_rodou` + motivo em destaque); achados com ferramenta, severidade, arquivo:linha, descrição, correção; e, se alguma ferramenta tem `usa_rede`, o aviso fixo: "Esta varredura consultou serviços externos (OSV, registry do npm), enviando apenas nomes e versões de dependências. Nenhum código-fonte saiu da máquina."

- [ ] **Step 1: Testes que falham:** `test_json_round_trip_dos_achados`, `test_markdown_contem_aviso_de_rede_quando_ha_ferramenta_com_rede`, `test_markdown_sem_aviso_quando_nenhuma_usa_rede`, `test_markdown_destaca_ferramenta_que_nao_rodou`, `test_nenhum_segredo_completo_no_json_e_markdown` (achado com `segredo="AKIA****"`), `test_relatorio_vazio_diz_nenhum_achado`.
- [ ] **Step 2: Rodar** — esperado: FAIL.
- [ ] **Step 3: Implementar.**
- [ ] **Step 4: Rodar** testes e `uv run lint-imports` — esperado: PASS.
- [ ] **Step 5: Commit** `feat: contrato de gerador e saídas json e markdown`

### Task 11: Gerador HTML

**Files:**
- Create: `src/buscavuln/geradores/html.py`, `tests/geradores/test_html.py`

**Interfaces:**
- Produces: `GeradorHtml` (`nome="html"`) → `{"relatorio.html": ...}`. Arquivo único, CSS embutido, sem JavaScript nem recursos externos. Todo texto vindo de achado passa por `html.escape`.

- [ ] **Step 1: Testes que falham:** `test_html_escapa_conteudo_do_achado` (descrição com `<script>alert(1)</script>` não aparece crua), `test_html_nao_referencia_recursos_externos` (nenhum `http://`/`https://` em `src=`/`href=`), `test_html_tem_aviso_de_rede`, `test_html_nao_vaza_segredo`.
- [ ] **Step 2: Rodar** — esperado: FAIL.
- [ ] **Step 3: Implementar.**
- [ ] **Step 4: Rodar** — esperado: PASS.
- [ ] **Step 5: Commit** `feat: gerador html`

### Task 12: Prompt para agentes e CLI

**Files:**
- Create: `src/buscavuln/geradores/prompt_agente.py`, `src/buscavuln/cli.py`, `tests/geradores/test_prompt_agente.py`, `tests/test_cli.py`

**Interfaces:**
- Produces:
  - `GeradorPromptAgente` (`nome="prompt"`) → `{"prompt-agente-1.md": ..., "prompt-agente-2.md": ...}`. No máximo 40 achados por arquivo, mais graves primeiro; dentro de um arquivo, agrupados por `arquivo`. Cada prompt abre com as instruções ao agente: corrigir só o listado, não mudar comportamento fora disso, rodar os testes do projeto, e **trocar** (não só apagar) segredos. Sem achados: gera um único arquivo dizendo que não há o que corrigir.
  - `cli.main(argv: list[str] | None = None) -> int`. Uso: `buscavuln <caminho> [--formato html|markdown|json ...] [--saida PASTA] [--falhar-em baixa|media|alta|critica]`. `--formato` repetível, padrão `markdown`; o prompt é sempre gerado. Valida: caminho existe e é pasta (senão `2`); `--saida` resolvida não pode estar dentro do alvo (senão `2`). Importa os módulos de adaptadores e geradores para registrá-los, roda `executar_scan`, grava os arquivos de todos os geradores escolhidos mais o prompt, imprime o caminho da pasta e um resumo, e devolve `1` se algum achado ≥ limiar, senão `0`.

- [ ] **Step 1: Testes que falham:** prompt: `test_prompt_limita_40_por_arquivo` (100 achados → 3 arquivos), `test_prompt_agrupa_por_arquivo`, `test_prompt_manda_trocar_segredo`, `test_prompt_sem_achados`, `test_prompt_nao_vaza_segredo`. CLI (com adaptadores falsos registrados): `test_codigo_2_caminho_inexistente`, `test_codigo_2_caminho_e_arquivo`, `test_codigo_2_saida_dentro_do_alvo`, `test_codigo_1_com_achado_no_limiar`, `test_codigo_0_com_achado_abaixo_do_limiar`, `test_repositorio_vazio_codigo_0`, `test_caminho_com_espaco_e_acento`, `test_nao_grava_nada_dentro_do_alvo` (compara a árvore antes e depois), `test_formatos_multiplos_geram_todos_os_arquivos`.
- [ ] **Step 2: Rodar** — esperado: FAIL.
- [ ] **Step 3: Implementar** com `argparse`. Pasta de saída padrão `./relatorios/<nome>-<AAAA-MM-DD>/`.
- [ ] **Step 4: Rodar** `uv run pytest -v && uv run lint-imports && uv run ruff check` — esperado: PASS.
- [ ] **Step 5: Commit** `feat: prompt para agentes e linha de comando`

### Task 13: Setup, verificação e teste de ponta a ponta

**Files:**
- Create: `scripts/setup.sh`, `src/buscavuln/verificar.py`, `tests/test_verificar.py`, `tests/test_e2e.py`, `tests/fixtures/repo_vulneravel/` (mini-repositório com `settings.py` com `DEBUG = True`, um segredo falso no formato de chave AWS de exemplo da documentação, `package.json` com dependência sabidamente vulnerável e `package-lock.json`), `README.md`
- Modify: `src/buscavuln/cli.py` (subcomando `verificar`)

**Interfaces:**
- Produces: `verificar_ferramentas() -> list[tuple[str, bool, str]]` — (nome, instalada, versão ou instrução de instalação) para Semgrep, Bandit, Gitleaks, OSV-Scanner e `npm`; `buscavuln verificar` imprime a tabela e devolve `1` se algo falta. `scripts/setup.sh`: idempotente, instala Semgrep e Bandit via `uv tool install`, baixa Gitleaks e OSV-Scanner em versão fixa com checksum SHA-256 conferido para `~/.local/bin`, e termina rodando `buscavuln verificar`. Pula o que já está na versão certa.

- [ ] **Step 1: Testes que falham:** `test_verificar_lista_as_cinco_ferramentas`, `test_verificar_aponta_ausente` (com `PATH` vazio), e `test_e2e_repo_vulneravel` (`skipif` se as ferramentas não estão instaladas): roda `main([caminho, "--formato", "json", "--saida", tmp])` e confere código `1`, achado de `DEBUG = True` em `settings.py`, achado de segredo mascarado, e que o valor completo do segredo não aparece em nenhum arquivo gerado.
- [ ] **Step 2: Rodar** — esperado: FAIL.
- [ ] **Step 3: Implementar `verificar.py`, o subcomando e o `setup.sh`**; escrever o `README.md` curto (instalar, rodar, formatos, código de saída, como acrescentar um adaptador ou gerador em 3 passos, scanner de URL como futuro).
- [ ] **Step 4: Rodar `scripts/setup.sh` duas vezes** (a segunda não baixa nada) e `uv run pytest -v` — esperado: PASS, e2e incluído.
- [ ] **Step 5: Commit** `feat: setup, verificação das ferramentas e teste de ponta a ponta`

---

## Autoavaliação
- **Cobertura da spec:** qualquer linguagem (Tasks 2, 5–9); formatos escolhíveis e prompt (10–12); segredos mascarados (4, 6, 10–12); aviso de rede (10, 11); só leitura e saída fora do alvo (12); código de saída e limiar (12); ferramenta ausente não derruba (3); modularidade verificada por `import-linter` (1, 4, 10); WSL e setup com versões fixas (13); scanner de URL fica registrado como futuro no README (13) e a fronteira `AlvoRepositorio` o permite.
- **Tipos:** `Achado`, `ResultadoFerramenta`, `Relatorio`, `Adaptador` e `Gerador` têm a assinatura definida uma vez (Tasks 1, 3, 10) e as demais só as consomem.
- **Lacunas conscientes:** tratamento de falsos positivos (arquivo de ignorados) e tamanho do HTML para repositórios enormes ficam para uma segunda versão, porque a spec os deixou ao construtor.
