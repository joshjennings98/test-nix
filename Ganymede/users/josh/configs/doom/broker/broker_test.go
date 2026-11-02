package main

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/netip"
	"net/url"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/ARM-software/golang-utils/utils/filesystem"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestRoutes(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name, method, path, host string
		allowed                  bool
	}{
		{"model", "POST", "/openai/responses", "chatgpt.com", true},
		{"model query", "POST", "/openai/responses?target=evil", "", false},
		{"model get", "GET", "/openai/responses", "", false},
		{"git discovery", "GET", "/github/owner/repo.git/info/refs?service=git-upload-pack", "github.com", true},
		{"git push", "POST", "/github/owner/repo.git/git-receive-pack", "github.com", true},
		{"github API", "POST", "/github/api/user", "", false},
		{"git extra parameter", "GET", "/github/owner/repo.git/info/refs?service=git-upload-pack&secret=x", "", false},
		{"traversal", "GET", "/github/owner/../info/refs?service=git-upload-pack", "", false},
		{"connect", "CONNECT", "https://example.invalid", "", false},
		{"module", "GET", "/gomod/example.org/module/@v/list", "proxy.golang.org", true},
		{"checksum", "GET", "/gosum/supported", "sum.golang.org", true},
		{"search", "GET", "/search?q=synthetic", "html.duckduckgo.com", true},
		{"unknown", "GET", "/anything", "", false},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			route, err := selectRoute(httptest.NewRequest(test.method, test.path, nil), configuration{})
			if !test.allowed {
				require.Error(t, err)
				return
			}
			require.NoError(t, err)
			assert.Equal(t, test.host, route.URL.Host)
		})
	}
}

func TestCleanPage(t *testing.T) {
	t.Parallel()
	clean, err := cleanPageURL("https://go.dev/doc/?private=synthetic#fragment", []string{"go.dev"})
	require.NoError(t, err)
	assert.Equal(t, "https://go.dev/doc/", clean.String())
	for _, raw := range []string{"http://go.dev/doc", "https://go.dev.evil.invalid/", "https://go.dev:444/", "https://user:password@go.dev/", "file:///etc/passwd", "https://127.0.0.1/"} {
		_, subErr := cleanPageURL(raw, []string{"go.dev"})
		require.Error(t, subErr)
	}
}

func TestPublicAddresses(t *testing.T) {
	t.Parallel()
	for _, raw := range []string{"127.0.0.1", "10.1.1.1", "169.254.169.254", "100.64.0.1", "0.1.1.1", "192.0.2.1", "::1", "fd00::1", "::ffff:127.0.0.1", "64:ff9b::7f00:1", "2002:7f00:1::"} {
		assert.False(t, publicAddress(netip.MustParseAddr(raw)), raw)
	}
	assert.True(t, publicAddress(netip.MustParseAddr("1.1.1.1")))
	assert.True(t, publicAddress(netip.MustParseAddr("2606:4700:4700::1111")))
}

type syntheticCredentials struct{}

func (syntheticCredentials) Headers(_ context.Context, kind string) (http.Header, error) {
	headers := make(http.Header)
	if kind != "" {
		headers.Set("Authorization", "Bearer SYNTHETIC-BROKER-CREDENTIAL")
	}
	return headers, nil
}

type recordingTransport struct {
	request        *http.Request
	body           string
	status         int
	responseHeader http.Header
}

func (r *recordingTransport) RoundTrip(request *http.Request) (*http.Response, error) {
	r.request = request
	if request.Body != nil {
		body, err := io.ReadAll(request.Body)
		if err != nil {
			return nil, err
		}
		r.body = string(body)
	}
	return &http.Response{StatusCode: r.status, Header: r.responseHeader, Body: io.NopCloser(strings.NewReader("synthetic response")), Request: request}, nil
}

func TestCredentialsAndHeaders(t *testing.T) {
	t.Parallel()
	transport := &recordingTransport{status: 200, responseHeader: http.Header{"Set-Cookie": {"synthetic"}, "Content-Type": {"text/event-stream"}}}
	b := &broker{client: &http.Client{Transport: transport}, credentials: syntheticCredentials{}}
	r := httptest.NewRequest("POST", "/openai/responses", strings.NewReader(`{"model":"synthetic","store":true,"temperature":1}`))
	r.Header.Set("Authorization", "Bearer ATTACKER")
	r.Header.Set("Cookie", "private=synthetic")
	r.Header.Set("X-Forwarded-Host", "evil.invalid")
	w := httptest.NewRecorder()
	b.ServeHTTP(w, r)
	require.Equal(t, 200, w.Code)
	assert.Equal(t, "Bearer SYNTHETIC-BROKER-CREDENTIAL", transport.request.Header.Get("Authorization"))
	assert.Empty(t, transport.request.Header.Get("Cookie"))
	assert.Empty(t, transport.request.Header.Get("X-Forwarded-Host"))
	assert.Empty(t, w.Header().Get("Set-Cookie"))
	assert.JSONEq(t, `{"model":"synthetic","store":false,"stream":true}`, transport.body)
	assert.True(t, w.Flushed)
}

func TestPageHasNoCredential(t *testing.T) {
	t.Parallel()
	transport := &recordingTransport{status: 200}
	b := &broker{config: configuration{PageHosts: []string{"go.dev"}}, client: &http.Client{Transport: transport}, credentials: syntheticCredentials{}}
	r := httptest.NewRequest("GET", fmt.Sprintf("/page?url=%s", url.QueryEscape("https://go.dev/doc/?secret=SYNTHETIC")), nil)
	r.Header.Set("Authorization", "Bearer SYNTHETIC")
	w := httptest.NewRecorder()
	b.ServeHTTP(w, r)
	require.Equal(t, 200, w.Code)
	assert.Empty(t, transport.request.Header.Get("Authorization"))
	assert.Empty(t, transport.request.URL.RawQuery)
}

func TestRedirectAndErrorBodiesAreHidden(t *testing.T) {
	t.Parallel()
	for _, status := range []int{302, 401, 500} {
		transport := &recordingTransport{status: status, responseHeader: http.Header{"Location": {"https://evil.invalid/"}}}
		b := &broker{client: &http.Client{Transport: transport}, credentials: syntheticCredentials{}}
		w := httptest.NewRecorder()
		b.ServeHTTP(w, httptest.NewRequest("POST", "/openai/responses", strings.NewReader(`{}`)))
		assert.Equal(t, http.StatusBadGateway, w.Code)
		assert.NotContains(t, w.Body.String(), "synthetic response")
		assert.Empty(t, w.Header().Get("Location"))
	}
}

func TestPrivateCredentialFile(t *testing.T) {
	t.Parallel()
	directory := filepath.Join(t.TempDir(), "state")
	require.NoError(t, saveToken(directory, token{Access: "SYNTHETIC", Refresh: "SYNTHETIC", ExpiresAt: time.Now()}))
	info, err := filesystem.Stat(filepath.Join(directory, "openai.json"))
	require.NoError(t, err)
	assert.EqualValues(t, 0600, info.Mode().Perm())
	info, err = filesystem.Stat(directory)
	require.NoError(t, err)
	assert.EqualValues(t, 0700, info.Mode().Perm())
}

func TestGitRepositoryCanonicalPath(t *testing.T) {
	t.Parallel()
	for _, repository := range []string{"repo", "repo.git"} {
		r := httptest.NewRequest("GET", fmt.Sprintf("/github/owner/%s/info/refs?service=git-upload-pack", repository), nil)
		destination, err := selectRoute(r, configuration{})
		require.NoError(t, err)
		assert.Equal(t, "https://github.com/owner/repo.git/info/refs?service=git-upload-pack", destination.URL.String())
	}
}

func TestInvalidModelBodyDoesNotReachUpstream(t *testing.T) {
	t.Parallel()
	for _, body := range []string{"null", "[]", "invalid", `{"model":"synthetic"} trailing`} {
		transport := &recordingTransport{status: 200}
		b := &broker{client: &http.Client{Transport: transport}, credentials: syntheticCredentials{}}
		w := httptest.NewRecorder()
		b.ServeHTTP(w, httptest.NewRequest("POST", "/openai/responses", strings.NewReader(body)))
		assert.Equal(t, http.StatusBadRequest, w.Code)
		assert.Nil(t, transport.request)
	}
}
