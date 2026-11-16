;;; state.el --- Persisted editor state -*- lexical-binding: t; -*-

(setq make-backup-files t
      vc-make-backup-files t
      kept-old-versions 10
      kept-new-versions 10
      auto-save-default t
      auto-save-interval 300
      auto-save-timeout 30
      recentf-save-file (expand-file-name "recentf" emacs2-state-directory)
      savehist-file (expand-file-name "history" emacs2-state-directory)
      save-place-file (expand-file-name "saveplace" emacs2-state-directory)
      project-list-file (expand-file-name "projects" emacs2-state-directory)
      bookmark-default-file (expand-file-name "bookmarks" emacs2-state-directory)
      undo-fu-session-directory (expand-file-name "undo/" emacs2-state-directory)
      easysession-directory (expand-file-name "sessions/" emacs2-state-directory)
      cider-repl-history-file (expand-file-name "cider-history" emacs2-state-directory)
      nrepl-log-messages nil)

(make-directory (expand-file-name "backup/" emacs2-state-directory) t)

(use-package autorevert
  :demand t
  :config
  (setq auto-revert-remote-files nil
        auto-revert-use-notify t)
  (global-auto-revert-mode 1))

(use-package recentf
  :demand t
  :config
  (setq recentf-auto-cleanup (if (daemonp) 300 'never))
  (recentf-mode 1))

(use-package savehist
  :demand t
  :config
  (setq history-length 300 savehist-autosave-interval 600)
  (savehist-mode 1))

(use-package saveplace
  :demand t
  :config (save-place-mode 1))

(use-package undo-fu :commands (undo-fu-only-undo undo-fu-only-redo))
(use-package undo-fu-session
  :demand t
  :config (undo-fu-session-global-mode 1))

(use-package easysession
  :demand t
  :config
  (setq easysession-save-interval 600
        easysession-switch-to-save-session t
        easysession-switch-to-exclude-current nil
        easysession-setup-load-session t)
  (unless noninteractive (easysession-setup)))

(use-package buffer-terminator
  :hook (after-init . buffer-terminator-mode))
