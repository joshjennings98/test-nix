;;; pre-init.el --- Separate runtime state -*- lexical-binding: t; -*-

;; The init file has been located; subsequent state belongs outside the store.
(setq user-emacs-directory emacs2-state-directory)

(require 'server)
(setq server-name "emacs2")
