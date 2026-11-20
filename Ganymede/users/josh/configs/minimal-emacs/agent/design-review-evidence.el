;;; design-review-evidence.el --- Freshness of advisory assessments -*- lexical-binding: t; -*-

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

(defun design-review--format-assessments (run _decoded)
  "Report freshness for every advisory assessment in RUN."
  (let* ((document (plist-get run :document))
         (fresh (condition-case nil (design-review--run-current-p run) (error nil))))
    (when-let* ((link (design-review--evidence-link document)))
      (list (format "Evidence freshness: %s %s" (if fresh "CURRENT" "STALE") link)))))

(org-link-set-parameters "design-evidence" :follow #'design-review-follow-evidence)
(add-hook 'after-save-hook #'design-review--invalidate-evidence-after-save)
(add-hook 'find-file-hook #'design-review-refresh-evidence)
(provide 'design-review-evidence)
