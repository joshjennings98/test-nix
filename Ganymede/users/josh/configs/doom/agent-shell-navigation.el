;;; agent-shell-navigation.el --- Navigate Emacs through MCP -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'json)
(require 'seq)
(require 'subr-x)

(defun agent-shell-navigation--source-window-p (window)
  "Return non-nil when WINDOW can display a navigation result."
  (and (not (window-minibuffer-p window))
       (not (window-dedicated-p window))
       (not (window-parameter window 'window-side))
       (with-current-buffer (window-buffer window)
         (not (or (derived-mode-p 'agent-shell-mode
                                  'agent-shell-viewport-view-mode
                                  'agent-shell-viewport-edit-mode
                                  'agent-shell-inline-prompt-mode)
                  (string-prefix-p "*agent-shell" (buffer-name)))))))

(defun agent-shell-navigation--show (buffer args)
  "Display BUFFER at the optional one-based line and column in ARGS."
  (let ((line (alist-get 'line args))
        (column (alist-get 'column args)))
    (dolist (value (list line column))
      (unless (or (null value) (and (integerp value) (> value 0)))
        (user-error "Line and column must be positive integers")))
    (let* ((windows (window-list (selected-frame) 'nomini))
           (window (or (seq-find (lambda (win)
                                   (and (eq (window-buffer win) buffer)
                                        (agent-shell-navigation--source-window-p win)))
                                 windows)
                       (seq-find #'agent-shell-navigation--source-window-p windows)
                       (split-window (frame-selected-window) nil 'below))))
      (select-window window)
      (switch-to-buffer buffer)
      (widen)
      (when line
        (goto-char (point-min))
        (forward-line (1- line)))
      (when column (move-to-column (1- column)))
      (recenter)
      (json-encode `((buffer . ,(buffer-name))
                     (file . ,buffer-file-name)
                     (line . ,(line-number-at-pos))
                     (column . ,(1+ (current-column))))))))

(defun agent-shell-navigation-open-file (args)
  "Open the existing absolute file path in ARGS and show its location."
  (let ((path (alist-get 'path args)))
    (unless (and (stringp path) (file-name-absolute-p path)
                 (not (file-remote-p path)) (file-regular-p path))
      (user-error "Provide an absolute path to an existing local file"))
    (agent-shell-navigation--show (find-file-noselect path) args)))

(defun agent-shell-navigation-switch-buffer (args)
  "Show the existing buffer named in ARGS, optionally at a location."
  (let* ((name (alist-get 'buffer args))
         (buffer (and (stringp name) (get-buffer name))))
    (unless buffer (user-error "No buffer named %s" name))
    (agent-shell-navigation--show buffer args)))

(defun agent-shell-navigation-list-buffers (_args)
  "List user-visible buffers and their file names."
  (json-encode
   (vconcat
    (cl-loop for buffer in (buffer-list)
             unless (string-prefix-p " " (buffer-name buffer))
             collect (with-current-buffer buffer
                       `((buffer . ,(buffer-name)) (file . ,buffer-file-name)
                         (mode . ,(symbol-name major-mode))))))))

(defun agent-shell-navigation-connect ()
  "Start the local MCP server if needed and return its socat arguments."
  (require 'mcp-server)
  (setq mcp-server-emacs-tools-enabled '(open_file switch_buffer list_buffers))
  (let ((position-properties
         '((line . ((type . "integer") (minimum . 1)
                    (description . "One-based line number to centre")))
           (column . ((type . "integer") (minimum . 1)
                      (description . "One-based display column"))))))
    (dolist (entry
             `(("open_file" "Open a file in Emacs"
                "Take the user to an existing local file. Use this after finding code the user wants to see. Preserves agent windows and centres the location."
                ((type . "object")
                 (properties . ((path . ((type . "string") (description . "Absolute file path")))
                                ,@position-properties))
                 (required . ["path"]))
                agent-shell-navigation-open-file)
               ("switch_buffer" "Switch Emacs buffer"
                "Take the user to an existing named buffer, optionally at a line and column. Use list_buffers to discover exact names."
                ((type . "object")
                 (properties . ((buffer . ((type . "string") (description . "Exact buffer name")))
                                ,@position-properties))
                 (required . ["buffer"]))
                agent-shell-navigation-switch-buffer)
               ("list_buffers" "List Emacs buffers"
                "List open buffers with their file paths and modes for navigation."
                ((type . "object") (properties . ,(make-hash-table)))
                agent-shell-navigation-list-buffers)))
      (mcp-server-register-tool
       (make-mcp-server-tool :name (nth 0 entry) :title (nth 1 entry)
                             :description (nth 2 entry) :input-schema (nth 3 entry)
                             :function (nth 4 entry)))))
  (unless mcp-server-running
    (setq mcp-server-socket-directory
          (expand-file-name (format "emacs-navigation-%s" (user-uid))
                            (or (getenv "XDG_RUNTIME_DIR") temporary-file-directory))
          mcp-server-socket-name 'session)
    (make-directory mcp-server-socket-directory t)
    (set-file-modes mcp-server-socket-directory #o700)
    (mcp-server-start-unix))
  (list "-" (concat "UNIX-CONNECT:" (mcp-server-get-socket-path))))

(provide 'agent-shell-navigation)
;;; agent-shell-navigation.el ends here
