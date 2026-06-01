package main

import (
	"log"
	"net/http"
	"time"
)

func main() {
	w := newWorkload()
	go w.run()

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(rw http.ResponseWriter, _ *http.Request) {
		rw.WriteHeader(http.StatusOK)
		_, _ = rw.Write([]byte("ok\n"))
	})
	mux.HandleFunc("/scenario", w.handleScenario)
	mux.HandleFunc("/scenario/", w.handleSetScenario)
	mux.HandleFunc("/metrics", w.handleMetrics)

	server := &http.Server{
		Addr:              ":18080",
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}

	log.Println("synthetic workload generator listening on :18080")
	if err := server.ListenAndServe(); err != nil {
		log.Fatal(err)
	}
}
