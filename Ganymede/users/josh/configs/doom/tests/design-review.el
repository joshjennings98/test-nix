;;; design-review.el --- Offline document, Babel and MCP checks -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(add-to-list 'load-path (expand-file-name ".." (file-name-directory (or load-file-name buffer-file-name))))
(require 'design-review-mcp)
(require 'agent-shell-navigation)

(defconst josh/review-test-directory (file-name-directory (or load-file-name buffer-file-name)))
(setq design-review-program
      (or (getenv "GO_DESIGN_CHECK")
          (expand-file-name "../go-design-check/bin/go-design-check" josh/review-test-directory)))

(defmacro josh/with-review (&rest body)
  "Run BODY in a disposable Git project and real Org review."
  (declare (indent 0) (debug t))
  `(let* ((root (file-name-as-directory (make-temp-file "org-review-test-" t)))
          (path (expand-file-name "review.org" root))
          (default-directory root)
          (source (expand-file-name "app.go" root))
          (org-confirm-babel-evaluate nil)
          (org-element-use-cache nil)
          buffer)
     (unwind-protect
         (progn
           (with-temp-file (expand-file-name "go.mod" root) (insert "module example.com/review\ngo 1.26\n"))
           (with-temp-file source (insert "package review\nfunc Start() { Save() }\nfunc Save() {}\n"))
           (design-review--git root "init" "--quiet")
           (design-review--git root "add" "go.mod" "app.go")
           (design-review--git root "-c" "user.name=Review Test" "-c" "user.email=review@example.invalid" "commit" "--quiet" "-m" "baseline")
           (design-review-create path root "Fixture review")
           (setq buffer (find-file-noselect path))
           (with-current-buffer buffer ,@body))
       (dolist (candidate (buffer-list))
         (when (and (buffer-live-p candidate)
                    (with-current-buffer candidate
                      (and buffer-file-name (file-in-directory-p buffer-file-name root))))
           (with-current-buffer candidate (set-buffer-modified-p nil))
           (kill-buffer candidate)))
       (delete-directory root t))))

(defun josh/review-proposal ()
  '((declarations . [((symbol . "example.com/review.Validate") (kind . "function")
                      (change . "add") (signature . "func()"))])
    (roots . [((symbol . "example.com/review.Start")
               (children . [((symbol . "example.com/review.Validate") (relation . "direct_call") (change . "add"))
                            ((symbol . "example.com/review.Save") (relation . "direct_call"))]))])))

(ert-deftest josh/review-roundtrip-readable-graphs ()
  (let* ((graph (josh/review-proposal))
         (parsed (design-review--parse-graph "calls" (design-review--render-graph graph))))
    (should (equal (alist-get 'symbol (aref (alist-get 'declarations parsed) 0)) "example.com/review.Validate"))
    (should (equal (alist-get 'change (aref (alist-get 'children (aref (alist-get 'roots parsed) 0)) 0)) "add"))
    (should-not (alist-get 'change (aref (alist-get 'children (aref (alist-get 'roots parsed) 0)) 1)))
    (should-error (design-review--parse-graph "x" "example.A\n   example.B [direct_call]\n"))))

(ert-deftest josh/review-validated-upserts-and-babel ()
  (josh/with-review
    (goto-char (point-max))
    (insert "\nMy unsaved review note.\n")
    (design-review-mcp-set-graph `((path . ,path) (id . "calls") (graph . ,(josh/review-proposal))))
    (should (string-match-p "My unsaved review note" (buffer-string)))
    (should (equal (alist-get 'status (design-review-validate-document)) "PASS"))
    (goto-char (plist-get (design-review--block "calls") :begin))
    (let ((result (org-babel-execute-src-block)))
      (should (string-match-p "FAIL" result))
      (should (string-match-p (regexp-quote "#+RESULTS: calls") (buffer-string))))
    (design-review-mcp-set-graph `((path . ,path) (id . "calls") (graph . ,(josh/review-proposal))))
    (should (= (cl-count "calls" (plist-get (design-review--document) :blocks)
                         :key (lambda (block) (plist-get block :id)) :test #'equal) 1))
    (should-not (string-match-p (regexp-quote "#+RESULTS: calls") (buffer-string)))
    (let ((before (buffer-string)) (disk (with-temp-buffer (insert-file-contents path) (buffer-string))))
      (should-error (design-review-mcp-set-graph
                     `((path . ,path) (id . "broken") (graph . ((roots . [((symbol . "does.not.Exist"))]))))))
      (should (equal before (buffer-string)))
      (should (equal disk (with-temp-buffer (insert-file-contents path) (buffer-string)))))
    (with-temp-file source
      (insert "package review\nfunc Start() { Validate(); Save() }\nfunc Save() {}\nfunc Validate() {}\n"))
    ;; The proposal remains valid against its baseline after implementation.
    (should (equal (alist-get 'status (design-review-validate-document)) "PASS"))
    (goto-char (plist-get (design-review--block "calls") :begin))
    (should (string-match-p "Status: PASS" (design-review-check-block)))
    (should (string-match-p "design-diff:" (buffer-string)))
    (should (string-match-p "PASS" (design-review-mcp-results `((path . ,path)))))
    (should-not (string-match-p "design-review-baseline" (design-review--git root "worktree" "list")))))

(ert-deftest josh/review-cross-block-and-manual-validation ()
  (josh/with-review
    (design-review-mcp-set-graph
     `((path . ,path) (id . "declarations") (graph . ((declarations . ,(alist-get 'declarations (josh/review-proposal)))))))
    (design-review-mcp-set-graph
     `((path . ,path) (id . "calls") (graph . ((roots . ,(alist-get 'roots (josh/review-proposal)))))))
    (should (equal (alist-get 'status (design-review-validate-document)) "PASS"))
    (let ((before (buffer-string)))
      (should-error (design-review-mcp-set-graph
                     `((path . ,path) (id . "declarations") (graph . ((roots . [((symbol . "example.com/review.Start"))]))))))
      (should (equal before (buffer-string))))
    (goto-char (point-min))
    (search-forward "add function example.com/review.Validate :: func()")
    (replace-match "add function example.com/review.Validate :: func(MissingType)" t t)
    (should (equal (alist-get 'status (design-review-validate-document)) "ERROR"))))

(ert-deftest josh/review-repairs-manually-broken-graph ()
  (josh/with-review
    (design-review-mcp-set-graph `((path . ,path) (id . "calls") (graph . ,(josh/review-proposal))))
    (goto-char (point-min))
    (search-forward "  + example.com/review.Validate")
    (replace-match "   + example.com/review.Validate" t t)
    (should-error (design-review-validate-document))
    (design-review-mcp-set-graph `((path . ,path) (id . "calls") (graph . ,(josh/review-proposal))))
    (should (equal (alist-get 'status (design-review-validate-document)) "PASS"))
    (goto-char (point-max))
    (insert "\n#+name: unfinished\n#+begin_src design-graph\nexample.com/review.Start\n")
    (should-error (design-review-validate-document))))

(ert-deftest josh/review-rejects-malformed-tests-and-duplicate-ids ()
  (josh/with-review
    (should-error (design-review-mcp-set-tests
                   `((path . ,path) (id . "tests") (tests . [((name . "TestA") (description . "Behaviour") (expectations . []))]))))
    (design-review-mcp-set-tests
     `((path . ,path) (id . "tests") (tests . [((name . "TestA") (description . "Reject invalid data")
                                              (expectations . ["Error returned" "No write occurs"]))])))
    (should (string-match-p "\nTestA :: Reject invalid data\n- Error returned\n- No write occurs\n"
                            (buffer-string)))
    (should (equal (alist-get 'status (design-review-validate-document)) "PASS"))
    (should-error (design-review-mcp-set-tests
                   `((path . ,path) (id . "other-tests") (tests . [((name . "TestA") (description . "Duplicate") (expectations . ["Fails"]))]))))
    (goto-char (point-max))
    (insert "\n#+name: tests\n#+begin_src test-review\n- TestB :: something\n  - expectation\n#+end_src\n")
    (should-error (design-review-validate-document))))

(ert-deftest josh/review-test-headings-accept-flat-and-legacy-blocks ()
  (dolist (body '("TestA :: Reject invalid data\n- Error returned\n- No write occurs\n"
                  "- TestA :: Reject invalid data\n  - Error returned\n  - No write occurs\n"))
    (should (equal (design-review--test-names body) '("TestA"))))
  (should (equal (design-review--test-names
                  "TestA :: Reject input\n- Error returned\n\nTestB :: Accept input\n- File written\n")
                 '("TestA" "TestB")))
  (should-error (design-review--test-names "TestA :: Reject input\n") :type 'user-error)
  (should-error (design-review--test-names "- Error returned\n") :type 'user-error))

(ert-deftest josh/review-validation-displays-readable-results-and-parse-errors ()
  (save-window-excursion
    (unwind-protect
        (josh/with-review
          (let ((original (buffer-string)))
            (cl-letf (((symbol-function 'called-interactively-p) (lambda (_) t)))
              (design-review-validate-document))
            (should (equal (plist-get design-review--preparation :status) "RUNNING"))
            (josh/review-wait (lambda () (not (equal (plist-get design-review--preparation :status) "RUNNING"))))
            (should (equal original (buffer-string))))
          (with-current-buffer "*Design review validation*"
            (should (derived-mode-p 'special-mode))
            (should (string-match-p "Document validation: PASS" (buffer-string)))
            (should (string-match-p "does not run tests" (buffer-string))))
          (goto-char (point-max))
          (insert "\n#+name: malformed\n#+begin_src test-review\nMissing behaviour\n#+end_src\n")
          (cl-letf (((symbol-function 'called-interactively-p) (lambda (_) t)))
            (design-review-validate-document))
          (with-current-buffer "*Design review validation*"
            (should (string-match-p "Document validation: ERROR" (buffer-string)))
            (should (string-match-p "TestName :: behaviour" (buffer-string)))
            (should-not (string-match-p "Document validation: PASS" (buffer-string))))
          ;; Synchronous authoring validation must still reject invalid input.
          (should-error (design-review-validate-document) :type 'user-error))
      (when (get-buffer "*Design review validation*")
        (kill-buffer "*Design review validation*")))))

(ert-deftest josh/review-background-check-validates-once-and-keeps-ui-responsive ()
  (josh/with-review
    (design-review-mcp-set-graph `((path . ,path) (id . "calls") (graph . ,(josh/review-proposal))))
    (let* ((calls (expand-file-name "checker-calls" root))
           (wrapper (expand-file-name "checker-wrapper" root))
           (program design-review-program)
           (heartbeats 0) queued timer)
      (with-temp-file wrapper
        (insert (format "#!%s\nprintf '%%s\\n' \"$1\" >> %s\nexec %s \"$@\"\n"
                        (executable-find "sh") (shell-quote-argument calls) (shell-quote-argument program))))
      (set-file-modes wrapper #o700)
      (let ((design-review-program wrapper))
        (cl-letf (((symbol-function 'design-review--command)
                   (lambda (&rest _) (ert-fail "Synchronous subprocess on the UI thread")))
                  ((symbol-function 'design-review--start-review)
                   (lambda (block document validated)
                     (should (equal (alist-get 'status validated) "PASS"))
                     (should (stringp (design-review--brief block document)))
                     (push (plist-get block :id) queued)
                     "RUNNING: fixture review queued")))
          (unwind-protect
              (progn
                (setq timer (run-at-time 0 0.01 (lambda () (cl-incf heartbeats))))
                (should (equal (alist-get 'status (design-review--json (design-review-check-document))) "RUNNING"))
                (should-not queued)
                (let ((progress (design-review--json (design-review-mcp-results `((path . ,path))))))
                  (should (equal (alist-get 'status (alist-get 'preparation progress)) "RUNNING"))
                  (should (eq (alist-get 'running (aref (alist-get 'results progress) 0)) t)))
                (should-error (design-review--prepare "check") :type 'user-error)
                (josh/review-wait (lambda () (not (equal (plist-get design-review--preparation :status) "RUNNING"))))
                (should (equal (plist-get design-review--preparation :status) "PASS"))
                (should (> heartbeats 0))
                (should (= (length queued) 2))
                (should-not (member "test-alignment" queued))
                (should (string-match-p "BLOCKED: test review not run" (buffer-string)))
                (should (string-match-p "Status: FAIL" (buffer-string))))
            (when timer (cancel-timer timer)))))
      (should (equal (with-temp-buffer (insert-file-contents calls) (split-string (buffer-string) "\n" t))
                     '("validate" "check")))
      (should-not (string-match-p "design-review-baseline" (design-review--git root "worktree" "list"))))))

(ert-deftest josh/review-background-validation-discards-edited-plans ()
  (save-window-excursion
    (josh/with-review
      (should (equal (alist-get 'status (design-review--json (design-review-mcp-validate `((path . ,path))))) "RUNNING"))
      (goto-char (point-max))
      (insert "\nA new decision.\n")
      (josh/review-wait (lambda () (not (equal (plist-get design-review--preparation :status) "RUNNING"))))
      (should (equal (plist-get design-review--preparation :status) "STALE"))
      (should-not (string-match-p "#+RESULTS:" (buffer-string))))))

(ert-deftest josh/review-background-worker-errors-clean-up-baseline ()
  (save-window-excursion
    (josh/with-review
      (let ((design-review-program "/does-not-exist/go-design-check"))
        (design-review--prepare "validate")
        (josh/review-wait (lambda () (not (equal (plist-get design-review--preparation :status) "RUNNING")))))
      (should (equal (plist-get design-review--preparation :status) "ERROR"))
      (should-not (string-match-p "design-review-baseline" (design-review--git root "worktree" "list"))))))

(ert-deftest josh/review-registers-tools-with-schema ()
  (require 'mcp-server)
  (let (tools)
    (cl-letf (((symbol-function 'mcp-server-register-tool) (lambda (tool) (push tool tools))))
      (let ((names (design-review-register-tools)))
        (should (memq 'validate-document names))
        (should (memq 'review-set-graph names))
        (should (= (length tools) 8))))))

(ert-deftest josh/review-mcp-wire-schema-and-call ()
  (require 'mcp-server)
  (let ((mcp-server-emacs-tools-enabled 'all))
    (design-review-register-tools)
    (let* ((encoded (mcp-server-transport--format-json-rpc `((tools . ,(mcp-server-tools-list)))))
           (decoded (design-review--json encoded))
           (graph-tool (seq-find (lambda (tool) (equal (alist-get 'name tool) "review-set-graph"))
                                 (alist-get 'tools decoded))))
      (should (eq (alist-get 'additionalProperties (alist-get 'inputSchema graph-tool)) :json-false)))
    (josh/with-review
      (let* ((args (alist-get 'arguments
                              (mcp-server-transport--parse-json-rpc
                               (json-encode `((arguments . ((path . ,path) (id . "calls") (graph . ,(josh/review-proposal)))))))))
             (response (mcp-server-tools-call "review-set-graph" args)))
        (should (equal (alist-get 'status (design-review--json (alist-get 'text (aref response 0)))) "updated"))))))

(ert-deftest josh/review-late-answer-preserves-edited-block ()
  (require 'agent-shell)
  (josh/with-review
    (let* ((key (cons (current-buffer) "changes-outside-plan"))
           (block (design-review--block "changes-outside-plan"))
           (run (list :body (plist-get block :body) :language "change-review" :shell nil :subscription nil)))
      (puthash key run design-review--runs)
      (goto-char (plist-get block :begin))
      (search-forward "Review all changes")
      (replace-match "Review all important changes" t t)
      (let ((before (buffer-string)))
        (design-review--finish key run "Old answer")
        (should (equal before (buffer-string))))
      (should-not (gethash key design-review--runs)))))

(ert-deftest josh/review-navigation-connection-enables-review-tools ()
  (require 'mcp-server)
  (let ((mcp-server-running t) mcp-server-emacs-tools-enabled)
    (cl-letf (((symbol-function 'mcp-server-register-tool) #'ignore)
              ((symbol-function 'mcp-server-get-socket-path) (lambda () "/tmp/review-test.sock")))
      (should (equal (agent-shell-navigation-connect) '("-" "UNIX-CONNECT:/tmp/review-test.sock")))
      (should (memq 'open_file mcp-server-emacs-tools-enabled))
      (should (memq 'validate-document mcp-server-emacs-tools-enabled)))))

(ert-deftest josh/review-diff-link-opens-real-magit-hunk ()
  (josh/with-review
    (require 'magit)
    (with-temp-file source (insert "package review\nfunc Start() {}\nfunc Save() {}\n"))
    (save-window-excursion
      (design-review-follow-diff
       (base64-encode-string (json-encode `((root . ,root) (baseline . ,(plist-get (design-review--document) :baseline))
                                           (file . "app.go") (line . 2))) t) nil)
      (should (derived-mode-p 'magit-diff-mode))
      (should (string-match-p "@@" (buffer-substring-no-properties (line-beginning-position) (line-end-position)))))))

(ert-deftest josh/review-diff-link-shows-untracked-file-without-staging ()
  (josh/with-review
    (require 'magit)
    (let ((new (expand-file-name "commands.go" root))
          (baseline (plist-get (design-review--document) :baseline)))
      (with-temp-file new (insert "package review\nfunc Run() {}\n"))
      (save-window-excursion
        (design-review-follow-diff
         (base64-encode-string (json-encode `((root . ,root) (baseline . ,baseline)
                                             (file . "commands.go") (line . 2))) t) nil)
        (should (derived-mode-p 'magit-diff-mode))
        (should (string-match-p "\\+func Run" (buffer-string)))
        (should (string-match-p "@@" (buffer-substring-no-properties (line-beginning-position) (line-end-position)))))
      (should (string-match-p "?? commands.go" (design-review--git root "status" "--short")))
      (should (string-empty-p (design-review--git root "diff" "--cached" "--name-only"))))))

(ert-deftest josh/review-diff-link-opens-unchanged-source ()
  (josh/with-review
    (let ((baseline (plist-get (design-review--document) :baseline)))
      (save-window-excursion
        (design-review-follow-diff
         (base64-encode-string (json-encode `((root . ,root) (baseline . ,baseline)
                                             (file . "app.go") (line . 2))) t) nil)
        (should (equal buffer-file-name source))
        (should (= (line-number-at-pos) 2))))))

(ert-deftest josh/review-diff-link-handles-project-under-repository-root ()
  (josh/with-review
    (let* ((nested (expand-file-name "nested/" root))
           (file (expand-file-name "file.go" nested)))
      (make-directory nested)
      (with-temp-file file (insert "package nested\nfunc Run() {}\n"))
      (design-review--git root "add" "nested/file.go")
      (design-review--git root "-c" "user.name=Review Test" "-c" "user.email=review@example.invalid" "commit" "--quiet" "-m" "nested file")
      (let ((baseline (design-review--git root "rev-parse" "HEAD")))
        (with-temp-file file (insert "package nested\nfunc Run() { println(1) }\n"))
        (save-window-excursion
          (design-review-follow-diff
           (base64-encode-string (json-encode `((root . ,nested) (baseline . ,baseline)
                                               (file . "file.go") (line . 2))) t) nil)
          (should (derived-mode-p 'magit-diff-mode))
          (should (string-match-p "\\+func Run() { println(1) }" (buffer-string))))))))

(defun josh/review-wait (predicate)
  (let ((deadline (+ (float-time) 10)))
    (while (and (not (funcall predicate)) (< (float-time) deadline)) (accept-process-output nil 0.03))
    (should (funcall predicate))))

(ert-deftest josh/review-shared-agent-results ()
  (require 'agent-shell)
  (josh/with-review
    (design-review-set-context path "#+name: sequence\n#+begin_src mermaid\ngraph TD; A-->B\n#+end_src")
    (let* ((python (getenv "AGENT_SHELL_TEST_PYTHON"))
           (fixture (expand-file-name "mock-acp.py" josh/review-test-directory))
           (shell-maker-root-path (expand-file-name ".git/review-fixture-state/" root))
           (agent-shell-dot-subdir-function (lambda (subdir) (expand-file-name subdir shell-maker-root-path)))
           (agent-shell-transcript-file-path-function nil)
           (agent-shell-show-welcome-message nil)
           (agent-shell-show-busy-indicator nil)
           (agent-shell-inhibit-system-sleep nil)
           (shell-maker-prompt-before-killing-buffer nil)
           (agent-shell-highlight-blocks nil)
           (agent-shell-prefer-viewport-interaction nil)
           shells
           (design-review-agent-config
            (agent-shell-make-agent-config
             :identifier 'review-fixture :mode-line-name "Review fixture" :buffer-name "Review fixture"
             :shell-prompt "Review> " :shell-prompt-regexp "Review> "
             :client-maker (lambda (buffer)
                             (push buffer shells)
                             (acp-make-client :command python :command-params (list fixture) :context-buffer buffer)))))
      (should python)
      (unwind-protect
          (progn
            (design-review-mcp-set-tests
             `((path . ,path) (id . "tests") (tests . [((name . "TestExample") (description . "REVIEW_JSON")
                                                      (expectations . ["Supports the stated behaviour"]))])))
            (should (string-match-p "RUNNING" (design-review-mcp-check `((path . ,path)))))
            (josh/review-wait (lambda () (not (equal (plist-get design-review--preparation :status) "RUNNING"))))
            (should (equal (plist-get design-review--preparation :status) "PASS"))
            (let ((document-buffer (current-buffer)))
              (josh/review-wait
               (lambda () (seq-every-p
                           (lambda (id) (not (gethash (cons document-buffer id) design-review--runs)))
                           '("tests" "test-alignment" "planned-implementation" "diagram-alignment" "changes-outside-plan")))))
            (should (= (length (delete-dups shells)) 1))
            (dolist (id '("tests" "planned-implementation" "diagram-alignment" "changes-outside-plan"))
              (goto-char (plist-get (design-review--block id) :begin))
              (let ((result (org-babel-where-is-src-block-result)))
                (should result)
                (goto-char result)
                (should (string-match-p "Fixture assessment"
                                        (buffer-substring-no-properties result (org-babel-result-end))))))
            (should (string-match-p "Fixture assessment" (buffer-string)))
            (should (string-match-p "Test execution: not run" (buffer-string)))
            (should (string-match-p "design-session:" (buffer-string))))
        (dolist (shell shells)
          (when (buffer-live-p shell)
            (with-current-buffer shell (setq-local kill-buffer-query-functions nil))
            (kill-buffer shell)))))))

(ert-deftest josh/review-test-submission-requires-feature-pass ()
  (require 'agent-shell)
  (dolist (case '(("PASS" "PASS" t) ("FAIL" "FAIL" nil) ("UNKNOWN" "UNKNOWN" nil)
                  ("REVIEW" "REVIEW" nil) (nil "PASS" nil) ("PASS" "REVIEW" nil)
                  ("malformed" "PASS" nil) ("cancelled" "PASS" nil) ("stale" "PASS" nil)
                  ("graph-unknown" "PASS" nil) ("graph-fail" "PASS" nil) ("plan-edited" "PASS" nil)))
    (josh/with-review
      (let* ((gate (list :implementations (list (cons "planned-implementation" "PENDING"))))
             (document (append (list :test-gate gate :path path :fingerprint nil
                                     :authored-text (design-review--authored-text)) (design-review--document)))
             (shell (generate-new-buffer " *review-gate-fixture*"))
             (implementation (list :key (cons (current-buffer) "planned-implementation") :shell shell
                                   :document document :language "implementation-review" :outcome "UNKNOWN" :text nil
                                   :body (plist-get (design-review--block "planned-implementation") :body)))
             (test (list :key (cons (current-buffer) "test-alignment") :shell shell :document document
                         :language "test-review" :submitted nil :prompt "Assess tests"
                         :body (plist-get (design-review--block "test-alignment") :body)))
             sent)
        (setf (plist-get document :fingerprint) (design-review--source-fingerprint document))
        (unwind-protect
            (cl-letf (((symbol-function 'agent-shell-initialized-p) (lambda (&rest _) t))
                      ((symbol-function 'agent-shell-insert) (lambda (&rest _) (setq sent t)))
                      ((symbol-function 'design-review--advance) #'ignore))
              (puthash (plist-get implementation :key) implementation design-review--runs)
              (puthash (plist-get test :key) test design-review--runs)
              (design-review--submit (plist-get test :key) test)
              (should-not sent)
              (should (gethash (plist-get test :key) design-review--runs))
              (setf (plist-get implementation :text)
                    (if (equal (car case) "malformed") "not JSON"
                      (json-encode `((status . ,(if (member (car case) '("stale" "graph-unknown" "graph-fail" "plan-edited")) "PASS" (car case)))
                                     (summary . "Fixture") (test_execution . "not run")
                                     (findings . [((status . ,(cadr case)) (message . "Evidence"))])))))
              (let ((text (if (equal (car case) "cancelled") "UNKNOWN: cancelled"
                            (design-review--review-result implementation))))
                (when (equal (car case) "stale")
                  (with-temp-file source (insert "package review\nfunc Start() {}\nfunc Save() {}\n")))
                (when (equal (car case) "plan-edited")
                  (goto-char (point-max))
                  (insert "\nChanged feature requirement.\n"))
                (design-review--finish (plist-get implementation :key) implementation text))
              (when (member (car case) '("graph-unknown" "graph-fail"))
                (setf (plist-get (plist-get document :test-gate) :graph-blocker) "Graph checks did not pass."))
              (design-review--submit (plist-get test :key) test)
              (should (eq (not (null sent)) (nth 2 case)))
              (unless sent (should (string-match-p "BLOCKED: test review not run" (buffer-string)))))
          (remhash (plist-get implementation :key) design-review--runs)
          (remhash (plist-get test :key) design-review--runs)
          (kill-buffer shell))))))

(ert-deftest josh/review-single-test-check-includes-implementation-first ()
  (josh/with-review
    (let (queued)
      (cl-letf (((symbol-function 'design-review--start-review)
                 (lambda (block document _validated)
                   (should (plist-get document :test-gate))
                   (push (plist-get block :language) queued)
                   "WAITING: fixture")))
        (design-review--prepare "check" "test-alignment")
        (josh/review-wait (lambda () (not (equal (plist-get design-review--preparation :status) "RUNNING")))))
      (should (equal (nreverse queued) '("implementation-review" "test-review"))))))

(ert-deftest josh/review-default-codex-astra ()
  (let ((config (design-review--default-agent-config)))
    (should (eq (alist-get :identifier config) 'codex))
    (should (equal (funcall (alist-get :default-model-id config)) "gpt-6-astra"))))

(ert-deftest josh/review-context-and-explicit-diagrams ()
  (josh/with-review
    (goto-char (point-max))
    (insert "\n* User notes\nPreserve this unsaved note.\n")
    (let ((context "** Agreed interaction\n#+name: save-sequence\n#+begin_src mermaid :file save.svg\nsequenceDiagram\n    Handler->>Store: Save\n#+end_src\n"))
      (design-review-mcp-set-context `((path . ,path) (body . ,context)))
      (design-review-mcp-set-context `((path . ,path) (body . ,context)))
      (should (string-match-p "Preserve this unsaved note" (buffer-string)))
      (should (equal (design-review--diagrams) '("save-sequence")))
      (let ((document (design-review--document)))
        (dolist (id '("test-alignment" "planned-implementation" "diagram-alignment" "changes-outside-plan"))
          (let ((brief (design-review--brief (design-review--block id) document)))
            (should (string-match-p "Handler->>Store: Save" brief))
            (should (eq (not (null (string-match-p "Explicit diagram review:" brief)))
                        (equal id "diagram-alignment")))))
        (goto-char (point-max))
        (save-restriction
          (narrow-to-region (line-beginning-position) (point-max))
          (should (string-match-p "Handler->>Store: Save" (design-review--authored-text))))
        (let* ((reply '((summary . "Done") (findings . []) (test_execution . "not run")))
               (run (list :shell (current-buffer) :document document :diagrams '("save-sequence")
                          :text (json-encode reply))))
          (should (string-match-p "UNKNOWN \\[save-sequence\\]" (design-review--review-result run)))
          (setf (alist-get 'findings reply)
                [((diagram_id . "save-sequence") (status . "FAIL") (message . "Save happens before validation"))])
          (setf (plist-get run :text) (json-encode reply))
          (should (string-match-p "FAIL \\[save-sequence\\]" (design-review--review-result run)))
          (should-not (string-match-p "omitted" (design-review--review-result run)))))
      (let ((before (buffer-string)))
        (should-error (design-review-set-context path "* A top-level heading") :type 'user-error)
        (should (equal before (buffer-string)))))))

(ert-deftest josh/review-uncertainty-context-and-agent-assessment ()
  (josh/with-review
    (let* ((finding '((id . "rule") (status . "UNKNOWN") (message . "Unresolved dispatch")
                     (review . ((kind . "review_needed")
                                (requirement . ((kind . "forbid_call") (from . "example.Run") (to . "example.Save")))
                                (guidance . ["Inspect receiver assignments."])))
                     (gaps . [((reason . "interface dispatch") (expression . "err.Error()")
                               (location . ((file . "app.go") (line . 2))))])))
           (document (append (list :path path :authored-text (design-review--authored-text)
                                   :checks (vector `((id . "calls") (result . ((findings . ,(vector finding)))))))
                             (design-review--document)))
           (answer '((key . "calls/rule") (assessment . "checked_no_concern")
                     (rationale . "Inspected assignments; target cannot reach this call.")
                     (citations . [((file . "app.go") (line . 2))])))
           (run (list :shell (current-buffer) :language "implementation-review" :document document))
           (reply `((uncertainty_assessments . ,(vector answer)))))
      (setf (plist-get document :fingerprint) (design-review--source-fingerprint document))
      (setf (plist-get run :document) document)
      (let ((brief (design-review--brief (design-review--block "planned-implementation") document))
            (text (string-join (design-review--format-assessments run reply) "\n")))
        (should (string-match-p "calls/rule" brief))
        (should (string-match-p "uncertainty_assessments" brief))
        (should (string-match-p "Analysis: UNKNOWN" text))
        (should (string-match-p "Checked — no concern found" text))
        (should (string-match-p "err.Error()" text))
        (should (string-match-p "design-source:" text))
        (should (string-match-p "Evidence freshness: CURRENT" text)))
      (dolist (citations '([] [((file . "../outside.go") (line . 1))] [((file . "app.go") (line . 900))] [42]))
        (setf (alist-get 'citations answer) citations)
        (should (string-match-p "missing or invalid" (string-join (design-review--format-assessments run reply) "\n"))))
      (setf (alist-get 'citations answer) [((file . "app.go") (line . 2))])
      (should (string-match-p "missing or invalid" (string-join (design-review--format-assessments run nil) "\n")))
      (should (string-match-p "missing or invalid"
                              (string-join (design-review--format-assessments run `((uncertainty_assessments . ,(vector answer answer)))) "\n")))
      (setf (alist-get 'kind (alist-get 'review finding)) "analysis_blocked")
      (should (string-match-p "missing or invalid" (string-join (design-review--format-assessments run reply) "\n")))
      (setf (alist-get 'kind (alist-get 'review finding)) "review_needed")
      (with-temp-file source (insert "package review\nfunc Start() {}\nfunc Save() {}\n"))
      (let ((text (string-join (design-review--format-assessments run reply) "\n")))
        (should (string-match-p "Evidence freshness: STALE" text))
        (should-not (string-match-p "Checked — no concern found" text))))))

(ert-deftest josh/review-implementation-block-includes-fresh-graph-evidence ()
  (josh/with-review
    (design-review-mcp-set-graph
     `((path . ,path) (id . "calls")
       (graph . ((roots . [((symbol . "example.com/review.Start")
                            (children . [((symbol . "example.com/review.Save") (relation . "reaches") (change . "remove"))]))])))))
    (with-temp-file source
      (insert "package review\nfunc Start() { var err error; _ = err.Error() }\nfunc Save() {}\n"))
    (let (captured)
      (cl-letf (((symbol-function 'design-review--start-review)
                 (lambda (_block document _validated)
                   (setq captured document)
                   "RUNNING: fixture")))
        (design-review--prepare "check" "planned-implementation")
        (josh/review-wait (lambda () (not (equal (plist-get design-review--preparation :status) "RUNNING")))))
      (should captured)
      (should (equal (plist-get captured :fingerprint) (design-review--source-fingerprint captured)))
      (let* ((items (design-review--uncertainties captured))
             (finding (alist-get 'finding (car items))))
        (should (= (length items) 1))
        (should (equal (alist-get 'kind (alist-get 'review finding)) "review_needed"))
        (should (seq-some (lambda (gap) (equal (alist-get 'expression gap) "err.Error()")) (alist-get 'gaps finding)))
        (should (string-match-p "err.Error" (design-review--brief (design-review--block "planned-implementation") captured)))))))

(ert-deftest josh/review-persisted-evidence-freshness ()
  (josh/with-review
    (let* ((document (append (list :path path :authored-text (design-review--authored-text)) (design-review--document))))
      (setf (plist-get document :fingerprint) (design-review--source-fingerprint document))
      (goto-char (plist-get (design-review--block "planned-implementation") :begin))
      (org-babel-insert-result (concat "Evidence freshness: CURRENT " (design-review--evidence-link document)) '("drawer" "replace"))
      (design-review-refresh-evidence)
      (should (string-match-p "Evidence freshness: CURRENT" (buffer-string)))
      (with-temp-file source (insert "package review\nfunc Start() {}\nfunc Save() {}\n"))
      (design-review-refresh-evidence)
      (should (string-match-p "Evidence freshness: STALE" (buffer-string)))
      (should (string-match-p "STALE" (design-review-mcp-results `((path . ,path))))))))

(ert-deftest josh/review-role-briefs ()
  (josh/with-review
    (let ((document (design-review--document)))
      (should (equal (mapcar (lambda (block) (plist-get block :language))
                            (plist-get document :blocks))
                     '("implementation-review" "test-review" "change-review")))
      (dolist (entry '(("test-alignment" . "discover added or changed tests")
                       ("planned-implementation" . "all planned work")
                       ("changes-outside-plan" . "undermines or otherwise affects")))
        (should (string-match-p (cdr entry)
                                (design-review--brief (design-review--block (car entry)) document)))))))

(ert-deftest josh/review-adjacent-context-and-separate-test-results ()
  (josh/with-review
    (dolist (entry '(("test-alignment" . "TestReject") ("test-success" . "TestSuccess")))
      (design-review-mcp-set-tests
       `((path . ,path) (id . ,(car entry))
         (tests . [((name . ,(cdr entry)) (description . "Check the stated behaviour")
                    (expectations . ["Preserve stored data"]))]))))
    (dolist (id '("test-alignment" "test-success"))
      (goto-char (plist-get (design-review--block id) :begin))
      (org-babel-insert-result (format "Recorded result for %s" id) '("drawer" "replace")))
    (design-review-mcp-set-context
     `((path . ,path) (before . "test-success") (body . "A valid request must reach storage.")))
    (design-review-mcp-set-context
     `((path . ,path) (before . "test-alignment") (body . "Reject invalid input before writing.")))
    (design-review-mcp-set-context
     `((path . ,path) (before . "test-alignment") (body . "Invalid input must not change stored data.")))
    (should-not (string-match-p "Reject invalid input before writing" (buffer-string)))
    (should (string-match-p "Invalid input must not change stored data" (buffer-string)))
    (should (string-match-p "A valid request must reach storage" (buffer-string)))
    (dolist (id '("test-alignment" "test-success"))
      (goto-char (plist-get (design-review--block id) :begin))
      (should (org-babel-where-is-src-block-result))
      (save-excursion
        (org-back-to-heading t)
        (should (equal (org-get-heading t t t t) (format "Notes for %s" id)))))
    (design-review-mcp-set-tests
     `((path . ,path) (id . "test-alignment")
       (tests . [((name . "TestReject") (description . "Reject invalid input")
                  (expectations . ["Do not write files"]))])))
    (should-not (string-match-p "Recorded result for test-alignment" (buffer-string)))
    (should (string-match-p "Recorded result for test-success" (buffer-string)))
    (should (string-match-p "Invalid input must not change stored data" (buffer-string)))
    (let ((original (buffer-string)))
      (should-error (design-review-set-context path "Unknown block" "missing") :type 'user-error)
      (should-error (design-review-set-context path "** Unexpected heading" "test-alignment") :type 'user-error)
      (should (equal original (buffer-string))))))

(ert-deftest josh/review-diagrams-are-optional ()
  (josh/with-review
    (should-not (design-review--block "diagram-alignment"))
    (design-review-set-context path "Keep this refactor small.")
    (should-not (design-review--block "diagram-alignment"))
    (goto-char (point-min))
    (re-search-forward "^\\* Context and decisions")
    (should (re-search-forward "^\\* Design and changes" nil t))
    (design-review-set-context path "#+name: flow\n#+begin_src mermaid\ngraph TD; A-->B\n#+end_src"
                               "planned-implementation")
    (should (design-review--block "diagram-alignment"))
    (design-review-set-context path "No diagram is needed for this change." "planned-implementation")
    (should-not (design-review--block "diagram-alignment"))
    (should-not (string-match-p "^\\* Diagram alignment$" (buffer-string)))
    (should (equal (alist-get 'status (design-review-validate-document)) "PASS"))))

(ert-deftest josh/review-malformed-response-advances-queue ()
  (require 'agent-shell)
  (josh/with-review
    (design-review-set-context path "#+name: sequence\n#+begin_src mermaid\ngraph TD; A-->B\n#+end_src")
    (dolist (text '("{\"summary\":\"done\",\"findings\":[42],\"test_execution\":\"not run\"}"
                    "{\"summary\":\"done\",\"findings\":[{}],\"test_execution\":\"not run\"}"
                    "{\"summary\":\"done\",\"findings\":42,\"test_execution\":\"not run\"}"))
      (let* ((shell (generate-new-buffer " *review-malformed*"))
             (block (design-review--block "diagram-alignment"))
             (key (cons (current-buffer) "diagram-alignment"))
             (run (list :key key :shell shell :document (design-review--document)
                        :body (plist-get block :body) :language "diagram-review"
                        :diagrams '("sequence") :submitted t :text text))
             (next (list :key (cons (current-buffer) "planned-implementation") :subscription nil))
             advanced)
        (unwind-protect
            (cl-letf (((symbol-function 'agent-shell-subscribe-to) (lambda (&rest _) 'fixture))
                      ((symbol-function 'design-review--submit)
                       (lambda (_key queued) (setq advanced (eq queued next)))))
              (puthash key run design-review--runs)
              (with-current-buffer shell (setq design-review--queue (list run next)))
              (design-review--agent-event key run '((:event . turn-complete) (:data . ((:stop-reason . "end_turn")))))
              (should-not (gethash key design-review--runs))
              (should (string-match-p "UNKNOWN" (buffer-string)))
              (josh/review-wait (lambda () advanced))
              (with-current-buffer shell (should (equal design-review--queue (list next)))))
          (remhash key design-review--runs)
          (kill-buffer shell))))))
