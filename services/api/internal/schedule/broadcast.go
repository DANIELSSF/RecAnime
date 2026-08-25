// Package schedule computes when the next episode of a watched anime airs.
package schedule

import (
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"
)

// ErrUnknownBroadcast is returned when MAL has no usable day/time for the anime.
var ErrUnknownBroadcast = errors.New("schedule: unknown broadcast slot")

var weekdays = map[string]time.Weekday{
	"monday": time.Monday, "tuesday": time.Tuesday, "wednesday": time.Wednesday, "thursday": time.Thursday,
	"friday": time.Friday, "saturday": time.Saturday, "sunday": time.Sunday,
}

// ParseDay accepts MAL's "Fridays"/"Friday" spelling.
func ParseDay(day string) (time.Weekday, bool) {
	d := strings.ToLower(strings.TrimSpace(day))
	d = strings.TrimSuffix(d, "s")
	wd, ok := weekdays[d]
	return wd, ok
}

// ParseClock parses "23:00".
func ParseClock(s string) (hour, minute int, err error) {
	parts := strings.Split(strings.TrimSpace(s), ":")
	if len(parts) != 2 {
		return 0, 0, fmt.Errorf("%w: time %q", ErrUnknownBroadcast, s)
	}
	h, err1 := strconv.Atoi(parts[0])
	m, err2 := strconv.Atoi(parts[1])
	if err1 != nil || err2 != nil || h < 0 || h > 23 || m < 0 || m > 59 {
		return 0, 0, fmt.Errorf("%w: time %q", ErrUnknownBroadcast, s)
	}
	return h, m, nil
}

// NextAiring returns the first broadcast slot strictly after `after` (UTC). notBefore (usually the
// premiere date) moves the search forward for shows that have not started yet.
func NextAiring(day, clock, tz string, after time.Time, notBefore *time.Time) (time.Time, error) {
	wd, ok := ParseDay(day)
	if !ok {
		return time.Time{}, fmt.Errorf("%w: day %q", ErrUnknownBroadcast, day)
	}
	h, m, err := ParseClock(clock)
	if err != nil {
		return time.Time{}, err
	}
	if tz == "" {
		tz = "Asia/Tokyo"
	}
	loc, err := time.LoadLocation(tz)
	if err != nil {
		return time.Time{}, fmt.Errorf("%w: timezone %q", ErrUnknownBroadcast, tz)
	}
	start := after
	if notBefore != nil && notBefore.After(start) {
		// The premiere itself is a valid slot, so search from just before it.
		start = notBefore.Add(-time.Second)
	}
	local := start.In(loc)
	candidate := time.Date(local.Year(), local.Month(), local.Day(), h, m, 0, 0, loc)
	for i := 0; i < 8; i++ {
		if candidate.Weekday() == wd && candidate.After(start) {
			return candidate.UTC(), nil
		}
		candidate = candidate.AddDate(0, 0, 1)
	}
	return time.Time{}, ErrUnknownBroadcast
}
