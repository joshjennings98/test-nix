;;; emacs2-agent-setup.el --- Agent Shell and Org design reviews -*- lexical-binding: t; -*-

(require 'agent-shell)
(require 'agent-shell-permission-transient)
(require 'agent-shell-inline)
(require 'agent-shell-output-limit)
(require 'agent-shell-completion-notify)
(require 'design-review-mcp)
(require 'agent-shell-navigation)
(require 'org-mermaid)

(defun emacs2-agent-project-directory (subdir)
  "Store agent SUBDIR under persisted state, separated by project path."
  (expand-file-name
   subdir
   (expand-file-name
    (secure-hash 'sha256 (file-truename (agent-shell-cwd)))
    (expand-file-name "agent-shell/projects/" emacs2-state-directory))))

(defun emacs2-agent-cache-directory (&rest components)
  "Return a persisted agent cache directory for COMPONENTS."
  (let ((directory (apply #'file-name-concat emacs2-state-directory "agent-shell/cache" components)))
    (make-directory directory t)
    directory))

(setq agent-shell-preferred-agent-config 'codex
      agent-shell-openai-default-model-id "gpt-6.2-sol"
      agent-shell-inhibit-system-sleep nil
      agent-shell-dot-subdir-function #'emacs2-agent-project-directory
      shell-maker-root-path (expand-file-name "agent-shell/" emacs2-state-directory))
(setf (alist-get "reasoning_effort" agent-shell-openai-default-config-options nil nil #'equal)
      "medium")
(when-let* ((codex-path (getenv "EMACS_CODEX_PATH")))
  (add-to-list 'agent-shell-openai-codex-environment (concat "CODEX_PATH=" codex-path)))
(advice-add 'agent-shell-cache-dir :override #'emacs2-agent-cache-directory)
(agent-shell-permission-transient-mode 1)
(add-to-list 'agent-shell-mcp-servers
             '((name . "emacs-navigation")
               (command . (lambda () (or (executable-find "socat")
                                        (error "socat is not installed"))))
               (args . (lambda () (agent-shell-navigation-connect)))
               (env . [])))

(defun emacs2-agent-command ()
  "Choose any public Agent Shell command using completion."
  (interactive)
  (call-interactively
   (intern (completing-read
            "Agent command: " obarray
            (lambda (symbol)
              (and (commandp symbol)
                   (string-prefix-p "agent-shell-" (symbol-name symbol))
                   (not (string-match-p "--" (symbol-name symbol))))) t))))

(defun emacs2-agent-return ()
  "Activate the item at point or submit the current prompt."
  (interactive)
  (let* ((map (get-char-property (point) 'keymap))
         (action (and map (lookup-key map (kbd "RET")))))
    (cond
     ((commandp action) (call-interactively action))
     ((button-at (point)) (push-button))
     ((derived-mode-p 'agent-shell-mode) (call-interactively #'agent-shell-submit))
     ((derived-mode-p 'agent-shell-viewport-edit-mode)
      (call-interactively #'agent-shell-viewport-compose-send))
     (t (user-error "No agent action at point")))))

(require 'emacs2-agent-keys)
(provide 'emacs2-agent-setup)
