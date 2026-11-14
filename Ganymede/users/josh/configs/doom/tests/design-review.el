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
    (should (equal (alist-get 'status (design-review-validate-document)) "PASS"))
    (should-error (design-review-mcp-set-tests
                   `((path . ,path) (id . "other-tests") (tests . [((name . "TestA") (description . "Duplicate") (expectations . ["Fails"]))]))))
    (goto-char (point-max))
    (insert "\n#+name: tests\n#+begin_src test-review\n- TestB :: something\n  - expectation\n#+end_src\n")
    (should-error (design-review-validate-document))))

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

(defun josh/review-wait (predicate)
  (let ((deadline (+ (float-time) 10)))
    (while (and (not (funcall predicate)) (< (float-time) deadline)) (accept-process-output nil 0.03))
    (should (funcall predicate))))

(ert-deftest josh/review-shared-agent-results ()
  (require 'agent-shell)
  (josh/with-review
    (let* ((python (getenv "AGENT_SHELL_TEST_PYTHON"))
           (fixture (expand-file-name "mock-acp.py" josh/review-test-directory))
           (shell-maker-root-path root)
           (agent-shell-transcript-file-path-function nil)
           (agent-shell-show-welcome-message nil)
           (agent-shell-show-busy-indicator nil)
           (agent-shell-inhibit-system-sleep nil)
           (shell-maker-prompt-before-killing-buffer nil)
           (agent-shell-highlight-blocks nil)
           (agent-shell-prefer-viewport-interaction nil)
           (design-review-agent-config
            (agent-shell-make-agent-config
             :identifier 'review-fixture :mode-line-name "Review fixture" :buffer-name "Review fixture"
             :shell-prompt "Review> " :shell-prompt-regexp "Review> "
             :client-maker (lambda (buffer)
                             (acp-make-client :command python :command-params (list fixture) :context-buffer buffer))))
           shells)
      (should python)
      (unwind-protect
          (progn
            (design-review-mcp-set-tests
             `((path . ,path) (id . "tests") (tests . [((name . "TestExample") (description . "REVIEW_JSON")
                                                      (expectations . ["Supports the stated behaviour"]))])))
            (dolist (id '("tests" "planned-implementation" "diagram-alignment" "changes-outside-plan"))
              (goto-char (plist-get (design-review--block id) :begin))
              (should (string-match-p "RUNNING" (design-review-check-block)))
              (let ((run (gethash (cons (current-buffer) id) design-review--runs)))
                (push (plist-get run :shell) shells)))
            (let ((document-buffer (current-buffer)))
              (josh/review-wait
               (lambda () (seq-every-p
                           (lambda (id) (not (gethash (cons document-buffer id) design-review--runs)))
                           '("tests" "planned-implementation" "diagram-alignment" "changes-outside-plan")))))
            (should (eq (car shells) (cadr shells)))
            (should (eq (car shells) (caddr shells)))
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

(ert-deftest josh/review-role-briefs ()
  (josh/with-review
    (let ((document (design-review--document)))
      (should (equal (mapcar (lambda (block) (plist-get block :language))
                            (plist-get document :blocks))
                     '("implementation-review" "test-review" "diagram-review" "change-review")))
      (dolist (entry '(("test-alignment" . "discover added or changed tests")
                       ("planned-implementation" . "all planned work")
                       ("changes-outside-plan" . "undermines or otherwise affects")))
        (should (string-match-p (cdr entry)
                                (design-review--brief (design-review--block (car entry)) document)))))))

(ert-deftest josh/review-malformed-response-advances-queue ()
  (require 'agent-shell)
  (josh/with-review
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
