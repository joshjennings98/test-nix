;;; doom-startup.el -*- lexical-binding: t; -*-
;; Run with normal interactive startup: emacs -nw --load this-file.
;; Send a movement key after startup so Emacs runs its normal idle timers.
;; Uses a temporary Go project; never sends an LLM request.

(require 'ert)

(load (expand-file-name "../configs/doom/tests/keys.el"
                        (file-name-directory load-file-name)) nil t)

(load (expand-file-name "../configs/doom/tests/org-fc.el"
                        (file-name-directory load-file-name)) nil t)

(defvar josh/test-project (make-temp-file "doom-go-" t))
(defvar josh/test-buffer nil)

(let ((default-directory josh/test-project))
  (call-process "git" nil nil nil "init" "--quiet")
  (with-temp-file "go.mod"
    (insert "module example.com/doomcheck\n\ngo 1.22\n"))
  (with-temp-file "main.go"
    (insert "package main\n\nfunc greet(name string) string { return name }\n\nfunc main() { message := greet(\"hello\"); _ = message }\n")))

(run-at-time
 0.2 nil
 (lambda ()
   (setq josh/test-buffer (find-file (expand-file-name "main.go" josh/test-project)))
   (execute-kbd-macro (kbd "g g"))))

(ert-deftest josh/interactive-doom-go ()
  (switch-to-buffer josh/test-buffer)
  (should (memq 'doom-gruvbox custom-enabled-themes))
  (should (eq major-mode 'go-ts-mode))
  (should (eglot-managed-p))
  (should eglot-inlay-hints-mode)
  (should (seq-some (lambda (overlay) (overlay-get overlay 'eglot--inlay-hint))
                    (overlays-in (point-min) (point-max))))
  (require 'agent-shell)
  (should (eq (key-binding (kbd "SPC a a")) 'agent-shell))
  (should (eq (key-binding (kbd "SPC a N n")) 'agent-shell-new-shell))
  (should (eq (key-binding (kbd "SPC a n")) 'agent-shell-inline-navigate))
  (should (eq (key-binding (kbd "SPC a r")) 'agent-shell-inline-reply))
  (should (eq (key-binding (kbd "SPC a S")) 'agent-shell-send-region))
  (should (executable-find "codex-acp"))
  (should (commandp (lookup-key evil-inner-text-objects-map "f")))
  (goto-char (point-max))
  (search-backward "greet")
  (execute-kbd-macro (kbd "g d"))
  (should (eq (current-buffer) josh/test-buffer))
  (should (= (line-number-at-pos) 3)))

(run-at-time
 20 nil
 (lambda ()
   (let ((stats (ert-run-tests-batch "^josh/")))
     (with-temp-file (or (getenv "DOOM_TEST_RESULT") "/tmp/doom-startup-result.log")
       (insert (with-current-buffer "*Messages*" (buffer-string))))
     (kill-emacs (if (zerop (ert-stats-completed-unexpected stats)) 0 1)))))
