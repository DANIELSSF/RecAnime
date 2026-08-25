// Package migrations embeds the SQL migration files applied by goose at startup.
package migrations

import "embed"

// FS holds the goose SQL migrations (NNNNN_name.sql).
//
//go:embed *.sql
var FS embed.FS
