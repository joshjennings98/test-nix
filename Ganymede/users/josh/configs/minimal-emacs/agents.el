;;; agents.el --- Lazy entry points for the agent workflow -*- lexical-binding: t; -*-

(add-to-list 'load-path minimal-emacs-user-directory)
(add-to-list 'load-path (expand-file-name "agent/" minimal-emacs-user-directory))

(defun emacs2-agent-bindings (map bindings)
  "Install BINDINGS in MAP, creating their prefix maps as needed."
  (dolist (binding bindings)
    (let ((keys (kbd (car binding))))
      (dotimes (index (1- (length keys)))
        (let ((prefix (seq-take keys (1+ index))))
          (unless (keymapp (lookup-key map prefix))
            (define-key map prefix (make-sparse-keymap)))))
      (define-key map keys (cdr binding)))))

(defvar emacs2-agent-map (make-sparse-keymap))
(defconst emacs2-agent-bindings
  '(("a" . agent-shell) ("t" . agent-shell-toggle)
    ("b" . agent-shell-switch-buffer) ("r" . agent-shell-inline-reply)
    ("S" . agent-shell-send-region) ("f" . agent-shell-send-file)
    ("p" . agent-shell-inline) ("l" . agent-shell-inline-continue-recent)
    ("P" . agent-shell-inline-visit) ("m" . agent-shell-inline-message)
    ("n" . agent-shell-inline-navigate) ("o" . agent-shell-inline--response-overlay-dispatch)
    ("v" . agent-shell-inline-review) ("x" . agent-shell-inline-interrupt)
    ("j" . agent-shell-inline--response-overlay-down)
    ("k" . agent-shell-inline--response-overlay-up)
    ("D" . agent-shell-inline--response-overlay-pagedown)
    ("U" . agent-shell-inline--response-overlay-pageup)
    ("i f" . agent-shell-send-other-file) ("i i" . agent-shell-send-clipboard-image)
    ("i s" . agent-shell-send-screenshot) ("i d" . agent-shell-send-dwim)
    ("N n" . agent-shell-new-shell) ("N r" . agent-shell-resume-session)
    ("N w" . agent-shell-new-worktree-shell) ("?" . emacs2-agent-command)))

(dolist (binding emacs2-agent-bindings)
  (autoload (cdr binding) "emacs2-agent-setup" nil t))
(emacs2-agent-bindings emacs2-agent-map emacs2-agent-bindings)
(define-key emacs2-leader-map (kbd "a") emacs2-agent-map)
(which-key-add-keymap-based-replacements emacs2-leader-map "a" "agent")
(which-key-add-keymap-based-replacements emacs2-agent-map
  "i" "send context" "N" "new / resume session")

(defvar emacs2-design-review-map (make-sparse-keymap))
(dolist (binding '(("n" . design-review-create) ("v" . design-review-validate-document)
                   ("c" . design-review-check-block) ("a" . design-review-check-document)))
  (autoload (cdr binding) "emacs2-agent-setup" nil t)
  (define-key emacs2-design-review-map (kbd (car binding)) (cdr binding)))
(with-eval-after-load 'org
  (evil-define-key '(normal motion visual) org-mode-map
    (kbd "SPC m D") emacs2-design-review-map)
  (define-key org-mode-map (kbd "C-c m D") emacs2-design-review-map))

(dolist (language '(design-graph test-review change-review implementation-review diagram-review))
  (autoload (intern (format "org-babel-execute:%s" language)) "emacs2-agent-setup")
  (with-eval-after-load 'org
    (add-to-list 'org-src-lang-modes (cons (symbol-name language) 'text))))
(autoload 'org-babel-execute:mermaid "emacs2-agent-setup")
