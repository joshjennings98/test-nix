;;; ob-mermaid.el --- Mermaid argument regression tests -*- lexical-binding: t; -*-

(require 'ert)
(load (getenv "OB_MERMAID_FILE") nil t)

(ert-deftest mermaid-headers-are-literal-arguments ()
  (let* ((directory (make-temp-file "mermaid-arguments-" t))
         (program (expand-file-name "fake mmdc" directory))
         (arguments (expand-file-name "arguments" directory))
         (input (expand-file-name "input" directory))
         (marker (expand-file-name "injected" directory))
         (process-environment (copy-sequence process-environment))
         (ob-mermaid-cli-path program)
         (ob-mermaid-default-config-file nil)
         (payload (format "1; touch %s; $(touch %s)" marker marker)))
    (unwind-protect
        (progn
          (with-temp-file program
            (insert (format "#!%s\nprintf '%%s\\n' \"$@\" > \"$MERMAID_TEST_ARGS\"\ncat > \"$MERMAID_TEST_INPUT\"\n"
                            (executable-find "sh"))))
          (set-file-modes program #o700)
          (setenv "MERMAID_TEST_ARGS" arguments)
          (setenv "MERMAID_TEST_INPUT" input)
          (dolist (header '(:width :height :scale :theme :background-color
                           :file :css-file :mermaid-config-file :puppeteer-config-file))
            (org-babel-execute:mermaid "graph TD; A-->B"
                                      (list (cons header payload) '(:file . "out.svg")))
            (should-not (file-exists-p marker))
            (should (with-temp-buffer
                      (insert-file-contents arguments)
                      (member (if (memq header '(:file :css-file :mermaid-config-file :puppeteer-config-file))
                                  (expand-file-name payload)
                                payload)
                              (split-string (buffer-string) "\n" t)))))
          (org-babel-execute:mermaid "graph TD; A-->B"
                                    `((:file . "diagram with spaces.svg")
                                      (:width . 800) (:scale . 2)
                                      (:cmdline . ,(format "--theme \"dark\" ; touch %s" marker))))
          (should-not (file-exists-p marker))
          (should (equal (with-temp-buffer
                           (insert-file-contents arguments)
                           (split-string (buffer-string) "\n" t))
                         (list "-o" (expand-file-name "diagram with spaces.svg") "-i" "-"
                               "-w" "800" "-s" "2" "--theme" "dark" ";" "touch" marker)))
          (should (equal (with-temp-buffer (insert-file-contents input) (buffer-string))
                         "graph TD; A-->B"))
          (setq ob-mermaid-cli-path (executable-find "false"))
          (should-error (org-babel-execute:mermaid "graph TD" '((:file . "out.svg")))))
      (delete-directory directory t))))

(ert-run-tests-batch-and-exit)
