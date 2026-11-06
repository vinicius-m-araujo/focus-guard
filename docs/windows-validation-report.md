# Validação Windows — 2026-11-03

## Resultado

**Validação funcional automatizada aprovada; segurança reprovada.** O validador final registrou 14 checks aprovados e 2 reprovados, ambos de segurança. O desktop agora tem somente Windows como plataforma suportada. Android foi preservado e não faz parte desta validação Windows.

Ambiente: Windows NT 10.0.26300, PowerShell 5.1, Go 1.26.5 windows/amd64 e Node 24.21.0. O CI usa Node 22. Nenhuma release foi publicada.

## Alterações realizadas

- Removidos implementações e testes específicos de Linux, fallbacks de outras plataformas, integração systemd, instalador Linux, scripts de VM e validação Linux.
- GoReleaser publica apenas ZIPs Windows amd64/arm64; MSI continua no pipeline Windows. Testes do desktop e detector de corrida passam a usar runners Windows.
- Criados `scripts/validate-windows.ps1` e `scripts/test-windows-platform.ps1`. Atualizados os guias e marcados os planos Linux como históricos.
- Testes do daemon agora usam enforcer simulado, estado temporário e porta TCP isolada. Removido um teste dependente de root/Linux; o lifecycle mantém testes da recusa de parada com bloqueios ativos.
- Corrigidos testes assíncronos de hosts e exclusão/renomeação de arquivos temporários sujeitos a sharing violations no Windows.
- Adicionado BOM UTF-8 ao script de assinatura para permitir sua leitura no PowerShell 5.1; normalizadas as quebras de linha relevantes para CI Windows.

## Verificações aprovadas

| Verificação | Evidência |
|---|---|
| Política Windows, guias sincronizados, sintaxe PowerShell e BOM | Aprovados pelo validador |
| Formatação Go e contrato Go/TypeScript | Sem divergências |
| Frontend | 42 testes, 6 arquivos; TypeScript e build Vite aprovados |
| Backend | `go build ./...`, `go vet ./...` e suíte completa aprovados |
| Cobertura Go | 75,0%; 44 pacotes com testes aprovados e 1 pacote sem testes |
| Estabilidade de hosts watcher | Pacote executado 10 vezes após corrigir esperas assíncronas |
| Binários | CLI, daemon, web, tray e watchdog compilados para Windows amd64 |
| Windows ARM64 | `GOARCH=arm64 CGO_ENABLED=0 go build ./...` aprovado |
| Ícone embutido | Pixels conferidos nas 6 resoluções |
| Smoke HTTP do executável web | HTTP 200, React embutido, CSP, `X-Frame-Options: DENY` e sessão não autenticada |
| Workflows | Sintaxe YAML aprovada; execução remota do CI não foi disparada |

## Achados de segurança

- **npm:** 27 vulnerabilidades: 3 críticas, 12 altas, 11 moderadas e 1 baixa. Incluem Vitest/tinypool, Vite e dependências transitivas de shadcn. As correções sugeridas incluem mudanças de versão principal e precisam de migração/testes próprios.
- **Go:** govulncheck 1.9.0 identificou 19 vulnerabilidades alcançáveis segundo sua análise, na biblioteca padrão de Go 1.26.5 e em `golang.org/x/crypto`, trazido pelo atualizador. A ferramenta aponta correções de biblioteca padrão até Go 1.26.10 e uma migração da dependência OpenPGP.
- Esses achados não foram corrigidos nesta alteração. O validador retorna código 1 e o novo gate de CI reprova enquanto persistirem.

Relatórios locais, ignorados pelo Git: `validation-results/checks.json`, `coverage.out`, `govulncheck.txt` e `web-smoke.json`. A auditoria npm detalhada desta sessão está em `.tools/npm-audit.json`.

## Ocorrência durante a validação

A primeira execução elevada da suíte legada do daemon usou o enforcer real e regravou o arquivo hosts do Windows. O isolamento de firewall/hosts foi corrigido antes da validação final. A inspeção posterior encontrou zero entradas ativas no hosts e nenhum serviço FocusGuard/FocusGuardWatchdog instalado. Sem uma cópia anterior, não é possível comprovar o conteúdo original. Nenhuma restauração especulativa foi feita.

## Limites e pendências

- Detector de corrida configurado no CI; não executado localmente porque GCC/MinGW não está instalado.
- MSI, assinatura Authenticode e testes de instalação, bloqueio real, reboot e atualização/rollback precisam de VM Windows e ferramentas/certificado próprios. O roteiro está em `development.md`.
- Avisos React de encaminhamento de refs e chaves de lista permanecem nos testes; não causaram falhas.
- Android preservado; testes Gradle e APK não executados nesta sessão.

Para repetir: execute `./scripts/validate-windows.ps1` no PowerShell elevado. Adicione `-Race` quando CGO e GCC estiverem disponíveis. A consulta das bases de segurança requer rede.
