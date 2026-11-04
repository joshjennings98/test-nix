;;; config.el -*- lexical-binding: t; -*-

(setq doom-theme 'doom-gruvbox
      doom-font (font-spec :family "Iosevka" :size 18)
      doom-variable-pitch-font (font-spec :family "Iosevka" :size 14)
      org-directory (expand-file-name "~/Documents/org/")
      avy-all-windows nil
      treesit-font-lock-level 4)

(setq custom-file (expand-file-name "custom.el" doom-state-dir))
(load custom-file 'noerror 'nomessage)

(after! ispell
  (setq ispell-program-name "aspell"
        ispell-dictionary "en_GB"
        ispell-alternate-dictionary (expand-file-name "english-words" doom-user-dir)))

(load! "keys")
(load! "agent-shell-inline")

(use-package! agent-shell
  :commands (agent-shell agent-shell-new-shell agent-shell-toggle
             agent-shell-switch-buffer agent-shell-resume-session
             agent-shell-prompt-compose agent-shell-viewport-view-last
             agent-shell-send-region agent-shell-send-dwim agent-shell-send-file
             agent-shell-send-other-file agent-shell-send-clipboard-image
             agent-shell-send-screenshot agent-shell-new-worktree-shell))

(after! eglot
  (setq-default eglot-workspace-configuration
                '(:gopls
                  (:hints
                   (:assignVariableTypes t
                    :compositeLiteralFields t
                    :compositeLiteralTypes t
                    :constantValues t
                    :functionTypeParameters t
                    :parameterNames t
                    :rangeVariableTypes t))))

  (defun josh/organise-go-imports ()
    "Organise imports in the current managed Go buffer."
    (when (eglot-managed-p)
      (dolist (action (eglot-code-actions (point-min) (point-max)
                                         "source.organizeImports"))
        (eglot-execute (eglot-current-server) action))))

  (add-hook! 'eglot-managed-mode-hook
    (defun josh/configure-go-eglot ()
      "Enable Go hints and import organisation while Eglot manages the buffer."
      (when (derived-mode-p 'go-mode 'go-ts-mode)
        (eglot-inlay-hints-mode (if (eglot-managed-p) 1 -1))
        (if (eglot-managed-p)
            (add-hook 'before-save-hook #'josh/organise-go-imports nil t)
          (remove-hook 'before-save-hook #'josh/organise-go-imports t))))))

(setq go-ts-mode-indent-offset 4)

(after! evil
  (dolist (command '(find-file project-find-file consult-buffer consult-ripgrep
                     +default/search-project eglot-find-declaration
                     eglot-find-implementation eglot-find-typeDefinition))
    (evil-add-command-properties command :jump t))

  (map! :m "G" #'evil-avy-goto-char-2
        :m "g e" #'evil-goto-line
        :m "g o" #'evil-jump-backward
        :m "g O" #'evil-jump-forward
        :nv "g O" #'evil-jump-forward
        :n "U" #'evil-redo
        :n "g r" #'xref-find-references
        :nv "w" #'expreg-expand
        :nv "W" #'expreg-contract))

(use-package! evil-textobj-tree-sitter
  :after evil
  :demand t
  :config
  (map! :textobj "f" (evil-textobj-tree-sitter-get-textobj "function.inner")
                    (evil-textobj-tree-sitter-get-textobj "function.outer")
        :textobj "s" (evil-textobj-tree-sitter-get-textobj "class.inner")
                    (evil-textobj-tree-sitter-get-textobj "class.outer")
        :textobj "a" (evil-textobj-tree-sitter-get-textobj "parameter.inner")
                    (evil-textobj-tree-sitter-get-textobj "parameter.outer")
        :textobj "c" (evil-textobj-tree-sitter-get-textobj "conditional.inner")
                    (evil-textobj-tree-sitter-get-textobj "conditional.outer")
        :textobj "l" (evil-textobj-tree-sitter-get-textobj "loop.inner")
                    (evil-textobj-tree-sitter-get-textobj "loop.outer")
        :textobj "g" (evil-textobj-tree-sitter-get-textobj "comment.inner")
                    (evil-textobj-tree-sitter-get-textobj "comment.outer"))

  (dolist (text-object '(("f" . "function")
                         ("s" . "class")
                         ("a" . "parameter")
                         ("c" . "conditional")
                         ("l" . "loop")
                         ("g" . "comment")))
    (let ((key (car text-object))
          (capture (cdr text-object)))
      (define-key evil-normal-state-map (kbd (format "] %s" key))
                  (lambda ()
                    (interactive)
                    (evil-set-jump)
                    (evil-textobj-tree-sitter-goto-textobj
                     (format "%s.outer" capture))))
      (define-key evil-normal-state-map (kbd (format "[ %s" key))
                  (lambda ()
                    (interactive)
                    (evil-set-jump)
                    (evil-textobj-tree-sitter-goto-textobj
                     (format "%s.outer" capture) t))))))

