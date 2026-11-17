;;; completion-notify.el --- Completion alert regression tests -*- lexical-binding: t; -*-

(load (expand-file-name "inline.el" (file-name-directory load-file-name)) nil t)
(load (expand-file-name "../agent-shell-completion-notify.el"
                        (file-name-directory load-file-name)) nil t)

(ert-deftest josh/completion-notify-transport-never-waits-for-daemon ()
  (let (calls ready-id
        (sender ":1.42")
        notifications-on-action-object notifications-on-close-object
        notifications-on-action-map notifications-on-close-map)
    (cl-letf (((symbol-function 'dbus-call-method)
               (lambda (&rest _) (ert-fail "Synchronous D-Bus call")))
              ((symbol-function 'dbus-get-name-owner)
               (lambda (&rest _) (ert-fail "Synchronous name lookup")))
              ((symbol-function 'dbus-register-signal)
               (lambda (&rest _) (setq sender "org.freedesktop.DBus") 'registered))
              ((symbol-function 'dbus-event-service-name) (lambda (_) sender))
              ((symbol-function 'dbus-call-method-asynchronously)
               (lambda (&rest args) (push args calls))))
      (agent-shell-completion-notify--notify
       (lambda (id) (setq ready-id id))
       :app-name "Agent Shell" :title "Done" :body "Done"
       :actions '("default" "View response") :timeout 0
       :on-action #'ignore :on-close #'ignore)
      (should-not ready-id)
      (should (equal (nth 4 (car calls)) "Notify"))
      (funcall (nth 5 (car calls)) 42)
      (should (= ready-id 42))
      (should (assoc '(:session ":1.42" 42) notifications-on-action-map))
      (agent-shell-completion-notify--close 42)
      (should (equal (nth 4 (car calls)) "CloseNotification")))))

(ert-deftest josh/completion-notify-discards-late-replies-after-dismissal ()
  (with-temp-buffer
    (let (ready closed agent-shell-completion-notify--pending)
      (cl-letf (((symbol-function 'agent-shell-completion-notify--notify)
                 (lambda (callback &rest _) (setq ready callback)))
                ((symbol-function 'agent-shell-completion-notify--close)
                 (lambda (id) (push id closed)))
                ((symbol-function 'agent-shell-completion-notify--viewed-p)
                 (lambda (_) nil)))
        (agent-shell-completion-notify--finished '((:data . ((:stop-reason . "end_turn")))))
        (agent-shell-completion-notify--dismiss (current-buffer))
        (funcall ready 43)
        (should (equal closed '(43)))
        (should-not agent-shell-completion-notify--pending)))))

(ert-deftest josh/completion-notify-persists-and-clicks-back-to-inline ()
  (let (sent closed
        (agent-shell-completion-notify--pending nil))
    (cl-letf (((symbol-function 'agent-shell-completion-notify--notify)
               (lambda (ready &rest args) (setq sent args) (funcall ready 41)))
              ((symbol-function 'agent-shell-completion-notify--close)
               (lambda (id) (push id closed)))
              ((symbol-function 'select-frame-set-input-focus) #'ignore))
      (josh/with-inline-agent
        (let ((elsewhere (generate-new-buffer " *flashcard-review*"))
              (overlay (agent-shell-inline-message "background work" shell)))
          (unwind-protect
              (progn
                (switch-to-buffer elsewhere)
                (josh/inline-wait (lambda () sent))
                (should (eq (current-buffer) elsewhere))
                (should (= (plist-get sent :timeout) 0))
                (should (equal (plist-get sent :actions) '("default" "View response")))
                (should (= (alist-get shell agent-shell-completion-notify--pending) 41))
                (agent-shell-completion-notify--dismiss-viewed)
                (should-not closed)
                (funcall (plist-get sent :on-action) 41 "default")
                (should (eq (current-buffer) elsewhere))
                (josh/inline-wait (lambda () (eq (window-buffer) source)))
                (should (= (window-point) (overlay-start overlay)))
                (should (equal closed '(41)))
                (should-not agent-shell-completion-notify--pending))
            (kill-buffer elsewhere)))))))

(ert-deftest josh/completion-notify-dismisses-only-the-viewed-shell ()
  (save-window-excursion
    (let ((first (generate-new-buffer " *agent-one*"))
          (second (generate-new-buffer " *agent-two*"))
          agent-shell-completion-notify--pending closed)
      (unwind-protect
          (cl-letf (((symbol-function 'agent-shell-completion-notify--close)
                     (lambda (id) (push id closed))))
            (setq agent-shell-completion-notify--pending (list (cons first 1) (cons second 2)))
            (switch-to-buffer first)
            (agent-shell-completion-notify--dismiss-viewed)
            (should (equal closed '(1)))
            (should (equal agent-shell-completion-notify--pending (list (cons second 2)))))
        (kill-buffer first)
        (kill-buffer second)))))

(ert-deftest josh/completion-notify-replaces-alert-and-handles-manual-dismissal ()
  (save-window-excursion
    (let ((shell (generate-new-buffer " *completed-agent*"))
          agent-shell-completion-notify--pending sent)
      (unwind-protect
          (cl-letf (((symbol-function 'agent-shell-completion-notify--notify)
                     (lambda (ready &rest args) (setq sent args) (funcall ready 22))))
            (setq agent-shell-completion-notify--pending (list (cons shell 11)))
            (with-current-buffer shell
              (agent-shell-completion-notify--finished '((:data . ((:stop-reason . "end_turn"))))))
            (should (= (plist-get sent :replaces-id) 11))
            (funcall (plist-get sent :on-close) 11 'close-notification)
            (should (= (alist-get shell agent-shell-completion-notify--pending) 22))
            (funcall (plist-get sent :on-close) 22 'dismissed)
            (should-not agent-shell-completion-notify--pending))
        (kill-buffer shell)))))

(ert-deftest josh/completion-notify-click-falls-back-to-shell ()
  (save-window-excursion
    (let ((shell (generate-new-buffer " *agent-without-preview*"))
          agent-shell-completion-notify--pending closed)
      (unwind-protect
          (cl-letf (((symbol-function 'agent-shell-completion-notify--close)
                     (lambda (id) (setq closed id)))
                    ((symbol-function 'select-frame-set-input-focus) #'ignore))
            (setq agent-shell-completion-notify--pending (list (cons shell 7)))
            (agent-shell-completion-notify--visit shell)
            (should (eq (current-buffer) shell))
            (should (= closed 7)))
        (kill-buffer shell)))))

(ert-deftest josh/completion-notify-click-focuses-i3-window-asynchronously ()
  (save-window-excursion
    (with-temp-buffer
      (let ((window-system 'x)
            (process-environment (cons "I3SOCK=/tmp/test-i3-socket" process-environment))
            (original-frame-parameter (symbol-function 'frame-parameter))
            command)
        (cl-letf (((symbol-function 'agent-shell-completion-notify--previews) #'ignore)
                  ((symbol-function 'agent-shell-completion-notify--dismiss) #'ignore)
                  ((symbol-function 'select-frame-set-input-focus) #'ignore)
                  ((symbol-function 'frame-parameter)
                   (lambda (frame parameter)
                     (if (eq parameter 'outer-window-id)
                         "12345"
                       (funcall original-frame-parameter frame parameter))))
                  ((symbol-function 'executable-find) (lambda (_) "/bin/i3-msg"))
                  ((symbol-function 'make-process)
                   (lambda (&rest args) (setq command (plist-get args :command)))))
          (agent-shell-completion-notify--visit (current-buffer))
          (should (equal command '("/bin/i3-msg" "-s" "/tmp/test-i3-socket" "[id=12345] focus")))
          (dolist (socket '(nil ""))
            (setenv "I3SOCK" socket)
            (setq command nil)
            (agent-shell-completion-notify--visit (current-buffer))
            (should (equal command '("/bin/i3-msg" "[id=12345] focus")))))))))

(ert-deftest josh/completion-notify-does-not-alert-for-viewed-or-cancelled-turns ()
  (save-window-excursion
    (with-temp-buffer
      (switch-to-buffer (current-buffer))
      (cl-letf (((symbol-function 'agent-shell-completion-notify--notify)
                 (lambda (&rest _) (ert-fail "Unexpected alert"))))
        (agent-shell-completion-notify--finished '((:data . ((:stop-reason . "end_turn")))))
        (with-temp-buffer
          (agent-shell-completion-notify--finished '((:data . ((:stop-reason . "cancelled"))))))))))

(ert-deftest josh/completion-notify-preview-must-be-visible-and-current ()
  (skip-unless (not noninteractive))
  (save-window-excursion
    (with-temp-buffer
      (switch-to-buffer (current-buffer))
      (dotimes (i 100) (insert (format "Line %d\n" i)))
      (goto-char (point-min))
      (forward-line 80)
      (let* ((shell (generate-new-buffer " *preview-agent*"))
             (overlay (agent-shell-inline--setup-response-overlay
                       (list :marker (point-marker) :buffer shell)))
             (agent-shell-completion-notify--pending (list (cons shell 31)))
             closed)
        (unwind-protect
            (cl-letf (((symbol-function 'agent-shell-completion-notify--close)
                       (lambda (id) (setq closed id))))
              (goto-char (point-min))
              (set-window-start nil (point-min))
              (agent-shell-completion-notify--dismiss-viewed)
              (should-not closed)
              (agent-shell-inline--visit-preview overlay)
              (overlay-put overlay 'agent-shell-inline-history-source (current-buffer))
              (agent-shell-completion-notify--dismiss-viewed)
              (should-not closed)
              (overlay-put overlay 'agent-shell-inline-history-source nil)
              (agent-shell-completion-notify--dismiss-viewed)
              (should (= closed 31)))
          (overlay-put overlay 'agent-shell-inline-history-source nil)
          (agent-shell-inline-clear-response-overlay overlay)
          (kill-buffer shell))))))

(ert-deftest josh/completion-notify-unfocused-frame-keeps-alert ()
  (save-window-excursion
    (with-temp-buffer
      (switch-to-buffer (current-buffer))
      (let ((agent-shell-completion-notify--pending (list (cons (current-buffer) 42))))
        (cl-letf (((symbol-function 'display-graphic-p) (lambda (&optional _) t))
                  ((symbol-function 'frame-focus-state) (lambda (&optional _) nil))
                  ((symbol-function 'agent-shell-completion-notify--close)
                   (lambda (_) (ert-fail "Closed an unread alert"))))
          (agent-shell-completion-notify--dismiss-viewed)
          (should agent-shell-completion-notify--pending))))))
