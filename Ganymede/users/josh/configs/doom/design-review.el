;;; design-review.el --- Authoritative Org design reviews -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'json)
(require 'org)
(require 'org-element)
(require 'ob)
(require 'seq)
(require 'subr-x)

(defgroup design-review nil "Org design review tools." :group 'org)
(defcustom design-review-program "go-design-check"
  "Executable providing typed Go graph validation and checks."
  :type 'file :group 'design-review)
(defcustom design-review-tool-arguments nil
  "Extra Go build/scope arguments used consistently for validation and checks.
For example, (\"--cgo\" \"off\") or (\"--tags\" \"integration\")."
  :type '(repeat string) :group 'design-review)

(defconst design-review--languages '("design-graph" "test-review" "implementation-review" "diagram-review" "change-review"))

(defun design-review--json (text)
  "Decode TEXT with consistent object and array representations."
  (json-parse-string text :object-type 'alist :array-type 'array
                     :null-object nil :false-object :json-false))

(defun design-review--line (value label)
  "Require VALUE to be a non-empty single line for LABEL."
  (unless (and (stringp value) (not (string-empty-p (string-trim value)))
               (not (string-match-p "[\n\r]" value)))
    (user-error "%s must be a non-empty single line" label))
  value)

(defun design-review--id (id)
  "Validate a portable Org block ID."
  (unless (and (stringp id) (string-match-p "\\`[a-zA-Z][a-zA-Z0-9_-]*\\'" id))
    (user-error "Block ID must start with a letter and contain letters, digits, _ or -"))
  id)

(defun design-review--keys (object allowed)
  "Reject fields in OBJECT that are not in ALLOWED."
  (unless (listp object) (user-error "Expected an object"))
  (dolist (entry object)
    (unless (memq (car entry) allowed) (user-error "Unknown field %s" (car entry)))))

(defun design-review--render-graph (graph)
  "Render structured GRAPH into editable declaration lines and trees."
  (design-review--keys graph '(roots declarations))
  (let (lines imports)
    (dolist (declaration (append (alist-get 'declarations graph) nil))
      (design-review--keys declaration '(symbol kind change signature imports))
      (dolist (entry (alist-get 'imports declaration))
        (let ((previous (assoc (car entry) imports)))
          (when (and previous (not (equal (cdr previous) (cdr entry))))
            (user-error "Conflicting import alias %s" (car entry)))
          (cl-pushnew entry imports :test #'equal)))
      (push (format "%s %s %s%s"
                    (design-review--line (alist-get 'change declaration) "Declaration change")
                    (design-review--line (alist-get 'kind declaration) "Declaration kind")
                    (design-review--line (alist-get 'symbol declaration) "Symbol")
                    (if-let* ((signature (alist-get 'signature declaration)))
                        (format " :: %s" (design-review--line signature "Signature")) "")) lines))
    (setq lines (nreverse lines))
    (dolist (entry (reverse (sort imports (lambda (a b) (string< (symbol-name (car a)) (symbol-name (car b)))))))
      (push (format "import %s %s" (car entry) (json-encode (cdr entry))) lines))
    (cl-labels ((node-lines
                (node depth)
                (design-review--keys node '(symbol relation change description children))
                (let* ((change (alist-get 'change node))
                       (marker (pcase change
                                 ((or 'nil "") "") ("add" "+ ") ("remove" "- ")
                                 ("preserve" "= ") (_ (user-error "Unknown tree change %s" change))))
                       (relation (alist-get 'relation node))
                       (description (alist-get 'description node)))
                  (setq lines
                        (append lines
                                (list (format "%s%s%s%s%s" (make-string (* depth 2) ?\s) marker
                                              (design-review--line (alist-get 'symbol node) "Symbol")
                                              (if relation (format " [%s]" (design-review--line relation "Relationship")) "")
                                              (if description (format " ; %s" (design-review--line description "Description")) "")))))
                  (dolist (child (append (alist-get 'children node) nil)) (node-lines child (1+ depth))))))
      (dolist (root (append (alist-get 'roots graph) nil)) (node-lines root 0)))
    (concat (string-join lines "\n") "\n")))

(defun design-review--parse-graph (id body)
  "Parse a named graph BODY into the tool's structured request."
  (let (declarations roots stack imports)
    (dolist (line (split-string body "\n"))
      (cond
       ((string-match-p "\\`[ \t]*\\(?:;.*\\)?\\'" line))
       ((string-match "\\`import \\([a-zA-Z_][a-zA-Z0-9_]*\\) \\(.*\\)\\'" line)
        (let ((alias (intern (match-string 1 line)))
              (path (design-review--json (match-string 2 line))))
          (design-review--line path "Import path")
          (when (assq alias imports) (user-error "Duplicate import alias %s" alias))
          (push (cons alias path) imports)))
       ((string-match "\\`\\(add\\|modify\\|remove\\|preserve\\) \\(function\\|method\\|type\\|interface\\|field\\|variable\\|constant\\) \\([^ \t].*?\\)\\(?: :: \\(.*\\)\\)?\\'" line)
        (let ((declaration `((change . ,(match-string 1 line)) (kind . ,(match-string 2 line))
                             (symbol . ,(match-string 3 line))))
              (signature (match-string 4 line)))
          (when signature (push (cons 'signature signature) declaration))
          (push declaration declarations)))
       ((string-match "\\`\\( *\\)\\([+=-] \\)?\\([^ \t].*?\\)\\(?: \\[\\([^]]+\\)\\]\\)?\\(?: ; \\(.*\\)\\)?\\'" line)
        (let* ((indent (length (match-string 1 line)))
               (depth (/ indent 2))
               (marker (match-string 2 line))
               (symbol (match-string 3 line))
               (relation (match-string 4 line))
               (description (match-string 5 line))
               (node (list (cons 'symbol symbol) (cons 'children (vector)))))
          (unless (and (= (% indent 2) 0) (<= depth (length stack)))
            (user-error "Use two-space tree indentation: %s" line))
          (when marker (push (cons 'change (pcase marker ("+ " "add") ("- " "remove") ("= " "preserve"))) node))
          (when relation (push (cons 'relation relation) node))
          (when description (push (cons 'description description) node))
          (if (= depth 0)
              (setq roots (append roots (list node)))
            (let ((parent (nth (1- depth) stack)))
              (setf (alist-get 'children parent) (vconcat (alist-get 'children parent) (list node)))))
          (setq stack (append (seq-take stack depth) (list node)))))
       (t (user-error "Invalid graph line: %s" line))))
    (dolist (declaration declarations)
      (when imports (nconc declaration (list (cons 'imports imports)))))
    `((id . ,id) (declarations . ,(vconcat (nreverse declarations))) (roots . ,(vconcat roots)))))

(defun design-review--test-names (body)
  "Validate test behaviours in BODY and return their names."
  (let (names current expectations)
    (dolist (line (split-string body "\n"))
      (cond
       ((string-empty-p (string-trim line)))
       ((string-prefix-p ";" line))
       ((string-match "\\`- \\(.+?\\) :: \\(.+\\)\\'" line)
        (when (and current (not expectations)) (user-error "Test %s has no expectations" current))
        (setq current (match-string 1 line) expectations nil)
        (push current names))
       ((string-match-p "\\`  - .+\\'" line)
        (unless current (user-error "Expectation must follow a test behaviour"))
        (setq expectations t))
       (t (user-error "Use '- TestName :: behaviour' and indented '  - expectation' lines"))))
    (when (and current (not expectations)) (user-error "Tests need names, behaviours and expectations"))
    (nreverse names)))

(defun design-review--document ()
  "Read metadata and named review blocks from the current Org buffer."
  (unless (derived-mode-p 'org-mode) (user-error "This is not an Org document"))
  (save-excursion
    (goto-char (point-min))
    (let ((case-fold-search t))
      (while (re-search-forward "^[ \t]*#\\+begin_src[ \t]+\\(design-graph\\|test-review\\|implementation-review\\|diagram-review\\|change-review\\)\\(?:[ \t].*\\)?$" nil t)
        (let ((context (org-element-context)))
          (unless (memq (org-element-type context) '(src-block example-block export-block comment-block))
            (user-error "Incomplete review block at line %s" (line-number-at-pos)))))))
  (let ((tree (org-element-parse-buffer)) metadata blocks names graphs test-names)
    (org-element-map tree 'keyword
      (lambda (item)
        (let ((key (org-element-property :key item)))
          (when (member key '("DESIGN_ROOT" "DESIGN_BASELINE"))
            (when (assoc key metadata) (user-error "Duplicate %s" key))
            (push (cons key (org-element-property :value item)) metadata)))))
    (let* ((root (cdr (assoc "DESIGN_ROOT" metadata)))
           (baseline (cdr (assoc "DESIGN_BASELINE" metadata))))
      (unless (and root (file-name-absolute-p root) (not (file-remote-p root)) (file-directory-p root))
        (user-error "DESIGN_ROOT must be an existing absolute local directory"))
      (unless (and baseline (or (equal baseline "none") (string-match-p "\\`[0-9a-f]\\{40,64\\}\\'" baseline)))
        (user-error "DESIGN_BASELINE must be a full Git commit or none"))
      (org-element-map tree 'src-block
        (lambda (block)
          (let ((name (org-element-property :name block))
                (language (org-element-property :language block))
                (body (org-element-property :value block)))
            (when name
              (when (member name names) (user-error "Duplicate block ID %s" name))
              (push name names))
            (when (member language design-review--languages)
              (design-review--id name)
              (when (string-empty-p (string-trim body)) (user-error "Block %s is empty" name))
              (when (equal language "test-review")
                (dolist (test-name (design-review--test-names body))
                  (when (member test-name test-names) (user-error "Duplicate planned test %s" test-name))
                  (push test-name test-names)))
              (push (list :id name :language language :body body :begin (org-element-property :begin block)
                          :end (org-element-property :end block)) blocks)
              (when (equal language "design-graph")
                (push (design-review--parse-graph name body) graphs))))))
      (list :root (file-name-as-directory root) :baseline baseline :blocks (nreverse blocks)
            :request `((graphs . ,(vconcat (nreverse graphs))))))))

(defun design-review--command (directory program args &optional input)
  "Run PROGRAM with ARGS in DIRECTORY, returning (exit . output)."
  (let ((default-directory directory))
    (with-temp-buffer
      (when input (insert input))
      (let ((status (apply #'call-process-region (point-min) (point-max) program t t nil args)))
        (cons status (buffer-string))))))

(defun design-review--git (root &rest args)
  "Run Git ARGS in ROOT, failing with its diagnostics."
  (let ((result (design-review--command root "git" args)))
    (unless (eq (car result) 0) (user-error "Git: %s" (string-trim (cdr result))))
    (string-trim-right (cdr result))))

(defun design-review--tool (root command request)
  "Invoke COMMAND with REQUEST and return decoded JSON, including findings."
  (let* ((result (design-review--command root design-review-program
                                        (append (list command "--root" root) design-review-tool-arguments) (json-encode request)))
         (decoded (condition-case nil (design-review--json (cdr result))
                    (error (user-error "Go design checker: %s" (cdr result))))))
    (unless (memq (car result) '(0 3 4 5)) (user-error "Go design checker exited %s" (car result)))
    (when (alist-get 'error decoded) (user-error "%s" (alist-get 'error decoded)))
    decoded))

(defun design-review--with-baseline (document function)
  "Call FUNCTION with DOCUMENT's baseline directory; clean up owned worktrees."
  (let ((root (plist-get document :root)) (baseline (plist-get document :baseline)))
    (if (equal baseline "none") (funcall function root)
      (let* ((prefix (design-review--git root "rev-parse" "--show-prefix"))
             (temporary (make-temp-file "design-review-baseline-" t)) added)
        (unwind-protect
            (progn
              (design-review--git root "worktree" "add" "--detach" temporary baseline)
              (setq added t)
              (funcall function (file-name-as-directory (expand-file-name prefix temporary))))
          (when added
            (design-review--git root "worktree" "remove" "--force" temporary))
          (when (file-directory-p temporary) (delete-directory temporary t)))))))

(defun design-review--validate (document)
  "Validate DOCUMENT's complete proposal without executing Babel blocks."
  (design-review--with-baseline
   document (lambda (root) (design-review--tool root "validate" (plist-get document :request)))))

(defun design-review--require-valid (document)
  "Return validated compiled requests or reject DOCUMENT."
  (let ((result (design-review--validate document)))
    (unless (equal (alist-get 'status result) "PASS")
      (user-error "Document is %s: %s" (alist-get 'status result)
                  (mapconcat (lambda (finding) (format "%s: %s" (alist-get 'id finding) (alist-get 'message finding)))
                             (append (alist-get 'findings result) nil) "; ")))
    result))

(defun design-review-validate-document ()
  "Check document validity without running tests, Babel or agents."
  (interactive)
  (let ((result (design-review--validate (design-review--document))))
    (when (called-interactively-p 'interactive)
      (message "%s" (json-encode result)))
    result))

(defun design-review--buffer (path)
  "Visit an existing local Org review PATH without changing selected windows."
  (unless (and (stringp path) (file-name-absolute-p path) (not (file-remote-p path))
               (file-regular-p path) (string-suffix-p ".org" path))
    (user-error "Provide an existing absolute local .org path"))
  (let ((buffer (find-file-noselect path)))
    (with-current-buffer buffer
      (unless (verify-visited-file-modtime buffer)
        (user-error "Document changed on disk; reconcile the open buffer before editing")))
    buffer))

(defun design-review--put-block (id language body heading)
  "Insert or replace a block in the current candidate buffer."
  (design-review--id id)
  (when (string-match-p "^[ \t]*#\\+\\(?:begin_src\\|end_src\\)" (downcase body))
    (user-error "Block body must not contain Org source delimiters"))
  (let* ((tree (org-element-parse-buffer))
         (matches (org-element-map tree 'src-block
                    (lambda (block) (when (equal id (org-element-property :name block)) block))))
         (existing (car matches)))
    (when (cdr matches) (user-error "Block ID %s is ambiguous" id))
    (if existing
        (progn
          (unless (equal language (org-element-property :language existing)) (user-error "Block %s has another kind" id))
          (goto-char (org-element-property :begin existing))
          (org-babel-remove-result)
          ;; Reparse after removing results; :begin includes affiliated name lines.
          (let ((block (org-element-context)))
            (delete-region (org-element-property :begin block) (org-element-property :end block))))
      (let ((position (org-element-map tree 'headline
                        (lambda (item)
                          (when (and (= (org-element-property :level item) 1)
                                     (equal heading (org-element-property :raw-value item)))
                            (org-element-property :begin item))) nil t)))
        (if position (goto-char position)
          (goto-char (point-max))
          (insert (format "\n* %s\n" heading))
          (forward-line -1)))
      (org-end-of-subtree t t)
      (unless (bolp) (insert "\n")))
    (insert (format "\n#+name: %s\n#+begin_src %s :results drawer replace :exports both :eval never-export\n%s\n#+end_src\n"
                    id language (string-trim-right body)))))

(defun design-review--edit-document (path edit)
  "Validate a candidate edit and atomically replace the visited document."
  (let ((buffer (design-review--buffer path)) candidate)
    (with-current-buffer buffer
      (let ((original (buffer-substring-no-properties (point-min) (point-max)))
            (directory default-directory))
        (with-temp-buffer
          (setq default-directory directory)
          (insert original)
          (org-mode)
          (funcall edit)
          (design-review--require-valid (design-review--document))
          (setq candidate (buffer-string)))
        (atomic-change-group
          (replace-region-contents (point-min) (point-max) (lambda () candidate))
          (save-buffer))))))

(defun design-review-set-block (path id language body heading)
  "Upsert a validated block in PATH, preserving other document content."
  (design-review--edit-document
   path (lambda () (design-review--put-block id language body heading)))
  `((path . ,path) (id . ,id) (status . "updated")))

(defun design-review-set-context (path body)
  "Replace PATH's context section with Org BODY, preserving review blocks."
  (unless (and (stringp body) (not (string-empty-p (string-trim body))))
    (user-error "Context must be non-empty Org text"))
  (when (string-match-p "^\\* " body)
    (user-error "Context subheadings must use two or more stars"))
  (with-temp-buffer
    (insert body)
    (org-mode)
    (org-element-map (org-element-parse-buffer) 'src-block
      (lambda (block)
        (when (member (org-element-property :language block) design-review--languages)
          (user-error "Use the dedicated tools for review blocks")))))
  (design-review--edit-document
   path
   (lambda ()
     (let ((sections (org-element-map (org-element-parse-buffer) 'headline
                       (lambda (item)
                         (when (and (= (org-element-property :level item) 1)
                                    (equal (org-element-property :raw-value item) "Context and decisions"))
                           item)))))
       (when (cdr sections) (user-error "Context section is ambiguous"))
       (if-let* ((section (car sections)))
           (progn
             (goto-char (org-element-property :begin section))
             (forward-line 1)
             (delete-region (point) (org-element-property :end section)))
         (goto-char (point-max))
         (insert "\n* Context and decisions\n"))
       (insert "\n" (string-trim-right body) "\n\n")
       (unless (seq-some (lambda (block) (equal (plist-get block :language) "diagram-review"))
                         (plist-get (design-review--document) :blocks))
         (design-review--put-block
          "diagram-alignment" "diagram-review"
          "Review each authored diagram against the implementation, using the full plan as context."
          "Diagram alignment")))))
  `((path . ,path) (status . "updated")))

(defun design-review-create (path root title &optional baseline)
  "Create a review template at PATH for ROOT and TITLE."
  (interactive (list (read-file-name "Review document: " default-directory "design-review.org")
                     (read-directory-name "Go project root: " default-directory)
                     (read-string "Review title: ")
                     (when current-prefix-arg "none")))
  (design-review--line title "Title")
  (design-review--line root "Project root")
  (unless (and (file-name-absolute-p path) (not (file-remote-p path)) (string-suffix-p ".org" path)
               (file-name-absolute-p root) (not (file-remote-p root)) (file-directory-p root))
    (user-error "Use an absolute local .org path and an existing project root"))
  (when (or (file-exists-p path) (get-file-buffer path)) (user-error "Document already exists"))
  (setq baseline (or baseline (design-review--git root "rev-parse" "--verify" "HEAD^{commit}")))
  (with-temp-buffer
    (insert (format "#+title: %s\n#+DESIGN_ROOT: %s\n#+DESIGN_BASELINE: %s\n\n* Design and changes\n\n* Implementation alignment\n\n#+name: planned-implementation\n#+begin_src implementation-review :results drawer replace :exports both :eval never-export\nReview whether all planned implementation matches its intended behaviour and responsibilities.\n#+end_src\n\n* Tests and behaviours\n\n#+name: test-alignment\n#+begin_src test-review :results drawer replace :exports both :eval never-export\n; No planned tests listed yet. Discover new tests and assess alignment with the full plan.\n#+end_src\n\n* Diagram alignment\n\n#+name: diagram-alignment\n#+begin_src diagram-review :results drawer replace :exports both :eval never-export\nReview each authored diagram against the implementation, using the full plan as context.\n#+end_src\n\n* Changes outside plan\n\n#+name: changes-outside-plan\n#+begin_src change-review :results drawer replace :exports both :eval never-export\nReview all changes against the plan, including changes inside planned functions.\nIdentify unexpected responsibilities and explain any additional changes.\n#+end_src\n"
                    title (directory-file-name root) baseline))
    (org-mode)
    (design-review--require-valid (design-review--document))
    (write-region (point-min) (point-max) path nil 'silent nil 'excl))
  (when (called-interactively-p 'interactive) (find-file path))
  `((path . ,path) (baseline . ,baseline) (status . "created")))

(provide 'design-review)
;;; design-review.el ends here
