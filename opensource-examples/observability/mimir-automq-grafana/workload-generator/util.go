package main

import (
	"math"
	"net/http"
	"strconv"
	"strings"
	"time"
)

func queryFloat(r *http.Request, name string, fallback float64) float64 {
	raw := r.URL.Query().Get(name)
	if raw == "" {
		return fallback
	}
	value, err := strconv.ParseFloat(raw, 64)
	if err != nil {
		return fallback
	}
	return value
}

func queryInt(r *http.Request, name string, fallback int) int {
	raw := r.URL.Query().Get(name)
	if raw == "" {
		return fallback
	}
	value, err := strconv.Atoi(raw)
	if err != nil || value < 1 {
		return fallback
	}
	if value > 10000 {
		return 10000
	}
	return value
}

func queryDuration(r *http.Request, name string, fallback time.Duration) time.Duration {
	raw := r.URL.Query().Get(name)
	if raw == "" {
		return fallback
	}
	value, err := time.ParseDuration(raw)
	if err != nil {
		return fallback
	}
	return value
}

func reasonFor(regionIndex, channelIndex int) string {
	reasons := []string{"card_declined", "risk_control", "provider_timeout", "insufficient_funds"}
	return reasons[(regionIndex+channelIndex)%len(reasons)]
}

func label(parts ...string) string {
	return strings.Join(parts, "\xff")
}

func clamp(v, low, high float64) float64 {
	return math.Max(low, math.Min(high, v))
}

func formatFloat(v float64) string {
	return strconv.FormatFloat(v, 'f', -1, 64)
}
