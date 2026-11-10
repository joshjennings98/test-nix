;;; completion-notify.el --- Completion alert regression tests -*- lexical-binding: t; -*-

(load (expand-file-name "inline.el" (file-name-directory load-file-name)) nil t)
(load (expand-file-name "../agent-shell-completion-notify.el"
                        (file-name-directory load-file-name)) nil t)

(ert-deftest josh/completion-notify-persists-and-clicks-back-to-inline ()
  (let (sent closed
        (agent-shell-completion-notify--pending nil))
    (cl-letf (((symbol-function 'notifications-notify)
               (lambda (&rest args) (setq sent args) 41))
              ((symbol-function 'notifications-close-notification)
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
                (should (eq (current-buffer) source))
                (should (= (point) (overlay-start overlay)))
                (should (equal closed '(41)))
                (should-not agent-shell-completion-notify--pending))
            (kill-buffer elsewhere)))))))

(ert-deftest josh/completion-notify-dismisses-only-the-viewed-shell ()
  (save-window-excursion
    (let ((first (generate-new-buffer " *agent-one*"))
          (second (generate-new-buffer " *agent-two*"))
          agent-shell-completion-notify--pending closed)
      (unwind-protect
          (cl-letf (((symbol-function 'notifications-close-notification)
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
          (cl-letf (((symbol-function 'notifications-notify)
                     (lambda (&rest args) (setq sent args) 22)))
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
          (cl-letf (((symbol-function 'notifications-close-notification)
                     (lambda (id) (setq closed id)))
                    ((symbol-function 'select-frame-set-input-focus) #'ignore))
            (setq agent-shell-completion-notify--pending (list (cons shell 7)))
            (agent-shell-completion-notify--visit shell)
            (should (eq (current-buffer) shell))
            (should (= closed 7)))
        (kill-buffer shell)))))

(ert-deftest josh/completion-notify-does-not-alert-for-viewed-or-cancelled-turns ()
  (save-window-excursion
    (with-temp-buffer
      (switch-to-buffer (current-buffer))
      (cl-letf (((symbol-function 'notifications-notify)
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
            (cl-letf (((symbol-function 'notifications-close-notification)
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
                  ((symbol-function 'notifications-close-notification)
                   (lambda (_) (ert-fail "Closed an unread alert"))))
          (agent-shell-completion-notify--dismiss-viewed)
          (should agent-shell-completion-notify--pending))))))
