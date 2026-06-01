package main

import (
	"fmt"
	"math"
	"math/rand"
	"sync"
	"time"
)

var (
	regions  = []string{"us-east", "eu-west", "ap-south"}
	channels = []string{"web", "mobile", "partner"}
	buckets  = []float64{0.05, 0.1, 0.2, 0.4, 0.8, 1.6, 3.2}
)

type scenarioConfig struct {
	Name       string    `json:"name"`
	Until      time.Time `json:"until,omitempty"`
	Multiplier float64   `json:"multiplier"`
	ErrorRate  float64   `json:"error_rate"`
	Series     int       `json:"series"`
}

type workload struct {
	mu sync.RWMutex

	start    time.Time
	scenario scenarioConfig
	rnd      *rand.Rand

	orders       map[string]float64
	payFailures  map[string]float64
	latBuckets   map[string][]float64
	latSum       map[string]float64
	latCount     map[string]float64
	activeUsers  map[string]float64
	revenue      map[string]float64
	inventory    map[string]float64
	cartEvents   map[string]float64
	queueDepth   map[string]float64
	sloViolation map[string]float64
	productViews map[string]float64
}

func newWorkload() *workload {
	return &workload{
		start: time.Now(),
		scenario: scenarioConfig{
			Name:       "normal",
			Multiplier: 1,
			ErrorRate:  0.006,
			Series:     50,
		},
		rnd:          rand.New(rand.NewSource(42)),
		orders:       map[string]float64{},
		payFailures:  map[string]float64{},
		latBuckets:   map[string][]float64{},
		latSum:       map[string]float64{},
		latCount:     map[string]float64{},
		activeUsers:  map[string]float64{},
		revenue:      map[string]float64{},
		inventory:    map[string]float64{},
		cartEvents:   map[string]float64{},
		queueDepth:   map[string]float64{},
		sloViolation: map[string]float64{},
		productViews: map[string]float64{},
	}
}

func (w *workload) run() {
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	for now := range ticker.C {
		w.tick(now)
	}
}

func (w *workload) tick(now time.Time) {
	w.mu.Lock()
	defer w.mu.Unlock()

	if !w.scenario.Until.IsZero() && now.After(w.scenario.Until) {
		w.scenario = scenarioConfig{Name: "normal", Multiplier: 1, ErrorRate: 0.006, Series: 50}
	}

	elapsed := now.Sub(w.start).Seconds()
	baseWave := 1 + 0.18*math.Sin(elapsed/19) + 0.09*math.Sin(elapsed/7)
	cfg := w.scenario

	for regionIndex, region := range regions {
		regionWeight := []float64{0.48, 0.32, 0.20}[regionIndex]
		regionWave := 1 + 0.10*math.Sin(elapsed/11+float64(regionIndex))
		totalOrders := (120 * regionWeight * baseWave * regionWave * cfg.Multiplier) + w.rnd.Float64()*8

		if cfg.Name == "recover" {
			recovery := 1.0 + 2.5*math.Max(0, 1-math.Mod(elapsed, 90)/90)
			totalOrders *= recovery
		}

		for channelIndex, channel := range channels {
			channelWeight := []float64{0.50, 0.38, 0.12}[channelIndex]
			orders := totalOrders * channelWeight
			errorRate := cfg.ErrorRate
			if cfg.Name == "failure" {
				errorRate += 0.10 + 0.04*math.Sin(elapsed/5)
			}
			if cfg.Name == "spike" {
				errorRate += 0.006
			}

			failed := orders * clamp(errorRate+w.rnd.Float64()*0.004, 0, 0.45)
			success := math.Max(0, orders-failed)
			cancelled := orders * (0.006 + w.rnd.Float64()*0.006)

			w.orders[label(region, channel, "success")] += success
			w.orders[label(region, channel, "failed")] += failed
			w.orders[label(region, channel, "cancelled")] += cancelled
			w.payFailures[label(region, reasonFor(regionIndex, channelIndex))] += failed
			w.inventory[label(region, "reserved")] += success * 0.92
			w.inventory[label(region, "rejected")] += failed*0.25 + cancelled*0.5
			w.cartEvents[label(region, "add")] += orders * (2.5 + w.rnd.Float64()*0.6)
			w.cartEvents[label(region, "checkout")] += orders
			w.cartEvents[label(region, "abandon")] += orders * (0.20 + w.rnd.Float64()*0.08)
			w.revenue[label(region, "USD")] += success * (42 + w.rnd.Float64()*38)

			latBase := 0.10 + 0.035*float64(channelIndex) + 0.02*float64(regionIndex)
			switch cfg.Name {
			case "spike":
				latBase += 0.10 + 0.08*math.Sin(elapsed/6)
			case "failure":
				latBase += 0.55 + 0.25*math.Sin(elapsed/4)
			case "recover":
				latBase += 0.20 * math.Max(0, 1-math.Mod(elapsed, 90)/90)
			}
			observations := int(math.Max(1, math.Min(80, orders/4)))
			for i := 0; i < observations; i++ {
				latency := math.Max(0.015, latBase+w.rnd.ExpFloat64()*latBase*0.6)
				w.observeLatency(region, channel, latency)
				if latency > 0.8 {
					w.sloViolation[label(region, "checkout_latency")]++
				}
			}
		}

		active := 1600*regionWeight*baseWave*cfg.Multiplier + 70*math.Sin(elapsed/8+float64(regionIndex))
		if cfg.Name == "failure" {
			active *= 0.86
		}
		w.activeUsers[region] = math.Max(20, active)
		w.queueDepth[region] = math.Max(0, w.queueDepth[region]*0.82+totalOrders*(cfg.Multiplier-1)*0.12)
		if cfg.Name == "failure" {
			w.queueDepth[region] += totalOrders * 0.18
		}
	}

	w.tickHighCardinality(cfg, elapsed)
}

func (w *workload) tickHighCardinality(cfg scenarioConfig, elapsed float64) {
	series := cfg.Series
	if series <= 0 {
		series = 50
	}
	rateMultiplier := 1.0
	if cfg.Name == "cardinality-spike" {
		rateMultiplier = 2.5
	}

	for i := 0; i < series; i++ {
		region := regions[i%len(regions)]
		shopID := fmt.Sprintf("shop-%04d", i+1)
		campaignID := fmt.Sprintf("campaign-%03d", (i/17)%200)
		category := []string{"electronics", "fashion", "home", "sports", "beauty"}[i%5]
		key := label(region, shopID, campaignID, category)
		w.productViews[key] += (0.5 + 0.35*math.Sin(elapsed/13+float64(i%29))) * rateMultiplier
	}
}

func (w *workload) observeLatency(region, channel string, value float64) {
	key := label(region, channel)
	if _, ok := w.latBuckets[key]; !ok {
		w.latBuckets[key] = make([]float64, len(buckets)+1)
	}
	for i, upper := range buckets {
		if value <= upper {
			w.latBuckets[key][i]++
		}
	}
	w.latBuckets[key][len(buckets)]++
	w.latSum[key] += value
	w.latCount[key]++
}
