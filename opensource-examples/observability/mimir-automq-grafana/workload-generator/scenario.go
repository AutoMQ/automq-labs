package main

import (
	"encoding/json"
	"net/http"
	"strings"
	"time"
)

func (w *workload) handleScenario(rw http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(rw, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	w.mu.RLock()
	defer w.mu.RUnlock()
	rw.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(rw).Encode(w.scenario)
}

func (w *workload) handleSetScenario(rw http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(rw, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	name := strings.TrimPrefix(r.URL.Path, "/scenario/")
	cfg := scenarioConfig{Name: name}
	switch name {
	case "normal":
		cfg.Multiplier = 1
		cfg.ErrorRate = 0.006
		cfg.Series = 50
	case "spike":
		cfg.Multiplier = queryFloat(r, "multiplier", 8)
		cfg.ErrorRate = queryFloat(r, "error_rate", 0.018)
		cfg.Series = queryInt(r, "series", 80)
	case "failure":
		cfg.Multiplier = queryFloat(r, "multiplier", 3)
		cfg.ErrorRate = queryFloat(r, "error_rate", 0.14)
		cfg.Series = queryInt(r, "series", 80)
	case "recover":
		cfg.Multiplier = queryFloat(r, "multiplier", 2)
		cfg.ErrorRate = queryFloat(r, "error_rate", 0.025)
		cfg.Series = queryInt(r, "series", 80)
	case "cardinality-spike":
		cfg.Multiplier = queryFloat(r, "multiplier", 4)
		cfg.ErrorRate = queryFloat(r, "error_rate", 0.018)
		cfg.Series = queryInt(r, "series", 3000)
	default:
		http.Error(rw, "unknown scenario", http.StatusBadRequest)
		return
	}

	if d := queryDuration(r, "duration", 0); d > 0 {
		cfg.Until = time.Now().Add(d)
	}

	w.mu.Lock()
	w.scenario = cfg
	w.mu.Unlock()

	rw.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(rw).Encode(cfg)
}
