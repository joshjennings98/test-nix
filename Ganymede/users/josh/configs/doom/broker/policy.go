package main

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"net/netip"
	"net/url"
	"regexp"
	"slices"
	"strings"
	"time"

	"github.com/ARM-software/golang-utils/utils/commonerrors"
	"github.com/ARM-software/golang-utils/utils/parallelisation"
)

type configuration struct {
	ModelEndpoint string   `json:"modelEndpoint"`
	Socket        string   `json:"socket"`
	State         string   `json:"state"`
	PageHosts     []string `json:"pageHosts"`
}

type route struct {
	URL        *url.URL
	Credential string
	Limit      int64
}

var repositoryPath = regexp.MustCompile(`^/github/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)/(info/refs|git-upload-pack|git-receive-pack)$`)

func selectRoute(r *http.Request, cfg configuration) (destination route, err error) {
	destination.Limit = 8 << 20
	if r.URL.IsAbs() || r.URL.RawPath != "" || strings.Contains(r.URL.Path, "..") {
		err = commonerrors.Newf(commonerrors.ErrInvalid, "invalid request path")
		return
	}

	switch {
	case r.URL.Path == "/openai/responses" && r.Method == http.MethodPost && r.URL.RawQuery == "":
		if cfg.ModelEndpoint == "" {
			destination.URL, err = url.Parse("https://chatgpt.com/backend-api/codex/responses")
		} else {
			destination.URL, err = modelEndpoint(cfg.ModelEndpoint)
		}
		destination.Credential = "openai"
	case strings.HasPrefix(r.URL.Path, "/github/"):
		parts := repositoryPath.FindStringSubmatch(r.URL.Path)
		if len(parts) == 0 || parts[1] == "." || parts[2] == "." {
			err = commonerrors.Newf(commonerrors.ErrInvalid, "unsupported GitHub repository path")
			return
		}

		query, subErr := url.ParseQuery(r.URL.RawQuery)
		if subErr != nil {
			err = subErr
			return
		}

		if parts[3] == "info/refs" {
			service := query.Get("service")
			if r.Method != http.MethodGet || len(query) != 1 || len(query["service"]) != 1 ||
				(service != "git-upload-pack" && service != "git-receive-pack") {
				err = commonerrors.Newf(commonerrors.ErrInvalid, "unsupported Git discovery request")
				return
			}
		} else if r.Method != http.MethodPost || r.URL.RawQuery != "" {
			err = commonerrors.Newf(commonerrors.ErrInvalid, "unsupported Git operation")
			return
		}

		repository := parts[2]
		if !strings.HasSuffix(repository, ".git") {
			repository = fmt.Sprintf("%s.git", repository)
		}

		destination.URL = &url.URL{Scheme: "https", Host: "github.com", Path: fmt.Sprintf("/%s/%s/%s", parts[1], repository, parts[3]), RawQuery: query.Encode()}
		destination.Credential = "github"
		destination.Limit = 256 << 20
	case r.URL.Path == "/page" && r.Method == http.MethodGet:
		destination.URL, err = cleanPageURL(r.URL.Query().Get("url"), cfg.PageHosts)
	case r.URL.Path == "/search" && r.Method == http.MethodGet:
		query := r.URL.Query().Get("q")
		if len(query) == 0 || len(query) > 2048 {
			err = commonerrors.Newf(commonerrors.ErrInvalid, "search query must contain 1 to 2048 bytes")
			return
		}
		destination.URL = &url.URL{Scheme: "https", Host: "html.duckduckgo.com", Path: "/html/", RawQuery: url.Values{"q": {query}}.Encode()}
	case r.Method == http.MethodGet && r.URL.RawQuery == "" && strings.HasPrefix(r.URL.Path, "/gomod/"):
		destination.URL = &url.URL{Scheme: "https", Host: "proxy.golang.org", Path: strings.TrimPrefix(r.URL.Path, "/gomod")}
	case r.Method == http.MethodGet && r.URL.RawQuery == "" && strings.HasPrefix(r.URL.Path, "/gosum/"):
		destination.URL = &url.URL{Scheme: "https", Host: "sum.golang.org", Path: strings.TrimPrefix(r.URL.Path, "/gosum")}
	default:
		err = commonerrors.Newf(commonerrors.ErrInvalid, "route or method is not permitted")
	}
	return
}

func cleanPageURL(raw string, allowed []string) (clean *url.URL, err error) {
	clean, err = url.Parse(raw)
	if err != nil {
		return
	}

	host := strings.ToLower(clean.Hostname())
	if clean.Scheme != "https" || clean.User != nil || clean.Opaque != "" ||
		(clean.Port() != "" && clean.Port() != "443") || !slices.Contains(allowed, host) {
		err = commonerrors.Newf(commonerrors.ErrInvalid, "page destination is not permitted")
		return
	}

	clean.Host = host
	clean.RawQuery, clean.Fragment, clean.RawFragment = "", "", ""
	clean.ForceQuery = false
	return
}

func publicAddress(ip netip.Addr) bool {
	ip = ip.Unmap()
	if !ip.IsGlobalUnicast() || ip.IsPrivate() || ip.IsLoopback() || ip.IsLinkLocalUnicast() {
		return false
	}
	if ip.Is6() && !netip.MustParsePrefix("2000::/3").Contains(ip) {
		return false
	}

	for _, raw := range []string{"0.0.0.0/8", "100.64.0.0/10", "192.0.0.0/24", "192.0.2.0/24", "198.18.0.0/15", "198.51.100.0/24", "203.0.113.0/24", "240.0.0.0/4", "2001:db8::/32", "2002::/16", "2001::/23"} {
		if netip.MustParsePrefix(raw).Contains(ip) {
			return false
		}
	}
	return true
}

func dialPublic(ctx context.Context, network, address string) (connection net.Conn, err error) {
	if err = parallelisation.DetermineContextError(ctx); err != nil {
		return
	}

	host, port, err := net.SplitHostPort(address)
	if err != nil || port != "443" {
		err = commonerrors.Newf(commonerrors.ErrInvalid, "only HTTPS is permitted")
		return
	}

	addresses, err := net.DefaultResolver.LookupNetIP(ctx, "ip", host)
	if err != nil {
		return
	}

	for _, ip := range addresses {
		if !publicAddress(ip) {
			err = commonerrors.Newf(commonerrors.ErrInvalid, "destination has a non-public address")
			return
		}
	}

	for _, ip := range addresses {
		if err = parallelisation.DetermineContextError(ctx); err != nil {
			return
		}

		dialler := net.Dialer{Timeout: 15 * time.Second}
		connection, err = dialler.DialContext(ctx, network, net.JoinHostPort(ip.String(), port))
		if err == nil {
			return
		}
	}
	err = commonerrors.Newf(commonerrors.ErrUnavailable, "cannot connect to %s", host)
	return
}

func upstreamClient() *http.Client {
	return &http.Client{
		Timeout:       5 * time.Minute,
		Transport:     &http.Transport{DialContext: dialPublic, TLSHandshakeTimeout: 15 * time.Second, ResponseHeaderTimeout: 60 * time.Second, MaxIdleConnsPerHost: 8},
		CheckRedirect: func(_ *http.Request, _ []*http.Request) error { return http.ErrUseLastResponse },
	}
}

func endpointError(status int) error {
	return commonerrors.Newf(commonerrors.ErrUnavailable, "upstream returned HTTP %s", fmt.Sprint(status))
}

// The administrator supplies a complete endpoint, never a client-selected URL.
func modelEndpoint(raw string) (endpoint *url.URL, err error) {
	endpoint, err = url.Parse(raw)
	if err != nil {
		err = commonerrors.Newf(commonerrors.ErrInvalid, "invalid model endpoint")
		return
	}

	if endpoint.Scheme != "https" || endpoint.Hostname() == "" || endpoint.User != nil || endpoint.Opaque != "" ||
		(endpoint.Port() != "" && endpoint.Port() != "443") || endpoint.RawQuery != "" || endpoint.ForceQuery || endpoint.Fragment != "" {
		err = commonerrors.Newf(commonerrors.ErrInvalid, "model endpoint must be HTTPS on port 443 without credentials, query or fragment")
	}
	return
}
