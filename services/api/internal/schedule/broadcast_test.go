package schedule

import (
	"errors"
	"testing"
	"time"
)

func TestNextAiringJSTToUTC(t *testing.T) {
	// Sunday 2026-08-23 12:00 UTC; Frieren airs Fridays 23:00 JST = Fridays 14:00 UTC.
	after := time.Date(2026, 8, 23, 12, 0, 0, 0, time.UTC)
	got, err := NextAiring("Fridays", "23:00", "Asia/Tokyo", after, nil)
	if err != nil {
		t.Fatal(err)
	}
	want := time.Date(2026, 8, 28, 14, 0, 0, 0, time.UTC)
	if !got.Equal(want) {
		t.Fatalf("got %v want %v", got, want)
	}
}

func TestNextAiringCrossesMidnight(t *testing.T) {
	// Saturday 01:30 JST slots fall on Friday 16:30 UTC.
	after := time.Date(2026, 8, 28, 15, 0, 0, 0, time.UTC) // Friday 15:00 UTC = Saturday 00:00 JST
	got, err := NextAiring("Saturdays", "01:30", "Asia/Tokyo", after, nil)
	if err != nil {
		t.Fatal(err)
	}
	want := time.Date(2026, 8, 28, 16, 30, 0, 0, time.UTC)
	if !got.Equal(want) {
		t.Fatalf("got %v want %v", got, want)
	}
}

func TestNextAiringSameDayLaterAndEarlier(t *testing.T) {
	// Friday 13:00 UTC = Friday 22:00 JST -> same day 23:00 JST.
	after := time.Date(2026, 8, 28, 13, 0, 0, 0, time.UTC)
	got, _ := NextAiring("Friday", "23:00", "Asia/Tokyo", after, nil)
	if !got.Equal(time.Date(2026, 8, 28, 14, 0, 0, 0, time.UTC)) {
		t.Fatalf("same-day slot expected, got %v", got)
	}
	// Friday 14:00 UTC exactly is not strictly after -> next week.
	got, _ = NextAiring("Friday", "23:00", "Asia/Tokyo", time.Date(2026, 8, 28, 14, 0, 0, 0, time.UTC), nil)
	if !got.Equal(time.Date(2026, 9, 4, 14, 0, 0, 0, time.UTC)) {
		t.Fatalf("next-week slot expected, got %v", got)
	}
}

func TestNextAiringHonorsPremiere(t *testing.T) {
	after := time.Date(2026, 8, 23, 12, 0, 0, 0, time.UTC)
	premiere := time.Date(2026, 10, 2, 0, 0, 0, 0, time.UTC) // Friday
	got, err := NextAiring("Fridays", "23:00", "Asia/Tokyo", after, &premiere)
	if err != nil {
		t.Fatal(err)
	}
	if !got.Equal(time.Date(2026, 10, 2, 14, 0, 0, 0, time.UTC)) {
		t.Fatalf("premiere slot expected, got %v", got)
	}
}

func TestNextAiringUnknown(t *testing.T) {
	cases := [][3]string{{"Unknown", "23:00", "Asia/Tokyo"}, {"Fridays", "", "Asia/Tokyo"}, {"Fridays", "25:00", "Asia/Tokyo"}, {"Fridays", "23:00", "Mars/Olympus"}}
	for _, c := range cases {
		if _, err := NextAiring(c[0], c[1], c[2], time.Now(), nil); !errors.Is(err, ErrUnknownBroadcast) {
			t.Fatalf("%v: expected ErrUnknownBroadcast, got %v", c, err)
		}
	}
}
