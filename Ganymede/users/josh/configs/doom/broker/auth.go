package main

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/ARM-software/golang-utils/utils/commonerrors"
	"github.com/ARM-software/golang-utils/utils/filesystem"
	"github.com/ARM-software/golang-utils/utils/parallelisation"
)

// Public OAuth application identifier reused from Doom's pinned gptel backend;
// not an account ID, access token or client secret. No existing credentials were used.
// Source: https://github.com/karthink/gptel/blob/ebf0f3d8e9932e0ac6de82542220864cc17f6784/gptel-openai-oauth.el#L29
const openAIClientID = "app_EMoamEEZ73f0CkXaXp7hrann"

// Fixed localhost callback used by that OAuth flow; the broker listens here only during sign-in.
// Source: https://github.com/karthink/gptel/blob/ebf0f3d8e9932e0ac6de82542220864cc17f6784/gptel-openai-oauth.el#L48-L50
const redirectURI = "http://localhost:1455/auth/callback"

type token struct {
	Access    string    `json:"access_token"`
	Refresh   string    `json:"refresh_token"`
	ID        string    `json:"id_token"`
	ExpiresIn int64     `json:"expires_in"`
	ExpiresAt time.Time `json:"expires_at"`
	Account   string    `json:"account"`
}

type credentialSource interface {
	Headers(context.Context, string) (http.Header, error)
}

type credentials struct {
	modelToken string
	state      string
	client     *http.Client
	mu         sync.Mutex
}

func (c *credentials) Headers(ctx context.Context, kind string) (headers http.Header, err error) {
	if err = parallelisation.DetermineContextError(ctx); err != nil {
		return
	}
	if c == nil || c.client == nil {
		err = commonerrors.UndefinedVariable("credentials")
		return
	}

	headers = make(http.Header)
	switch kind {
	case "openai":
		if c.modelToken != "" {
			headers.Set("Authorization", fmt.Sprintf("Bearer %s", c.modelToken))
			return
		}
		c.mu.Lock()
		defer c.mu.Unlock()
		data, subErr := filesystem.ReadFile(filepath.Join(c.state, "openai.json"))
		if subErr != nil {
			err = commonerrors.Newf(commonerrors.ErrUnavailable, "run emacs-broker-login openai on the host")
			return
		}

		var saved token
		if err = json.Unmarshal(data, &saved); err != nil {
			return
		}

		if saved.Access == "" || time.Until(saved.ExpiresAt) < time.Minute {
			previous := saved
			saved, err = exchangeToken(ctx, c.client, url.Values{"grant_type": {"refresh_token"}, "refresh_token": {saved.Refresh}, "client_id": {openAIClientID}})
			if err != nil {
				return
			}
			if saved.Refresh == "" {
				saved.Refresh = previous.Refresh
			}
			if saved.Account == "" {
				saved.Account = previous.Account
			}
			if err = saveToken(c.state, saved); err != nil {
				return
			}
		}

		headers.Set("Authorization", fmt.Sprintf("Bearer %s", saved.Access))
		headers.Set("Originator", "gptel")
		if saved.Account != "" {
			headers.Set("ChatGPT-Account-Id", saved.Account)
		}
	case "github":
		command := exec.CommandContext(ctx, "gh", "auth", "token", "--hostname", "github.com")
		data, subErr := command.Output()
		if subErr != nil || len(strings.TrimSpace(string(data))) == 0 {
			err = commonerrors.Newf(commonerrors.ErrUnavailable, "run emacs-broker-login github on the host")
			return
		}
		encoded := base64.StdEncoding.EncodeToString([]byte(fmt.Sprintf("x-access-token:%s", strings.TrimSpace(string(data)))))
		headers.Set("Authorization", fmt.Sprintf("Basic %s", encoded))
	}
	return
}

func saveToken(directory string, value token) (err error) {
	if err = filesystem.MkDir(directory); err != nil {
		return
	}
	if err = filesystem.Chmod(directory, 0700); err != nil {
		return
	}

	data, err := json.Marshal(value)
	if err != nil {
		return
	}
	file, err := filesystem.TempFile(directory, ".openai-*")
	if err != nil {
		return
	}
	defer os.Remove(file.Name())
	defer file.Close()
	if err = filesystem.Chmod(file.Name(), 0600); err != nil {
		return
	}
	if _, err = file.Write(data); err != nil {
		return
	}
	if err = file.Sync(); err != nil {
		return
	}
	if err = file.Close(); err != nil {
		return
	}
	// Require an atomic same-directory rename, without a copy fallback.
	err = os.Rename(file.Name(), filepath.Join(directory, "openai.json"))
	return
}

func exchangeToken(ctx context.Context, client *http.Client, form url.Values) (value token, err error) {
	if err = parallelisation.DetermineContextError(ctx); err != nil {
		return
	}
	if client == nil {
		err = commonerrors.UndefinedVariable("HTTP client")
		return
	}

	request, err := http.NewRequestWithContext(ctx, http.MethodPost, "https://auth.openai.com/oauth/token", strings.NewReader(form.Encode()))
	if err != nil {
		return
	}
	request.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	response, err := client.Do(request)
	if err != nil {
		err = commonerrors.Newf(commonerrors.ErrUnavailable, "OpenAI sign-in request failed")
		return
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		err = endpointError(response.StatusCode)
		return
	}
	if err = json.NewDecoder(io.LimitReader(response.Body, 1<<20)).Decode(&value); err != nil {
		err = commonerrors.Newf(commonerrors.ErrInvalid, "OpenAI returned an invalid sign-in response")
		return
	}
	if value.Access == "" || value.ExpiresIn <= 0 {
		err = commonerrors.Newf(commonerrors.ErrInvalid, "OpenAI did not issue an access token")
		return
	}
	value.ExpiresAt = time.Now().Add(time.Duration(value.ExpiresIn) * time.Second)
	parts := strings.Split(value.ID, ".")
	if len(parts) == 3 {
		payload, subErr := base64.RawURLEncoding.DecodeString(parts[1])
		if subErr == nil {
			var claims struct {
				Auth struct {
					Account string `json:"chatgpt_account_id"`
				} `json:"https://api.openai.com/auth"`
			}
			if json.Unmarshal(payload, &claims) == nil {
				value.Account = claims.Auth.Account
			}
		}
	}
	// Account metadata only; the upstream service authorises the access token.
	value.ID = ""
	return
}

func loginOpenAI(ctx context.Context, directory string) (err error) {
	if err = parallelisation.DetermineContextError(ctx); err != nil {
		return
	}
	ctx, cancel := context.WithTimeout(ctx, 5*time.Minute)
	defer cancel()
	randomness := make([]byte, 32)
	if _, err = rand.Read(randomness); err != nil {
		return
	}
	verifier := base64.RawURLEncoding.EncodeToString(randomness)
	state := rand.Text()
	digest := sha256.Sum256([]byte(verifier))
	query := url.Values{
		"response_type": {"code"}, "client_id": {openAIClientID}, "redirect_uri": {redirectURI},
		"scope": {"openid profile email offline_access"}, "code_challenge": {base64.RawURLEncoding.EncodeToString(digest[:])},
		"code_challenge_method": {"S256"}, "state": {state}, "originator": {"gptel"},
		"id_token_add_organizations": {"true"}, "codex_cli_simplified_flow": {"true"},
	}
	listener, err := net.Listen("tcp", "127.0.0.1:1455")
	if err != nil {
		return
	}
	codes := make(chan string, 1)
	server := &http.Server{ReadHeaderTimeout: 5 * time.Second, MaxHeaderBytes: 16 << 10, Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet || r.URL.Path != "/auth/callback" || r.URL.Query().Get("state") != state || r.URL.Query().Get("code") == "" {
			http.Error(w, "Invalid sign-in callback", http.StatusBadRequest)
			return
		}
		select {
		case codes <- r.URL.Query().Get("code"):
		default:
		}
		w.Header().Set("Cache-Control", "no-store")
		fmt.Fprintln(w, "Sign-in received. Return to the host terminal.")
	})}
	defer server.Close()
	go server.Serve(listener)
	fmt.Printf("Open this address in your host browser (do not share it):\nhttps://auth.openai.com/oauth/authorize?%s\n", query.Encode())
	select {
	case code := <-codes:
		value, subErr := exchangeToken(ctx, upstreamClient(), url.Values{"grant_type": {"authorization_code"}, "client_id": {openAIClientID}, "code": {code}, "code_verifier": {verifier}, "redirect_uri": {redirectURI}})
		if subErr != nil {
			err = subErr
			return
		}
		if value.Refresh == "" {
			err = commonerrors.Newf(commonerrors.ErrInvalid, "OpenAI did not issue a refresh token")
			return
		}
		err = saveToken(directory, value)
	case <-ctx.Done():
		err = ctx.Err()
	}
	return
}
