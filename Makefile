# Same commands as package.json, without depending on pnpm/Node. Usage: make api
SHELL := /bin/sh
export CLOUDSDK_ACTIVE_CONFIG_NAME := recanime

.PHONY: help db-up db-down db-reset db-psql api api-build api-test api-test-it api-lint migrate apple-gen apple-build apple-test lan

help:
	@grep -E '^[a-z-]+:' Makefile | cut -d: -f1 | tr '\n' ' '; echo

db-up:            ## Postgres 17 in Docker on 127.0.0.1:5433
	docker compose up -d db

db-down:
	docker compose down

db-reset:
	docker compose down -v && docker compose up -d db

db-psql:
	docker compose exec db psql -U recanime -d recanime

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

migrate:
	set -a && . ./.env && set +a && cd services/api && go run ./cmd/api migrate up

apple-gen:
	cd apple && xcodegen generate

apple-build: apple-gen
	xcodebuild -project apple/RecAnime.xcodeproj -scheme RecAnime -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build

apple-test: apple-gen
	xcodebuild -project apple/RecAnime.xcodeproj -scheme RecAnime -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build test

lan:              ## API in Docker, published on the LAN for a physical iPhone/Watch
	docker build -t recanime-api:local services/api
	docker run --rm --name recanime-api -p 8080:8080 --env-file .env -e DATABASE_URL=postgres://recanime:recanime@host.docker.internal:5433/recanime?sslmode=disable recanime-api:local
