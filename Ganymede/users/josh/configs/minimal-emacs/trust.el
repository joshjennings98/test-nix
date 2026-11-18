;;; trust.el --- Explicit, persisted project trust -*- lexical-binding: t; -*-

(defvar emacs2-trusted-projects-file
  (expand-file-name "trusted-projects" emacs2-state-directory))
(defvar emacs2-trusted-projects nil)
(defvar-local emacs2-project-untrusted nil)

(defun emacs2-load-project-trust ()
  "Read trusted project directories as data, without evaluating Lisp."
  (when (file-exists-p emacs2-trusted-projects-file)
    (condition-case err
        (let ((directories
               (with-temp-buffer
                 (insert-file-contents emacs2-trusted-projects-file)
                 (read (current-buffer)))))
          (unless (and (proper-list-p directories)
                       (cl-every (lambda (directory)
                                   (and (stringp directory)
                                        (file-name-absolute-p directory)
                                        (not (file-remote-p directory))
                                        (string-suffix-p "/" directory)))
                                 directories))
            (error "Invalid trusted project directories"))
          (setq emacs2-trusted-projects directories)
          (dolist (directory directories)
            (add-to-list 'trusted-content directory)))
      (error (display-warning 'emacs2 (format "Cannot read project trust: %s" err))))))

(defun emacs2-save-project-trust ()
  "Persist explicitly trusted projects in the central state directory."
  (with-temp-file emacs2-trusted-projects-file
    (prin1 emacs2-trusted-projects (current-buffer))
    (insert "\n")))

(defun emacs2-update-project-trust-status ()
  "Cache trust status so mode-line redisplay does not access the filesystem."
  (setq emacs2-project-untrusted
        (and buffer-file-name
             (not (file-remote-p buffer-file-name))
             (or (derived-mode-p 'prog-mode) (bound-and-true-p flymake-mode))
             (not (trusted-content-p))))
  (force-mode-line-update))

(defun emacs2-refresh-project-trust ()
  "Refresh open buffers and retry their Flymake backends after a trust change."
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (let ((was-untrusted emacs2-project-untrusted))
        (emacs2-update-project-trust-status)
        (when (and (bound-and-true-p flymake-mode)
                   (not (eq was-untrusted emacs2-project-untrusted)))
          (if emacs2-project-untrusted
              (progn (flymake-mode -1) (flymake-mode 1))
            (flymake-start nil t)))))))

(defun emacs2-trust-project ()
  "Confirm and remember trust for the current project, then retry diagnostics."
  (interactive)
  (when (or (file-remote-p default-directory) untrusted-content)
    (user-error "Trust projects from an ordinary local file buffer"))
  (let* ((project (project-current nil))
         (directory (and project
                         (abbreviate-file-name
                          (file-name-as-directory (file-truename (project-root project)))))))
    (unless directory
      (user-error "This buffer does not belong to a project"))
    (when (yes-or-no-p
           (format "Trust %s and its contents? Automatic checks may execute project code. " directory))
      (add-to-list 'emacs2-trusted-projects directory)
      (emacs2-save-project-trust)
      (add-to-list 'trusted-content directory)
      (emacs2-refresh-project-trust)
      (message "Trusted project: %s" directory))))

(defun emacs2-untrust-project ()
  "Choose a remembered project and revoke its trust."
  (interactive)
  (unless emacs2-trusted-projects
    (user-error "No remembered trusted projects"))
  (let ((directory (completing-read "Revoke project trust: " emacs2-trusted-projects nil t)))
    (setq emacs2-trusted-projects (delete directory emacs2-trusted-projects))
    (emacs2-save-project-trust)
    (setq trusted-content (delete directory trusted-content))
    (emacs2-refresh-project-trust)
    (message "Revoked trust: %s" directory)))

(require 'cl-lib)
(emacs2-load-project-trust)
(add-hook 'find-file-hook #'emacs2-update-project-trust-status)
(add-hook 'after-change-major-mode-hook #'emacs2-update-project-trust-status 95)
(add-hook 'flymake-mode-hook #'emacs2-update-project-trust-status)
