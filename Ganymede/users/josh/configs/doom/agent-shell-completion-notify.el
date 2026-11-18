;;; agent-shell-completion-notify.el --- Persistent completion alerts -*- lexical-binding: t; -*-

(require 'agent-shell)
(require 'agent-shell-inline)
(require 'notifications)
(require 'xml)

(defvar agent-shell-completion-notify--pending nil
  "Alist of shell buffers and their outstanding desktop notification IDs.")

(defvar-local agent-shell-completion-notify--subscription nil
  "Completion subscription for this shell.")

(defvar-local agent-shell-completion-notify--request nil
  "Token for the latest pending asynchronous notification request.")

(defun agent-shell-completion-notify--close (id)
  "Close ID without waiting for the notification daemon."
  (dbus-call-method-asynchronously
   :session notifications-service notifications-path notifications-interface
   "CloseNotification" #'ignore :timeout 1000 :uint32 id))

(defun agent-shell-completion-notify--notify (ready &rest params)
  "Send PARAMS asynchronously and call READY with the notification ID.
Use the reply's sender for signal dispatch, avoiding a synchronous owner query."
  (dbus-call-method-asynchronously
   :session notifications-service notifications-path notifications-interface
   "Notify"
   (lambda (id)
     (when (integerp id)
       (let ((key (list :session (dbus-event-service-name last-input-event) id)))
         (unless notifications-on-action-object
           (setq notifications-on-action-object
                 (dbus-register-signal :session nil notifications-path notifications-interface
                                       notifications-action-signal #'notifications-on-action-signal)))
         (unless notifications-on-close-object
           (setq notifications-on-close-object
                 (dbus-register-signal :session nil notifications-path notifications-interface
                                       notifications-closed-signal #'notifications-on-closed-signal)))
         (push (list key (plist-get params :on-action)) notifications-on-action-map)
         (push (list key (lambda (closed-id reason)
                           (setq notifications-on-action-map
                                 (assoc-delete-all key notifications-on-action-map))
                           (funcall (plist-get params :on-close) closed-id reason)))
               notifications-on-close-map)
         (funcall ready id))))
   :timeout 1000
   :string (plist-get params :app-name)
   :uint32 (or (plist-get params :replaces-id) 0)
   :string "emacs"
   :string (plist-get params :title)
   :string (plist-get params :body)
   `(:array ,@(plist-get params :actions))
   '(:array (:dict-entry "urgency" (:variant :byte 1)))
   :int32 (plist-get params :timeout)))

(defun agent-shell-completion-notify--previews (shell)
  "Return live inline previews associated with SHELL."
  (let (previews)
    (dolist (buffer (buffer-list))
      (with-current-buffer buffer
        (when agent-shell-inline--response-overlay-mode
          (dolist (overlay (overlays-in (point-min) (point-max)))
            (when (eq shell (plist-get (overlay-get overlay 'agent-shell-inline) :buffer))
              (push overlay previews))))))
    previews))

(defun agent-shell-completion-notify--viewed-p (shell)
  "Whether the focused window is showing SHELL or its current inline reply."
  (let* ((window (selected-window))
         (buffer (window-buffer window)))
    (and (or (not (display-graphic-p)) (frame-focus-state))
         (or (eq buffer shell)
             (eq (agent-shell-viewport--shell-buffer buffer) shell)
             (seq-some
              (lambda (overlay)
                (and (eq (overlay-buffer overlay) buffer)
                     (not (overlay-get overlay 'agent-shell-inline-history-source))
                     (= (or (overlay-get overlay 'agent-shell-inline-interaction-index) -1)
                        (1- (with-current-buffer shell (length (shell-maker-history)))))
                     (pos-visible-in-window-p (overlay-start overlay) window)))
              (agent-shell-completion-notify--previews shell))))))

(defun agent-shell-completion-notify--dismiss (shell)
  "Close only SHELL's outstanding alert."
  (when (buffer-live-p shell)
    (with-current-buffer shell
      (setq agent-shell-completion-notify--request nil)))
  (when-let* ((entry (assq shell agent-shell-completion-notify--pending)))
    (setq agent-shell-completion-notify--pending
          (assq-delete-all shell agent-shell-completion-notify--pending))
    (condition-case err
        (agent-shell-completion-notify--close (cdr entry))
      (error (message "Could not close agent notification: %s" (error-message-string err))))))

(defun agent-shell-completion-notify--dismiss-viewed ()
  "Dismiss alerts whose replies the user has returned to."
  (dolist (entry (copy-sequence agent-shell-completion-notify--pending))
    (when (or (not (buffer-live-p (car entry)))
              (agent-shell-completion-notify--viewed-p (car entry)))
      (agent-shell-completion-notify--dismiss (car entry)))))

(defun agent-shell-completion-notify--visit (shell)
  "Focus Emacs and visit SHELL's inline reply, or its conversation buffer."
  (when (buffer-live-p shell)
    (select-frame-set-input-focus (selected-frame))
    (if-let* ((overlay (car (agent-shell-completion-notify--previews shell))))
        (progn
          (agent-shell-inline-latest-reply overlay)
          (agent-shell-inline--visit-preview overlay))
      (pop-to-buffer-same-window shell))
    ;; i3's smart activation policy does not switch to another workspace.
    (when-let* (((eq window-system 'x))
                (program (executable-find "i3-msg"))
                (id (frame-parameter nil 'outer-window-id))
                ((string-match-p "\\`[0-9]+\\'" id)))
      (let ((socket (getenv "I3SOCK")))
        (make-process
         :name "agent-notification-focus" :buffer nil
         :command (append (list program)
                          (when (and socket (not (string-empty-p socket)))
                            (list "-s" socket))
                          (list (format "[id=%s] focus" id)))
         :noquery t
         :sentinel (lambda (process _event)
                     (when (and (memq (process-status process) '(exit signal))
                                (not (zerop (process-exit-status process))))
                       (message "Could not focus Emacs through i3 (exit %s)"
                                (process-exit-status process))))))))
  (agent-shell-completion-notify--dismiss shell))

(defun agent-shell-completion-notify--finished (event)
  "Notify for a completed agent turn described by EVENT."
  (let ((shell (current-buffer))
        (reason (map-nested-elt event '(:data :stop-reason))))
    (unless (or (equal reason "cancelled")
                (agent-shell-completion-notify--viewed-p shell))
      (condition-case err
          (let ((token (gensym "notification-")))
            (setq agent-shell-completion-notify--request token)
            (agent-shell-completion-notify--notify
             (lambda (id)
               (if (and (buffer-live-p shell)
                        (eq token (buffer-local-value
                                   'agent-shell-completion-notify--request shell))
                        (not (agent-shell-completion-notify--viewed-p shell)))
                   (setf (alist-get shell agent-shell-completion-notify--pending) id)
                 (agent-shell-completion-notify--close id)))
             :app-name "Agent Shell"
             :title "Agent finished"
             :body (xml-escape-string
                    (format "%s\nClick to view the response." (buffer-name shell)))
             :timeout 0
             :urgency 'normal
             :replaces-id (alist-get shell agent-shell-completion-notify--pending)
             :actions '("default" "View response")
             :on-action (lambda (_id _action)
                          (run-at-time 0 nil #'agent-shell-completion-notify--visit shell))
             :on-close (lambda (id _reason)
                         (when (equal id (alist-get shell agent-shell-completion-notify--pending))
                           (setq agent-shell-completion-notify--pending
                                 (assq-delete-all shell agent-shell-completion-notify--pending))))))
        (error (message "Agent finished; notification unavailable: %s" (error-message-string err)))))))

(defun agent-shell-completion-notify--clean-up ()
  "Release this shell's completion subscription and alert."
  (agent-shell-completion-notify--dismiss (current-buffer))
  (when agent-shell-completion-notify--subscription
    (agent-shell-unsubscribe :subscription agent-shell-completion-notify--subscription)
    (setq agent-shell-completion-notify--subscription nil)))

(defun agent-shell-completion-notify--subscribe ()
  "Subscribe once to completion events in the current shell."
  (unless agent-shell-completion-notify--subscription
    (setq agent-shell-completion-notify--subscription
          (agent-shell-subscribe-to :shell-buffer (current-buffer)
                                   :event 'turn-complete
                                   :on-event #'agent-shell-completion-notify--finished)))
  (add-hook 'kill-buffer-hook #'agent-shell-completion-notify--clean-up nil t))

(defun agent-shell-completion-notify--close-all ()
  "Close this Emacs instance's outstanding alerts before exit."
  (dolist (entry (copy-sequence agent-shell-completion-notify--pending))
    (agent-shell-completion-notify--dismiss (car entry))))

(add-hook 'agent-shell-mode-hook #'agent-shell-completion-notify--subscribe)
(add-hook 'post-command-hook #'agent-shell-completion-notify--dismiss-viewed)
(add-hook 'kill-emacs-hook #'agent-shell-completion-notify--close-all)
(add-function :after after-focus-change-function #'agent-shell-completion-notify--dismiss-viewed)

(dolist (buffer (buffer-list))
  (with-current-buffer buffer
    (when (derived-mode-p 'agent-shell-mode)
      (agent-shell-completion-notify--subscribe))))

(provide 'agent-shell-completion-notify)
;;; agent-shell-completion-notify.el ends here
