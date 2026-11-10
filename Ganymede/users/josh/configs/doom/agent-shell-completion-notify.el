;;; agent-shell-completion-notify.el --- Persistent completion alerts -*- lexical-binding: t; -*-

(require 'agent-shell)
(require 'agent-shell-inline)
(require 'notifications)
(require 'xml)

(defvar agent-shell-completion-notify--pending nil
  "Alist of shell buffers and their outstanding desktop notification IDs.")

(defvar-local agent-shell-completion-notify--subscription nil
  "Completion subscription for this shell.")

(defun agent-shell-completion-notify--previews (shell)
  "Return live inline previews associated with SHELL."
  (let (previews)
    (dolist (buffer (buffer-list))
      (with-current-buffer buffer
        (when agent-shell-inline--response-overlay-mode
          (dolist (overlay (append (car (overlay-lists)) (cdr (overlay-lists))))
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
                     (pos-visible-in-window-p (overlay-start overlay) window)))
              (agent-shell-completion-notify--previews shell))))))

(defun agent-shell-completion-notify--dismiss (shell)
  "Close only SHELL's outstanding alert."
  (when-let* ((entry (assq shell agent-shell-completion-notify--pending)))
    (setq agent-shell-completion-notify--pending
          (assq-delete-all shell agent-shell-completion-notify--pending))
    (condition-case err
        (notifications-close-notification (cdr entry))
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
          (agent-shell-inline--show-live overlay)
          (agent-shell-inline--visit-preview overlay))
      (pop-to-buffer-same-window shell)))
  (agent-shell-completion-notify--dismiss shell))

(defun agent-shell-completion-notify--finished (event)
  "Notify for a completed agent turn described by EVENT."
  (let ((shell (current-buffer))
        (reason (map-nested-elt event '(:data :stop-reason))))
    (unless (or (equal reason "cancelled")
                (agent-shell-completion-notify--viewed-p shell))
      (condition-case err
          (when-let* ((id
                       (notifications-notify
                        :app-name "Agent Shell"
                        :title "Agent finished"
                        :body (xml-escape-string
                               (format "%s\nClick to view the response." (buffer-name shell)))
                        :timeout 0
                        :urgency 'normal
                        :replaces-id (alist-get shell agent-shell-completion-notify--pending)
                        :actions '("default" "View response")
                        :on-action (lambda (_id _action)
                                     (agent-shell-completion-notify--visit shell))
                        :on-close (lambda (id _reason)
                                    (when (equal id (alist-get shell agent-shell-completion-notify--pending))
                                      (setq agent-shell-completion-notify--pending
                                            (assq-delete-all shell agent-shell-completion-notify--pending)))))))
            (setf (alist-get shell agent-shell-completion-notify--pending) id))
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
