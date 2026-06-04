package main

import (
	"fmt"
	"net/http"
	"strings"
)

func (w *workload) handleMetrics(rw http.ResponseWriter, _ *http.Request) {
	w.mu.RLock()
	defer w.mu.RUnlock()

	rw.Header().Set("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
	fmt.Fprintln(rw, "# HELP demo_workload_scenario Active synthetic workload scenario.")
	fmt.Fprintln(rw, "# TYPE demo_workload_scenario gauge")
	for _, name := range []string{"normal", "spike", "failure", "recover", "cardinality-spike"} {
		value := 0
		if w.scenario.Name == name {
			value = 1
		}
		fmt.Fprintf(rw, "demo_workload_scenario{scenario=%q} %d\n", name, value)
	}
	fmt.Fprintln(rw, "# HELP demo_workload_target_series Target number of synthetic high-cardinality product-view series.")
	fmt.Fprintln(rw, "# TYPE demo_workload_target_series gauge")
	fmt.Fprintf(rw, "demo_workload_target_series %.0f\n", float64(w.scenario.Series))

	writeCounter3(rw, "demo_orders_total", "Synthetic commerce orders.", "region", "channel", "status", w.orders)
	writeCounter2(rw, "demo_payment_failures_total", "Synthetic payment failures.", "region", "reason", w.payFailures)
	writeGauge1(rw, "demo_active_users", "Synthetic active users.", "region", w.activeUsers)
	writeCounter2(rw, "demo_revenue_total", "Synthetic gross revenue.", "region", "currency", w.revenue)
	writeCounter2(rw, "demo_inventory_reservations_total", "Synthetic inventory reservation events.", "region", "status", w.inventory)
	writeCounter2(rw, "demo_cart_events_total", "Synthetic cart events.", "region", "event", w.cartEvents)
	writeGauge1(rw, "demo_queue_depth", "Synthetic checkout work queued by region.", "region", w.queueDepth)
	writeCounter2(rw, "demo_slo_violations_total", "Synthetic business SLO violations.", "region", "type", w.sloViolation)
	writeProductViews(rw, "demo_product_views_total", "Synthetic high-cardinality product views.", w.productViews, w.scenario.Series)

	fmt.Fprintln(rw, "# HELP demo_checkout_latency_seconds Synthetic checkout latency.")
	fmt.Fprintln(rw, "# TYPE demo_checkout_latency_seconds histogram")
	for key, values := range w.latBuckets {
		parts := strings.Split(key, "\xff")
		for i, upper := range buckets {
			fmt.Fprintf(rw, "demo_checkout_latency_seconds_bucket{region=%q,channel=%q,le=%q} %.0f\n", parts[0], parts[1], formatFloat(upper), values[i])
		}
		fmt.Fprintf(rw, "demo_checkout_latency_seconds_bucket{region=%q,channel=%q,le=%q} %.0f\n", parts[0], parts[1], "+Inf", values[len(values)-1])
		fmt.Fprintf(rw, "demo_checkout_latency_seconds_sum{region=%q,channel=%q} %.6f\n", parts[0], parts[1], w.latSum[key])
		fmt.Fprintf(rw, "demo_checkout_latency_seconds_count{region=%q,channel=%q} %.0f\n", parts[0], parts[1], w.latCount[key])
	}
}

func writeCounter3(rw http.ResponseWriter, name, help, l1, l2, l3 string, values map[string]float64) {
	fmt.Fprintf(rw, "# HELP %s %s\n# TYPE %s counter\n", name, help, name)
	for key, value := range values {
		parts := strings.Split(key, "\xff")
		fmt.Fprintf(rw, "%s{%s=%q,%s=%q,%s=%q} %.6f\n", name, l1, parts[0], l2, parts[1], l3, parts[2], value)
	}
}

func writeCounter2(rw http.ResponseWriter, name, help, l1, l2 string, values map[string]float64) {
	fmt.Fprintf(rw, "# HELP %s %s\n# TYPE %s counter\n", name, help, name)
	for key, value := range values {
		parts := strings.Split(key, "\xff")
		fmt.Fprintf(rw, "%s{%s=%q,%s=%q} %.6f\n", name, l1, parts[0], l2, parts[1], value)
	}
}

func writeGauge1(rw http.ResponseWriter, name, help, l1 string, values map[string]float64) {
	fmt.Fprintf(rw, "# HELP %s %s\n# TYPE %s gauge\n", name, help, name)
	for key, value := range values {
		fmt.Fprintf(rw, "%s{%s=%q} %.6f\n", name, l1, key, value)
	}
}

func writeProductViews(rw http.ResponseWriter, name, help string, values map[string]float64, limit int) {
	fmt.Fprintf(rw, "# HELP %s %s\n# TYPE %s counter\n", name, help, name)
	if limit <= 0 {
		limit = 50
	}
	for i := 0; i < limit; i++ {
		region := regions[i%len(regions)]
		shopID := fmt.Sprintf("shop-%04d", i+1)
		campaignID := fmt.Sprintf("campaign-%03d", (i/17)%200)
		category := []string{"electronics", "fashion", "home", "sports", "beauty"}[i%5]
		key := label(region, shopID, campaignID, category)
		fmt.Fprintf(rw, "%s{region=%q,shop_id=%q,campaign_id=%q,category=%q} %.6f\n", name, region, shopID, campaignID, category, values[key])
	}
}
