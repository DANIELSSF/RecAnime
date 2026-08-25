package auth

import (
	"crypto/sha1" //nolint:gosec // UUIDv5 is defined over SHA-1; not used for security
	"fmt"
	"strings"
)

// recanimeNamespace is a fixed UUID used to derive deterministic dev user ids from emails.
var recanimeNamespace = [16]byte{0x7a, 0x3f, 0x1c, 0x2e, 0x9b, 0x4d, 0x4f, 0x61, 0x8e, 0x2a, 0x5c, 0x7d, 0x0b, 0x9e, 0x6f, 0x11}

// DevPrincipal builds the principal used when DEV_BYPASS_AUTH is enabled. The user id is a
// UUIDv5 of the email so the same email always maps to the same database user.
func DevPrincipal(email string) Principal {
	email = strings.ToLower(strings.TrimSpace(email))
	h := sha1.New() //nolint:gosec // see above
	h.Write(recanimeNamespace[:])
	h.Write([]byte(email))
	sum := h.Sum(nil)
	var u [16]byte
	copy(u[:], sum[:16])
	u[6] = (u[6] & 0x0f) | 0x50 // version 5
	u[8] = (u[8] & 0x3f) | 0x80 // RFC 4122 variant
	id := fmt.Sprintf("%x-%x-%x-%x-%x", u[0:4], u[4:6], u[6:8], u[8:10], u[10:16])
	name := email
	if at := strings.IndexByte(email, '@'); at > 0 {
		name = email[:at]
	}
	return Principal{UserID: id, Email: email, Name: name}
}
