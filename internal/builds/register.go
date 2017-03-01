package builds

import (
	"encoding/json"
	"errors"
	"net/http"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"gitlab.com/gitlab-org/gitlab-workhorse/internal/helper"
	"gitlab.com/gitlab-org/gitlab-workhorse/internal/redis"
)

const (
	maxRegisterBodySize = 32 * 1024
	runnerBuildQueue    = "runner:build_queue:"
)

var (
	registerHandlerHits = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "gitlab_workhorse_builds_register_handler_hits",
			Help: "Describes how many requests in different states hit a register handler",
		},
		[]string{"status"},
	)
	registerHandlerOpen = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "gitlab_workhorse_builds_register_handler_open",
			Help: "Describes how many requests is currently open in given state",
		},
		[]string{"state"},
	)
)

var (
	registerHandlerOpenAtReading  = registerHandlerOpen.WithLabelValues("reading")
	registerHandlerOpenAtProxying = registerHandlerOpen.WithLabelValues("proxying")
	registerHandlerOpenAtWatching = registerHandlerOpen.WithLabelValues("watching")
)

var (
	registerHandlerBodyReadErrors     = registerHandlerHits.WithLabelValues("body-read-error")
	registerHandlerBodyParseErrors    = registerHandlerHits.WithLabelValues("body-parse-error")
	registerHandlerMissingValues      = registerHandlerHits.WithLabelValues("missing-values")
	registerHandlerWatchErrors        = registerHandlerHits.WithLabelValues("watch-error")
	registerHandlerAlreadyChangedHits = registerHandlerHits.WithLabelValues("already-changed")
	registerHandlerSeenChangeHits     = registerHandlerHits.WithLabelValues("seen-change")
	registerHandlerTimeoutHits        = registerHandlerHits.WithLabelValues("timeout")
	registerHandlerNoChangeHits       = registerHandlerHits.WithLabelValues("no-change")
)

type largeBodyError struct{ error }
type watchError struct{ error }

type WatchKeyHandler func(key, value string, timeout time.Duration) (redis.WatchKeyStatus, error)

func init() {
	prometheus.MustRegister(
		registerHandlerHits,
		registerHandlerOpen,
	)
}

type runnerRequest struct {
	Token      string `json:"token,omitempty"`
	LastUpdate string `json:"last_update,omitempty"`
}

func readRunnerBody(w http.ResponseWriter, r *http.Request) ([]byte, error) {
	registerHandlerOpenAtReading.Inc()
	defer registerHandlerOpenAtReading.Dec()

	return helper.ReadRequestBody(w, r, maxRegisterBodySize)
}

func readRunnerRequest(r *http.Request, body []byte) (runnerRequest, error) {
	var runnerRequest runnerRequest

	if !helper.IsApplicationJson(r) {
		return runnerRequest, errors.New("invalid content-type received")
	}

	err := json.Unmarshal(body, &runnerRequest)
	if err != nil {
		return runnerRequest, err
	}

	return runnerRequest, nil
}

func proxyRegisterRequest(h http.Handler, w http.ResponseWriter, r *http.Request) {
	registerHandlerOpenAtProxying.Inc()
	defer registerHandlerOpenAtProxying.Dec()

	h.ServeHTTP(w, r)
}

func watchForRunnerChange(watchHandler WatchKeyHandler, token, lastUpdate string, duration time.Duration) (redis.WatchKeyStatus, error) {
	registerHandlerOpenAtWatching.Inc()
	defer registerHandlerOpenAtWatching.Dec()

	return watchHandler(runnerBuildQueue+token, lastUpdate, duration)
}

func RegisterHandler(h http.Handler, watchHandler WatchKeyHandler, pollingDuration time.Duration) http.Handler {
	if pollingDuration == 0 {
		return h
	}

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestBody, err := readRunnerBody(w, r)
		if err != nil {
			registerHandlerBodyReadErrors.Inc()
			helper.RequestEntityTooLarge(w, r, &largeBodyError{err})
			return
		}

		newRequest := helper.CloneRequestWithNewBody(r, requestBody)

		runnerRequest, err := readRunnerRequest(r, requestBody)
		if err != nil {
			registerHandlerBodyParseErrors.Inc()
			proxyRegisterRequest(h, w, newRequest)
			return
		}

		if runnerRequest.Token == "" || runnerRequest.LastUpdate == "" {
			registerHandlerMissingValues.Inc()
			proxyRegisterRequest(h, w, newRequest)
			return
		}

		result, err := watchForRunnerChange(watchHandler, runnerRequest.Token,
			runnerRequest.LastUpdate, pollingDuration)
		if err != nil {
			registerHandlerWatchErrors.Inc()
			proxyRegisterRequest(h, w, newRequest)
			return
		}

		switch result {
		// It means that we detected a change before starting watching on change,
		// We proxy request to Rails, to see whether we can receive the build
		case redis.WatchKeyStatusAlreadyChanged:
			registerHandlerAlreadyChangedHits.Inc()
			proxyRegisterRequest(h, w, newRequest)

		// It means that we detected a change after watching.
		// We could potentially proxy request to Rails, but...
		// We can end-up with unreliable responses,
		// as don't really know whether ResponseWriter is still in a sane state,
		// whether the connection is not dead
		case redis.WatchKeyStatusSeenChange:
			registerHandlerSeenChangeHits.Inc()
			w.WriteHeader(http.StatusNoContent)

		// When we receive one of these statuses, it means that we detected no change,
		// so we return to runner 204, which means nothing got changed,
		// and there's no new builds to process
		case redis.WatchKeyStatusTimeout:
			registerHandlerTimeoutHits.Inc()
			w.WriteHeader(http.StatusNoContent)

		case redis.WatchKeyStatusNoChange:
			registerHandlerNoChangeHits.Inc()
			w.WriteHeader(http.StatusNoContent)
		}
	})
}
