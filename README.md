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
| `infra/` | Docker init scripts, Cloud Run deploy script |
| `docs/` | API contract and design notes |

## Prerequisites (macOS)

- Xcode 26+, `brew install go golangci-lint xcodegen swiftformat`, Docker Desktop
- Node ≥ 22.13 for pnpm (`nvm use` reads `.nvmrc`); pnpm is only a task runner, there are no JS dependencies

## Status (2026-08-24)

- `services/api`: complete — auth (Supabase JWKS + allowlist, dev bypass), 12 h Jikan cache with stale-on-error, catalog, library, franchise chain, schedule; unit + integration tests, golden fixtures, Cloud Run scripts.
- `apple/`: iOS app (all screens, Liquid Glass shell, local notifications, background refresh), Watch app (list, +1, outbox, WatchConnectivity sync with a dedicated Supabase session), complication. Verified in the iOS 26.5 / watchOS 26.5 simulators against the local API.
- Pending user-side setup: Supabase project + Google OAuth clients (`apple/Configs/Secrets.xcconfig`, `.env`), Google Cloud project for Cloud Run, Apple ID in Xcode (`apple/Configs/Local.xcconfig`).

## Quick start

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
