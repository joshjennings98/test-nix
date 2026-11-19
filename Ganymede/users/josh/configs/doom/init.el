;;; init.el -*- lexical-binding: t; -*-

;; Register before Doom initialises Evil Collection; keys.el owns these bindings.
(with-eval-after-load 'evil-collection
  (setq evil-collection-mode-list (delq 'agent-shell evil-collection-mode-list)))

(doom! :input
       :completion
       (corfu +orderless)
       vertico

       :ui
       doom
       dashboard
       hl-todo
       indent-guides
       modeline
       nav-flash
       ophints
       (popup +defaults)
       vc-gutter
       vi-tilde-fringe
       window-select
       workspaces

       :editor
       (evil +everywhere)
       file-templates
       fold
       (format +onsave +lsp)
       multiple-cursors
       snippets

       :emacs
       dired
       electric
       ibuffer
       undo
       vc

       :term
       eshell
       ghostel
       vterm

       :checkers
       syntax

       :tools
       direnv
       editorconfig
       eval
       lookup
       (lsp +eglot)
       magit
       make
       tree-sitter

       :lang
       data
       emacs-lisp
       (go +lsp +tree-sitter)
       (json +tree-sitter)
       markdown
       (nix +lsp +tree-sitter)
       (org +pretty)
       (python +lsp +tree-sitter)
       (sh +tree-sitter)
       (yaml +tree-sitter)

       :config
       (default +bindings +smartparens))
