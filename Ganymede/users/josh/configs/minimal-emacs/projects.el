;;; projects.el --- Discover projects in Documents -*- lexical-binding: t; -*-

(defvar emacs2-projects-directory (expand-file-name "~/Documents/")
  "Directory whose immediate subdirectories are projects.")

(defun emacs2-document-project (directory)
  "Recognise a project folder below `emacs2-projects-directory'."
  (unless (file-remote-p directory)
    (let* ((parent (file-name-as-directory emacs2-projects-directory))
           (directory (file-name-as-directory (expand-file-name directory))))
      (when (and (string-prefix-p parent directory)
                 (not (equal parent directory)))
        (let ((name (car (split-string (file-relative-name directory parent) "/" t))))
          (cons 'transient (file-name-as-directory (expand-file-name name parent))))))))

(defun emacs2-discover-projects (&rest _)
  "Remember the folders in Documents without visiting their files."
  (when (file-directory-p emacs2-projects-directory)
    (dolist (directory (directory-files emacs2-projects-directory t directory-files-no-dot-files-regexp))
      (when (file-directory-p directory)
        (project-remember-project
         (cons 'transient (file-name-as-directory directory)) t)))))

;; Prefer normal version-control backends when the folder is a repository.
(add-hook 'project-find-functions #'emacs2-document-project 90)
(add-hook 'emacs-startup-hook #'emacs2-discover-projects)
(advice-add 'project-prompt-project-dir :before #'emacs2-discover-projects)
