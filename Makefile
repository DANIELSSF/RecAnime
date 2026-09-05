# Same commands as package.json, without depending on pnpm/Node. Usage: make api
SHELL := /bin/sh
export CLOUDSDK_ACTIVE_CONFIG_NAME := recanime

IOS_DEST := platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5
WATCH_DEST := platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.5
# Without this file xcodebuild writes the app-level SwiftPM lock into
# packages/RecAnimeKit/Package.resolved, which is committed. Seed it once.
WS_RESOLVED := apple/RecAnime.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved

.PHONY: help \
	db-up db-down db-reset db-psql db-logs \
	api api-build api-test api-test-it api-lint api-vet api-fmt \
	migrate migrate-status api-docker-build api-docker-run lan \
	apple-gen apple-build apple-test apple-test-all apple-test-kit apple-test-ui-pkg \
	apple-watch-build apple-runtime-watch apple-fmt apple-lint apple-lint-tokens \
	fixtures-sync deploy-api

help:             ## every target in this file
	@awk -F: '/^[a-z-]+:/ { doc = ""; if (match($$0, /## /)) doc = substr($$0, RSTART + 3); printf "  %-20s %s\n", $$1, doc }' Makefile

db-up:            ## Postgres 17 in Docker on 127.0.0.1:5433
	docker compose up -d db

db-down:
	docker compose down

db-reset:
	docker compose down -v && docker compose up -d db

db-psql:
	docker compose exec db psql -U recanime -d recanime

db-logs:          ## follow the database container logs
	docker compose logs -f db

api: db-up        ## run the API locally (reads .env)
	set -a && . ./.env && set +a && cd services/api && go run ./cmd/api serve

api-build:
	cd services/api && go build -trimpath -o bin/api ./cmd/api

api-test:
	cd services/api && go test ./... -race -count=1

api-test-it:
	cd services/api && TEST_DATABASE_URL=postgres://recanime:recanime@127.0.0.1:5433/recanime_test?sslmode=disable go test ./... -race -count=1 -p 1

api-lint:
	cd services/api && golangci-lint run

api-vet:
	cd services/api && go vet ./...

api-fmt:
	cd services/api && gofmt -l -w . && go mod tidy

migrate:
	set -a && . ./.env && set +a && cd services/api && go run ./cmd/api migrate up

migrate-status:
	set -a && . ./.env && set +a && cd services/api && go run ./cmd/api migrate status

api-docker-build:
	docker build -t recanime-api:local services/api

api-docker-run:
	docker run --rm --name recanime-api -p 8080:8080 --env-file .env -e DATABASE_URL=postgres://recanime:recanime@host.docker.internal:5433/recanime?sslmode=disable recanime-api:local

apple-gen:
	cd apple && xcodegen generate
	@mkdir -p $(dir $(WS_RESOLVED))
	@[ -f $(WS_RESOLVED) ] || echo '{"pins":[],"version":3}' > $(WS_RESOLVED)

apple-build: apple-gen
	xcodebuild -project apple/RecAnime.xcodeproj -scheme RecAnime -destination '$(IOS_DEST)' build

apple-test: apple-gen  ## unit bundle only (RecAnimeTests)
	xcodebuild -project apple/RecAnime.xcodeproj -scheme RecAnime -destination '$(IOS_DEST)' test -only-testing:RecAnimeTests

apple-test-all: apple-gen  ## whole scheme test action (unit + UI bundles)
	xcodebuild -project apple/RecAnime.xcodeproj -scheme RecAnime -destination '$(IOS_DEST)' test

apple-test-kit:
	swift test --package-path packages/RecAnimeKit

apple-test-ui-pkg:
	swift test --package-path packages/RecAnimeUI

apple-watch-build: apple-gen
	xcodebuild -project apple/RecAnime.xcodeproj -scheme RecAnimeWatch -destination '$(WATCH_DEST)' build

apple-runtime-watch:  ## download the watchOS simulator runtime
	xcodebuild -downloadPlatform watchOS

apple-fmt:
	swiftformat apple packages

apple-lint:
	swiftformat apple packages --lint

apple-lint-tokens:  ## fail on colors outside the design tokens
	sh apple/scripts/check-theme-tokens.sh

fixtures-sync:    ## copy the Go golden files into the Swift fixtures
	cp services/api/testdata/golden/*.json packages/RecAnimeKit/Sources/RecAnimeKitTesting/Fixtures/

deploy-api:
	sh infra/gcp/deploy.sh

lan:              ## API in Docker, published on the LAN for a physical iPhone/Watch
	docker build -t recanime-api:local services/api
	docker run --rm --name recanime-api -p 8080:8080 --env-file .env -e DATABASE_URL=postgres://recanime:recanime@host.docker.internal:5433/recanime?sslmode=disable recanime-api:local
