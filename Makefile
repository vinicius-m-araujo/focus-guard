.PHONY: all build build-cli build-daemon build-web ui icon winres contract contract-check test vet hooks session-check clean install uninstall msi help fmt tidy

GO       := go
BIN_DIR  := bin


# No Windows, `go build -o` explícito NÃO acrescenta .exe — mas o CLI localiza
# os binários irmãos pelo nome com extensão (ex.: focusguard-web.exe). Deriva a
# extensão do alvo do Go (GOOS) para os builds ficarem corretos em ambos os SOs.
GOOS := $(shell $(GO) env GOOS)
ifneq ($(GOOS),windows)
$(error FocusGuard desktop supports Windows only)
endif
ifeq ($(GOOS),windows)
EXE := .exe
else
EXE :=
endif

CLI_BIN  := $(BIN_DIR)/focusguard$(EXE)
DAEMON   := focusguard-daemon$(EXE)

all: build test vet

build: icon build-cli build-daemon build-web

# icon regenera o ícone multi-tamanho a partir do artwork
# packaging/artwork/focusguard.png: o .ico Windows usado pelo go-winres
# (metadados .exe), o .png de distribuição e o .png 32px do tray
# (internal/system/tray/icon_source.png, mantido no pacote por causa do go:embed).
icon:
	$(GO) run ./cmd/focusguard-icon

# winres gera os resource .syso (rsrc_windows_*.syso) que o go build embeda
# nos .exe — requer o go-winres instalado (go install github.com/tc-hib/go-winres@latest).
winres:
	cd cmd/focusguard-daemon && go-winres make --in ../../packaging/versioninfo-daemon.json --arch amd64,arm64
	cd cmd/focusguard && go-winres make --in versioninfo.json --arch amd64,arm64
	cd cmd/focusguard-tray && go-winres make --in versioninfo.json --arch amd64,arm64
	cd cmd/focusguard-watchdog && go-winres make --in versioninfo.json --arch amd64,arm64

# hooks ativa os hooks versionados (.githooks/commit-msg): o commit-msg
# rejeita mensagens com o footer automático ("Codebuff") — política do AGENT.md
# §7. Rodar uma vez por clone (git config core.hooksPath é local).
hooks:
	git config core.hooksPath .githooks
	@echo "✔ Hooks instalados: .githooks/commit-msg (mensagens com 'Codebuff' serão rejeitadas)."

build-cli:
	$(GO) build -o $(CLI_BIN) ./cmd/focusguard

build-daemon:
	$(GO) build -o $(BIN_DIR)/$(DAEMON) ./cmd/focusguard-daemon

# build-web compila o focusguard-web. Avisa quando os assets estão vazios
# (sem "make ui" antes): nesse caso o binário embute uma pasta vazia e a UI
# não abre — o servidor mostra a página "UI não compilada" na raiz em vez
# da interface.
build-web:
	@if [ ! -f cmd/focusguard-web/assets/index.html ]; then \
		echo "⚠ Aviso: cmd/focusguard-web/assets está vazio — a UI não será embutida no binário."; \
		echo "  Rode 'make ui' antes (make ui && make build) para incluir a interface web."; \
	fi
	$(GO) build -o $(BIN_DIR)/focusguard-web$(EXE) ./cmd/focusguard-web

# ui compila o frontend (React + Vite) e copia o dist para dentro de
# cmd/focusguard-web/assets, onde o go:embed o embute no binário. Rode antes
# de compilar o focusguard-web para incluir a última versão da interface.
ui:
	cd focusguard-ui && npm ci && npm run build
	find cmd/focusguard-web/assets -mindepth 1 -maxdepth 1 ! -name '.gitkeep' -exec rm -rf {} +
	cp -r focusguard-ui/dist/. cmd/focusguard-web/assets/

# contract regenera focusguard-ui/src/api/types.ts a partir dos structs Go que
# definem o contrato IPC (internal/transport/ipc + policy, preset, pomodoro, analytics,
# schedule, tamper) — o Go é a fonte de verdade do espelho TypeScript, sem
# edição manual (Fase 2 do docs/refactor-plan.md). Rode após mudar um struct do
# contrato (regra do AGENT.md: mudou o IPC, muda os 4 lados no mesmo commit).
contract:
	go run ./scripts/gen-contract/main.go

# contract-check falha se types.ts estiver desatualizado (drift) — usado no CI
# para garantir que o codegen rodou antes do commit.
contract-check:
	go run ./scripts/gen-contract/main.go --check

# session-check falha se o resumo da sessão de HOJE não existir em
# docs/session-log/ (regra do AGENT.md raiz §4.15 e item do Definition of
# Done §5): é o handoff que guia o agente do dia seguinte. Rode no fim da
# sessão, antes de commitar. O CI valida a ESTRUTURA de todos os resumos
# existentes (scripts/check-session-log.sh no .github/workflows/test.yml) —
# este alvo é a checagem do dia, local.
session-check:
	bash scripts/check-session-log.sh --today

# sync-rules espelha os arquivos GEMINI.md -> AGENT.md na raiz e subdiretórios
sync-rules:
	@for dir in . cmd focusguard-ui internal scripts; do \
		cp "$$dir/GEMINI.md" "$$dir/AGENT.md"; \
	done
	@echo "✔ Arquivos GEMINI.md sincronizados para AGENT.md"

# sync-rules-check valida se os arquivos AGENT.md e GEMINI.md estão 100% idênticos
sync-rules-check:
	@for dir in . cmd focusguard-ui internal scripts; do \
		diff -u "$$dir/GEMINI.md" "$$dir/AGENT.md" || { echo "✖ Erro: $$dir/AGENT.md diverge de $$dir/GEMINI.md. Execute 'make sync-rules'."; exit 1; }; \
	done
	@echo "✔ Todos os arquivos GEMINI.md e AGENT.md estão em sincronia"

# msi gera o instalador do Windows (focusguard-<versão>-amd64.msi)
# via go-msi + WiX Toolset. Requer um ambiente Windows (o go-msi chama o WiX
# via cmd.exe) com go-msi e WiX 3.10+ instalados — ver scripts/build-msi.sh.
# Uso: make msi VERSION=0.9.0 [ARCH=amd64|arm64]
msi:
	bash scripts/build-msi.sh $(VERSION) $(ARCH)

install:
	@echo "=== Instalando FocusGuard ==="
	$(GO) build -o $(CLI_BIN) ./cmd/focusguard
	$(GO) build -o $(BIN_DIR)/$(DAEMON) ./cmd/focusguard-daemon
	$(CLI_BIN) install
	@echo "✔ Instalacao concluida"

uninstall:
	@echo "=== Desinstalando FocusGuard ==="
	$(GO) build -o $(CLI_BIN) ./cmd/focusguard
	$(CLI_BIN) uninstall
	@echo "✔ Desinstalacao concluida"

test:
	$(GO) test ./... -count=1 -timeout=60s

vet:
	$(GO) vet ./...

clean:
	rm -rf $(BIN_DIR)
	rm -f focusguard-daemon.exe focusguard.exe

fmt:
	$(GO) fmt ./...

tidy:
	$(GO) mod tidy

help:
	@echo "FocusGuard - Comandos disponiveis:"
	@echo ""
	@echo "  make build       Compila CLI, daemon e focusguard-web"
	@echo "  make ui          Compila a interface web e embute no focusguard-web"
	@echo "  make msi         Gera o instalador .msi do Windows (go-msi + WiX)"
	@echo "  make install     Compila e instala (Windows: SCM)"
	@echo "  make uninstall   Remove da inicializacao"
	@echo "  make test        Executa todos os testes"
	@echo "  make vet         Verifica com go vet"
	@echo "  make session-check  Falha se o resumo da sessão de hoje não existir"
	@echo "  make sync-rules  Sincroniza GEMINI.md para AGENT.md"
	@echo "  make sync-rules-check  Verifica paridade entre GEMINI.md e AGENT.md"
	@echo "  make clean       Remove artefatos de build"
	@echo "  make fmt         Formata codigo fonte"
	@echo "  make tidy        go mod tidy"
	@echo ""
	@echo "Variaveis:"
