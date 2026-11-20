;;; navigation.el --- MCP navigation checks -*- lexical-binding: t; -*-
(require 'ert)
(load (expand-file-name "../agent-shell-navigation.el"
                        (file-name-directory (or load-file-name buffer-file-name))) nil t)

(ert-deftest josh/navigation-switch-preserves-agent-window ()
  (save-window-excursion
    (let ((agent (generate-new-buffer "*agent-shell-navigation-test*"))
          (source (generate-new-buffer "navigation-source")))
      (unwind-protect
          (progn
            (delete-other-windows)
            (switch-to-buffer agent)
            (with-current-buffer source (insert "First\nSecond\nThird\n"))
            (let ((agent-window (selected-window)))
              (agent-shell-navigation-switch-buffer
               `((buffer . ,(buffer-name source)) (line . 2) (column . 3)))
              (should (eq (window-buffer agent-window) agent))
              (should (eq (window-buffer (selected-window)) source))
              (should (= (line-number-at-pos) 2))
              (should (= (current-column) 2))
              (should (= (length (window-list)) 2))))
        (kill-buffer agent)
        (kill-buffer source)))))

(ert-deftest josh/navigation-open-file-reuses-source-window ()
  (save-window-excursion
    (let ((file (make-temp-file "navigation-" nil ".txt" "First\nSecond\n"))
          (agent (generate-new-buffer "*agent-shell-navigation-test*"))
          (source (generate-new-buffer "navigation-source"))
          file-buffer)
      (unwind-protect
          (progn
            (delete-other-windows)
            (switch-to-buffer source)
            (let ((source-window (selected-window))
                  (agent-window (split-window-below)))
              (select-window agent-window)
              (switch-to-buffer agent)
              (agent-shell-navigation-open-file `((path . ,file) (line . 2)))
              (setq file-buffer (current-buffer))
              (should (eq (selected-window) source-window))
              (should (equal buffer-file-name file))
              (should (= (line-number-at-pos) 2))
              (should (eq (window-buffer agent-window) agent))
              (should (= (length (window-list)) 2))))
        (when file-buffer (kill-buffer file-buffer))
        (kill-buffer agent)
        (kill-buffer source)
        (delete-file file)))))

(ert-deftest josh/navigation-rejects-invalid-targets ()
  (let ((original (current-buffer)))
    (should-error (agent-shell-navigation-open-file '((path . "relative.el"))))
    (should-error (agent-shell-navigation-switch-buffer '((buffer . "missing-navigation-buffer"))))
    (should-error (agent-shell-navigation-switch-buffer
                   `((buffer . ,(buffer-name)) (line . 0))))
    (should-error (agent-shell-navigation-switch-buffer
                   `((buffer . ,(buffer-name)) (column . "2"))))
    (should (eq (current-buffer) original))))

(ert-deftest josh/navigation-lists-exact-buffer-names ()
  (with-temp-buffer
    (rename-buffer "navigation-visible" t)
    (let ((buffers (json-read-from-string (agent-shell-navigation-list-buffers nil))))
      (should (seq-find (lambda (entry)
                         (equal (alist-get 'buffer entry) (buffer-name))) buffers)))))
