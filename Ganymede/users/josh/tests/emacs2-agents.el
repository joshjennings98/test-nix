;;; emacs2-agents.el --- Agent workflow integration checks -*- lexical-binding: t; -*-

(require 'ert)

(ert-deftest emacs2-agent-entry-points-and-local-leaders ()
  (dolist (binding emacs2-agent-bindings)
    (should (commandp (cdr binding)))
    (should (eq (lookup-key emacs2-leader-map (kbd (concat "a " (car binding))))
                (cdr binding))))
  (with-temp-buffer
    (org-mode)
    (evil-normal-state)
    (should (eq (key-binding (kbd "SPC m D a")) #'design-review-check-document))
    (should (eq (key-binding (kbd "SPC f")) #'project-find-file)))
  (with-temp-buffer
    (agent-shell-inline-prompt-mode)
    (evil-insert-state)
    (should (eq (key-binding (kbd "RET")) #'newline))
    (evil-normal-state)
    (should (eq (key-binding (kbd "RET")) #'agent-shell-inline-send))
    (should (eq (key-binding (kbd "SPC m m")) #'agent-shell-inline-cycle-reference))
    (should (eq (key-binding (kbd "SPC f")) #'project-find-file))
    (should (eq (command-remapping 'evil-save-and-close) #'agent-shell-inline-write-and-quit)))
  (dolist (map (list agent-shell-mode-map agent-shell-viewport-view-mode-map
                     agent-shell-viewport-edit-mode-map agent-shell-diff-mode-map))
    (cl-labels ((check (map)
                  (map-keymap (lambda (_ binding)
                                (if (keymapp binding)
                                    (check binding)
                                  (should (commandp binding)))) map)))
      (check (lookup-key map (kbd "C-c m"))))))

(ert-deftest emacs2-agent-state-stays-outside-projects ()
  (let ((root (make-temp-file "agent-state-project-" t)))
    (cl-letf (((symbol-function 'agent-shell-cwd) (lambda () root)))
      (dolist (subdir '("transcripts" "screenshots"))
        (should (file-in-directory-p (agent-shell--dot-subdir subdir) emacs2-state-directory)))
      (should-not (file-exists-p (expand-file-name ".agent-shell" root)))
      (should-not (file-exists-p (expand-file-name ".gitignore" root))))
    (should (file-in-directory-p (agent-shell-cache-dir "content") emacs2-state-directory))
    (should (file-in-directory-p shell-maker-root-path emacs2-state-directory))))

(ert-deftest emacs2-agent-core-features-loaded ()
  (dolist (feature '(agent-shell agent-shell-inline agent-shell-permission-transient
                     agent-shell-output-limit agent-shell-completion-notify
                     agent-shell-navigation design-review design-review-execution
                     design-review-async design-review-mcp org-mermaid))
    (should (featurep feature)))
  (should agent-shell-permission-transient-mode)
  (should-not agent-shell-inhibit-system-sleep)
  (should (file-exists-p ob-mermaid-default-config-file))
  (should (eq agent-shell-preferred-agent-config 'codex)))
