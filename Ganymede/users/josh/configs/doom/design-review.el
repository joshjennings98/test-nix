;;; design-review.el --- Authoritative Org design reviews -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'json)
(require 'org)
(require 'org-element)
(require 'ob)
(require 'seq)
(require 'subr-x)

(require 'design-review-fontification)
(defconst design-review--languages '("plan-review" "test-review" "implementation-review" "diagram-review" "change-review"))

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

(defun design-review--test-names (body)
  "Validate test behaviours in BODY and return their names."
  (let (names current expectations)
    (dolist (line (split-string body "\n"))
      (cond
       ((string-empty-p (string-trim line)))
       ((string-prefix-p ";" line))
       ((string-match "\\`\\(?:- \\)?\\([^ \t].*?\\) :: \\(.+\\)\\'" line)
        (when (and current (not expectations)) (user-error "Test %s has no expectations" current))
        (setq current (match-string 1 line) expectations nil)
        (push current names))
       ((string-match-p "\\`\\(?:  \\)?- .+\\'" line)
        (unless current (user-error "Expectation must follow a test behaviour"))
        (setq expectations t))
       (t (user-error "Use 'TestName :: behaviour' followed by '- expectation' lines"))))
    (when (and current (not expectations)) (user-error "Tests need names, behaviours and expectations"))
    (nreverse names)))

(defun design-review--document ()
  "Read metadata and named review blocks from the current Org buffer."
  (unless (derived-mode-p 'org-mode) (user-error "This is not an Org document"))
  (save-excursion
    (goto-char (point-min))
    (let ((case-fold-search t))
      (while (re-search-forward "^[ \t]*#\\+begin_src[ \t]+\\(plan-review\\|design-graph\\|test-review\\|implementation-review\\|diagram-review\\|change-review\\)\\(?:[ \t].*\\)?$" nil t)
        (let ((context (org-element-context)))
          (unless (memq (org-element-type context) '(src-block example-block export-block comment-block))
            (user-error "Incomplete review block at line %s" (line-number-at-pos)))))))
  (let ((tree (org-element-parse-buffer)) metadata blocks names test-names)
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
            (when (equal language "design-graph")
              (setq language "plan-review"))
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
                          :end (org-element-property :end block)) blocks)))))
      (list :root (file-name-as-directory root) :baseline baseline :blocks (nreverse blocks)))))

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

(defun design-review--validate (_document)
  "Confirm the document passed local structural parsing, without semantic claims."
  '((status . "PASS") (findings . [])))

(defun design-review--require-valid (document)
  "Return validated compiled requests or reject DOCUMENT."
  (let ((result (design-review--validate document)))
    (unless (equal (alist-get 'status result) "PASS")
      (user-error "Document is %s: %s" (alist-get 'status result)
                  (mapconcat (lambda (finding) (format "%s: %s" (alist-get 'id finding) (alist-get 'message finding)))
                             (append (alist-get 'findings result) nil) "; ")))
    result))

(defun design-review--show-validation (result source)
  "Display a readable validation RESULT for SOURCE."
  (let ((buffer (get-buffer-create "*Design review validation*"))
        (status (alist-get 'status result)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "Document validation: %s\n\n%s\n\n" status source))
        (insert (pcase status
                  ("RUNNING" "Validation is running in the background. You can keep editing.\n")
                  ("STALE" "The document changed during validation. Run validation again.\n")
                  ("PASS" "The document is valid. Review the plan before authorising implementation.\n")
                  (_ "Resolve the problems below, then validate the document again.\n")))
        (insert "This checks the plan. It does not run tests or review the implementation.\n\n")
        (dolist (finding (append (alist-get 'findings result) nil))
          (insert (format "- %s: %s\n"
                          (or (alist-get 'id finding) "Document")
                          (alist-get 'message finding))))
        (goto-char (point-min))
        (special-mode)))
    (display-buffer buffer '((display-buffer-below-selected) (window-height . 0.3)))
    (message "Document validation: %s — see *Design review validation*" status)))

(defun design-review--format-document ()
  "Tidy prose and review block spacing, preserving other source bodies."
  (save-excursion
    (save-restriction
      (widen)
      (atomic-change-group
        (dolist (block (reverse (org-element-map (org-element-parse-buffer) 'src-block #'identity)))
          (when (equal (org-element-property :language block) "test-review")
            (goto-char (org-element-property :begin block))
            (re-search-forward "^[ \t]*#\\+begin_src.*\n")
            (let ((start (point))
                  (end (copy-marker (progn (re-search-forward "^[ \t]*#\\+end_src") (line-beginning-position)))))
              (goto-char start)
              (while (re-search-forward "^\\(?:- \\)?[^ \t\n]+ :: [^\n]+\n\\(?:[ \t]*\n\\)*" end t)
                (when (looking-at "[ \t]*- ")
                  (let ((finish (point)))
                    (skip-chars-backward " \t\n" start)
                    (delete-region (point) finish)
                    (insert "\n\n"))))
              (set-marker end nil))))
        (let (protected)
          (org-element-map (org-element-parse-buffer)
              '(src-block example-block export-block verse-block special-block fixed-width
                drawer property-drawer table plain-list)
            (lambda (element)
              (goto-char (org-element-property :end element))
              ;; Two blank lines can terminate a list; retain that boundary.
              (unless (eq (org-element-type element) 'plain-list)
                (forward-line (- (or (org-element-property :post-blank element) 0))))
              (push (cons (org-element-property :begin element) (point)) protected)))
          (goto-char (point-max))
          (while (re-search-backward "\\(?:^[ \t]*\n\\)\\{2,\\}" nil t)
            (let ((start (match-beginning 0)) (end (match-end 0)))
              (unless (seq-some (lambda (span) (and (< start (cdr span)) (> end (car span)))) protected)
                (replace-match "\n" t t)))))
        (dolist (heading (reverse (org-element-map (org-element-parse-buffer) 'headline #'identity)))
          (goto-char (org-element-property :begin heading))
          (org-end-of-meta-data)
          (unless (or (eobp) (looking-at "[ \t]*$")) (insert "\n"))
          (goto-char (org-element-property :begin heading))
          (unless (bobp)
            (forward-line -1)
            (unless (looking-at "[ \t]*$")
              (forward-line 1)
              (insert "\n"))))))))

(defun design-review--formatted-document ()
  "Parse before formatting, then return the document with updated positions."
  (design-review--document)
  (design-review--format-document)
  (design-review--document))

(defun design-review-validate-document ()
  "Tidy spacing and check validity without running tests, Babel or agents.
Formatting is undoable and does not save the buffer."
  (interactive)
  (if (called-interactively-p 'interactive)
      (progn
        (require 'design-review-async)
        (design-review--prepare "validate"))
    (design-review--validate (design-review--formatted-document))))

(defun design-review--validation-error (err)
  "Represent ERR as a readable validation failure."
  `((status . "ERROR")
    (findings . [((id . "Document") (message . ,(error-message-string err)))])))

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
          (unless (or (equal language (org-element-property :language existing))
                      (and (equal language "plan-review")
                           (equal (org-element-property :language existing) "design-graph")))
            (user-error "Block %s has another kind" id))
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
          (let ((document (design-review--document)))
            (design-review--require-valid document))
          (design-review--format-document)
          (setq candidate (buffer-string)))
        (atomic-change-group
          (replace-region-contents (point-min) (point-max) (lambda () candidate))
          (save-buffer))
        (font-lock-flush)))))

(defun design-review-set-block (path id language body heading)
  "Upsert a validated block in PATH, preserving other document content."
  (design-review--edit-document
   path (lambda () (design-review--put-block id language body heading)))
  `((path . ,path) (id . ,id) (status . "updated")))

(defun design-review--authored-text ()
  "Copy the document without previous Babel results into the review brief."
  (let ((text (save-restriction
                (widen)
                (buffer-substring-no-properties (point-min) (point-max)))))
    (with-temp-buffer
      (insert text)
      (org-mode)
      (org-babel-map-src-blocks nil (org-babel-remove-result))
      ;; Babel inserts a separator after blocks which previously had none.
      ;; Canonicalise only that separator, preserving source bodies and prose.
      (dolist (block (reverse (org-element-map (org-element-parse-buffer) 'src-block #'identity)))
        (goto-char (org-element-property :end block))
        (skip-chars-backward " \t\n")
        (forward-line 1)
        (let ((start (point)))
          (while (looking-at "[ \t]*\n") (forward-line 1))
          (delete-region start (point))
          (insert "\n")))
      (buffer-substring-no-properties (point-min) (point-max)))))

(defun design-review--diagrams ()
  "Identify authored diagram blocks and image links in the whole document."
  (let ((text (design-review--authored-text)) ids (index 0))
    (with-temp-buffer
      (insert text)
      (org-mode)
      (org-element-map (org-element-parse-buffer) '(src-block link)
        (lambda (element)
          (pcase (org-element-type element)
            ('src-block
             (when (member (org-element-property :language element)
                           '("mermaid" "plantuml" "dot" "ditaa" "d2"))
               (cl-incf index)
               (push (or (org-element-property :name element)
                         (format "diagram-%s" index)) ids)))
            ('link
             (let ((path (org-element-property :path element)))
               (when (string-match-p "\\.\\(?:svg\\|png\\|jpe?g\\|webp\\)\\'" path)
                 (push (concat "image:" path) ids))))))))
    (delete-dups (nreverse ids))))

(defconst design-review--diagram-instructions
  "Review each authored diagram against the implementation, using the full plan as context.")

(defun design-review--sync-diagram-review ()
  "Add a diagram review when needed; remove an unused generated review."
  (let* ((blocks (plist-get (design-review--document) :blocks))
         (reviews (seq-filter (lambda (block) (equal (plist-get block :language) "diagram-review")) blocks)))
    (if (design-review--diagrams)
        (unless reviews
          (design-review--put-block "diagram-alignment" "diagram-review"
                                    design-review--diagram-instructions "Diagram alignment"))
      (dolist (block reviews)
        (when (and (equal (plist-get block :id) "diagram-alignment")
                   (equal (string-trim (plist-get block :body)) design-review--diagram-instructions))
          (goto-char (plist-get block :begin))
          (let ((heading (save-excursion
                           (when (ignore-errors (org-back-to-heading t))
                             (when (looking-at-p "^\\* Diagram alignment$") (point))))))
            (org-babel-remove-result)
            (let ((element (org-element-context)))
              (delete-region (org-element-property :begin element) (org-element-property :end element)))
            (when heading
              (goto-char heading)
              (let ((end (save-excursion (org-end-of-subtree t t) (point))))
                (when (string-empty-p (string-trim
                                       (buffer-substring-no-properties (line-beginning-position 2) end)))
                  (delete-region heading end))))))))))

(defun design-review--put-context-before (id body)
  "Place ordinary Org BODY immediately before the review block ID."
  (design-review--id id)
  (when (string-match-p "^\\*+ " body)
    (user-error "Block context uses paragraphs and lists, not headings"))
  (let* ((block (or (seq-find (lambda (item) (equal (plist-get item :id) id))
                            (plist-get (design-review--document) :blocks))
                    (user-error "No review block %s" id)))
         (heading (format "Notes for %s" id))
         (sections (org-element-map (org-element-parse-buffer) 'headline
                     (lambda (item)
                       (when (and (= (org-element-property :level item) 2)
                                  (equal (org-element-property :raw-value item) heading))
                         item)))))
    (when (cdr sections) (user-error "Duplicate context for %s" id))
    (if-let* ((section (car sections)))
        (progn
          (unless (and (< (org-element-property :begin section) (plist-get block :begin))
                       (>= (org-element-property :end section) (plist-get block :end))
                       (not (seq-some
                             (lambda (other)
                               (< (org-element-property :begin section)
                                  (plist-get other :begin) (plist-get block :begin)))
                             (plist-get (design-review--document) :blocks))))
            (user-error "Context for %s is no longer adjacent; reconcile the document" id))
          (goto-char (org-element-property :begin section))
          (delete-region (point) (plist-get block :begin)))
      (goto-char (plist-get block :begin)))
    (insert (format "** %s\n\n%s\n\n" heading (string-trim-right body)))))

(defun design-review-set-context (path body &optional before)
  "Replace PATH's global context or context BEFORE a named review block."
  (unless (and (stringp body) (not (string-empty-p (string-trim body))))
    (user-error "Context must be non-empty Org text"))
  (when (string-match-p "^\\* " body)
    (user-error "Context subheadings must use two or more stars"))
  (with-temp-buffer
    (insert body)
    (org-mode)
    (org-element-map (org-element-parse-buffer) 'src-block
		     (lambda (block)
		       (when (member (org-element-property :language block)
                                     (cons "design-graph" design-review--languages))
			 (user-error "Use the dedicated tools for review blocks")))))
  (design-review--edit-document
   path
   (lambda ()
     (if before
         (design-review--put-context-before before body)
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
           (goto-char (point-min))
           (if (re-search-forward "^\\* " nil t)
               (beginning-of-line)
             (goto-char (point-max)))
           (insert "\n* Context and decisions\n"))
	 (insert "\n" (string-trim-right body) "\n\n")))
     (design-review--sync-diagram-review)))
  `((path . ,path) (status . "updated")))

(defun design-review-create (path root title &optional baseline)
  "Create a review template at PATH for ROOT and TITLE."
  (interactive (list (read-file-name "Review document: " default-directory "design-review.org")
                     (read-directory-name "Project root: " default-directory)
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
    (insert (format "#+title: %s\n#+DESIGN_ROOT: %s\n#+DESIGN_BASELINE: %s\n\n* Context and decisions\n\n* Design and changes\n\n* Implementation alignment\n\n#+name: planned-implementation\n#+begin_src implementation-review :results drawer replace :exports both :eval never-export\nReview overall behaviour, integration, edge cases and document-wide decisions. Focused plan-review blocks own their specific planned changes; use them as context without duplicating their assessments.\n#+end_src\n\n* Tests and behaviours\n\n#+name: test-alignment\n#+begin_src test-review :results drawer replace :exports both :eval never-export\n; No planned tests listed yet. Discover new tests and assess alignment with the full plan.\n#+end_src\n\n* Changes outside plan\n\n#+name: changes-outside-plan\n#+begin_src change-review :results drawer replace :exports both :eval never-export\nReview all changes against the plan, including changes inside planned functions.\nIdentify unexpected responsibilities and explain any additional changes.\n#+end_src\n"
                    title (directory-file-name root) baseline))
    (org-mode)
    (design-review--require-valid (design-review--document))
    (write-region (point-min) (point-max) path nil 'silent nil 'excl))
  (when (called-interactively-p 'interactive) (find-file path))
  `((path . ,path) (baseline . ,baseline) (status . "created")))

(provide 'design-review)
;;; design-review.el ends here
