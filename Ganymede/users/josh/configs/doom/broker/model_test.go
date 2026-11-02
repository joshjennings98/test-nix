package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	"github.com/ARM-software/golang-utils/utils/filesystem"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestModelEndpoint(t *testing.T) {
	t.Parallel()
	for _, test := range []struct {
		endpoint string
		allowed  bool
	}{
		{"https://enterprise.example/v1/responses", true},
		{"https://enterprise.example:443/responses", true},
		{"http://enterprise.example/responses", false},
		{"https://enterprise.example:8443/responses", false},
		{"https://user:secret@enterprise.example/responses", false},
		{"https://enterprise.example/responses?token=secret", false},
		{"https://enterprise.example/responses?", false},
		{"https://enterprise.example/responses#fragment", false},
		{"/responses", false},
	} {
		t.Run(test.endpoint, func(t *testing.T) {
			t.Parallel()
			_, err := modelEndpoint(test.endpoint)
			if !test.allowed {
				require.Error(t, err)
				return
			}
			require.NoError(t, err)
		})
	}
}

func TestModelToken(t *testing.T) {
	t.Parallel()
	for _, test := range []struct {
		name, value string
		allowed     bool
	}{
		{"plain", "SYNTHETIC", true},
		{"newline", "SYNTHETIC\n", true},
		{"crlf", "SYNTHETIC\r\n", true},
		{"empty", "", false},
		{"header injection", "SYNTHETIC\r\nX-Extra: value", false},
		{"space", "Bearer SYNTHETIC", false},
		{"oversize", strings.Repeat("x", 16385), false},
	} {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			directory := t.TempDir()
			file, err := filesystem.CreateFile(filepath.Join(directory, "model-token"))
			require.NoError(t, err)
			_, err = file.Write([]byte(test.value))
			require.NoError(t, err)
			require.NoError(t, file.Close())
			value, err := readModelToken(directory)
			if !test.allowed {
				require.Error(t, err)
				assert.Empty(t, value)
				return
			}
			require.NoError(t, err)
			assert.Equal(t, "SYNTHETIC", value)
		})
	}
	_, err := readModelToken("")
	require.Error(t, err)
	_, err = readModelToken(t.TempDir())
	require.Error(t, err)
}

func TestEnterpriseResponses(t *testing.T) {
	t.Parallel()
	transport := &recordingTransport{status: 200}
	client := &http.Client{Transport: transport}
	credentials := &credentials{client: client, modelToken: "SYNTHETIC-ENTERPRISE"}
	b := &broker{
		config: configuration{ModelEndpoint: "https://enterprise.example/v1/responses", PageHosts: []string{"go.dev"}},
		client: client, credentials: credentials,
	}
	request := httptest.NewRequest("POST", "/openai/responses", strings.NewReader(`{"model":"enterprise-model","store":true,"previous_response_id":"old","conversation":"old","temperature":0.5,"max_output_tokens":100,"input":"hello"}`))
	request.Header.Set("Authorization", "Bearer CLIENT-TOKEN")
	request.Header.Set("ChatGPT-Account-Id", "CLIENT-ACCOUNT")
	response := httptest.NewRecorder()
	b.ServeHTTP(response, request)
	require.Equal(t, 200, response.Code)
	assert.Equal(t, "https://enterprise.example/v1/responses", transport.request.URL.String())
	assert.Equal(t, "Bearer SYNTHETIC-ENTERPRISE", transport.request.Header.Get("Authorization"))
	assert.Empty(t, transport.request.Header.Get("ChatGPT-Account-Id"))
	assert.Empty(t, transport.request.Header.Get("Originator"))
	assert.JSONEq(t, `{"model":"enterprise-model","store":false,"stream":true,"temperature":0.5,"max_output_tokens":100,"input":"hello"}`, transport.body)

	headers, err := credentials.Headers(context.Background(), "")
	require.NoError(t, err)
	assert.Empty(t, headers)
	b.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest("GET", "/page?url=https://go.dev/doc/", nil))
	assert.Empty(t, transport.request.Header.Get("Authorization"))
}

func TestEnterpriseRedirectNotFollowed(t *testing.T) {
	t.Parallel()
	transport := &recordingTransport{status: 302, responseHeader: http.Header{"Location": {"https://other.example/"}}}
	client := upstreamClient()
	client.Transport = transport
	b := &broker{
		config: configuration{ModelEndpoint: "https://enterprise.example/v1/responses"},
		client: client, credentials: &credentials{client: client, modelToken: "SYNTHETIC"},
	}
	response := httptest.NewRecorder()
	b.ServeHTTP(response, httptest.NewRequest("POST", "/openai/responses", strings.NewReader(`{}`)))
	assert.Equal(t, http.StatusBadGateway, response.Code)
	assert.Equal(t, "enterprise.example", transport.request.URL.Host)
	assert.Empty(t, response.Header().Get("Location"))
}
