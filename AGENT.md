# GEMINI.md — FocusGuard repository guide

> Primary reference document for **AI agents and developers** working in this
> repository. Read it before editing code. Keep it up to date whenever
> conventions, architecture, or rules change.
>
> **MANDATORY INSTRUCTION:** Whenever any change to architecture, design
> decisions, conventions, IPC contracts, workflows, or operational rules is made,
> you **MUST document the change in both `GEMINI.md` and `AGENTS.md`**.

## Table of contents

0. [Never do without explicit confirmation](#0-never-do-without-explicit-confirmation)
1. [Specs — what this project is](#1-specs--what-this-project-is)
2. [Language and stack](#2-language-and-stack)
3. [Architecture & Architectural Decisions (ADRs)](#3-architecture--architectural-decisions-adrs)
   - [3.1 Architectural Decision Records (ADRs)](#31-architectural-decision-records-adrs)
   - [3.2 Full Windows Integration & OS Perimeters](#32-full-windows-integration--os-perimeters)
   - [3.3 Data flow & Component model](#33-data-flow--component-model)
4. [Code conventions](#4-code-conventions)
5. [Testing, validation, and Definition of Done](#5-testing-validation-and-definition-of-done)
   - [5.1 GitHub Actions Zero-Failure Protocol (CI Immunity)](#51-github-actions-zero-failure-protocol-ci-immunity)
   - [5.2 Definition of Done](#52-definition-of-done)
6. [Relevant file structure](#6-relevant-file-structure)
7. [Commit conventions](#7-commit-conventions)
8. [Release](#8-release)
9. [Known pitfalls & Gotchas](#9-known-pitfalls--gotchas)
10. [Glossary](#10-glossary)

---

## 0. Never do without explicit confirmation

If a task requires any of the following, **stop and ask** before proceeding —
do not assume it is implied by the request:

- **Elevation**: Adding an admin/elevation manifest to the tray or to `focusguard-web` (only the daemon is privileged).
- **Manual unblock / Bypass**: Creating any "manual unblock" command, shortcut, or backdoor to undo an active block before expiration — that is a core product design decision, not a bug.
- **Pending restart**: Reintroducing the pending-restart mechanism (`pendingRestart`/watcher) in the update flow — it was deliberately removed.
- **Real OS binaries in tests**: Invoking real `sc.exe`, `iptables`, `systemctl`, `netsh`, or other OS binaries inside unit tests — always mock them (`execCommand`, `os.Stat`, etc.).
- **Manual asset generation**: Manually editing or hand-crafting `.syso`, `.ico`/`.png`, or `versioninfo.json` — only use `make icon` and `make winres`.
- **Breaking IPC contract**: Changing `internal/transport/ipc` payloads without updating CLI, tray, web, and `focusguard-ui/src/api/types.ts` (`make contract`) in the exact same commit.
- **Unmigrated state changes**: Modifying the `state.json` schema without a backward-compatible migration plan for disk state.
- **PowerShell BOM**: Saving `install-daemon.ps1` without preserving its UTF-8 BOM (`EF BB BF`).
- **Undocumented rule drift**: Making architectural or convention changes without documenting them in both `GEMINI.md` and `AGENTS.md`.

In any of these cases: explain the plan and obtain explicit confirmation before modifying code.

---

## 1. Specs — what this project is

**FocusGuard** is an integrity-focused tool to **block distracting websites and applications** and preserve productivity, operating at the system level (`hosts` file, DNS sinkhole, and firewall rules).

- **CLI (`focusguard`)** — Command-line interface. When invoked without arguments, it opens the web UI in the default browser. One file per command in `cmd/focusguard/` + command table in `commands.go`.
- **Daemon (`focusguard-daemon`)** — Background Windows service that applies and maintains blocks; communicates over loopback TCP IPC (`127.0.0.1:48901`).
- **Tray (`focusguard-tray`)** — System tray icon with quick controls and status updates. Runs unelevated.
- **Watchdog (`focusguard-watchdog`)** — External health-check monitor and Smart Recovery engine (rolls back broken updates).
- **Web UI & Server (`focusguard-web`)** — Serves the embedded React 18 + TS UI (`focusguard-ui/`) and proxies IPC actions to the daemon at `http://127.0.0.1:48902`. All 12 screens are implemented: Dashboard, Bloquear, Pomodoro, Agenda, Apps, Presets, Estatísticas, Segurança, Configurações, Login, Rede, Guia.
- **Build tool (`focusguard-icon`)** — Build-time generator for multi-size `.ico` and `.png` icons from canonical artwork.

### Platforms

FocusGuard exclusively supports **Windows 10/11** (x86_64 and ARM64). Linux and Android implementations, installers, and release targets have been completely removed. Use `scripts/validate-windows.ps1` for Windows validation.

| Component | Windows |
|---|---|
| Firewall | `netsh advfirewall firewall ...` |
| Hosts | `C:\Windows\System32\drivers\etc\hosts` |
| Service | SCM (`FocusGuard` / `FocusGuardWatchdog`) |
| IPC | Loopback TCP (`ipc.WindowsPort`, currently `48901`) |
| Install / State | `Program Files\FocusGuard` / `ProgramData\FocusGuard` |
| Tray autostart | `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` |

---

## 2. Language and stack

- **Go 1.26.10** (module `focusguard`). Desktop builds use `CGO_ENABLED=0`; race checks require CGO and MinGW-w64 on Windows.
- Key dependencies: `fsnotify` (filesystem watchers), `getlantern/systray` (tray), `creativeprojects/go-selfupdate` (update engine), `golang.org/x/sys` (Windows services), `golang.org/x/mod/semver` (version comparison).
- **Stdlib first**: Avoid adding new dependencies unless strictly necessary.

### Languages used in the repository

- **Agent and developer guidelines (`GEMINI.md`, `AGENT.md`, `AGENTS.md`)**: English across root and all subdirectories.
- **Code, identifiers, and code comments**: English.
- **UI/CLI user-facing strings**: Brazilian Portuguese (PT-BR).
- **End-user documentation (README, CHANGELOG, manuals)**: Brazilian Portuguese (PT-BR).
- **Commit messages**: English (Conventional Commits).

---

## 3. Architecture & Architectural Decisions (ADRs)

### 3.1 Architectural Decision Records (ADRs)

Every contributor and AI agent must adhere to the 10 core architectural decisions governing FocusGuard:

#### ADR-01: Exclusivity to Windows Platform (Full Windows Architecture)
- **Decision**: FocusGuard is built exclusively for Windows desktop without cross-platform abstraction overhead.
- **Rationale**: Deep integration with Windows security and OS perimeters (`netsh advfirewall`, Windows Service Control Manager / SCM, Windows hosts file, Registry HKCU Run, process Toolhelp32) cannot be cleanly unified with POSIX models without significant compromises and testing debt. All Linux and Android code has been excised.
- **Invariant**: Strictly prohibit non-Windows files (`*_linux.go`, `*_darwin.go`, Android modules) or non-Windows system calls (`syscall.Kill`, `SIGTERM`).

#### ADR-02: Strict Separation of Privilege (Principle of Least Privilege)
- **Decision**: Only `focusguard-daemon` runs with elevated administrator privileges (Windows Service running under `LocalSystem`, built with `requireAdministrator` manifest). The CLI, Tray (`focusguard-tray`), Web UI server (`focusguard-web`), and Watchdog (`focusguard-watchdog`) run **unelevated** in user space.
- **Rationale**: The Web UI handles browser requests and GUI rendering. If a vulnerability exists in web handlers or tray components, attackers cannot tamper with kernel firewall rules or system hosts without passing through the strictly validated IPC command contract.
- **Invariant**: **NEVER** add an elevation manifest or request admin privileges for `focusguard-tray` or `focusguard-web`.

#### ADR-03: Authoritative State in RAM (RAM > Disk)
- **Decision**: The `Scheduler` in daemon memory is the single authoritative source of truth. The disk state `%ProgramData%\FocusGuard\state.json` is an asynchronous, atomic persistence mirror.
- **Rationale**: External users or disk corruption can manipulate disk files while the daemon runs. If disk state diverges from memory, **RAM wins**: the daemon rewrites and repairs the disk state and re-enforces OS rules (`Reconcile`).
- **Invariant**: All state queries are served from RAM; disk updates write to temporary files first and atomically rename.

#### ADR-04: Cryptographic Self-Write Marking (Anti-Loop SHA-256)
- **Decision**: The daemon computes and stores the SHA-256 hash of its legitimate writes to `hosts` and `state.json` via `MarkSelfWrite`.
- **Rationale**: Filesystem watchers (`HostsWatcher`, `StateWatcher` using `fsnotify`) cannot distinguish daemon writes from external edits. Self-write marking prevents recursive tamper alarms and infinite reconciliation loops.
- **Invariant**: Any modification detected by watchers without a matching hash in memory is classified as external tampering, reverted immediately, and logged in `tamper.jsonl`.

#### ADR-05: Zero-Backdoor / Strict Focus Policy
- **Decision**: FocusGuard provides **NO** manual unblock command, shortcut, bypass, or backdoor to terminate an active Pomodoro or hard block session before its scheduled expiration.
- **Rationale**: FocusGuard's core value is behavioral integrity through irrevocability.
- **Invariant**: Prohibit any endpoint, parameter, or shortcut that enables early unblocking during active sessions.

#### ADR-06: Independent Watchdog & Smart Recovery
- **Decision**: An independent Windows service (`focusguard-watchdog`) monitors daemon health via loopback IPC heartbeat.
- **Rationale**: Automatic updates can fail or produce broken binaries. If the daemon crash-loops, the machine is left without focus protection and unable to update.
- **Invariant**: If the daemon fails health checks repeatedly, the watchdog initiates Smart Recovery, automatically rolling back `.exe` files to the previous stable backup.

#### ADR-07: Single Source of Truth for IPC Contracts (Go AST $\rightarrow$ TypeScript)
- **Decision**: Go structs in `internal/transport/ipc` and associated domain packages define the canonical IPC wire contract. `scripts/gen-contract` parses Go AST and generates `focusguard-ui/src/api/types.ts`.
- **Rationale**: Eliminates manual synchronization errors between the Go backend and React frontend.
- **Invariant**: Modifying IPC types requires running `make contract`, and both Go and TypeScript files must be committed together.

#### ADR-08: Monolithic Embedded Web UI
- **Decision**: The React 18 SPA is compiled into static assets and embedded directly into `focusguard-web.exe` via `go:embed all:assets`.
- **Rationale**: End users run a single binary without needing Node.js or loose HTML/CSS/JS files on disk.
- **Invariant**: Always compile the UI (`make ui`) before building `focusguard-web`.

#### ADR-09: Windows Executable Locking & Safe Binary Swapping
- **Decision**: Windows locks executing `.exe` files from in-place replacement. The update engine stops non-essential companions (tray, watchdog), attempts atomic file move/rename, and falls back to Win32 `MoveFileEx(MOVEFILE_DELAY_UNTIL_REBOOT)` if a file remains locked.
- **Invariant**: The daemon restarts immediately with exit code 1 upon applying an update, allowing the SCM supervisor to restart it with the new binary.

#### ADR-10: Best-Effort Non-Fatal OS Operations
- **Decision**: Failures in non-critical OS operations (desktop toast notifications, secondary firewall rule sweep, non-critical registry query) are logged as warnings and never panic or abort the daemon.
- **Invariant**: OS errors must be handled gracefully without crashing the core blocking loop.

---

### 3.2 Full Windows Integration & OS Perimeters

FocusGuard interacts directly with Windows OS perimeters:
- **Firewall (`netsh advfirewall`)**: Rules are managed via `internal/infrastructure/enforcer`. Active domain blocks are enforced by sinkholing IP addresses. Orphan rules are swept upon session expiration.
- **Hosts File (`C:\Windows\System32\drivers\etc\hosts`)**: Domain sinkholing (`0.0.0.0`) is written atomically and monitored continuously by `hostswatch`.
- **Windows Service Control Manager (SCM)**: `focusguard-daemon` and `focusguard-watchdog` are registered as Windows services via `golang.org/x/sys/windows/svc`.
- **Windows Registry Autostart**: The user tray app registers under `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`.
- **Process Guard**: Distracting desktop applications are matched by executable name and terminated via Windows Toolhelp32 APIs.
- **Windows Defender & Security Mitigation**: `focusguard doctor` detects Defender false positives on `hosts` (`SettingsModifier:Win32/HostsFileHijack`), verifies exclusion lists (`Add-MpPreference`), monitors Windows Defender Firewall service status (`mpssvc`), and checks for port 53/DNS conflicts (e.g. `SharedAccess`).
- **Authenticode Code Signing**: `scripts/sign-windows.ps1` supports official PFX signing, local self-signed test certificates (`-TestCert` via `New-SelfSignedCertificate`), Windows Certificate Store thumbprints (`-CertThumbprint`), and falls back to PowerShell native `Set-AuthenticodeSignature` when `signtool.exe` is absent.

---

### 3.3 Data flow & Component model

```
CLI (focusguard) ────────┐
Tray (focusguard-tray) ──┼── IPC (loopback TCP / JSON: 48901) ──→ Daemon (focusguard-daemon)
Web (focusguard-web) ────┘                                                │
                                                                     [Scheduler]  ← Source of truth in RAM
                                                                  ┌────────┴────────┐
                                                             [Store]          [Enforcer]
                                                       (atomic state.json)   ┌────┴────┐
                                                                       hosts      Windows Firewall
                                                                  ┌────────┴────────┐
                                                           [HostsWatcher]    [StateWatcher]
                                                          (fsnotify + SHA-256 anti-tamper)
```

### Binaries (`cmd/`)

| Binary | Role | Windows Resources |
|---|---|---|
| `focusguard` | CLI (no args opens web UI) | `cmd/focusguard/versioninfo.json` (icon only, no manifest) |
| `focusguard-daemon` | Privileged background service | `packaging/versioninfo-daemon.json` + manifest (**`requireAdministrator`**) |
| `focusguard-tray` | Unelevated user tray app | `cmd/focusguard-tray/versioninfo.json` (**icon only — NEVER manifest/admin**) |
| `focusguard-watchdog` | Health-check & Smart Recovery | `cmd/focusguard-watchdog/versioninfo.json` (icon + version, no manifest) |
| `focusguard-web` | User-space UI server & IPC proxy | Unelevated — **never** add admin |
| `focusguard-icon` | Build-time icon generator | — |

### Internal layers (`internal/` — 34 packages)

Packages are organized in 4 layers (`docs/reorg-plan.md`):
1. **`domain/`**: Business rules (pure Go, OS-agnostic) — `analytics`, `apps`, `blocks`, `goal`, `interceptor`, `policy`, `pomodoro`, `preset`, `presets`, `recovery`, `schedule`, `scheduler`, `user`, `users`.
2. **`infrastructure/`**: Windows OS I/O — `autostart`, `dns`, `dnsserver`, `enforcer`, `filelog`, `fsutil`, `hostswatch`, `icon`, `processguard`, `statewatch`, `store`, `tamper`, `update`.
3. **`transport/`**: IPC / HTTP & metrics — `eventhub`, `httpapi`, `ipc`, `ipcerr`, `metrics`.
4. **`system/`**: Process lifecycle — `daemon`, `tray`. The external Windows watchdog lives in `cmd/focusguard-watchdog`.

---

## 4. Code conventions

1. **Strict TDD (Test-Driven Development) — MANDATORY (Tests FIRST)**:
   Every feature, business rule, or bug fix MUST strictly follow Red → Green → Refactor. Write the failing unit test before implementing production code, within the same commit. Never push code without automated test coverage.
2. **Per-platform separation**: Desktop targets Windows only. Keep Windows API integrations in `_windows.go` files.
3. **Source of truth in RAM**: The scheduler holds authoritative state in memory; `state.json` is a persisted mirror. On discrepancy, RAM wins and disk is repaired.
4. **Atomic writes & SHA-256 loop prevention**: `store` writes to temp files before rename. Daemon self-writes are hashed (`MarkSelfWrite`) so watchers never trigger recursive loops.
5. **Best-effort OS operations**: Non-critical OS failures (firewall warning, notification error, autostart) log and proceed; they **never crash the daemon**.
6. **Non-blocking IPC**: Tray and web interactions use `SendWithTimeout` (5s max). Handlers must never block GUI threads.
7. **Defensive validation**: Sanitize domains (`sanitizeDomain`), enforce safe bounds (pomodoro max 7 days, daily goal max 1440m), atomic rollbacks on update, sweep orphan firewall rules.
8. **Append-only JSONL logging**: Analytics and tamper event logs append safely; corrupt lines are skipped on read.
9. **Windows resources via `go-winres`**: Run `make icon && make winres` whenever icons or `versioninfo.json` change. Committed `.syso` files are versioned for CI.
10. **Web UI compilation**: Run `make ui` before building `focusguard-web`. Assets are embedded via `go:embed`.
11. **Unelevated user applications**: The tray and web binaries run in user space and must never require administrative elevation.
12. **Shell scripts & BOM**: Shell scripts (`*.sh`) must have LF endings. `install-daemon.ps1` MUST retain its UTF-8 BOM (`EF BB BF`).
13. **Tests mock the OS**: Never invoke real system binaries (`sc.exe`, `iptables`, `systemctl`, `netsh`) in unit tests. Always mock through `execCommand`, `os.Stat`, etc.
14. **IPC registry pattern**: Actions register via `server.Register(action, handler)` and `specs` (`internal/transport/ipc/spec.go`). No monolithic switch statements.
15. **Daily session log**: Update `docs/session-log/YYYY-MM-DD.md` at the end of every working session. `make session-check` validates today's handoff.
16. **Rule synchronization**: Keep `GEMINI.md` and legacy `AGENT.md` synchronized via `make sync-rules`. CI validates parity with `make sync-rules-check`.
17. **Document all changes in AGENTS.md and GEMINI.md**: Any architectural decision, rule change, IPC update, or convention change MUST be documented in both `AGENTS.md` and `GEMINI.md` in the same commit.

---

## 5. Testing, validation, and Definition of Done

### 5.1 GitHub Actions Zero-Failure Protocol (CI Immunity)

The GitHub Actions CI suite (`.github/workflows/test.yml`) runs on `windows-latest` when generating releases (tags `v*`, release publications, or manual `workflow_dispatch`). To guarantee **100% CI pass rate**, every change must respect the following 18 validations:

| # | CI Validation Step | Failure Risk | Prevention Rule |
|---|---|---|---|
| 1 | **Platform policy** (`test-windows-platform.ps1`) | Linux references in `.goreleaser.yaml`, `*_linux*.go`, or `android/` | Pure Windows codebase; no Unix code or Android folders. |
| 2 | **Rule mirrors** | Drift between `GEMINI.md` and `AGENT.md` | Run `make sync-rules` after editing any guideline. |
| 3 | **PowerShell syntax** | Syntax errors in `scripts/*.ps1` | Validate via PowerShell AST parser. |
| 4 | **Installer UTF-8 BOM** | Missing BOM (`EF BB BF`) in `install-daemon.ps1` | Preserve UTF-8 BOM when editing. |
| 5 | **Go formatting** | Unformatted Go files | Always run `gofmt -w .`. |
| 6 | **IPC contract** | Drift in `focusguard-ui/src/api/types.ts` | Run `make contract` after updating IPC Go structs. |
| 7 | **UI dependencies & audit** | High/critical npm security vulnerabilities | Run `npm audit --audit-level=high` in `focusguard-ui/`. |
| 8 | **UI unit tests** | Broken Vitest specs | Run `npm test` in `focusguard-ui/`. |
| 9 | **UI production build** | TypeScript compilation error | Run `npm run build` in `focusguard-ui/`. |
| 10 | **Embed UI assets** | Missing `dist/index.html` in web assets | Copy build output into `cmd/focusguard-web/assets/`. |
| 11 | **Go build & vet** | Build failure or `vet` diagnostics | Run `go build ./...` and `go vet ./...`. |
| 12 | **Go unit tests** | Unmocked OS calls failing in unprivileged runner | **Mock all OS binaries (`netsh`, `sc.exe`, `hosts`) in tests.** |
| 13 | **Windows executables** | Build failure in any of the 5 binaries | Verify building all 5 `.exe` binaries. |
| 14 | **Embedded tray icon** | Icon missing from resources | Run `make icon && make winres`. |
| 15 | **Go vulnerability audit** | Vulnerable Go dependency | Run `govulncheck ./...`. |
| 16 | **Session log structure** | Malformed log in `docs/session-log/` | Adhere strictly to the `YYYY-MM-DD.md` template. |
| 17 | **Windows ARM64 build** | CGO or architecture-specific assembly | Keep `CGO_ENABLED=0` and architecture-neutral APIs. |
| 18 | **Windows race detector** | Data race caught under `go test -race` | Protect shared concurrent state with mutexes or atomics. |

### 5.2 Definition of Done — all items must pass before completion:

- [ ] `go build ./...` succeeds
- [ ] `go vet ./...` succeeds
- [ ] `gofmt -l .` reports no unformatted files (or run `gofmt -w .`)
- [ ] `go test ./... -count=1 -timeout=60s` passes
- [ ] `make sync-rules-check` passes (zero drift between `GEMINI.md` and `AGENT.md`)
- [ ] `make session-check` passes (today's handoff log exists in `docs/session-log/`)
- [ ] `git status` shows no stray compiled artifacts
- [ ] New code is fully covered by automated tests written first (TDD)
- [ ] Commit message follows Conventional Commits format
- [ ] Any architectural, convention, or rule changes are documented in `AGENTS.md` and `GEMINI.md`

```bash
go build ./...
go vet ./...
go test ./... -count=1 -timeout=60s
make sync-rules-check
make session-check
```

---

## 6. Relevant file structure

```
├── AGENTS.md                   # Primary executive agent & developer guidelines
├── GEMINI.md                   # Primary repo guide (AGENT.md is an exact mirror)
├── docs/                       # Specifications, plans, and daily session logs
│   ├── ui-plan.md              # Web UI plan & API contract (12 screens)
│   ├── bug-hunt-plan.md        # Bug-hunt history and regression tests
│   ├── development.md          # Windows build and validation workflow
│   ├── release.md              # Release checklist and procedures
│   └── session-log/            # Daily handoff summaries (YYYY-MM-DD.md)
├── Makefile                    # build, ui, test, sync-rules, sync-rules-check, session-check
├── cmd/                        # 6 binary entry points (CLI, daemon, tray, watchdog, web, icon)
├── internal/                   # 34 internal packages across domain, infra, transport, system
├── focusguard-ui/              # React 18 + Vite + TS frontend (12 screens)
├── packaging/                  # Icons, manifests, Windows versioninfo
└── scripts/                    # Installer scripts, WiX templates, validation utilities
```

---

## 7. Commit conventions

**Conventional Commits, in English, with scope:**

```
<type>(<scope>): <short imperative description>
```

- **Types**: `feat`, `fix`, `perf`, `docs`, `test`, `ci`, `chore`.
- **Common scopes**: `ui`, `install`, `icon`, `tray`, `update`, `store`, `scheduler`, `enforcer`, `watchers`, `daemon`, `ipc`, `autostart`, `dns`, `session`.
- **Rules**:
  - One commit per coherent change. Keep descriptions ≤ 72 chars in lowercase imperative mood.
  - Never include automated agent or tool footers ("Generated with...", "Co-Authored-By:...").

---

## 8. Release

Releases are executed manually following `docs/release.md`. Publishing a Git tag `vX.Y.Z` triggers the CI GoReleaser pipeline. Always confirm version numbers and changelog entries before creating release tags.

---

## 9. Known pitfalls & Gotchas

- **Daemon privileges on Windows**: `focusguard-daemon` requires administrative elevation. Running `go test ./cmd/focusguard-daemon/...` on Windows requires an elevated prompt. Use the Windows validation workflow for automated tests.
- **Tray is unprivileged**: Never add an elevation manifest to the tray.
- **Immediate daemon restart on update**: Applying an update terminates any active pomodoro session and restarts the daemon immediately (exit code 1 → supervisor restarts with new binary). Persisted blocks in `state.json` are retained and restored.
- **Windows binary swap locks**: Before updating executables on Windows, the daemon terminates the tray and stops the watchdog service to unlock `.exe` files. If replacement is locked, `MoveFileEx(MOVEFILE_DELAY_UNTIL_REBOOT)` schedules swap on reboot.
- **IPC contract synchronization**: The IPC wire format is shared between CLI, tray, daemon, and web UI. Run `make contract` to update `focusguard-ui/src/api/types.ts` whenever IPC types change, and verify with `make contract-check`.
- **Default web port**: `48902` is defined canonically in `httpapi.DefaultAddr`. Never hardcode literal port numbers across packages.
- **GoReleaser hooks without shell**: The `go-winres` hook in `.goreleaser.yaml` invokes `sh -c` because GoReleaser does not execute hooks inside a subshell.
- **OS mocking in tests**: Never call real Windows OS binaries (`netsh`, `sc.exe`, `hosts`) in unit tests. GitHub Actions runners execute unprivileged; unmocked calls will fail or corrupt runner state.
- **Rule synchronization**: Always run `make sync-rules` after updating `GEMINI.md`.

---

## 10. Glossary

- **Self-write**: A write to `hosts` or `state.json` initiated by the daemon itself, marked with a cryptographic hash to avoid triggering tamper alerts.
- **Reconcile**: The scheduler re-evaluates in-memory state and re-enforces active rules at the OS level (hosts, DNS, firewall) to correct external drift.
- **Source of truth in RAM**: `state.json` reflects scheduler memory; on divergence, memory prevails and disk is repaired.
- **Tamper**: Any external unauthorized modification to `hosts` or `state.json` that attempts to weaken or bypass active blocks.
- **Best-effort**: Operations whose failures are logged as warnings but never abort daemon execution.
- **Smart Recovery**: The watchdog service's automatic rollback mechanism to restore previous working binaries when an update fails health checks.
