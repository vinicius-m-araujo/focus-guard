# Desenvolvimento — Windows

O FocusGuard suporta Windows (amd64 e arm64). Linux e Android não são suportados e foram removidos do repositório; documentos antigos de validação Linux são históricos.

## Preparação

- Instale Go 1.26.5 e Node.js 22 ou superior com npm.
- Para comandos Make e scripts Bash, use Git Bash e GNU Make. Para o fluxo nativo, use PowerShell.
- Para MSI, instale WiX e a versão de go-msi fixada em `.github/workflows/release.yml`.
- O detector de corrida exige CGO e GCC compatível (MinGW-w64 UCRT).

## Validação automatizada

No PowerShell elevado, execute na raiz (o manifesto do daemon também exige elevação no executável de testes):

```powershell
.\scripts\validate-windows.ps1
.\scripts\validate-windows.ps1 -Race
```

O script executa testes de plataforma, sincronização dos guias, sintaxe PowerShell, BOM do instalador, gofmt, contrato IPC, Vitest, TypeScript/build Vite, incorporação dos assets, build/vet/testes Go com cobertura, cinco executáveis, verificação do ícone e auditorias npm/govulncheck. As auditorias consultam bases online; falhas de segurança deixam o resultado geral reprovado. O relatório fica em `validation-results/checks.json`; cobertura em `validation-results/coverage.out`. Use `-SkipInstall` somente com dependências npm já instaladas.

O CI executa essas verificações no Windows, build ARM64 e detector de corrida. Testes unitários devem usar arquivos temporários e simular comandos do sistema.

## Desenvolvimento local

Em `focusguard-ui/`, execute `npm ci` e `npm run dev`. O proxy Vite precisa de `focusguard-web` para acessar o daemon. Para gerar a distribuição embutida: `make ui` e `make build`; o validador PowerShell também compila os cinco executáveis em `bin/`.

Depois de alterar estruturas IPC, execute `make contract` e inclua os consumidores no mesmo commit. Consulte `GEMINI.md` e os guias de cada diretório.

## Validação funcional em máquina de teste

Use uma VM Windows com snapshot. Instale o MSI como administrador; confirme serviços FocusGuard e FocusGuardWatchdog, painel e tray sem elevação, login, bloqueios IPv4/IPv6 em navegadores, expiração, Pomodoro, agenda, aplicativos, persistência após reboot e recuperação após falha do daemon. Verifique detecção de adulteração em hosts/estado, atualização/rollback e desinstalação. Registre versão, comandos, resultados e logs. Esses cenários alteram a máquina e não são executados pelos testes unitários.
