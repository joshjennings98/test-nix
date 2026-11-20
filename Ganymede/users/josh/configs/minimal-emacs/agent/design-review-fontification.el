;;; design-review-fontification.el --- Review result presentation -*- lexical-binding: t; -*-
(require 'org)
(defface design-review-unplanned-face '((t (:inherit warning :weight bold)))
  "Changes identified as outside the authored plan." :group 'org)

(defun design-review--match-unplanned-finding (limit)
  "Find an explicitly unplanned finding in a results drawer before LIMIT."
  (catch 'found
    (while (re-search-forward "^[ \t]*- \\(?:PASS\\|REVIEW\\|FAIL\\|UNKNOWN\\) \\[outside plan\\]:.*$" limit t)
      (let ((match (match-data)))
        (when (save-match-data
                (let ((drawer (org-element-lineage (org-element-context) '(drawer) t)))
                  (and drawer (equal (org-element-property :drawer-name drawer) "RESULTS"))))
          (set-match-data match)
          (throw 'found t))))))

(defun design-review--fontify-results ()
  "Highlight explicit outside-plan findings in result drawers."
  (font-lock-add-keywords nil
                         '((design-review--match-unplanned-finding
                            (0 'design-review-unplanned-face prepend))) 'append))
(add-hook 'org-mode-hook #'design-review--fontify-results)

(defface design-review-added-face '((t (:foreground "#8ec07c")))
  "Added plan lines." :group 'org)
(defface design-review-removed-face '((t (:foreground "#fb4934")))
  "Removed plan lines." :group 'org)
(defface design-review-comment-face '((t (:inherit shadow)))
  "Explanatory annotations within a plan." :group 'org)
(defface design-review-marker-face '((t (:background "#fabd2f" :foreground "#282828")))
  "Selected words emphasised with ==markers==." :group 'org)
(defface design-review-section-face '((t (:inherit font-lock-function-name-face :weight bold)))
  "Short section labels within a feature plan." :group 'org)

(define-derived-mode design-review-plan-mode text-mode "Feature plan"
  "Readable review specifications; bodies are never application code.
Use @@ labels, leading + or - changes, // or # annotations and ==emphasis==."
  (setq-local font-lock-defaults
              '((("^[ \t]*[+].*$" (0 'design-review-added-face))
                 ("^[ \t]*-.*$" (0 'design-review-removed-face))
                 ("^[ \t]*@@ .*$" (0 'design-review-section-face t))
                 ("\\(?:^\\|[ \t]\\)\\(//.*\\|#.*\\)$" (1 'design-review-comment-face t))
                 ("==\\([^=\n]+\\)==" (0 'design-review-marker-face prepend))) t)))

(with-eval-after-load 'org
  (setf (alist-get "plan-review" org-src-lang-modes nil nil #'equal) 'design-review-plan)
  (setf (alist-get "design-graph" org-src-lang-modes nil nil #'equal) 'design-review-plan))

(provide 'design-review-fontification)
