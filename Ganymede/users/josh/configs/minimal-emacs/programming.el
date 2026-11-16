;;; programming.el --- Languages and structural editing -*- lexical-binding: t; -*-

(add-to-list 'treesit-extra-load-path "@grammarDirectory@")
(setq major-mode-remap-alist
      '((go-mode . go-ts-mode)
        (python-mode . python-ts-mode)
        (js-mode . js-ts-mode)
        (css-mode . css-ts-mode)
        (json-mode . json-ts-mode)
        (yaml-mode . yaml-ts-mode)))
(add-to-list 'auto-mode-alist '("\\.go\\'" . go-ts-mode))
(add-to-list 'auto-mode-alist '("/go\\.mod\\'" . go-mod-ts-mode))
(add-to-list 'auto-mode-alist '("\\.json\\'" . json-ts-mode))
(add-to-list 'auto-mode-alist '("\\.ts\\'" . typescript-ts-mode))
(add-to-list 'auto-mode-alist '("\\.tsx\\'" . tsx-ts-mode))
(setq go-ts-mode-indent-offset 4)
(setq eldoc-idle-delay 0.1)

(use-package indent-bars
  :commands indent-bars-mode
  :init
  (setq indent-bars-color '(shadow :blend 0.3)
        indent-bars-color-by-depth nil
        indent-bars-highlight-current-depth nil
        indent-bars-treesit-support nil
        indent-bars-pattern "."
        indent-bars-width-frac 0.15
        indent-bars-display-on-blank-lines nil))

(defun emacs2-indent-guides ()
  "Enable static guides after the language has set up indentation."
  (when (derived-mode-p 'prog-mode 'yaml-mode)
    (require 'indent-bars)
    (cond
     ((derived-mode-p 'go-ts-mode 'go-mod-ts-mode)
      (setq-local tab-width go-ts-mode-indent-offset
                  indent-bars-spacing-override go-ts-mode-indent-offset))
     ((derived-mode-p 'clojure-mode 'yaml-ts-mode)
      (setq-local indent-bars-spacing-override 2))
     ((derived-mode-p 'nix-mode)
      (setq-local indent-bars-spacing-override smie-indent-basic)))
    ;; Parenthesised continuations should not introduce additional guides.
    (setq-local indent-bars-no-descend-lists t)
    (unless (derived-mode-p 'lisp-data-mode 'clojure-mode)
      (setq-local indent-bars-ppss-syntax-table (copy-syntax-table (syntax-table)))
      (modify-syntax-entry ?\{ "." indent-bars-ppss-syntax-table)
      (modify-syntax-entry ?\} "." indent-bars-ppss-syntax-table))
    (indent-bars-mode 1)))

(add-hook 'after-change-major-mode-hook #'emacs2-indent-guides 90)

(defun emacs2-go-semantic-colours ()
  "Keep the local Gruvbox theme's Go argument and package colours."
  (setq-local
   treesit-font-lock-settings
   (append treesit-font-lock-settings
           (treesit-font-lock-rules
            :language 'go :feature 'variable :override t
            '((parameter_declaration name: (identifier) @emacs2-gruvbox-argument)
              (variadic_parameter_declaration name: (identifier) @emacs2-gruvbox-argument)
              (argument_list (selector_expression field: (field_identifier) @emacs2-gruvbox-argument))
              (selector_expression operand: (selector_expression field: (field_identifier) @emacs2-gruvbox-argument))
              (index_expression index: (identifier) @emacs2-gruvbox-argument)
              (expression_list (selector_expression field: (field_identifier) @emacs2-gruvbox-argument)))
            :language 'go :feature 'keyword :override t
            '(["import" "package"] @emacs2-gruvbox-package-keyword)
            :language 'go :feature 'variable :override t
            '((import_spec name: (package_identifier) @font-lock-variable-name-face)
              (package_clause (package_identifier) @font-lock-variable-name-face)
              (qualified_type package: (package_identifier) @font-lock-variable-name-face)))))
  (treesit-font-lock-recompute-features)
  (font-lock-flush))
(add-hook 'go-ts-mode-hook #'emacs2-go-semantic-colours)

(use-package eglot
  :commands (eglot-ensure eglot-rename eglot-code-actions
             eglot-find-implementation eglot-find-typeDefinition)
  :hook ((go-ts-mode . eglot-ensure)
         (clojure-mode . eglot-ensure))
  :init
  (setq eglot-sync-connect nil)
  (setq-default eglot-workspace-configuration
                '(:gopls
                  (:hints (:assignVariableTypes t
                           :compositeLiteralFields t
                           :compositeLiteralTypes t
                           :constantValues t
                           :functionTypeParameters t
                           :parameterNames t
                           :rangeVariableTypes t))))
  :config
  (add-to-list 'eglot-ignored-server-capabilities :documentHighlightProvider)
  (add-to-list 'eglot-server-programs '(go-ts-mode . ("gopls")))
  (add-to-list 'eglot-server-programs
               '((clojure-mode clojurec-mode clojurescript-mode) . ("clojure-lsp"))))

(defun emacs2-organise-go-imports ()
  "Organise imports before saving an Eglot-managed Go buffer."
  (when (eglot-managed-p)
    (dolist (action (eglot-code-actions (point-min) (point-max)
                                       "source.organizeImports"))
      (eglot-execute (eglot-current-server) action))))

(defun emacs2-go-eglot-setup ()
  "Keep Go hints and import organisation tied to Eglot's lifetime."
  (when (derived-mode-p 'go-mode 'go-ts-mode)
    (eglot-inlay-hints-mode (if (eglot-managed-p) 1 -1))
    (if (eglot-managed-p)
        (add-hook 'before-save-hook #'emacs2-organise-go-imports nil t)
      (remove-hook 'before-save-hook #'emacs2-organise-go-imports t))))
(add-hook 'eglot-managed-mode-hook #'emacs2-go-eglot-setup)

(use-package dumb-jump
  :commands dumb-jump-xref-activate
  :init
  (add-hook 'xref-backend-functions #'dumb-jump-xref-activate 80)
  (setq dumb-jump-force-searcher 'rg
        dumb-jump-selector 'completing-read))

(use-package apheleia
  :hook (prog-mode . apheleia-mode)
  :config
  (setf (alist-get 'go-ts-mode apheleia-mode-alist) 'gofmt)
  (setf (alist-get 'nix-mode apheleia-mode-alist) 'nixfmt))
(use-package diff-hl
  :hook ((prog-mode text-mode conf-mode) . diff-hl-mode))

(use-package kirigami
  :demand t
  :config (kirigami-global-mode 1))
(use-package outline
  :hook ((emacs-lisp-mode lisp-mode conf-mode markdown-mode) . outline-minor-mode))
(use-package hideshow
  :hook ((c-mode c++-mode java-mode sh-mode clojure-mode) . hs-minor-mode))
(use-package outline-indent
  :hook ((python-mode python-ts-mode yaml-mode yaml-ts-mode) . outline-indent-minor-mode))
(use-package treesit-fold
  :hook ((go-ts-mode js-ts-mode typescript-ts-mode tsx-ts-mode
          css-ts-mode json-ts-mode bash-ts-mode) . treesit-fold-mode))

(use-package helpful
  :bind (("C-h f" . helpful-callable)
         ("C-h v" . helpful-variable)
         ("C-h k" . helpful-key)
         ("C-h x" . helpful-command)))

(defun emacs2-paredit-setup ()
  "Let Paredit own pairing in Lisp buffers."
  (electric-pair-local-mode -1))
(use-package paredit
  :hook ((emacs-lisp-mode lisp-interaction-mode lisp-mode
          clojure-mode cider-repl-mode) . paredit-mode)
  :config (add-hook 'paredit-mode-hook #'emacs2-paredit-setup))
(use-package enhanced-evil-paredit
  :hook (paredit-mode . enhanced-evil-paredit-mode))
(use-package aggressive-indent
  :hook ((emacs-lisp-mode lisp-mode clojure-mode) . aggressive-indent-mode))
(use-package highlight-defined
  :hook (emacs-lisp-mode . highlight-defined-mode))
(use-package page-break-lines
  :hook ((emacs-lisp-mode lisp-mode) . page-break-lines-mode))
(use-package elisp-refs
  :commands (elisp-refs-function elisp-refs-macro elisp-refs-variable elisp-refs-symbol))

(use-package clojure-mode
  :mode (("\\.clj\\'" . clojure-mode)
         ("\\.cljs\\'" . clojurescript-mode)
         ("\\.cljc\\'" . clojurec-mode)
         ("\\.edn\\'" . clojure-mode)))
(use-package cider
  :commands (cider-jack-in cider-connect cider-eval-last-sexp
             cider-eval-defun-at-point cider-eval-buffer cider-switch-to-repl-buffer
             cider-test-run-ns-tests)
  :init
  (setq cider-use-xref nil
        cider-use-overlays t
        cider-repl-history-size 1000))

(use-package git-modes :defer t)
(use-package yaml-mode :mode "\\.ya?ml\\'")
(use-package dockerfile-mode :mode "Dockerfile\\'")
(use-package gnuplot :mode ("\\.gp\\'" . gnuplot-mode))
(use-package lua-mode :mode "\\.lua\\'")
(use-package jinja2-mode :mode "\\.j2\\'")
(use-package csv-mode :mode "\\.csv\\'")
(use-package rust-mode :mode "\\.rs\\'")
(use-package crontab-mode :mode "crontab\\'")
(use-package nginx-mode :mode "nginx\\.conf\\'")
(use-package hcl-mode :mode "\\.\\(?:hcl\\|tf\\)\\'")
(use-package nix-mode :mode "\\.nix\\'")
(use-package fish-mode :mode "\\.fish\\'")
(use-package vimrc-mode :mode "\\.?vimrc\\'")
(use-package jenkinsfile-mode :mode "Jenkinsfile\\'")
