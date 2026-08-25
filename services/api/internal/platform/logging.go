// Package platform holds process-level wiring: logging, versioning helpers.
package platform

import (
	"io"
	"log/slog"
	"strings"
)

// NewLogger builds the process logger. Production emits JSON with the field names Cloud Logging
// understands (severity, message); development emits human-readable text.
func NewLogger(w io.Writer, production bool, level string) *slog.Logger {
	var lvl slog.Level
	switch strings.ToLower(level) {
	case "debug":
		lvl = slog.LevelDebug
	case "warn", "warning":
		lvl = slog.LevelWarn
	case "error":
		lvl = slog.LevelError
	default:
		lvl = slog.LevelInfo
	}
	if !production {
		return slog.New(slog.NewTextHandler(w, &slog.HandlerOptions{Level: lvl}))
	}
	return slog.New(slog.NewJSONHandler(w, &slog.HandlerOptions{
		Level: lvl,
		ReplaceAttr: func(_ []string, a slog.Attr) slog.Attr {
			switch a.Key {
			case slog.LevelKey:
				a.Key = "severity"
				if l, ok := a.Value.Any().(slog.Level); ok {
					a.Value = slog.StringValue(severity(l))
				}
			case slog.MessageKey:
				a.Key = "message"
			}
			return a
		},
	}))
}

func severity(l slog.Level) string {
	switch {
	case l >= slog.LevelError:
		return "ERROR"
	case l >= slog.LevelWarn:
		return "WARNING"
	case l >= slog.LevelInfo:
		return "INFO"
	default:
		return "DEBUG"
	}
}
