;;; post-init.el --- Nix-managed editing environment -*- lexical-binding: t; -*-

(require 'use-package)
(require 'project)
(setq use-package-always-ensure nil
      use-package-always-defer t)

(dolist (file '("state.el" "projects.el" "trust.el" "completion.el" "editing.el" "programming.el" "keys.el" "modeline.el"))
  (load (expand-file-name file minimal-emacs-user-directory) nil t))
