# Repository Guidelines

## Project Structure & Module Organization

FocusGuard blocks distracting websites and applications on Windows.

- `cmd/`: Go entry points for CLI, daemon, tray, watchdog, web server, and icon generator.
- `internal/`: `domain/` business rules, `infrastructure/` OS integration, `transport/` IPC/HTTP, and `system/` process lifecycle. Keep domain packages independent of transport.
- `focusguard-ui/src/`: React/TypeScript screens, components, hooks, and API bindings; tests live beside source files.
- `packaging/`, `scripts/`: artwork, installers, and build utilities. `docs/` contains specifications and session logs.

## Build, Test, and Development Commands

Use Go 1.26.5 and Node/npm for the UI. Make targets require Git Bash and Make; use `scripts/validate-windows.ps1` for native Windows checks.

- `make ui` then `make build`: compile/embed frontend assets, then build CLI, daemon, and web binaries into `bin/`.
- In `focusguard-ui/`, run `npm ci` then `npm run dev` for Vite development; run the Go web server for proxied API requests.
- `make test`: run Go tests with a 60-second timeout.
- `go build ./...` and `go vet ./...`: check compilation and Go diagnostics.
- In `focusguard-ui/`, use `npm test` for Vitest and `npm run typecheck` for TypeScript validation.

## Coding Style & Naming Conventions

Format Go with `gofmt` (tabs); follow existing two-space TypeScript indentation. Use PascalCase React components and `use...` hook names. Isolate platform implementations with `_windows.go` suffixes. Write identifiers/comments in English and user-facing strings in Brazilian Portuguese.

## Testing Guidelines

Follow test-first development for features and fixes. Use Go `testing` (`*_test.go`) and Vitest/React Testing Library (`*.test.tsx` or `*.test.ts`). Cover changed behavior; no numeric coverage threshold is configured. Mock OS commands in unit tests. Windows CI also runs the full Go race detector suite.

## Commit & Pull Request Guidelines

History follows English Conventional Commits: `fix(ci): resolve Windows signing`. Prefer scoped, imperative subjects under 72 characters; omit automated attribution footers. Keep commits cohesive. PRs should explain behavior changes, link relevant issues, report validation, and include screenshots for UI changes.

## Contracts & Repository Workflow

Read `GEMINI.md`, its mirrored `AGENT.md`, and area-specific guides before code changes. Regenerate IPC bindings with `make contract`; verify with `make contract-check`. Generate icons/resources through `make icon` and `make winres`. Keep tray/web unelevated. Record session handoffs in `docs/session-log/YYYY-MM-DD.md`; run `make session-check` and `make sync-rules-check`.
