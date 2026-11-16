;;; post-early-init.el --- Nix package ownership -*- lexical-binding: t; -*-

(setq use-package-always-ensure nil
      package-user-dir (expand-file-name "elpa/" emacs2-state-directory)
      package-quickstart-file (expand-file-name "package-quickstart.el" emacs2-state-directory)
      custom-file (expand-file-name "custom.el" emacs2-state-directory))
