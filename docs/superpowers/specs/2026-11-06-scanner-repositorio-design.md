# Scanner de vulnerabilidades de repositório — design

Data: 2026-11-06

## Intenção e porquê
O Renato cria vários projetos web com agentes de IA e não confia que o código produzido esteja livre de brechas de invasão. Ele quer um jeito de checar cada projeto depois que o agente termina, sem depender de achismo.

O resultado esperado: um comando que ele roda na própria máquina, aponta para um repositório e recebe um relatório do que está vulnerável e um prompt pronto para um agente de IA corrigir.

## Objetivos
- Um comando de linha de comando, rodado sob demanda na máquina do Renato, que recebe o caminho de um repositório.
- Funciona com **qualquer linguagem** (PHP, Java, Python, JavaScript, Go etc.), não só Django com React. O scanner detecta o que existe no repositório e roda só as ferramentas que se aplicam.
- Unifica os achados de várias ferramentas num relatório só, cada achado com severidade, arquivo, linha, descrição e como corrigir.
- O Renato escolhe o formato do relatório: HTML, Markdown ou JSON.
- Gera também um **prompt para agentes de IA** com os problemas encontrados e o que corrigir em cada um, para colar no agente e mandar corrigir.

## Fora do escopo agora
- Scanner de URL (ver "Implementação futura").
- Rodar no GitHub (CI) ou em hook de commit.
- Corrigir o código sozinho.

## Anti-objetivos
- Alterar qualquer arquivo do repositório analisado. O scanner só lê.
- Mandar código ou achados para serviço externo sem o Renato saber. Se uma ferramenta precisar de rede (por exemplo, consultar base de vulnerabilidades de dependências), isso é dito no relatório.
- Relatório que afoga o Renato em ruído. Um achado sem arquivo, linha e orientação de correção é falha do relatório.

## Como funciona (visão geral)
1. Recebe o caminho do repositório.
2. Detecta linguagens e gerenciadores de pacote presentes (por arquivos como `composer.json`, `pom.xml`, `build.gradle`, `package.json`, `pyproject.toml`, `go.mod`).
3. Roda as ferramentas aplicáveis:
   - **Análise do código (todas as linguagens):** Semgrep, com regras de segurança multi-linguagem (injeção, XSS, autenticação e criptografia fracas).
   - **Segredos (todas as linguagens):** Gitleaks, no código e no histórico do git.
   - **Dependências vulneráveis (todas as linguagens):** OSV-Scanner, que lê os lockfiles de vários ecossistemas (composer, maven, gradle, npm, pip/uv, go etc.).
   - **Específicas, quando o projeto as usa:** Bandit (Python), `npm audit` (JavaScript).
   - **Configuração insegura:** checagens próprias para erros comuns (modo debug ligado, CORS aberto, `ALLOWED_HOSTS` curinga, cookies sem flags) nas stacks conhecidas.
4. Normaliza a saída de cada ferramenta num formato interno único de achado (ferramenta, regra, severidade, arquivo, linha, descrição, correção sugerida).
5. Remove duplicatas e ordena por severidade.
6. Escreve o relatório no formato escolhido e o prompt para agentes.

## Decisões do Renato
- Roda na máquina dele, sob demanda.
- Reaproveita ferramentas de código aberto consagradas, em vez de detector escrito do zero.
- Formato de saída escolhível, mais o prompt para agentes de IA.
- Não é só Django com React: qualquer linguagem.

## Escolhas minhas (trocáveis)
- O comando é escrito em Python, com `uv`, pela stack dele.
- As ferramentas externas são instaladas como parte do setup (Semgrep e Bandit via `uv`; Gitleaks e OSV-Scanner como binários), com um comando que confere o que falta e avisa.
- O prompt para agentes é um arquivo Markdown separado, agrupado por arquivo, com os achados mais graves primeiro.
- Uma ferramenta ausente ou que falha não derruba tudo: o relatório marca a ferramenta como "não rodou" com o motivo, para não passar falsa sensação de segurança.

## Decisões do Renato após a revisão
- **Rede:** online, com aviso no relatório. Só nomes e versões de dependências saem da máquina (OSV-Scanner, `npm audit`), nunca o código. As métricas do Semgrep ficam desligadas e as regras vêm empacotadas com o projeto, sem baixar nada no uso.
- **Arquitetura:** modular, de fácil manutenção, com baixo acoplamento e espaço para acrescentar funcionalidades. Em termos de design (Adapter/Strategy, ver `engenharia.md`):
  - cada ferramenta externa é um **adaptador** com contrato único (detecta se se aplica, roda, devolve achados normalizados), registrado num catálogo; acrescentar uma ferramenta é criar um módulo, sem mexer no núcleo;
  - cada formato de saída (HTML, Markdown, JSON, prompt) é um **gerador** com contrato único, também registrado;
  - o núcleo (detecção, normalização, deduplicação, ordenação) não conhece nenhuma ferramenta nem formato; dependências num sentido só, checadas por `import-linter`;
  - o tipo de alvo (repositório hoje, URL no futuro) é uma fronteira própria, para o scanner de URL reaproveitar achado, relatório e gerador de prompt.

## Escolhas minhas, após revisão do design (trocáveis)
- **Código de saída:** 0 se não há achados no limiar, 1 se há. O limiar é uma opção do comando (`--falhar-em`, padrão `alta`). Assim o comando serve depois para CI ou hook, sem mudar nada.
- **Segredos:** o relatório e o prompt para agentes mostram só o início do valor mascarado (ex.: `AKIA****`), nunca o valor inteiro. O prompt manda o agente remover o segredo e **trocá-lo**, porque quem esteve no histórico do git deve ser tratado como vazado.
- **Onde grava:** fora do repositório analisado, por padrão em `./relatorios/<nome-do-repo>-<data>/` na pasta de onde o comando é rodado (e nunca dentro do alvo). O caminho é configurável.
- **Checagens de configuração:** regras customizadas do Semgrep, em vez de código Python próprio. Elas já dão arquivo e linha e funcionam em várias linguagens. Primeira versão: Django, Laravel/PHP (`.env`, `php.ini`), Spring (`application.properties`/`yml`) e Node/Express.
- **Monorepos:** detecção recursiva de projetos. Pastas ignoradas por padrão: `node_modules`, `.venv`, `venv`, `vendor`, `target`, `build`, `dist`, `.git`.
- **Ambiente:** WSL/Linux apenas. Binários com versão e checksum fixados no script de setup. Sem Docker.
- **Prompt para agentes:** limitado a 40 achados por arquivo de prompt, mais graves primeiro, dividido em `prompt-agente-1.md`, `-2.md` etc. quando passar disso.

## Deixado para quem for construir
- Nome do comando e estrutura interna dos módulos.
- Formato exato do achado interno e do layout do HTML.
- Escala de severidade e como mapear a de cada ferramenta.
- Regras exatas das checagens de configuração e quais stacks cobrir primeiro.
- Como lidar com falsos positivos (ex.: arquivo de ignorados por projeto).

## Implementação futura
**Scanner de URL:** o Renato aponta uma URL de um site no ar e recebe um relatório de vulnerabilidades, testando de fora como um invasor faria. Pontos a decidir quando chegar a hora:
- Só deve mirar sites do próprio Renato; precisa de uma confirmação explícita de que ele é dono do alvo antes de testar.
- Reaproveitar o formato de achado, o relatório e o gerador de prompt do scanner de repositório.
- Candidatas de ferramenta: OWASP ZAP e Nuclei, além de checagens de cabeçalhos HTTP e TLS.
