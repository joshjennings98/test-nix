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
(provide 'design-review-fontification)
