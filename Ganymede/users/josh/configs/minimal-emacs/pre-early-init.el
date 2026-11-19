;;; pre-early-init.el --- Nix integration -*- lexical-binding: t; -*-

(setq minimal-emacs-package-initialize-and-refresh nil)

;; Match Gruvbox before the first graphical frame is created.
(dolist (parameter '((background-color . "#282828")
                     (foreground-color . "#ebdbb2")
                     (background-mode . dark)))
  (add-to-list 'default-frame-alist parameter))

(defvar emacs2-state-directory
  (expand-file-name "emacs2/" (or (getenv "XDG_STATE_HOME")
                                 "~/.local/state/")))

(make-directory emacs2-state-directory t)

(when (fboundp 'startup-redirect-eln-cache)
  (startup-redirect-eln-cache
   (expand-file-name "eln-cache/" emacs2-state-directory)))
