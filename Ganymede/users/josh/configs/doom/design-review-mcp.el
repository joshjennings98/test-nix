;;; design-review-mcp.el --- Review operations on the existing MCP server -*- lexical-binding: t; -*-

(require 'design-review-execution)
(require 'design-review-async)

(declare-function make-mcp-server-tool "mcp-server")
(declare-function mcp-server-register-tool "mcp-server")

(defun design-review-mcp-create (args)
  (design-review--keys args '(path root title baseline))
  (json-encode (design-review-create (alist-get 'path args) (alist-get 'root args)
                                      (alist-get 'title args) (alist-get 'baseline args))))

(defun design-review-mcp-read (args)
  (design-review--keys args '(path))
  (with-current-buffer (design-review--buffer (alist-get 'path args))
    (json-encode `((path . ,buffer-file-name) (content . ,(buffer-substring-no-properties (point-min) (point-max)))
                   (modified . ,(if (buffer-modified-p) t :json-false))))))

(defun design-review-mcp-validate (args)
  (design-review--keys args '(path))
  (with-current-buffer (design-review--buffer (alist-get 'path args))
    (json-encode (design-review--prepare "validate"))))

(defun design-review-mcp-set-context (args)
  (design-review--keys args '(path body before))
  (json-encode (design-review-set-context (alist-get 'path args) (alist-get 'body args)
                                          (alist-get 'before args))))

(defun design-review-mcp-set-plan (args)
  (design-review--keys args '(path id body))
  (json-encode (design-review-set-block (alist-get 'path args) (alist-get 'id args) "plan-review"
                                       (alist-get 'body args) "Design and changes")))

(defun design-review-mcp-set-tests (args)
  (design-review--keys args '(path id tests))
  (let (lines names)
    (dolist (test (append (alist-get 'tests args) nil))
      (design-review--keys test '(name description expectations))
      (let ((name (design-review--line (alist-get 'name test) "Test name"))
            (description (design-review--line (alist-get 'description test) "Test behaviour"))
            (expectations (append (alist-get 'expectations test) nil)))
        (when (member name names) (user-error "Duplicate test %s" name))
        (push name names)
        (unless expectations (user-error "Test %s requires explicit expectations" name))
        (when lines (push "" lines))
        (push (format "%s :: %s" name description) lines)
        (push "" lines)
        (dolist (expectation expectations)
          (push (format "- %s" (design-review--line expectation "Expectation")) lines))))
    (unless lines (user-error "Provide at least one planned test"))
    (json-encode (design-review-set-block (alist-get 'path args) (alist-get 'id args) "test-review"
                                         (string-join (nreverse lines) "\n") "Tests and behaviours"))))

(defun design-review-mcp-check (args)
  (design-review--keys args '(path id))
  (with-current-buffer (design-review--buffer (alist-get 'path args))
    (json-encode (design-review--prepare "check" (alist-get 'id args)))))

(defun design-review-mcp-results (args)
  (design-review--keys args '(path))
  (with-current-buffer (design-review--buffer (alist-get 'path args))
    (design-review-refresh-evidence)
    (let (results)
      (save-excursion
        (dolist (block (plist-get (design-review--document) :blocks))
          (goto-char (plist-get block :begin))
          (let ((position (org-babel-where-is-src-block-result))
                (id (plist-get block :id)))
            (push `((id . ,id)
                    (running . ,(if (or (gethash (cons (current-buffer) id) design-review--runs)
                                        (and (equal (plist-get design-review--preparation :status) "RUNNING")
                                             (equal (plist-get design-review--preparation :command) "check")
                                             (seq-some (lambda (block) (equal (plist-get block :id) id))
                                                       (plist-get design-review--preparation :blocks)))) t :json-false))
                    (result . ,(if position
                                   (progn (goto-char position)
                                          (buffer-substring-no-properties position (org-babel-result-end)))
                                 "Not checked."))) results))))
      (json-encode `((preparation . ((status . ,(or (plist-get design-review--preparation :status) "IDLE"))
                                    (validation . ,(plist-get design-review--preparation :validation))))
                     (results . ,(vconcat (nreverse results))))))))

(defun design-review-check-document ()
  "Validate the document and queue the focused agent reviews."
  (interactive)
  (unless buffer-file-name (user-error "Save the review document first"))
  (design-review-mcp-check `((path . ,buffer-file-name))))

(defun design-review-register-tools ()
  "Register document operations and return their enabled MCP tool symbols."
  (require 'mcp-server)
  (let* ((text '((type . "string") (minLength . 1)))
         (path `((type . "string") (description . "Absolute local Org document path")))
         (id '((type . "string") (pattern . "^[A-Za-z][A-Za-z0-9_-]*$")))
         (entries
          `(("review-create" "Create Org review"
             "Create a new authoritative Org review. Pins Git HEAD by default; use baseline none explicitly outside Git. Never overwrites a document."
             ((path . ,path) (root . ,text) (title . ,text) (baseline . ,text))
             ["path" "root" "title"] design-review-mcp-create)
            ("review-read" "Read Org review"
             "Read the live Org document, including unsaved manual edits and results. Use before refining an existing block."
             ((path . ,path)) ["path"] design-review-mcp-read)
            ("validate-document" "Validate review document"
             "Tidy excess blank lines and heading spacing in the live buffer (undoable, not saved), then validate Org structure and unique IDs in the background. Returns RUNNING; poll review-results preparation until PASS, ERROR or STALE. Does NOT run Babel, tests, agents or require proposed changes to be implemented."
             ((path . ,path)) ["path"] design-review-mcp-validate)
            ("review-set-context" "Update planning context and diagrams"
             "Replace context with Org text. In context prose, use Org =inline code= for identifiers, paths and code snippets, not Markdown backticks. This convention does not apply inside source blocks. Set before to an existing review block ID to place short paragraphs, lists or diagrams immediately before that block; omit it for document-wide Context and decisions. Read first and send the complete revised context for that location, preserving user notes. Adjacent context must not contain headings. Use dedicated tools for plan/test blocks. Preserves review blocks and their results. Adds diagram review only when diagrams exist. Validates before saving; does not render or run reviews."
             ((path . ,path) (body . ,text) (before . ,id)) ["path" "body"] design-review-mcp-set-context)
            ("review-set-plan" "Add or replace planned changes"
             "Upsert one named freeform plan-review block. Choose a Show Me representation suited to this part of the feature: component trees, call-tree diffs, signatures, pseudocode, file trees, configuration or prose. No graph grammar or language restriction. Use separate stable IDs for distinct parts such as frontend and backend. Distinguish existing behaviour, proposed changes and preserved behaviour. Each block receives its own focused agent assessment with the full document as context. Reuse IDs to refine; existing design-graph blocks can be converted with the same ID and preserved body. Validates document structure before saving; does not verify semantics or execute the body."
             ((path . ,path) (id . ,id) (body . ,text))
             ["path" "id" "body"] design-review-mcp-set-plan)
            ("review-set-tests" "Add or replace planned tests"
             "Upsert a named test-review block with behaviours and explicit expectations. Prefer one test per block so each has its own Babel results; use separate calls and stable IDs for separate tests. Validates the document before saving; does not run tests or launch a reviewer."
             ((path . ,path) (id . ,id)
              (tests . ((type . "array") (minItems . 1)
                        (items . ((type . "object") (additionalProperties . :false)
                                  (properties . ((name . ,text) (description . ,text)
                                                 (expectations . ((type . "array") (minItems . 1) (items . ,text)))))
                                  (required . ["name" "description" "expectations"]))))))
             ["path" "id" "tests"] design-review-mcp-set-tests)
            ("review-check" "Execute review blocks"
             "Start background document validation for one named block, or all review blocks when id is omitted. Returns RUNNING immediately. Validates once, then queues plan/test/implementation/diagram/change reviews in one dedicated conversation. Poll review-results for preparation status and block completion. Plan edits during preparation discard the pending results; rerun after edits."
             ((path . ,path) (id . ,id)) ["path"] design-review-mcp-check)
            ("review-results" "Read check results"
             "Read preparation status, its validation result, current result drawers and which checks or independent assessments are still running. Preparation PASS means validation completed, not that all reviews passed. Results describe their recorded run time; rerun after code or plan edits."
             ((path . ,path)) ["path"] design-review-mcp-results)))
         enabled)
    (dolist (entry entries)
      (let ((schema `((type . "object") (additionalProperties . :false)
                      (properties . ,(nth 3 entry)) (required . ,(nth 4 entry)))))
        (mcp-server-register-tool
         (make-mcp-server-tool :name (nth 0 entry) :title (nth 1 entry)
                               :description (nth 2 entry) :input-schema schema :function (nth 5 entry))))
      (push (intern (car entry)) enabled))
    (nreverse enabled)))

(provide 'design-review-mcp)
;;; design-review-mcp.el ends here
