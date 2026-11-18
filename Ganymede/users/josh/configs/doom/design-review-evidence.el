;;; design-review-evidence.el --- Navigable uncertainty and advisory assessments -*- lexical-binding: t; -*-

(require 'design-review)

(defun design-review--source-fingerprint (document)
  "Hash Git-listed project files and authored requirements in DOCUMENT.
Results in the backing document are excluded. Ignored files and dependencies
outside this repository are outside this freshness boundary."
  (let* ((root (plist-get document :root))
         (path (plist-get document :path))
         (files (split-string (design-review--git root "ls-files" "-z" "--cached" "--others" "--exclude-standard") "\0" t))
         (parts (list (substring-no-properties (or (plist-get document :authored-text) "")))))
    (dolist (file (sort (delete-dups files) #'string<))
      (let ((absolute (expand-file-name file root)))
        (unless (or (equal absolute path) (string-prefix-p ".#" (file-name-nondirectory file)))
          (when-let* ((buffer (get-file-buffer absolute))
                      ((buffer-modified-p buffer)))
            (user-error "Save %s before assessing source freshness" file))
          (push (list file
                      (cond ((file-symlink-p absolute) (concat "symlink:" (file-symlink-p absolute)))
                            ((file-regular-p absolute)
                             (with-temp-buffer
                               (set-buffer-multibyte nil)
                               (insert-file-contents-literally absolute)
                               (secure-hash 'sha256 (current-buffer))))
                            (t "missing"))) parts))))
    (let ((json-encoding-pretty-print nil))
      (secure-hash 'sha256 (encode-coding-string (json-encode (vconcat parts)) 'utf-8)))))

(defun design-review--evidence-link (document)
  "Return a persistent freshness link for DOCUMENT's checked snapshot."
  (when (plist-get document :fingerprint)
    (format "[[design-evidence:%s][Check source freshness]]"
            (base64-encode-string
             (encode-coding-string
              (json-encode `((root . ,(plist-get document :root))
                             (path . ,(plist-get document :path))
                             (fingerprint . ,(plist-get document :fingerprint)))) 'utf-8) t))))

(defun design-review-refresh-evidence ()
  "Mark persisted evidence current or stale against saved project sources."
  (interactive)
  (when (derived-mode-p 'org-mode)
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "Evidence freshness: \\(CURRENT\\|STALE\\|UNAVAILABLE\\) \\[\\[design-evidence:\\([^]]+\\)\\]" nil t)
        (let* ((start (match-beginning 1)) (end (match-end 1))
               (encoded (match-string-no-properties 2))
               (status
                (condition-case nil
                    (let* ((data (design-review--decode-link encoded))
                           (document (list :root (alist-get 'root data) :path (alist-get 'path data)
                                           :authored-text (design-review--authored-text))))
                      (if (equal (alist-get 'fingerprint data) (design-review--source-fingerprint document))
                          "CURRENT" "STALE"))
                  (error "UNAVAILABLE"))))
          (unless (equal status (buffer-substring-no-properties start end))
            (goto-char start)
            (delete-region start end)
            (insert status)))))))

(defun design-review-follow-evidence (_path _argument)
  "Refresh the evidence labels in the current review document."
  (design-review-refresh-evidence)
  (message "Freshness checked against saved Git-listed files and authored requirements; ignored files and external dependencies are outside this snapshot."))

(defun design-review--invalidate-evidence-after-save ()
  "Conservatively mark open review assessments stale after project saves."
  (when buffer-file-name
    (let ((saved buffer-file-name))
      (dolist (buffer (buffer-list))
        (with-current-buffer buffer
          (when (and (derived-mode-p 'org-mode)
                     (save-excursion (goto-char (point-min)) (search-forward "[[design-evidence:" nil t)))
            (save-excursion
              (goto-char (point-min))
              (while (re-search-forward "Evidence freshness: CURRENT \\[\\[design-evidence:\\([^]]+\\)\\]" nil t)
                (let* ((start (match-beginning 0))
                       (data (condition-case nil (design-review--decode-link (match-string-no-properties 1)) (error nil))))
                  (when (and data (file-in-directory-p saved (alist-get 'root data)))
                    (goto-char start)
                    (search-forward "CURRENT")
                    (replace-match "STALE" t t)))))
            (when (equal saved buffer-file-name)
              (design-review-refresh-evidence))))))))

(defun design-review--uncertainties (document)
  "Return graph findings requiring attention, keyed by block and rule."
  (let (items)
    (dolist (check (append (plist-get document :checks) nil))
      (dolist (finding (append (alist-get 'findings (alist-get 'result check)) nil))
        (when (equal (alist-get 'status finding) "UNKNOWN")
          (push `((key . ,(concat (alist-get 'id check) "/" (alist-get 'id finding)))
                  (finding . ,finding)) items))))
    (nreverse items)))

(defun design-review--uncertainty-brief (block document)
  "Give the implementation reviewer deterministic uncertainty to assess."
  (when (equal (plist-get block :language) "implementation-review")
    (concat
     "\n\nDeterministic unresolved findings (do not change their UNKNOWN verdicts):\n"
     (json-encode (vconcat (design-review--uncertainties document)))
     "\nFor each key, add an entry to the final JSON field uncertainty_assessments: "
     "{\"key\":\"exact supplied key\",\"assessment\":\"checked_no_concern|concern|inconclusive\","
     "\"rationale\":\"what you inspected and its limitations\",\"citations\":[{\"file\":\"relative source path\",\"line\":1}]}. "
     "No concern and concern require source citations. Analysis-blocked findings must be inconclusive. "
     "An agent assessment is advisory, never verification. Inspect the linked call sites and candidates; do not assume compatible candidates execute.")))

(defun design-review--uncertainty-context (finding document)
  "Render deterministic FINDING context without an agent's interpretation."
  (let* ((review (alist-get 'review finding))
         (rule (alist-get 'requirement review))
         (lines (list (if (equal (alist-get 'kind review) "analysis_blocked")
                          "  Analysis blocked" "  Review needed"))))
    (when rule
      (push (format "  Requirement: %s %s -> %s"
                    (alist-get 'kind rule) (or (alist-get 'from rule) (alist-get 'symbol rule))
                    (or (alist-get 'to rule) (alist-get 'signature rule) "")) lines))
    (dolist (entry (append (list (alist-get 'caller review) (alist-get 'target review))
                           (append (alist-get 'candidates review) nil)))
      (when (and (alist-get 'id entry) (not (string-empty-p (alist-get 'id entry))))
        (let ((location (alist-get 'location entry)))
          (push (format "  Symbol/candidate: %s %s"
                        (design-review--text (alist-get 'id entry))
                        (or (design-review--location-links document (alist-get 'file location) (alist-get 'line location))
                            "(source unavailable)")) lines))))
    (dolist (gap (append (alist-get 'gaps finding) nil))
      (let ((location (alist-get 'location gap)))
        (when (alist-get 'expression gap)
          (push (format "  Call: %s" (design-review--text (alist-get 'expression gap))) lines))
        (push (format "  Uncertainty: %s%s %s"
                      (design-review--text (alist-get 'reason gap))
                      (if (alist-get 'method gap)
                          (format " (%s %s)" (alist-get 'method gap) (alist-get 'signature gap)) "")
                      (or (design-review--location-links document (alist-get 'file location) (alist-get 'line location)) "")) lines)))
    (dolist (guidance (append (alist-get 'guidance review) nil))
      (push (format "  Inspect: %s" (design-review--text guidance)) lines))
    (dolist (diagnostic (append (alist-get 'diagnostics review) nil))
      (push (format "  Diagnostic: %s" (design-review--text diagnostic)) lines))
    (nreverse lines)))

(defun design-review--valid-citation-p (citation document)
  "Check that CITATION names an existing local project source line."
  (let ((file (and (listp citation) (alist-get 'file citation)))
        (line (and (listp citation) (alist-get 'line citation))))
    (and (stringp file) (not (file-remote-p file)) (not (file-name-absolute-p file))
         (integerp line) (> line 0)
         (let ((path (expand-file-name file (plist-get document :root))))
           (and (file-regular-p path) (file-in-directory-p path (plist-get document :root))
                (with-temp-buffer
                  (insert-file-contents path)
                  (<= line (line-number-at-pos (point-max)))))))))

(defun design-review--format-assessments (run decoded)
  "Pair agent judgements with unchanged deterministic findings from RUN."
  (when (equal (plist-get run :language) "implementation-review")
    (let* ((document (plist-get run :document))
           (entries (alist-get 'uncertainty_assessments decoded))
           (fresh (and (plist-get document :fingerprint)
                       (condition-case nil
                           (equal (plist-get document :fingerprint) (design-review--source-fingerprint document))
                         (error nil))))
           lines)
      (when-let* ((link (design-review--evidence-link document)))
        (push (format "Evidence freshness: %s %s" (if fresh "CURRENT" "STALE") link) lines))
      (dolist (item (design-review--uncertainties document))
        (let* ((key (alist-get 'key item)) (finding (alist-get 'finding item))
               (matches (and (vectorp entries)
                             (seq-filter (lambda (entry) (and (listp entry) (equal (alist-get 'key entry) key))) entries)))
               (answer (and (= (length matches) 1) (elt matches 0)))
               (assessment (alist-get 'assessment answer))
               (citations (alist-get 'citations answer))
               (valid (and answer (member assessment '("checked_no_concern" "concern" "inconclusive"))
                           (or (null citations) (vectorp citations))
                           (stringp (alist-get 'rationale answer))
                           (not (string-empty-p (string-trim (alist-get 'rationale answer))))
                           (or (equal assessment "inconclusive")
                               (and (not (equal (alist-get 'kind (alist-get 'review finding)) "analysis_blocked"))
                                    (vectorp citations) (> (length citations) 0)
                                    (seq-every-p (lambda (citation) (design-review--valid-citation-p citation document)) citations))))))
          (push (format "- Analysis: UNKNOWN [%s] (unchanged)" key) lines)
          (dolist (line (design-review--uncertainty-context finding document)) (push line lines))
          (push (format "  Agent assessment (advisory; applies only while evidence is CURRENT): %s"
                        (cond ((not fresh) "STALE — rerun checks and review")
                              ((not valid) "Inconclusive — missing or invalid assessment/evidence")
                              ((equal assessment "checked_no_concern") "Checked — no concern found")
                              ((equal assessment "concern") "Checked — concern found")
                              (t "Inconclusive"))) lines)
          (when valid
            (push (format "  Rationale: %s" (design-review--text (alist-get 'rationale answer))) lines)
            (dolist (citation (append citations nil))
              (when (design-review--valid-citation-p citation document)
                (push (concat "  Agent evidence: " (design-review--location-links document (alist-get 'file citation) (alist-get 'line citation))) lines))))))
      (nreverse lines))))

(org-link-set-parameters "design-evidence" :follow #'design-review-follow-evidence)
(add-hook 'after-save-hook #'design-review--invalidate-evidence-after-save)
(add-hook 'find-file-hook #'design-review-refresh-evidence)

(provide 'design-review-evidence)
