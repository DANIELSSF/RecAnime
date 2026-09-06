# RecAnime

Personal anime tracker (2 users) built on the [Jikan](https://jikan.moe) API.
Monorepo: Go API (`services/api`), iOS 26 / watchOS 26 SwiftUI apps (`apple/`, `packages/`), PostgreSQL on Supabase, Google login via Supabase Auth, API hosted on Google Cloud Run.

## Layout

| Path | What |
|---|---|
| `services/api` | Go HTTP API: Jikan proxy with a 12 h DB cache, per-user library, schedule |
| `apple/` | XcodeGen project: `RecAnime` (iOS), `RecAnimeWatch` (watchOS), `RecAnimeWatchWidgets` |
| `packages/RecAnimeKit` | Swift package: models, API client, stores (iOS + watchOS) |
| `packages/RecAnimeUI` | Swift package: design tokens + reusable components |
| `infra/` | Docker init scripts, guarded Cloud Run scripts, database backup/restore |
| `docs/` | API contract, deployment runbook, design notes |

## Prerequisites (macOS)

- Xcode 26+, `brew install go golangci-lint xcodegen swiftformat`, Docker Desktop
- Node ≥ 22.13 for pnpm (`nvm use` reads `.nvmrc`); pnpm is only a task runner, there are no JS dependencies

## Status (2026-09-05)

- `services/api`: complete — auth (Supabase JWKS + allowlist, dev bypass), 12 h Jikan cache with stale-on-error, catalog, library, franchise chain, schedule; unit + integration tests, golden fixtures, Cloud Run scripts. Recent hardening landed: server-side SFW filtering, filter-only browse on `/v1/search`, batch library upsert, user re-key, request budgets and resilient boot.
- `apple/`: iOS app (all screens, Liquid Glass shell, local notifications, background refresh), Watch app (list, +1, outbox), complication. The phone↔watch session and sync path (WatchConnectivity with a dedicated Supabase session) landed. Verified in the iOS 26.5 / watchOS 26.5 simulators against the local API.
- CI covers both sides: `api-ci` for Go, `swift-ci` for the Swift packages and the Xcode apps (see [CI](#ci)).
- Pending user-side setup (browser + billing, nothing automatable): Supabase project + Google OAuth clients (`apple/Configs/Secrets.xcconfig`), Google Cloud project for Cloud Run, Apple ID in Xcode (`apple/Configs/Local.xcconfig`). **[docs/runbook.md](docs/runbook.md) walks through all of it step by step**, then covers day-2 operations (logs, rollback, key rotation, backups).

## Quick start

pnpm needs Node ≥ 22.13: run `nvm use` first (reads `.nvmrc`). Every pnpm script also exists as a `make` target for
shells without nvm: same name with `:` replaced by `-` (`pnpm api:test` → `make api-test`), except `pnpm api:dev` →
`make api` and `pnpm api:lan` → `make lan`. `make help` lists them all.

```sh
nvm use
cp .env.example .env
pnpm db:up          # Postgres 17 on 127.0.0.1:5433
pnpm migrate        # applies embedded goose migrations
pnpm api:dev        # http://localhost:8080/healthz
pnpm api:test       # unit tests
pnpm api:test:it    # integration tests against the Docker database
```

Without Supabase credentials the API can run with `DEV_BYPASS_AUTH=true` (development only) and the debug app talks to it
without signing in; `UPDATE_GOLDEN=1 pnpm api:test:it && pnpm fixtures:sync` refreshes the JSON fixtures the Swift package decodes.

API contract: `docs/api-contract.md`. Design canvas sources: `docs/design/` (`node docs/design/build-canvas.mjs`).

Apple side: `pnpm apple:gen` then open `apple/RecAnime.xcodeproj` (see `apple/README.md` for signing and device steps).
`pnpm apple:test` runs the unit bundle only (`RecAnimeTests`); `pnpm apple:test:all` runs the whole scheme test action
(unit + UI bundles, which self-skip unless their env flags are set). `pnpm apple:test:kit` and `pnpm apple:test:ui-pkg`
run the Swift package suites without Xcode.

## Deploy

Everything is scripted behind guards: the scripts pin gcloud to the personal `recanime`
configuration, refuse to run unless it is signed in as `GCP_ACCOUNT`, and print the whole plan
without touching anything when `DRY_RUN=1`. Start at [docs/runbook.md](docs/runbook.md).

```sh
cp infra/gcp/.env.deploy.example infra/gcp/.env.deploy   # then fill it in
set -a; . infra/gcp/.env.deploy; set +a
DATABASE_URL='<supabase session pooler url>' sh infra/gcp/bootstrap.sh   # once
make deploy-api                                          # sha-tagged image, /healthz verified
sh infra/gcp/allowlist.sh 'a@example.com,b@example.com'   # who may sign in, no rebuild
sh infra/gcp/rollback.sh                                  # list revisions, then roll one back
```

Back up the three tables that are not a rebuildable cache before every migration:
`DATABASE_URL='…' make db-backup` writes `backups/recanime-<UTC>.dump`;
`CONFIRM=yes make db-restore FILE=…` puts it back.

## CI

| Workflow | Runs on | Checks |
|---|---|---|
| `.github/workflows/api-ci.yml` | `ubuntu-latest`, paths `services/api/**` | `go vet`, unit + integration tests against a Postgres 17 service, `gofmt`, `golangci-lint`, `govulncheck` |
| `.github/workflows/swift-ci.yml` | `macos-26`, paths `packages/**`, `apple/**`, `.swiftformat`, golden fixtures | `swift test` for both packages, `swiftformat --lint`, the theme-token script, the Go→Swift fixture diff, and `xcodebuild` builds of the iOS and watchOS apps plus `RecAnimeTests` |

Both workflows cancel superseded runs on the same ref. `.github/dependabot.yml` opens weekly updates for Go modules,
GitHub Actions and the Swift package.
