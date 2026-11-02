package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"github.com/ARM-software/golang-utils/utils/commonerrors"
	"github.com/ARM-software/golang-utils/utils/filesystem"
	"github.com/ARM-software/golang-utils/utils/parallelisation"
)

func run(ctx context.Context) (err error) {
	if err = parallelisation.DetermineContextError(ctx); err != nil {
		return
	}
	configPath := flag.String("config", "", "Nix-generated policy file")
	login := flag.Bool("login-openai", false, "Perform a fresh browser login on the host")
	flag.Parse()
	data, err := filesystem.ReadFile(*configPath)
	if err != nil {
		return
	}
	var cfg configuration
	if err = json.Unmarshal(data, &cfg); err != nil {
		return
	}
	if cfg.State == "" || cfg.Socket == "" {
		err = commonerrors.Newf(commonerrors.ErrInvalid, "state and socket paths are required")
		return
	}
	if *login && cfg.ModelEndpoint != "" {
		return commonerrors.Newf(commonerrors.ErrInvalid, "custom endpoint uses the systemd model-token credential; browser login is disabled")
	}
	if *login {
		return loginOpenAI(ctx, cfg.State)
	}

	var modelToken string
	if cfg.ModelEndpoint != "" {
		if _, err = modelEndpoint(cfg.ModelEndpoint); err != nil {
			return
		}
		modelToken, err = readModelToken(os.Getenv("CREDENTIALS_DIRECTORY"))
		if err != nil {
			return
		}
	}

	if subErr := os.Remove(cfg.Socket); subErr != nil && !errors.Is(subErr, os.ErrNotExist) {
		err = subErr
		return
	}
	listener, err := net.Listen("unix", cfg.Socket)
	if err != nil {
		return
	}
	defer listener.Close()
	if err = filesystem.Chmod(cfg.Socket, 0660); err != nil {
		return
	}
	client := upstreamClient()
	server := &http.Server{
		Handler:           &broker{config: cfg, client: client, credentials: &credentials{state: cfg.State, client: client, modelToken: modelToken}},
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       5 * time.Minute,
		WriteTimeout:      6 * time.Minute,
		IdleTimeout:       30 * time.Second,
		MaxHeaderBytes:    32 << 10,
	}
	go func() {
		<-ctx.Done()
		server.Close()
	}()
	err = server.Serve(listener)
	if errors.Is(err, http.ErrServerClosed) {
		err = nil
	}
	return
}

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()
	if err := run(ctx); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func readModelToken(directory string) (value string, err error) {
	if directory == "" {
		return "", commonerrors.Newf(commonerrors.ErrInvalid, "systemd credential directory is required")
	}

	data, err := filesystem.ReadFile(filepath.Join(directory, "model-token"))
	if err != nil {
		return "", commonerrors.Newf(commonerrors.ErrUnavailable, "cannot read model-token credential")
	}

	value = strings.TrimSuffix(strings.TrimSuffix(string(data), "\n"), "\r")
	if len(value) == 0 || len(value) > 16384 || strings.ContainsFunc(value, func(r rune) bool { return r <= ' ' || r > '~' }) {
		return "", commonerrors.Newf(commonerrors.ErrInvalid, "model-token must contain a single non-empty bearer token")
	}
	return
}
