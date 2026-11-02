package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"maps"
	"net/http"
	"slices"
	"strings"
)

type broker struct {
	config      configuration
	client      *http.Client
	credentials credentialSource
}

func (b *broker) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if b == nil || b.client == nil || b.credentials == nil {
		http.Error(w, "Broker unavailable", http.StatusServiceUnavailable)
		return
	}
	destination, err := selectRoute(r, b.config)
	if err != nil {
		http.Error(w, "Request is not permitted by the Nix broker policy", http.StatusForbidden)
		return
	}
	if r.ContentLength > destination.Limit {
		http.Error(w, "Request too large", http.StatusRequestEntityTooLarge)
		return
	}

	var body io.Reader = http.MaxBytesReader(w, r.Body, destination.Limit)
	if destination.Credential == "openai" {
		data, subErr := io.ReadAll(body)
		if subErr != nil {
			http.Error(w, "Request too large or unreadable", http.StatusBadRequest)
			return
		}
		var payload map[string]json.RawMessage
		if json.Unmarshal(data, &payload) != nil || payload == nil {
			http.Error(w, "Expected a JSON request object", http.StatusBadRequest)
			return
		}
		if b.config.ModelEndpoint == "" {
			delete(payload, "temperature")
			delete(payload, "max_output_tokens")
		}
		delete(payload, "previous_response_id")
		delete(payload, "conversation")
		payload["store"] = json.RawMessage("false")
		payload["stream"] = json.RawMessage("true")
		data, err = json.Marshal(payload)
		if err != nil {
			http.Error(w, "Invalid request", http.StatusBadRequest)
			return
		}
		body = bytes.NewReader(data)
	} else if r.Method == http.MethodGet {
		body = nil
	}

	request, err := http.NewRequestWithContext(r.Context(), r.Method, destination.URL.String(), body)
	if err != nil {
		http.Error(w, "Invalid upstream request", http.StatusBadRequest)
		return
	}
	request.Header.Set("User-Agent", "emacs-broker/1")
	if destination.Credential == "github" {
		request.Header.Set("Git-Protocol", "version=2")
		if r.Method == http.MethodPost {
			operation := destination.URL.Path[strings.LastIndex(destination.URL.Path, "/")+1:]
			request.Header.Set("Content-Type", fmt.Sprintf("application/x-%s-request", operation))
		}
	} else if destination.Credential == "openai" {
		request.Header.Set("Content-Type", "application/json")
		request.Header.Set("Accept", "text/event-stream")
	}

	headers, err := b.credentials.Headers(r.Context(), destination.Credential)
	if err != nil {
		http.Error(w, "Broker sign-in required; run emacs-broker-login on the host", http.StatusUnauthorized)
		return
	}
	for _, key := range slices.Sorted(maps.Keys(headers)) {
		request.Header[key] = headers[key]
	}
	response, err := b.client.Do(request)
	// Go's module mirror redirects ZIP downloads to signed Google Storage URLs.
	if err == nil && strings.HasPrefix(r.URL.Path, "/gomod/") && response.StatusCode == http.StatusFound {
		location, subErr := response.Location()
		if subErr == nil && location.Scheme == "https" && location.Host == "storage.googleapis.com" && location.User == nil {
			response.Body.Close()
			request, err = http.NewRequestWithContext(r.Context(), http.MethodGet, location.String(), nil)
			if err == nil {
				response, err = b.client.Do(request)
			}
		}
	}
	if err != nil {
		http.Error(w, "Upstream connection failed", http.StatusBadGateway)
		return
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		// Never return upstream error bodies, cookies or redirect locations.
		http.Error(w, "Upstream rejected the request or attempted a redirect", http.StatusBadGateway)
		return
	}

	w.Header().Set("Content-Type", response.Header.Get("Content-Type"))
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	if strings.HasPrefix(r.URL.Path, "/gomod/") || strings.HasPrefix(r.URL.Path, "/gosum/") || destination.Credential == "github" {
		io.Copy(w, io.LimitReader(response.Body, 512<<20))
		return
	}
	if destination.Credential == "openai" {
		reader := io.LimitReader(response.Body, 32<<20)
		buffer := make([]byte, 32<<10)
		for {
			if r.Context().Err() != nil {
				return
			}
			count, subErr := reader.Read(buffer)
			if count > 0 {
				if _, writeErr := w.Write(buffer[:count]); writeErr != nil {
					return
				}
				if flushErr := http.NewResponseController(w).Flush(); flushErr != nil {
					return
				}
			}
			if subErr != nil {
				return
			}
		}
	}
	data, err := io.ReadAll(io.LimitReader(response.Body, (4<<20)+1))
	if err != nil || len(data) > 4<<20 {
		http.Error(w, "Page exceeds the broker limit", http.StatusBadGateway)
		return
	}
	w.Write(data)
}
