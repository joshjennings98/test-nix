;;; design-review-async.el --- Background validation and checks -*- lexical-binding: t; -*-

(require 'design-review-execution)

(defconst design-review--worker-library (or load-file-name buffer-file-name))

(defvar-local design-review--preparation nil
  "Most recent background job, including its status and validation result.")

(defun design-review--worker ()
  "Run validation and optional graph checks in a separate batch Emacs."
  (let* ((input (pop command-line-args-left))
         (output (pop command-line-args-left))
         (job (design-review--json (with-temp-buffer (insert-file-contents input) (buffer-string))))
         (design-review-program (alist-get 'program job))
         (design-review-tool-arguments (append (alist-get 'arguments job) nil))
         (exec-path (append (alist-get 'exec_path job) nil))
         (document (list :root (alist-get 'root job) :baseline (alist-get 'baseline job)
                         :path (alist-get 'path job) :authored-text (alist-get 'authored_text job)
                         :request (alist-get 'request job)))
         (result
          (condition-case err
              (let ((validation (design-review--validate document)) checks changes fingerprint)
                (when (and (equal (alist-get 'command job) "check")
                           (equal (alist-get 'status validation) "PASS"))
                  (setq fingerprint (design-review--source-fingerprint document))
                  (unless (equal (plist-get document :baseline) "none")
                    (setq changes
                          (concat (design-review--git (plist-get document :root) "status" "--short" "--untracked-files=all")
                                  "\n" (design-review--git (plist-get document :root) "diff" "--no-ext-diff" "--no-textconv"
                                                           (plist-get document :baseline) "--")))
                    (when (> (length changes) 60000)
                      (setq changes (concat (substring changes 0 60000) "\n[TRUNCATED: inspect remaining changes]"))))
                  (dolist (id (append (alist-get 'graphs job) nil))
                    (let ((request (alist-get (intern id) (alist-get 'requests validation))))
                      (push `((id . ,id)
                              (result . ,(if (= (length (alist-get 'rules request)) 0)
                                             '((status . "UNASSESSED")
                                               (findings . [((message . "Context only; no implementation requirements."))]))
                                           (design-review--tool (plist-get document :root) "check" request))))
                            checks))))
                `((validation . ,validation) (checks . ,(vconcat (nreverse checks)))
                  (fingerprint . ,fingerprint) (changes . ,changes)))
            (error `((validation . ,(design-review--validation-error err)))))))
    (with-temp-file output (insert (json-encode result)))))

(defun design-review--prepared (job result)
  "Apply background RESULT for JOB only while its authored document is unchanged."
  (let* ((document (plist-get job :document))
         (validation (alist-get 'validation result))
         (status (alist-get 'status validation)))
    (unless (equal (plist-get job :snapshot) (design-review--authored-text))
      (setq status "STALE"
            validation '((status . "STALE")
                         (findings . [((message . "Document edited; no checks or reviews were applied. Rerun the command."))]))))
    (setf (plist-get job :status) status
          (plist-get job :validation) validation
          (plist-get document :changes) (alist-get 'changes result)
          (plist-get document :checks) (alist-get 'checks result)
          (plist-get document :fingerprint) (alist-get 'fingerprint result)
          (plist-get document :path) buffer-file-name
          (plist-get document :authored-text) (plist-get job :snapshot))
    (if (or (equal (plist-get job :command) "validate") (not (equal status "PASS")))
        (design-review--show-validation validation (plist-get job :source))
      (save-excursion
        (dolist (original (plist-get job :blocks))
          (let* ((id (plist-get original :id))
                 (block (design-review--block id))
                 (text
                  (if (equal (plist-get block :language) "design-graph")
                      (design-review--format-findings
                       (alist-get 'result (seq-find (lambda (check) (equal (alist-get 'id check) id))
                                                   (append (alist-get 'checks result) nil))) document)
                    (design-review--start-review block document validation))))
            (goto-char (plist-get block :begin))
            (org-babel-insert-result text '("drawer" "replace")))))
      (message "Graph checks finished; independent reviews queued for %s" (plist-get job :source)))))

(defun design-review--preparation-finished (process job directory output log)
  "Collect PROCESS's result for JOB and release its temporary files."
  (when (memq (process-status process) '(exit signal))
    (unwind-protect
        (when (buffer-live-p (plist-get job :buffer))
          (with-current-buffer (plist-get job :buffer)
            (when (eq job design-review--preparation)
              (condition-case err
                  (progn
                    (unless (and (= (process-exit-status process) 0) (file-exists-p output))
                      (error "Background checker exited %s: %s" (process-exit-status process)
                             (with-current-buffer log
                               (buffer-substring-no-properties (point-min) (min (point-max) (+ (point-min) 2000))))))
                    (design-review--prepared
                     job (design-review--json (with-temp-buffer (insert-file-contents output) (buffer-string)))))
                (error
                 (let ((result (design-review--validation-error err)))
                   (setf (plist-get job :status) "ERROR" (plist-get job :validation) result)
                   (design-review--show-validation result (plist-get job :source))))))))
      (when (buffer-live-p log) (kill-buffer log))
      (delete-directory directory t))))

(defun design-review--prepare (command &optional id)
  "Start background COMMAND for the current document, optionally only block ID.
Validate once.  Git and Go subprocesses run in the worker, never on the UI thread."
  (when (equal (plist-get design-review--preparation :status) "RUNNING")
    (user-error "Document checks are already running in the background"))
  (condition-case err
      (let* ((document (design-review--document))
             (blocks (if id (list (or (design-review--block id) (user-error "No review block %s" id)))
                       (plist-get document :blocks)))
             (job (list :status "RUNNING" :command command :buffer (current-buffer)
                        :source (or buffer-file-name (buffer-name)) :document document :blocks blocks
                        :snapshot (design-review--authored-text) :validation nil)))
        (when (and (equal command "check")
                   (seq-some (lambda (block) (gethash (cons (current-buffer) (plist-get block :id)) design-review--runs)) blocks))
          (user-error "A requested block already has a queued or running review"))
        (let* ((directory (make-temp-file "design-review-job-" t))
               (input (expand-file-name "input.json" directory))
               (output (expand-file-name "output.json" directory))
               (log (generate-new-buffer " *design-review-worker*")))
          (condition-case err
              (progn
                (with-temp-file input
                  (insert (json-encode
                           `((root . ,(plist-get document :root)) (baseline . ,(plist-get document :baseline))
                             (path . ,(plist-get job :source)) (authored_text . ,(plist-get job :snapshot))
                             (request . ,(plist-get document :request)) (command . ,command)
                             (program . ,(or (executable-find design-review-program) design-review-program))
                             (arguments . ,(vconcat design-review-tool-arguments)) (exec_path . ,(vconcat exec-path))
                             (graphs . ,(vconcat (mapcar (lambda (block) (plist-get block :id))
                                                        (seq-filter (lambda (block) (equal (plist-get block :language) "design-graph"))
                                                                    (if (seq-some (lambda (block) (equal (plist-get block :language) "implementation-review")) blocks)
                                                                        (plist-get document :blocks) blocks)))))))))
                (setq design-review--preparation job)
                (make-process
                 :name "design-review-checker" :buffer log :noquery t :connection-type 'pipe
                 :command (list (expand-file-name invocation-name invocation-directory)
                                "-Q" "--batch" "-L" (file-name-directory design-review--worker-library)
                                "-l" design-review--worker-library "-f" "design-review--worker" input output)
                 :sentinel (lambda (process _event)
                             (design-review--preparation-finished process job directory output log))))
            (error
             (kill-buffer log)
             (delete-directory directory t)
             (signal (car err) (cdr err)))))
        (if (equal command "validate")
            (design-review--show-validation '((status . "RUNNING")) (plist-get job :source))
          (message "Checking document and graphs in the background; reviews will queue when ready"))
        '((status . "RUNNING") (message . "Poll review-results for preparation status and block results.")))
    (error
     (let ((result (design-review--validation-error err)))
       (setq design-review--preparation (list :status "ERROR" :validation result))
       (design-review--show-validation result (or buffer-file-name (buffer-name)))
       result))))

(provide 'design-review-async)
