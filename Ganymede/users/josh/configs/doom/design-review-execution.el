;;; design-review-execution.el --- Babel checks and independent reviews -*- lexical-binding: t; -*-

(require 'design-review)
(require 'design-review-evidence)

(defvar agent-shell--state)
(declare-function agent-shell--new-shell "agent-shell")
(declare-function agent-shell-subscribe-to "agent-shell")
(declare-function agent-shell-unsubscribe "agent-shell")
(declare-function agent-shell-initialized-p "agent-shell")
(declare-function agent-shell-insert "agent-shell")
(declare-function agent-shell-openai-make-codex-config "agent-shell-openai")
(declare-function magit-diff-range "magit-diff")
(declare-function magit-diff-setup-buffer "magit-diff")
(declare-function magit-file-tracked-p "magit-git")
(declare-function magit-git-success "magit-git")
(declare-function magit-current-section "magit-section")

(defcustom design-review-agent-config nil
  "Review configuration override.  Nil uses Codex with Astra."
  :type '(choice (const nil) sexp) :group 'design-review)

(defvar-local design-review--session nil
  "Review conversations indexed by block ID for this document.")

(defvar-local design-review--queue nil
  "Review runs queued in this dedicated Agent Shell buffer.")

(defun design-review--default-agent-config ()
  "Return a Codex configuration with Astra selected explicitly."
  (require 'agent-shell-openai)
  (let ((config (agent-shell-openai-make-codex-config)))
    (setf (alist-get :default-model-id config) (lambda () "gpt-6-astra"))
    config))

(defun design-review--review-task (language)
  "Return the assessment obligations for LANGUAGE."
  (pcase language
    ("plan-review"
     "Assess ONLY the planned changes in this assigned box against actual source and configuration, using only this approved box as the requirements. Inspect relevant source and dependencies, but do not read other plan boxes or the backing document to expand the assignment. If a required contract is missing, report UNKNOWN. There is no prescribed syntax or language: interpret the author's component tree, call-tree diff, interfaces, pseudocode, file tree, configuration, diagram or prose on its own terms. Identify each proposed addition, modification, removal and preserved behaviour; give an explicit assessment and source evidence for each, including cross-language boundaries relevant to this box. Distinguish existing behaviour and alternatives from agreed intent. Do not require literal call edges or identical notation when the implementation fulfils the intent. Report discrepancies, omissions and insufficient evidence; never silently skip an item or revise the plan to fit the code. General implementation concerns, other plan boxes, test quality and out-of-plan changes belong to their respective reviewers. Return a top-level status PASS, FAIL, REVIEW or UNKNOWN. PASS requires evidence for all planned changes; missing or uncertain coverage is UNKNOWN. Also return a required top-level comparison string containing a multiline Show Me view of the differences between the agreed plan and observed implementation. Choose a representation suited to this box: an annotated call/component tree, pseudocode or signature diff, file/configuration comparison, or labelled planned/observed views. Keep enough matching context to locate each difference. Clearly distinguish planned-but-missing work, actual additions or deviations, equivalent implementations and unknowns; explain your notation. This compares the PLAN with CURRENT IMPLEMENTATION, not baseline code with current code. Show relevant source locations and connect differences to the findings. If it matches, show the checked flow or structure and explicitly say no differences were found; do not invent a diff. Preserve indentation and line breaks in the JSON string. Use plain text, not Org source delimiters or Markdown fences. A verdict or prose summary alone is insufficient.")
    ("test-review"
     "Assess the tests named in this block, using the full document as context. Explain whether their assertions establish the stated behaviours and identify missing coverage for those behaviours. Do not repeat assessments owned by other test blocks. If this block has no named tests, discover added or changed tests, including untracked tests, and assess their alignment. Distinguish test execution from alignment.")
    ("implementation-review"
     "Assess overall implementation behaviour, integration between planned parts, edge cases and document-wide decisions using the full plan. Focused plan-review boxes own their individual planned changes; use them as context without repeating their assessments. Do not assess test quality or take over out-of-plan review. Return a top-level status PASS, FAIL, REVIEW or UNKNOWN. PASS means no concern or unresolved question; every finding must then be PASS. Test reviews wait for all non-test assessments to pass.")
    ("diagram-review"
     "Review conformance to each authored diagram, using the full plan as context. Own the diagram assessments: check interactions, order, states, branches, error paths and side effects where depicted. Give evidence for matches, mismatches and uncertainty. Do not take over test alignment, general implementation review or out-of-plan change review.")
    ("change-review"
     "Surface all changes outside the plan, including extra responsibilities inside planned functions, new helpers, tests and configuration files. Explain whether each additional change undermines or otherwise affects planned behaviour. Additional work is not automatically a defect. Inspect the full repository diff and untracked files.")))

(defvar design-review--runs (make-hash-table :test #'equal)
  "Active reviews keyed by document buffer and block ID.")

(defun design-review--block (id)
  "Return the current review block named ID."
  (seq-find (lambda (block) (equal id (plist-get block :id)))
            (plist-get (design-review--document) :blocks)))

(defun design-review--block-at-point ()
  "Return the named review source block at point."
  (let* ((info (org-babel-get-src-block-info 'light))
         (id (nth 4 info)))
    (unless (and info (member (car info) (cons "design-graph" design-review--languages)))
      (user-error "Point is not in a review block"))
    (or (design-review--block id) (user-error "Review block must have a unique name"))))

(defun design-review--stamp ()
  "Return an explicit time label without making a freshness claim."
  (format-time-string "Checked: %Y-%m-%d %H:%M:%S %z"))

(defun design-review--link (kind document file line label)
  "Build an Org KIND link carrying a source location and baseline."
  (format "[[%s:%s][%s]]" kind
          (base64-encode-string
           (encode-coding-string
            (json-encode `((root . ,(plist-get document :root)) (baseline . ,(plist-get document :baseline))
                           (file . ,file) (line . ,(or line 1)))) 'utf-8) t)
          (replace-regexp-in-string "[][]" "_" label)))

(defun design-review--location-links (document file line)
  "Render source and, when available, diff links for FILE and LINE."
  (when (and (stringp file) (not (string-empty-p file)))
    (concat (design-review--link "design-source" document file line (format "%s:%s" file (or line 1)))
            (unless (equal (plist-get document :baseline) "none")
              (concat " " (design-review--link "design-diff" document file line "diff"))))))

(defun design-review--text (value)
  "Keep returned prose on one Org result line."
  (replace-regexp-in-string "[\n\r]+" " " (format "%s" (or value ""))))

(defun design-review--diagram-task (block)
  "Require explicit per-diagram findings for a diagram review BLOCK."
  (when (equal (plist-get block :language) "diagram-review")
    (format "\n\nExplicit diagram review: %s. For EACH listed diagram, return at least one finding with diagram_id equal to its ID, a status, evidence and limitations. Read the complete authored diagram and its surrounding notes; distinguish agreed intent, existing behaviour and alternatives. Check participants, ordering, branches, errors, state transitions and side effects against implementation as applicable. Static call edges do not establish runtime ordering. Inspect linked images if accessible; otherwise report UNKNOWN. Rendering is not verification. Also identify any diagrams in prose or other formats and assess them explicitly."
            (json-encode (vconcat (design-review--diagrams))))))

(defun design-review--brief (block document)
  "Build a bounded review brief from the authored document and Git changes."
  (let* ((root (plist-get document :root))
         (baseline (plist-get document :baseline))
         (changes (if (plist-member document :changes)
                      (plist-get document :changes)
                    (unless (equal baseline "none")
                    (concat (design-review--git root "status" "--short" "--untracked-files=all") "\n"
                            (design-review--git root "diff" "--no-ext-diff" "--no-textconv" baseline "--")))))
         (limit 60000))
    (format "Independent design review. This conversation is dedicated to review, separate from the implementation conversation. Assess this task against the current supplied evidence; earlier turns are not proof that current code is correct. Do not edit project files or the Org document, and do not revise the plan to fit the code. Inspect the actual source and tests relevant to your assigned remit. The supplied specification defines your assignment. Feature reviews receive only their approved box; overall reviews receive the authored document. When subagents are supported, delegate this focused review to a fresh subagent with exactly the supplied specification, this task, project root and baseline. Preserve its remit and require evidence. Collect its findings and return the required JSON yourself. Do not ask the subagent to recursively delegate. If subagents are unavailable, perform this focused review directly. Report findings only for this review type: plan reviewers own their assigned freeform changes, test reviewers own test alignment, implementation reviewers own overall integration and context, diagram reviewers own diagram conformance, and change reviewers own out-of-plan changes. Use only the supplied specification as requirements; inspect source as evidence. You may run relevant tests; distinguish execution outcomes from semantic assessment. Do not claim tests ran unless you ran them and saw their outcomes.\n\nProject root: %s\nBaseline: %s\nReview block: %s (%s)\n\nTask:\n%s\n\nSupplied specification:\n%s\n\nGit status and tracked changes:\n%s\n\nInspect untracked files and any omitted diff/context yourself. For change-review, cover the entire repository, including changes within planned symbols, tests and configuration files; naming a symbol in the plan does not approve every change to it. If baseline is none, historical change coverage is unavailable.\n\nReturn an explicit top-level status PASS, FAIL, REVIEW or UNKNOWN. PASS requires positive source evidence and no unresolved findings. Return a final JSON object only: {\"status\":\"PASS|FAIL|REVIEW|UNKNOWN\",\"summary\":\"short assessment\",\"findings\":[{\"status\":\"PASS|REVIEW|FAIL|UNKNOWN\",\"message\":\"specific evidence and limitations\",\"file\":\"path relative to project root\",\"line\":1}],\"test_execution\":\"commands and observed results, or not run\"}. Include source references for concerns. If evidence is insufficient, report UNKNOWN. Passing tests alone do not establish the stated behaviours."
            root baseline (plist-get block :id) (plist-get block :language)
            (concat (design-review--review-task (plist-get block :language)) "\n\n" (plist-get block :body)
                    (design-review--diagram-task block)
                    (when (equal (plist-get block :language) "change-review")
                      "\n\nFor each finding, include outside_plan as a JSON boolean. Set it to true only for an actual implementation change identified as outside the authored plan, with evidence explaining the mismatch. Use false for planned changes, baseline context, general observations, or uncertainty about whether a change is outside the plan. This classification is separate from PASS/REVIEW/FAIL/UNKNOWN; additional work is not automatically a defect.")
                    )
            (if (equal (plist-get block :language) "plan-review")
                "The complete approved specification is the assigned box above."
              (or (plist-get document :authored-text) (design-review--authored-text)))
            (cond ((null changes) "Unavailable: no pinned Git baseline.")
                  ((equal (plist-get block :language) "plan-review") "Inspect relevant source changes against the supplied baseline. Other specifications are outside this assignment.")
                  ((> (length changes) limit) (concat (substring changes 0 limit) "\n[TRUNCATED: inspect the remaining changes yourself]"))
                  (t changes)))))

(defun design-review--review-result (run)
  "Turn a completed review RUN into advisory results with evidence links."
  (let* ((text (string-trim (or (plist-get run :text) "")))
         (decoded (condition-case nil (design-review--json text) (error nil)))
         (document (plist-get run :document))
         (plan-review (equal (plist-get run :language) "plan-review"))
         (comparison (alist-get 'comparison decoded))
         (has-comparison (and (stringp comparison)
                              (not (string-blank-p comparison))))
         (shell (plist-get run :shell))
         (lines (list (design-review--stamp) "Independent agent assessment (advisory)."
                      (format "Conversation: [[design-session:%s][open review session]]"
                              (base64-encode-string (encode-coding-string (buffer-name shell) 'utf-8) t)))))
    (if (not (and (listp decoded) (stringp (alist-get 'summary decoded))
                  (vectorp (alist-get 'findings decoded)) (stringp (alist-get 'test_execution decoded))
                  (seq-every-p (lambda (finding)
                                 (and (listp finding)
                                      (member (alist-get 'status finding) '("PASS" "REVIEW" "FAIL" "UNKNOWN"))
                                      (stringp (alist-get 'message finding))))
                               (alist-get 'findings decoded))))
        (setq lines (append lines '("UNKNOWN: reviewer did not return the required assessment format; inspect its conversation.")))
      (setq lines (append lines (list (design-review--text (alist-get 'summary decoded))
                                     (format "Test execution: %s" (design-review--text (alist-get 'test_execution decoded))))))
      (when plan-review
        (setq lines
              (append lines
                      (if has-comparison
                          (cons "Plan versus implementation:"
                                (mapcar (lambda (line) (concat ": " line))
                                        (split-string comparison "\n")))
                        '("UNKNOWN: reviewer omitted the Show Me comparison with the plan.")))))
      (unless (equal (plist-get run :language) "test-review")
        (setf (plist-get run :outcome)
              (cond ((and plan-review (not has-comparison)) "UNKNOWN")
                    ((and (equal (alist-get 'status decoded) "PASS")
                          (> (length (alist-get 'findings decoded)) 0)
                          (seq-every-p (lambda (finding) (equal (alist-get 'status finding) "PASS"))
                                       (alist-get 'findings decoded))) "PASS")
                    ((member (alist-get 'status decoded) '("FAIL" "REVIEW" "UNKNOWN")) (alist-get 'status decoded))
                    (t "UNKNOWN")))
        (setq lines (append lines (list (format "Review verdict: %s" (plist-get run :outcome))))))
      (dolist (finding (append (alist-get 'findings decoded) nil))
        (let ((status (alist-get 'status finding)) (line (alist-get 'line finding)))
          (unless (member status '("PASS" "REVIEW" "FAIL" "UNKNOWN")) (setq status "UNKNOWN"))
          (setq lines (append lines (list (format "- %s%s: %s" status
                                                 (cond
                                                  ((and (equal (plist-get run :language) "change-review")
                                                        (eq (alist-get 'outside_plan finding) t))
                                                   " [outside plan]")
                                                  ((alist-get 'diagram_id finding)
                                                   (format " [%s]" (design-review--text (alist-get 'diagram_id finding))))
                                                  (t ""))
                                                 (design-review--text (alist-get 'message finding))))))
          (when-let* ((link (design-review--location-links document (alist-get 'file finding)
                                                          (if (and (integerp line) (> line 0)) line 1))))
            (setq lines (append lines (list (format "  %s" link))))))))
    (dolist (id (plist-get run :diagrams))
      (unless (seq-some (lambda (finding)
                          (and (listp finding) (equal (alist-get 'diagram_id finding) id)
                               (member (alist-get 'status finding) '("PASS" "REVIEW" "FAIL" "UNKNOWN"))
                               (stringp (alist-get 'message finding))
                               (not (string-empty-p (string-trim (alist-get 'message finding))))))
                        (append (alist-get 'findings decoded) nil))
        (setf (plist-get run :outcome) "UNKNOWN")
        (setq lines (append lines (list (format "- UNKNOWN [%s]: reviewer omitted an explicit diagram assessment." id))))))
    (when (equal (plist-get run :outcome) "UNKNOWN")
      (setq lines (mapcar (lambda (line)
                           (if (string-prefix-p "Review verdict:" line)
                               "Review verdict: UNKNOWN" line)) lines)))
    (setq lines (append lines (design-review--format-assessments run decoded)))
    (string-join lines "\n")))

(defun design-review--wake-tests (document)
  "Reconsider waiting test sessions after a prerequisite completes."
  (maphash (lambda (_key run)
             (when (and (eq document (plist-get run :document))
                        (equal (plist-get run :language) "test-review")
                        (not (plist-get run :submitted)))
               (run-at-time 0 nil #'design-review--advance (plist-get run :shell))))
           design-review--runs))

(defun design-review--finish (key run text)
  "Complete RUN, inserting TEXT only into its unchanged originating block."
  (when (and (eq run (gethash key design-review--runs))
             (not (equal (plist-get run :language) "test-review")))
    (when-let* ((gate (plist-get (plist-get run :document) :test-gate))
                (entry (assoc (cdr key) (plist-get gate :prerequisites))))
      (setcdr entry (if (design-review--run-current-p run)
                        (or (plist-get run :outcome) "UNKNOWN") "STALE"))))
  (when-let* ((subscription (plist-get run :subscription))
              ((buffer-live-p (plist-get run :shell))))
    (with-current-buffer (plist-get run :shell)
      (agent-shell-unsubscribe :subscription subscription)))
  (when (buffer-live-p (plist-get run :shell))
    (with-current-buffer (plist-get run :shell)
      (setq design-review--queue (delq run design-review--queue))
      (run-at-time 0 nil #'design-review--advance (current-buffer))))
  (when (eq run (gethash key design-review--runs))
    (remhash key design-review--runs)
    (design-review--wake-tests (plist-get run :document))
    (when (buffer-live-p (car key))
      (with-current-buffer (car key)
        (condition-case err
            (let ((block (design-review--block (cdr key))))
              (if (and block (equal (plist-get block :body) (plist-get run :body))
                       (equal (plist-get block :language) (plist-get run :language)))
                  (save-excursion
                    (goto-char (plist-get block :begin))
                    (when (and (plist-get (plist-get run :document) :fingerprint)
                               (not (equal (plist-get (plist-get run :document) :authored-text)
                                           (design-review--authored-text))))
                      (setq text (replace-regexp-in-string "Evidence freshness: CURRENT" "Evidence freshness: STALE" text t t)))
                    (org-babel-insert-result text '("drawer" "replace")))
                (message "Review %s finished for an edited/removed block; inspect its conversation" (cdr key))))
          (error (message "Review result retained in conversation: %s" (error-message-string err))))))))

(defun design-review--agent-event (key run event)
  "Handle one Agent Shell EVENT for RUN."
  (let ((kind (map-elt event :event)) (data (map-elt event :data)))
    (pcase kind
      ('init-finished (design-review--submit key run))
      ('agent-message-chunk
       (when (plist-get run :submitted)
         (when-let* ((chunk (map-elt data :text-chunk)))
           (let ((group (with-current-buffer (plist-get run :shell)
                          (map-elt agent-shell--state :chunked-group-count))))
             (unless (equal group (plist-get run :group))
               (setf (plist-get run :text) "" (plist-get run :group) group)))
           (setf (plist-get run :text) (concat (plist-get run :text) chunk)))))
      ('turn-complete
       (when (plist-get run :submitted)
         (design-review--finish key run
                                (if (equal (map-elt data :stop-reason) "end_turn")
                                    (condition-case err
                                        (design-review--review-result run)
                                      (error (format "%s\nUNKNOWN: invalid reviewer response: %s"
                                                     (design-review--stamp) (error-message-string err))))
                                  (format "%s\nUNKNOWN: reviewer stopped (%s)." (design-review--stamp) (map-elt data :stop-reason))))))
      ('clean-up
       (with-current-buffer (plist-get run :shell)
         (design-review--interrupt-queue)))
      ((or 'error 'session-selection-cancelled)
       (design-review--finish key run (format "%s\nUNKNOWN: review interrupted: %s" (design-review--stamp)
                                            (or (map-elt data :message) kind)))))))

(defun design-review--submit (key run)
  "Send RUN's brief when its dedicated session is ready."
  (when (and (eq run (gethash key design-review--runs)) (not (plist-get run :submitted))
             (buffer-live-p (plist-get run :shell))
             (agent-shell-initialized-p :shell-buffer (plist-get run :shell)))
    (let ((reason (and (equal (plist-get run :language) "test-review")
                       (design-review--test-gate-reason run))))
      (cond ((equal reason "WAITING") nil)
            (reason (design-review--finish key run (format "%s\nBLOCKED: test review not run. %s" (design-review--stamp) reason)))
            (t
             (setf (plist-get run :submitted) t)
             (condition-case err
                 (agent-shell-insert :text (plist-get run :prompt) :submit t :no-focus t :shell-buffer (plist-get run :shell))
               (error (design-review--finish key run (format "UNKNOWN: could not submit review: %s" (error-message-string err))))))))))

(defun design-review--run-current-p (run)
  "Whether RUN still describes the same authored plan and saved source."
  (let ((document (plist-get run :document)) (buffer (car (plist-get run :key))))
    (and (buffer-live-p buffer) (plist-get document :fingerprint)
         (condition-case nil
             (with-current-buffer buffer
               (and (equal (plist-get document :authored-text) (design-review--authored-text))
                    (equal (plist-get document :fingerprint) (design-review--source-fingerprint document))))
           (error nil)))))

(defun design-review--test-gate-reason (run)
  "Return nil when test RUN may start, WAITING, or an explicit blocking reason."
  (let* ((gate (plist-get (plist-get run :document) :test-gate))
         (prerequisites (plist-get gate :prerequisites)))
    (cond ((not gate) "Run the document check to obtain implementation prerequisites.")
          ((not prerequisites) "No implementation prerequisites are available.")
          ((not (design-review--run-current-p run)) "Source or plan changed; rerun the checks and implementation review.")
          ((seq-find (lambda (entry) (not (member (cdr entry) '("PASS" "PENDING")))) prerequisites)
           (let ((entry (seq-find (lambda (entry) (not (member (cdr entry) '("PASS" "PENDING")))) prerequisites)))
             (format "Prerequisite review %s finished with %s; rerun after resolving it." (car entry) (cdr entry))))
          ((seq-some (lambda (entry) (equal (cdr entry) "PENDING")) prerequisites) "WAITING")
          (t nil))))

(defun design-review--start-review (block document &optional validated)
  "Queue BLOCK in the document's dedicated review conversation."
  (unless validated (setq validated (design-review--require-valid document)))
  (when (and (equal (plist-get block :language) "test-review")
             (not (plist-get document :test-gate)))
    (user-error "Run the document check before test reviews; implementation prerequisites are required"))
  (unless (plist-get document :authored-text)
    (setf (plist-get document :path) buffer-file-name
          (plist-get document :authored-text) (design-review--authored-text)))
  (unless (plist-get document :fingerprint)
    (setf (plist-get document :fingerprint) (design-review--source-fingerprint document)))
  (require 'agent-shell)
  ;; A live reload may retain the former single-session value.
  (when (bufferp design-review--session) (setq design-review--session nil))
  (let* ((key (cons (current-buffer) (plist-get block :id)))
         (prompt (design-review--brief block document))
         (_ (when (gethash key design-review--runs)
              (user-error "This block already has a queued or running review")))
         (id (plist-get block :id))
         (previous (cdr (assoc id design-review--session)))
         (shell (if (buffer-live-p previous) previous
                  (let ((created (agent-shell--new-shell
                                  :location (plist-get document :root)
                                  :config (or design-review-agent-config
                                              (design-review--default-agent-config))
                                  :no-display t)))
                    (setf (alist-get id design-review--session nil nil #'equal) created)
                    created)))
         (run (list :key key :shell shell :document document :body (plist-get block :body)
                    :diagrams (when (equal (plist-get block :language) "diagram-review")
                                (design-review--diagrams))
                    :language (plist-get block :language) :prompt prompt :text ""
                    :submitted nil :subscription nil :group nil :outcome "UNKNOWN")))
    (puthash key run design-review--runs)
    (with-current-buffer shell
      (add-hook 'kill-buffer-hook #'design-review--interrupt-queue nil t)
      (setq design-review--queue (append design-review--queue (list run))))
    ;; Leave time for Babel to insert the running result before a fast reply.
    (run-at-time 0 nil #'design-review--advance shell)
    (format "%s\n%s: queued in dedicated review conversation %s. Results will replace this drawer."
            (design-review--stamp)
            (if (equal (plist-get block :language) "test-review") "WAITING for all non-test reviews to PASS" "RUNNING")
            (buffer-name shell))))

(defun design-review--interrupt-queue ()
  "Finish every queued review when its conversation closes."
  (dolist (run (copy-sequence design-review--queue))
    (design-review--finish (plist-get run :key) run
                           (format "%s\nUNKNOWN: review conversation closed."
                                   (design-review--stamp)))))

(defun design-review--advance (shell)
  "Start the next queued review in SHELL, one turn at a time."
  (when (buffer-live-p shell)
    (with-current-buffer shell
      (when-let* ((run (car design-review--queue))
                  (key (plist-get run :key)))
        (unless (plist-get run :subscription)
          (setf (plist-get run :subscription)
                (agent-shell-subscribe-to
                 :shell-buffer shell
                 :on-event (lambda (event) (design-review--agent-event key run event)))))
        (design-review--submit key run)))))

(defun design-review-check-block ()
  "Execute the owned block at point, using only its review executor."
  (interactive)
  (let* ((block (design-review--block-at-point)) (document (design-review--document))
         (result (pcase (plist-get block :language)
                   ("test-review" (design-review--prepare-test block))
                   (_ (design-review--start-review block document)))))
    (org-babel-insert-result result '("drawer" "replace"))
    result))

(defun org-babel-execute:plan-review (_body _params)
  "Assess this freeform plan box; never execute its body as code."
  (design-review--start-review (design-review--block-at-point) (design-review--document)))

(defun org-babel-execute:design-graph (_body _params)
  "Review a legacy graph as freeform intent; no deterministic checker is used."
  (org-babel-execute:plan-review nil nil))

(defun org-babel-execute:test-review (_body _params)
  "Check prerequisites before assessing planned tests."
  (design-review--prepare-test (design-review--block-at-point)))

(defun design-review--prepare-test (block)
  "Start background prerequisites and the requested test BLOCK."
  (require 'design-review-async)
  (let ((result (design-review--prepare "check" (plist-get block :id))))
    (format "%s\n%s: all non-test assessments must pass before test review.\n%s"
            (design-review--stamp) (alist-get 'status result) (json-encode result))))

(defun org-babel-execute:change-review (_body _params)
  "Assess changes outside the plan in the dedicated review conversation."
  (design-review--start-review (design-review--block-at-point) (design-review--document)))

(defun org-babel-execute:implementation-review (_body _params)
  "Assess planned implementation in the dedicated review conversation."
  (design-review--start-review (design-review--block-at-point) (design-review--document)))

(defun org-babel-execute:diagram-review (_body _params)
  "Assess diagrams in a dedicated turn with the full authored plan."
  (design-review--start-review (design-review--block-at-point) (design-review--document)))

(defun design-review--decode-link (path)
  (design-review--json (decode-coding-string (base64-decode-string path) 'utf-8)))

(defun design-review-follow-source (path _argument)
  "Visit the source location encoded in PATH."
  (let* ((data (design-review--decode-link path))
         (file (expand-file-name (alist-get 'file data) (alist-get 'root data))))
    (unless (file-regular-p file) (user-error "Source no longer exists; use the diff link"))
    (find-file-other-window file)
    (goto-char (point-min))
    (forward-line (1- (alist-get 'line data)))))

(defun design-review-follow-diff (path _argument)
  "Open PATH's baseline diff, including untracked additions.
Open the source location when there is no content diff to display."
  (require 'magit-diff)
  (let* ((data (design-review--decode-link path))
         (root (file-name-as-directory (alist-get 'root data)))
         (repository (design-review--git root "rev-parse" "--show-toplevel"))
         (default-directory (file-name-as-directory repository))
         (absolute (expand-file-name (alist-get 'file data) root))
         (file (file-relative-name absolute repository))
         (baseline (alist-get 'baseline data))
         (line (or (alist-get 'line data) 1))
         (new (and (file-regular-p absolute)
                   (not (magit-file-tracked-p file))
                   (not (magit-git-success "cat-file" "-e" (format "%s:%s" baseline file))))))
    (if new
        (magit-diff-setup-buffer nil "--no-index" '("--no-ext-diff" "--no-textconv")
                                 (list null-device absolute) 'undefined)
      (magit-diff-range baseline '("--no-ext-diff" "--no-textconv") (list file)))
    (goto-char (point-min))
    (let (nearest)
      (while (re-search-forward "^@@ -[0-9]+\\(?:,[0-9]+\\)? +\\+\\([0-9]+\\)\\(?:,\\([0-9]+\\)\\)? @@" nil t)
        (let ((start (string-to-number (match-string 1)))
              (length (string-to-number (or (match-string 2) "1"))))
          (when (or (null nearest) (<= start line)) (setq nearest (line-beginning-position)))
          (when (and (<= start line) (< line (+ start (max 1 length))))
            (goto-char (point-max)))))
      (if nearest
          (progn
            (goto-char nearest)
            (magit-section-show (magit-current-section)))
        (if (file-regular-p absolute)
            (progn
              (find-file absolute)
              (goto-char (point-min))
              (forward-line (1- line))
              (message "No content diff against the review baseline for %s; opened source" file))
          (user-error "No diff or current source for %s; the review result may be outdated" file))))))

(org-link-set-parameters "design-source" :follow #'design-review-follow-source)
(org-link-set-parameters "design-diff" :follow #'design-review-follow-diff)
(org-link-set-parameters "design-session"
                         :follow (lambda (path _argument)
                                   (let ((buffer (get-buffer (decode-coding-string (base64-decode-string path) 'utf-8))))
                                     (unless buffer (user-error "Review session is no longer open"))
                                     (pop-to-buffer buffer))))

(dolist (language design-review--languages)
  (add-to-list 'org-src-lang-modes (cons language (if (equal language "plan-review") 'design-review-plan 'text))))

(provide 'design-review-execution)
;;; design-review-execution.el ends here
