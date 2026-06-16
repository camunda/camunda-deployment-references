package utils

import "testing"

func TestIncrementMinorVersionTwoParts(t *testing.T) {
	tests := []struct {
		name      string
		version   string
		expected  string
		expectErr bool
	}{
		{name: "standard minor bump", version: "1.34", expected: "1.35"},
		{name: "minor rolls over tens", version: "1.29", expected: "1.30"},
		{name: "zero minor", version: "2.0", expected: "2.1"},
		{name: "too many parts", version: "1.34.0", expectErr: true},
		{name: "too few parts", version: "134", expectErr: true},
		{name: "non numeric minor", version: "1.x", expectErr: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := IncrementMinorVersionTwoParts(tt.version)
			if tt.expectErr {
				if err == nil {
					t.Fatalf("expected an error for version %q, got none", tt.version)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error for version %q: %v", tt.version, err)
			}
			if got != tt.expected {
				t.Fatalf("IncrementMinorVersionTwoParts(%q) = %q, want %q", tt.version, got, tt.expected)
			}
		})
	}
}

func TestDecrementMinorVersionTwoParts(t *testing.T) {
	tests := []struct {
		name      string
		version   string
		expected  string
		expectErr bool
	}{
		{name: "standard minor drop", version: "1.35", expected: "1.34"},
		{name: "minor rolls under tens", version: "1.30", expected: "1.29"},
		{name: "cannot go below zero", version: "1.0", expectErr: true},
		{name: "too many parts", version: "1.34.0", expectErr: true},
		{name: "too few parts", version: "134", expectErr: true},
		{name: "non numeric minor", version: "1.x", expectErr: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := DecrementMinorVersionTwoParts(tt.version)
			if tt.expectErr {
				if err == nil {
					t.Fatalf("expected an error for version %q, got none", tt.version)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error for version %q: %v", tt.version, err)
			}
			if got != tt.expected {
				t.Fatalf("DecrementMinorVersionTwoParts(%q) = %q, want %q", tt.version, got, tt.expected)
			}
		})
	}
}

// TestIncrementDecrementRoundTrip ensures the two helpers are inverses for the
// version range the upgrade test relies on (start = latest - 1, target = start + 1).
func TestIncrementDecrementRoundTrip(t *testing.T) {
	for _, latest := range []string{"1.30", "1.34", "1.35", "1.40"} {
		start, err := DecrementMinorVersionTwoParts(latest)
		if err != nil {
			t.Fatalf("DecrementMinorVersionTwoParts(%q) unexpected error: %v", latest, err)
		}
		target, err := IncrementMinorVersionTwoParts(start)
		if err != nil {
			t.Fatalf("IncrementMinorVersionTwoParts(%q) unexpected error: %v", start, err)
		}
		if target != latest {
			t.Fatalf("round trip mismatch: latest=%q start=%q target=%q", latest, start, target)
		}
	}
}
