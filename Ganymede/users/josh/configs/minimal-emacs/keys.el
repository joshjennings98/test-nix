;;; keys.el --- Familiar Doom navigation -*- lexical-binding: t; -*-

(defvar emacs2-leader-map (make-sparse-keymap))
(evil-define-key '(normal motion visual) 'global (kbd "SPC") emacs2-leader-map)
(global-set-key (kbd "C-c SPC") emacs2-leader-map)

(dolist (state '(motion insert))
  (evil-define-minor-mode-key state 'visual-line-mode
    (kbd "<down>") #'evil-next-visual-line
    (kbd "<up>") #'evil-previous-visual-line))

(dolist (prefix '("F" "B" "P" "T" "c" "s" "h" "e"))
  (define-key emacs2-leader-map (kbd prefix) (make-sparse-keymap)))

(dolist (binding '(("f" . project-find-file)
                   ("b" . consult-buffer)
                   ("p" . project-switch-project)
                   ("." . find-file)
                   ("/" . consult-ripgrep)
                   ("F f" . find-file)
                   ("F r" . consult-recent-file)
                   ("F s" . save-buffer)
                   ("F R" . bufferfile-rename)
                   ("F D" . bufferfile-delete)
                   ("B b" . consult-buffer)
                   ("B k" . kill-current-buffer)
                   ("B n" . next-buffer)
                   ("B p" . previous-buffer)
                   ("P p" . project-switch-project)
                   ("P f" . project-find-file)
                   ("P b" . consult-project-buffer)
                   ("P t" . emacs2-trust-project)
                   ("P u" . emacs2-untrust-project)
                   ("T n" . emacs2-ghostel-here)
                   ("T s" . emacs2-ghostel-split)
                   ("c a" . eglot-code-actions)
                   ("c r" . eglot-rename)
                   ("c d" . consult-flymake)
                   ("c i" . consult-imenu)
                   ("s l" . easysession-switch-to)
                   ("s s" . easysession-save)
                   ("h f" . helpful-callable)
                   ("h v" . helpful-variable)
                   ("h k" . helpful-key)
                   ("e j" . cider-jack-in)
                   ("e c" . cider-connect)
                   ("e e" . cider-eval-last-sexp)
                   ("e f" . cider-eval-defun-at-point)
                   ("e b" . cider-eval-buffer)
                   ("e r" . cider-switch-to-repl-buffer)
                   ("e t" . cider-test-run-ns-tests)))
  (define-key emacs2-leader-map (kbd (car binding)) (cdr binding)))

(which-key-add-keymap-based-replacements emacs2-leader-map
  "f" "Find project file" "b" "Switch buffer" "p" "Switch project"
  "F" "file" "B" "buffer" "P" "project" "T" "terminal"
  "P t" "Trust project" "P u" "Revoke project trust"
  "c" "code" "s" "session" "h" "help" "e" "Clojure evaluation")

(evil-define-key '(normal motion) 'global
  (kbd "G") #'avy-goto-char-2
  (kbd "g e") #'evil-goto-line
  (kbd "g d") #'xref-find-definitions
  (kbd "g r") #'xref-find-references
  (kbd "g o") #'evil-jump-backward
  (kbd "g O") #'evil-jump-forward
  (kbd "g ;") #'goto-last-change
  (kbd "g ,") #'goto-last-change-reverse)
(evil-define-key 'normal 'global
  (kbd "u") #'undo-fu-only-undo
  (kbd "U") #'undo-fu-only-redo
  (kbd "z o") #'kirigami-open-fold
  (kbd "z O") #'kirigami-open-fold-rec
  (kbd "z c") #'kirigami-close-fold
  (kbd "z a") #'kirigami-toggle-fold
  (kbd "z r") #'kirigami-open-folds
  (kbd "z m") #'kirigami-close-folds)

(dolist (command '(avy-goto-char-2 find-file project-find-file consult-buffer
                   consult-ripgrep eglot-find-implementation eglot-find-typeDefinition))
  (evil-add-command-properties command :jump t))
