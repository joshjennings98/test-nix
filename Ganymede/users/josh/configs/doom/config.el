;;; config.el -*- lexical-binding: t; -*-

(setq doom-theme 'doom-gruvbox
      doom-font (font-spec :family "Iosevka" :size 18)
      doom-variable-pitch-font (font-spec :family "Iosevka" :size 14)
      org-directory (expand-file-name "~/Documents/org/")
      avy-all-windows nil
      treesit-font-lock-level 4)

(setq custom-file (expand-file-name "custom.el" doom-state-dir))
(load custom-file 'noerror 'nomessage)

(load! "keys")

(use-package! gptel
  :config
  (require 'gptel-openai-oauth)

  (setq gptel-openai-oauth-login-method 'authorization-code
        gptel--openai-oauth-token-file
        (expand-file-name "gptel-openai-oauth-token" doom-state-dir)
        gptel-model (intern (or (getenv "EMACS_BROKER_MODEL") "gpt-5.6-sol"))
        gptel-backend
        (if (getenv "EMACS_BROKER_URL")
            (gptel-make-openai-responses
             "Responses (broker)" :models (list gptel-model) :stream t
             :protocol "http" :host "127.0.0.1:8123"
             :endpoint "/openai/responses" :header nil :key nil)
          (gptel-make-openai-oauth
           "OpenAI subscription" :models '(gpt-5.6-sol)))
        gptel-log-level nil
        gptel-confirm-tool-calls 'auto))

(defun josh/gptel-agent-tool-path (tool-call)
  "Return the filesystem path targeted by TOOL-CALL, when it has one."
  (let ((name (plist-get tool-call :name))
        (args (plist-get tool-call :args)))
    (pcase name
      ("Read" (plist-get args :file_path))
      ((or "Glob" "Grep" "Edit" "Insert") (plist-get args :path))
      ("Write" (expand-file-name (plist-get args :filename)
                                 (or (plist-get args :path) default-directory)))
      ("Mkdir" (expand-file-name (plist-get args :name)
                                 (or (plist-get args :parent) default-directory))))))

(defun josh/gptel-confirm-outside-project (tool-call)
  "Require confirmation when TOOL-CALL targets outside the active project."
  (when-let ((path (josh/gptel-agent-tool-path tool-call)))
    (let* ((project (project-current nil default-directory))
           (project-directory (if project
                                  (project-root project)
                                default-directory))
           (target (expand-file-name path default-directory)))
      (unless (or (string-equal (directory-file-name target)
                                (directory-file-name project-directory))
                (file-in-directory-p target project-directory))
        '(:confirm t)))))

(after! gptel
  (add-hook 'gptel-pre-tool-call-functions #'josh/gptel-confirm-outside-project))

(use-package! gptel-agent
  :after gptel
  :config
  (when-let ((broker (getenv "EMACS_BROKER_URL")))
    (require 'eww)
    (setq eww-search-prefix (concat broker "/search?q="))
    (advice-add 'gptel-agent--read-url :filter-args
                (lambda (args)
                  (list (car args)
                        (concat broker "/page?url=" (url-hexify-string (cadr args)))))))
  (gptel-agent-update))

(use-package! gptel-inline
  :commands gptel-inline
  :config
  (defun josh/gptel-project-chat (buffer)
    "Reuse the project chat or start a planning session for BUFFER."
    (with-current-buffer buffer
      (let* ((details (or (gptel-inline-project-buffer buffer)
                          (format "*gptel:%s*" default-directory)))
             (directory (if (consp details) (cadr details) default-directory))
             (name (if (consp details)
                       (generate-new-buffer-name (car details))
                     details)))
        (unless (get-buffer name)
          (require 'gptel-agent)
          (with-current-buffer (gptel name)
            (setq default-directory directory)
            (gptel-agent-update)
            (gptel-preset 'gptel-plan
                          (lambda (symbol value)
                            (set (make-local-variable symbol) value)))))
        name)))

  (setq gptel-inline-find-chat-buffer-functions
        '(gptel-inline-previous-buffer gptel-inline-same-buffer
          josh/gptel-project-chat)))

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

