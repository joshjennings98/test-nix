;;; emacs-smoke.el --- Offline broker configuration checks -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'gptel)
(require 'gptel-agent)

;; Evaluate the two package configuration forms from the real Doom config.
(with-temp-buffer
  (insert-file-contents
   (expand-file-name "../config.el"
                     (file-name-directory load-file-name)))
  (goto-char (point-min))
  (condition-case nil
      (while t
        (let ((form (read (current-buffer))))
          (when (and (eq (car-safe form) 'use-package!)
                     (memq (cadr form) '(gptel gptel-agent)))
            (eval (cons 'progn (cdr (memq :config form))) t))))
    (end-of-file nil)))

(cl-assert (equal (gptel-backend-url gptel-backend)
                  "http://127.0.0.1:8123/openai/responses"))
(cl-assert (null (gptel-backend-header gptel-backend)))
(cl-assert (null (gptel-backend-key gptel-backend)))
(cl-assert (eq gptel-model 'gpt-5.6-sol))

(let (fetched)
  (cl-letf (((symbol-function 'gptel-agent--fetch-with-timeout)
             (lambda (url &rest _) (setq fetched url))))
    (gptel-agent--read-url #'ignore "https://go.dev/doc/?synthetic=1")
    (cl-assert
     (equal fetched
            "http://127.0.0.1:8123/page?url=https%3A%2F%2Fgo.dev%2Fdoc%2F%3Fsynthetic%3D1"))
    (let ((gptel-agent--web-search-active nil))
      (gptel-agent--web-search-eww #'ignore "synthetic search")
      (cl-assert (equal fetched "http://127.0.0.1:8123/search?q=synthetic%20search")))))

(princ "PASS: packaged gptel has no credential header/key; agent fetch and search use the broker.\n")
