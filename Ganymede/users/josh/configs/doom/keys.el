;;; keys.el -*- lexical-binding: t; -*-

(defun josh/gptel-visit-conversation ()
  "Visit the conversation associated with the prompt or inline response."
  (interactive)
  (require 'gptel-inline)
  (let* ((overlay (gptel-inline--response-overlay-at-point))
         (base (buffer-base-buffer))
         (chat (cond
                (overlay (plist-get (overlay-get overlay 'gptel-inline) :buffer))
                ((and base (buffer-local-value 'gptel-mode base)) base)
                (gptel-mode (current-buffer))
                (t (get-buffer (car (ensure-list
                                     (gptel-inline-chat-buffer-name (current-buffer)))))))))
    (unless (buffer-live-p chat)
      (user-error "No conversation yet; start one with SPC a p"))
    (gptel-inline-visit-buffer chat)
    (evil-normal-state)))

;; Internal commands below are tied to the pinned package versions.
(dolist (command '(gptel-inline-cycle-reference gptel-inline-append
                   gptel-inline-switch-buffer gptel-inline-help
                   gptel-inline--response-overlay-dispatch
                   gptel-inline--response-overlay-down
                   gptel-inline--response-overlay-up
                   gptel-inline--response-overlay-pagedown
                   gptel-inline--response-overlay-pageup))
  (autoload command "gptel-inline" nil t))

(dolist (command '(gptel--rewrite-dispatch gptel--rewrite-accept
                   gptel--rewrite-iterate gptel--rewrite-reject
                   gptel--rewrite-diff gptel--rewrite-ediff
                   gptel--rewrite-next gptel--rewrite-previous gptel--rewrite-merge))
  (autoload command "gptel-rewrite" nil t))

(dolist (command '(gptel-agent--next-overlay gptel-agent--previous-overlay
                   gptel-agent-toggle-todos))
  (autoload command "gptel-agent-tools" nil t))

(autoload 'gptel--suffix-context-buffer "gptel-transient" nil t)

(defun josh/gptel-local-action (key)
  "Invoke KEY's action in the current gptel interface, preserving its context."
  (let ((command (key-binding (kbd key))))
    ;; Never fall through to an unrelated mode's C-c command (e.g. Org).
    (unless (and (commandp command)
                 (or (memq command '(gptel-inline-quit
                                     gptel-inline--accept-tool-calls
                                     gptel-inline--reject-tool-calls
                                     gptel--accept-tool-calls gptel--reject-tool-calls
                                     gptel--inspect-tool-calls
                                     gptel--inspect-accept-tool-calls
                                     gptel--inspect-reject-tool-calls
                                     gptel--inspect-quit-tool-calls
                                     gptel-context-confirm gptel-context-quit
                                     gptel-agent--cycle-overlay
                                     gptel-agent-toggle-todos gptel-markdown-cycle-block
                                     gptel--continue-query))
                     ;; These editors install buffer-local closures for their actions.
                     (member (buffer-name) '("*gptel-prompt*" "*gptel-query*"))))
      (user-error "No gptel action for %s here" key))
    (call-interactively command)))

(map! :leader
      (:prefix ("a" . "agent")
       :desc "Discuss inline" "p" #'gptel-inline
       :desc "Open gptel agent" "g" #'gptel-agent
       :desc "Visit conversation" "v" #'josh/gptel-visit-conversation
       :desc "Response actions" "o" #'gptel-inline--response-overlay-dispatch
       :desc "Send prompt" "s" #'gptel-send
       :desc "Request options" "m" #'gptel-menu
       :desc "Cycle inline reference" "c" #'gptel-inline-cycle-reference
       :desc "Append without sending" "a" #'gptel-inline-append
       :desc "Switch conversation" "b" #'gptel-inline-switch-buffer
       :desc "Inline help" "h" #'gptel-inline-help
       :desc "Fold block / tool at point" "f" (cmd! (josh/gptel-local-action "TAB"))
       :desc "Return from conversation" "u" #'keyboard-quit
       :desc "Confirm current action" "RET" (cmd! (josh/gptel-local-action "C-c C-c"))
       :desc "Cancel current action" "q" (cmd! (josh/gptel-local-action "C-c C-k"))
       :desc "Inspect tools / return" "i" (cmd! (josh/gptel-local-action "C-c C-i"))
       :desc "Copy inspected query as curl" "y" (cmd! (josh/gptel-local-action "C-c C-w"))
       :desc "Rewrite selection / options" "r" #'gptel-rewrite
       :desc "System instructions" "d" #'gptel-system-prompt
       :desc "Inspect context" "C" #'gptel--suffix-context-buffer
       :desc "Load / save preset" "@" #'gptel-preset
       :desc "Preview down" "j" #'gptel-inline--response-overlay-down
       :desc "Preview up" "k" #'gptel-inline--response-overlay-up
       :desc "Preview page down" "J" #'gptel-inline--response-overlay-pagedown
       :desc "Preview page up" "K" #'gptel-inline--response-overlay-pageup
       (:prefix ("R" . "rewrite review")
        :desc "Actions at point" "o" #'gptel--rewrite-dispatch
        :desc "Accept" "a" #'gptel--rewrite-accept
        :desc "Iterate" "r" #'gptel--rewrite-iterate
        :desc "Reject" "q" #'gptel--rewrite-reject
        :desc "Diff" "d" #'gptel--rewrite-diff
        :desc "Ediff" "e" #'gptel--rewrite-ediff
        :desc "Merge" "m" #'gptel--rewrite-merge
        :desc "Next rewrite" "j" #'gptel--rewrite-next
        :desc "Previous rewrite" "k" #'gptel--rewrite-previous)
       (:prefix ("t" . "tools")
        :desc "Select tools" "t" #'gptel-tools
        :desc "Next tool" "j" #'gptel-agent--next-overlay
        :desc "Previous tool" "k" #'gptel-agent--previous-overlay
        :desc "Toggle task list" "T" #'gptel-agent-toggle-todos
        :desc "Approve pending tools" "a" (cmd! (josh/gptel-local-action "C-c C-c"))
        :desc "Reject pending tools" "q" (cmd! (josh/gptel-local-action "C-c C-k"))
        :desc "Inspect / return" "i" (cmd! (josh/gptel-local-action "C-c C-i")))))

(after! gptel-inline
  ;; Keep C-c RET for sending from the prompt, not opening response actions.
  (keymap-unset gptel-inline--response-overlay-mode-map "M-RET")
  (keymap-unset gptel-inline--response-overlay-mode-map "M-<return>")
  (keymap-set gptel-inline--response-overlay-mode-map
              "C-c C-o" #'gptel-inline--response-overlay-dispatch))

(after! (gptel-context evil)
  (evil-set-initial-state 'gptel-context-buffer-mode 'normal)
  (evil-define-key 'normal gptel-context-buffer-mode-map
    (kbd "j") #'gptel-context-next
    (kbd "k") #'gptel-context-previous
    (kbd "RET") #'gptel-context-visit
    (kbd "d") #'gptel-context-flag-deletion
    (kbd "q") #'gptel-context-quit))

(after! (gptel-agent evil)
  (defun josh/gptel-tool-preview-keys (overlay)
    "Add normal-state navigation to a newly created tool preview OVERLAY."
    ;; Overlay keymaps are not mode maps, so Evil's auxiliary maps do not apply.
    (dolist (binding '(("j" . gptel-agent--next-overlay)
                       ("k" . gptel-agent--previous-overlay)
                       ("TAB" . gptel-agent--cycle-overlay)
                       ("<tab>" . gptel-agent--cycle-overlay)))
      (define-key (overlay-get overlay 'keymap) (kbd (car binding))
                  `(menu-item "" ,(cdr binding)
                              :filter ,(lambda (command)
                                         (and (evil-normal-state-p) command)))))
    overlay)
  (advice-add 'gptel-agent--confirm-overlay :filter-return
              #'josh/gptel-tool-preview-keys))
