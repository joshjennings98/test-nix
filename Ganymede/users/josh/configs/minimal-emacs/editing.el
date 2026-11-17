;;; editing.el --- Editing and presentation -*- lexical-binding: t; -*-

(add-to-list 'custom-theme-load-path minimal-emacs-user-directory)
(load-theme 'emacs2-gruvbox t)
(set-face-attribute 'default nil :family "Iosevka" :height 120)
(add-to-list 'default-frame-alist '(font . "Iosevka-12"))
(setq-default display-line-numbers nil)
(setq display-line-numbers-type t)
(add-hook 'prog-mode-hook #'display-line-numbers-mode)
(add-hook 'prog-mode-hook #'visual-line-mode)
(add-hook 'text-mode-hook #'visual-line-mode)
(setq line-move-visual t)
(setq line-number-mode nil
      column-number-mode nil
      treesit-font-lock-level 4
      confirm-kill-emacs nil
      ediff-keep-variants t
      pixel-scroll-precision-use-momentum nil)
(show-paren-mode -1)
(delete-selection-mode 1)
(electric-pair-mode 1)
(window-divider-mode 1)
(pixel-scroll-precision-mode 1)
(minibuffer-depth-indicate-mode 1)

(require 'uniquify)
(setq uniquify-buffer-name-style 'reverse
      uniquify-separator "•"
      uniquify-after-kill-buffer-p t)

(use-package which-key
  :demand t
  :config
  (setq which-key-idle-delay 0.01
        which-key-idle-secondary-delay 0.01)
  (which-key-mode 1))

(use-package evil
  :demand t
  :init
  (setq evil-want-integration t
        evil-want-keybinding nil
        evil-respect-visual-line-mode t
        evil-undo-system 'undo-fu)
  :config (evil-mode 1))

(use-package evil-collection
  :after evil
  :demand t
  :config
  (setq evil-collection-mode-list (delq 'agent-shell evil-collection-mode-list))
  (evil-collection-init))

(use-package goto-chg :commands (goto-last-change goto-last-change-reverse))
(use-package evil-surround
  :after evil
  :demand t
  :config (global-evil-surround-mode 1))
(use-package evil-matchit
  :after evil
  :demand t
  :config (global-evil-matchit-mode 1))
(use-package avy
  :commands avy-goto-char-2
  :init (setq avy-all-windows nil))

(use-package yasnippet
  :hook ((prog-mode text-mode) . yas-minor-mode)
  :config (require 'yasnippet-snippets))
(use-package stripspace
  :hook ((prog-mode text-mode conf-mode) . stripspace-local-mode)
  :init (setq stripspace-only-if-initially-clean t))

(use-package markdown-mode
  :mode (("\\.md\\'" . markdown-mode) ("\\.markdown\\'" . markdown-mode)))
(use-package markdown-toc :commands markdown-toc-generate-toc)
(use-package org
  :mode ("\\.org\\'" . org-mode)
  :init
  (setq org-directory (expand-file-name "~/Documents/org/")
        org-startup-indented t
        org-hide-leading-stars t
        org-adapt-indentation nil
        org-edit-src-content-indentation 0
        org-startup-truncated t
        org-hide-emphasis-markers t
        org-return-follows-link t))
(use-package org-appear :hook (org-mode . org-appear-mode))
(use-package bufferfile :commands (bufferfile-rename bufferfile-delete))

(use-package dired
  :commands dired
  :hook ((dired-mode . dired-hide-details-mode)
         (dired-mode . dired-omit-mode))
  :config
  (require 'dired-x)
  (setq dired-listing-switches "--group-directories-first -ahlv"
        dired-movement-style 'bounded-files
        dired-omit-files
        (concat dired-omit-files "\\|\\`\\(?:\\.git\\|__pycache__\\)\\'\\|\\.\\(?:elc\\|o\\|pyc\\|class\\)\\'")))

(defun emacs2-ghostel-setup ()
  "Keep terminals uncluttered."
  (setq-local mode-line-format nil)
  (display-line-numbers-mode -1))

(defun emacs2-ghostel-environment (&rest _)
  "Allow direnv to initialise inside the terminal shell."
  (setq-local process-environment
              (seq-remove (lambda (value) (string-prefix-p "DIRENV_" value))
                          process-environment)))

(use-package ghostel
  :commands ghostel
  :init
  (setq ghostel-bold-color 'bright
        ghostel-module-auto-install nil)
  :hook ((ghostel-mode . emacs2-ghostel-setup)
         (ghostel-pre-spawn . emacs2-ghostel-environment)))
(use-package evil-ghostel
  :hook (ghostel-mode . evil-ghostel-mode))

(defun emacs2-ghostel-here ()
  "Open a new terminal in the current directory and window."
  (interactive)
  (require 'ghostel)
  (let ((ghostel-buffer-name (generate-new-buffer-name "*ghostel*")))
    (switch-to-buffer (save-window-excursion (ghostel)))))

(defun emacs2-ghostel-split ()
  "Open a new terminal in a split below the current window."
  (interactive)
  (select-window (split-window-below))
  (emacs2-ghostel-here))
