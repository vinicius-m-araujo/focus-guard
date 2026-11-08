# FocusGuard — Agent & Developer Guidelines (AGENTS.md)

> **MANDATORY INSTRUCTION FOR AGENTS & CONTRIBUTORS:**
> Whenever you make a change to architecture, design decisions, conventions, IPC contracts, workflows, or operational rules, you **MUST immediately document the change in `AGENTS.md` and `GEMINI.md`** within the same commit or session. Never leave documentation out of sync with code.

---

## 1. Project Overview & Full Windows Mandate

**FocusGuard** is an integrity-focused productivity system that blocks distracting websites and applications at the operating system level (Windows `hosts` file, DNS sinkhole, and Windows Firewall rules via `netsh`).

### 100% Full Windows Desktop
FocusGuard is exclusively built for and runs on **Windows 10/11** (x86_64 and ARM64).
- **Zero non-Windows code**: All Linux (`iptables`, `systemd`) and Android code, workflows, and installers have been completely purged from this repository.
- **Strictly prohibited**: Never reintroduce Linux, Android, or generic POSIX implementations, syscalls (`syscall.Kill`, `SIGTERM`), Unix file paths (`/etc/hosts`), or conditional runtime checks for non-Windows platforms.
- **Windows-native integrations**:
  - Firewall: `netsh advfirewall firewall ...`
  - Hosts file: `C:\Windows\System32\drivers\etc\hosts`
  - Service management: Windows Service Control Manager (SCM) via `golang.org/x/sys/windows/svc`
  - Autostart: Windows Registry `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`
  - Paths: `%ProgramFiles%\FocusGuard` (binaries) and `%ProgramData%\FocusGuard` (state and logs)
  - Scripts: PowerShell 5.1 & 7+ (`.ps1`). Shell scripts (`.sh`) are restricted to development tooling under Git Bash / MSYS2.
  - Windows Defender mitigation: `focusguard doctor` Defender inspection & Authenticode signing via `scripts/sign-windows.ps1` (`-TestCert`, `-CertThumbprint`, `Set-AuthenticodeSignature` fallback).

---

## 2. Architectural Decisions (ADRs)

Every contributor and AI agent must adhere to these 10 core architectural decisions:

### ADR-01: Exclusivity to Windows Platform
- **Decision**: Focus exclusively on Windows desktop without cross-platform abstraction overhead.
- **Rationale**: FocusGuard deeply interacts with Windows kernel/OS perimeters (SCM, netsh advfirewall, Windows hosts file, Registry). Abstraction layers introduced testing complexity, maintenance debt, and security gaps.
- **Invariant**: All platform-specific code must reside in `_windows.go` files or `internal/infrastructure/*`.

### ADR-02: Strict Separation of Privilege (Least Privilege Principle)
- **Decision**: Only `focusguard-daemon` runs with elevated administrative privileges (as a Windows Service under `LocalSystem`, built with `requireAdministrator` manifest). All client components (`focusguard` CLI, `focusguard-tray`, `focusguard-web`, and `focusguard-watchdog`) run **strictly unelevated** in user space.
- **Rationale**: Attack surface minimization. Even if the web interface or tray companion suffers a vulnerability, the attacker cannot manipulate system hosts or firewall rules without going through the strictly validated loopback IPC API.
- **Invariant**: **NEVER** add an elevation manifest or request administrative privileges for `focusguard-tray` or `focusguard-web`.

### ADR-03: Authoritative State in RAM (RAM > Disk)
- **Decision**: The `Scheduler` held in daemon memory is the single authoritative source of truth. The disk file `%ProgramData%\FocusGuard\state.json` is an asynchronous, atomic mirror.
- **Rationale**: Disk files can be tampered with or corrupted on power loss. If disk state diverges from memory, **RAM wins**: the daemon rewrites and heals the disk state and re-enforces OS rules (`Reconcile`).
- **Invariant**: Queries must be answered from memory; disk writes must be atomic (write to temp file then rename).

### ADR-04: Cryptographic Self-Write Marking (Anti-Loop SHA-256)
- **Decision**: The daemon calculates and records the SHA-256 hash of its legitimate writes to `hosts` and `state.json` via `MarkSelfWrite`.
- **Rationale**: Filesystem watchers (`HostsWatcher`, `StateWatcher` using `fsnotify`) cannot distinguish daemon writes from external modifications. Without self-write marking, daemon operations would trigger recursive tamper alarms and infinite reconciliation loops.
- **Invariant**: Any modification to watched files detected without a matching SHA-256 hash in memory is classified as external tampering, reverted immediately, and logged to `tamper.jsonl`.

### ADR-05: Zero-Backdoor / Strict Focus Policy
- **Decision**: There is **NO** manual unblock command, shortcut, bypass, or backdoor to terminate an active Pomodoro or hard block session before its scheduled expiration.
- **Rationale**: FocusGuard's core value proposition is psychological integrity through irrevocability. Providing an easy exit defeats the purpose.
- **Invariant**: Never implement any feature, endpoint, or hidden parameter to unblock an active session early.

### ADR-06: Independent Watchdog & Smart Recovery
- **Decision**: An independent Windows service (`focusguard-watchdog`) monitors daemon health via loopback IPC heartbeat.
- **Rationale**: In-place automatic updates can fail or produce broken binaries. If the daemon enters a crash loop, the machine is left without focus protection and unable to update.
- **Invariant**: When health checks repeatedly fail or the daemon fails to start, the watchdog initiates Smart Recovery, automatically rolling back `.exe` files to the previous stable backup.

### ADR-07: Single Source of Truth for IPC Contracts (Go AST $\rightarrow$ TypeScript)
- **Decision**: Go structs in `internal/transport/ipc` and associated domain packages define the canonical IPC schema. `scripts/gen-contract` parses Go AST and generates `focusguard-ui/src/api/types.ts`.
- **Rationale**: Eliminates manual synchronization errors between the Go backend and React frontend.
- **Invariant**: Any change to IPC request/response types must be followed by `make contract`, and both Go and TypeScript files must be committed together.

### ADR-08: Monolithic Embedded Web UI
- **Decision**: The React 18 SPA is compiled into static assets and embedded directly into `focusguard-web.exe` via `go:embed all:assets`.
- **Rationale**: The user runs a single binary without needing Node.js or loose HTML/CSS/JS files on disk.
- **Invariant**: Always compile the UI (`make ui`) before compiling the web server binary.

### ADR-09: Windows Executable Locking & Safe Binary Swapping
- **Decision**: Windows locks executing `.exe` files. The update mechanism terminates companion apps (tray, watchdog), swaps binaries using rename/move, and falls back to `MoveFileEx(MOVEFILE_DELAY_UNTIL_REBOOT)` if a file remains locked.
- **Invariant**: The daemon restarts immediately with exit code 1 upon applying an update, allowing the Windows Service Control Manager or supervisor to restart it with the new binary.

### ADR-10: Best-Effort Non-Fatal OS Operations
- **Decision**: Non-critical OS operations (desktop toast notifications, secondary firewall rule cleanup, autostart registration) log warnings on failure but **never crash or panic the daemon**.
- **Invariant**: Handle OS errors gracefully and keep the core blocking loop running.

---

## 3. GitHub Actions Zero-Failure Protocol (CI Immunity)

GitHub Actions CI checks (`.github/workflows/test.yml`) run on `windows-latest` when generating releases (tags `v*`, release publications, or manual `workflow_dispatch`). To ensure **100% CI pass rate**, follow this protocol:

### Complete Mapping of CI Checks:
1. **Windows Platform Policy (`scripts/test-windows-platform.ps1`)**: Verifies no Linux artifacts exist in `.goreleaser.yaml`, no `*_linux*.go` files remain, CI runs on `windows-latest`, and no `android/` directory exists.
2. **Rule Mirrors Parity (`scripts/validate-windows.ps1`)**: Verifies that `GEMINI.md` and `AGENT.md` are 100% byte-for-byte identical in all directories (`.`, `cmd`, `internal`, `scripts`, `focusguard-ui`).
3. **PowerShell Syntax**: All `.ps1` scripts must parse with zero errors under `[System.Management.Automation.Language.Parser]::ParseFile`.
4. **Installer UTF-8 BOM**: `scripts/install-daemon.ps1` MUST retain its UTF-8 BOM (`0xEF, 0xBB, 0xBF`). Never save this file without BOM!
5. **Go Formatting (`gofmt`)**: All Go files in `cmd`, `internal`, and `scripts` must be formatted with `gofmt` (using tabs). Run `gofmt -w .`.
6. **IPC Contract Check (`scripts/gen-contract/main.go --check`)**: Verifies zero drift between Go IPC types and `focusguard-ui/src/api/types.ts`.
7. **UI Dependencies & Security Audit**: `npm ci` and `npm audit --audit-level=high` in `focusguard-ui/` must pass with zero high/critical vulnerabilities.
8. **UI Unit Tests**: `npm test` (Vitest) in `focusguard-ui/` must pass.
9. **UI Production Build & Types**: `npm run build` (`tsc -b && vite build`) must succeed.
10. **Embedded Web Assets**: `focusguard-ui/dist/` must be copied into `cmd/focusguard-web/assets/`.
11. **Go Build & Vet**: `go build ./...` and `go vet ./...` must succeed with zero diagnostics.
12. **Go Unit Tests & Coverage**: `go test ./... -count=1 -timeout=120s` must pass.
13. **Windows Executables Build**: All 5 binaries must compile successfully: `focusguard.exe`, `focusguard-daemon.exe`, `focusguard-web.exe`, `focusguard-tray.exe`, `focusguard-watchdog.exe`.
14. **Embedded Tray Icon (`scripts/verifyicon/main.go`)**: Validates embedded icon resources.
15. **Vulnerability Audit (`govulncheck`)**: Go dependencies must pass security audit.
16. **Session Log Structure (`scripts/check-session-log.sh`)**: All files in `docs/session-log/*.md` must conform strictly to template naming and structure.
17. **Windows ARM64 Build**: `GOARCH=arm64 CGO_ENABLED=0 go build ./...` must compile cleanly.
18. **Windows Race Detector (`windows-race`)**: `go test -race ./... -count=1 -timeout=600s` under MSYS2/MinGW must pass with zero data races.

### Golden Rules to Prevent CI Failures:
- 🛡️ **Mock OS Binaries in Unit Tests**: Unit tests run unprivileged in CI. **NEVER** invoke real `netsh`, `sc.exe`, or modify the real `hosts` file. Always mock OS interactions via function pointers (`execCommand`), filesystem interfaces, or temporary directories.
- 🏎️ **Race-Condition Safety**: Protect all shared concurrent state in domain and infrastructure packages with `sync.Mutex` or `sync.RWMutex`. Always cancel background goroutines when calling `Stop()` or context cancellation.
- 🔄 **Always Run `make sync-rules`**: Whenever you edit `GEMINI.md`, synchronize `AGENT.md` immediately.
- 📋 **Maintain Daily Session Logs**: Record session handoffs in `docs/session-log/YYYY-MM-DD.md` with sections:
  - `## O que foi feito`
  - `## Em andamento / pendências`
  - `## Validação`
- 📑 **Document Changes Here**: Whenever you change architecture or rules, update `AGENTS.md` and `GEMINI.md`.

---

## 4. Project Structure & Module Organization

```
├── AGENTS.md                   # Primary executive agent & developer guidelines (THIS FILE)
├── GEMINI.md                   # Canonical reference manual (mirrored to AGENT.md)
├── cmd/                        # 6 binary entry points (package main)
│   ├── focusguard/             # CLI (opens web UI when run without args)
│   ├── focusguard-daemon/      # Privileged background Windows service
│   ├── focusguard-tray/        # Unelevated user notification tray app
│   ├── focusguard-watchdog/    # Unelevated health-check & recovery service
│   ├── focusguard-web/         # Unelevated web server (embeds React UI)
│   └── focusguard-icon/        # Build-time multi-size icon generator
├── internal/                   # 34 internal packages organized in 4 layers:
│   ├── domain/                 # Business logic (OS-agnostic, pure Go):
│   │                           # analytics, apps, blocks, goal, interceptor, policy,
│   │                           # pomodoro, preset, presets, recovery, schedule,
│   │                           # scheduler, user, users
│   ├── infrastructure/         # Windows OS I/O:
│   │                           # autostart, dns, dnsserver, enforcer, filelog, fsutil,
│   │                           # hostswatch, icon, processguard, statewatch, store,
│   │                           # tamper, update
│   ├── transport/              # Communication:
│   │                           # eventhub, httpapi, ipc, ipcerr, metrics
│   └── system/                 # Lifecycle:
│                               # daemon, tray
├── focusguard-ui/              # React 18 + Vite + TypeScript frontend (12 screens)
├── packaging/                  # Icons, Windows manifests, versioninfo resources
├── scripts/                    # PowerShell validation scripts, WiX installer templates
└── docs/                       # Specifications, ADRs, and session logs (docs/session-log/)
```

---

## 5. Coding & Naming Standards

- **Go**: Format with `gofmt` (tabs). Follow effective Go conventions.
- **TypeScript / React**: Two-space indentation, PascalCase component names, `use...` hooks.
- **Language separation**:
  - Code, identifiers, commit messages, and comments: **English**.
  - Agent and developer guides (`AGENTS.md`, `GEMINI.md`, `AGENT.md`): **English**.
  - User-facing UI and CLI strings: **Brazilian Portuguese (PT-BR)**.
  - End-user documentation (README, manuals): **Brazilian Portuguese (PT-BR)**.
- **TDD (Test-Driven Development)**: Write the failing unit test first, then implement production code, within the same commit.
- **Commits**: English Conventional Commits with scope: `<type>(<scope>): <description>` (e.g., `fix(enforcer): correct netsh rule cleanup on expiry`).
