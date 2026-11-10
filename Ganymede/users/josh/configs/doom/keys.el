;;; keys.el -*- lexical-binding: t; -*-

(when (keymapp (lookup-key doom-leader-map (kbd "f")))
  (define-key doom-leader-map (kbd "F") (lookup-key doom-leader-map (kbd "f"))))
(when (commandp (lookup-key doom-leader-map (kbd "SPC")))
  (define-key doom-leader-map (kbd "f") (lookup-key doom-leader-map (kbd "SPC"))))
(define-key doom-leader-map (kbd "SPC") nil)

(map! :leader
      :desc "Review all flashcards" "r" #'org-fc-review-all
      :desc "Edit flashcards" "R" #'josh/org-fc-edit)

(after! org
  (map! :map org-mode-map
        :localleader
        :desc "Flashcards" "F" #'org-fc-transient))

(after! (org-fc evil)
  ;; The bundled demo still documents n as the flip key.
  (define-key org-fc-review-flip-mode-map (kbd "n") #'org-fc-review-flip)
  (evil-make-overriding-map org-fc-review-flip-mode-map)
  (evil-make-overriding-map org-fc-review-rate-mode-map)
  (add-hook 'org-fc-review-flip-mode-hook #'evil-normalize-keymaps)
  (add-hook 'org-fc-review-rate-mode-hook #'evil-normalize-keymaps))

(when (keymapp (lookup-key doom-leader-map (kbd "b")))
  (let ((picker (lookup-key doom-leader-map (kbd "b b"))))
    (define-key doom-leader-map (kbd "B") (lookup-key doom-leader-map (kbd "b")))
    (define-key doom-leader-map (kbd "b") picker)))

(when (keymapp (lookup-key doom-leader-map (kbd "p")))
  (let ((picker (lookup-key doom-leader-map (kbd "p p"))))
    (define-key doom-leader-map (kbd "P") (lookup-key doom-leader-map (kbd "p")))
    (define-key doom-leader-map (kbd "p") picker)))

(define-key doom-leader-map (kbd "T") (make-sparse-keymap))
(map! :leader
      (:prefix ("T" . "terminal")
       :desc "New terminal" "n" #'+ghostel/here
       :desc "New terminal in split" "s" #'josh/ghostel-split))

(after! which-key
  (setq which-key-idle-delay 0.01
        which-key-idle-secondary-delay 0.01)
  (when which-key-mode
    (which-key-mode -1)
    (which-key-mode 1))
  (which-key-add-keymap-based-replacements doom-leader-map
    "f" "Find file in project"
    "F" "file"
    "b" "Switch buffer"
    "B" "buffer"
    "p" "Switch project"
    "P" "project"))

(defun josh/agent-shell-command ()
  "Choose any public Agent Shell command with Doom's completion interface."
  (interactive)
  (require 'agent-shell)
  (let ((command (completing-read
                  "Agent command: " obarray
                  (lambda (symbol)
                    (and (commandp symbol)
                         (string-prefix-p "agent-shell-" (symbol-name symbol))
                         (not (string-match-p "--" (symbol-name symbol)))))
                  t)))
    (call-interactively (intern command))))

(defun josh/agent-shell-return ()
  "Activate the item at point, or submit a prompt in an editable agent buffer."
  (interactive)
  (let* ((map (get-char-property (point) 'keymap))
         (action (and map (lookup-key map (kbd "RET")))))
    (cond
     ((commandp action) (call-interactively action))
     ((button-at (point)) (push-button))
     ((derived-mode-p 'agent-shell-mode) (call-interactively #'agent-shell-submit))
     ((derived-mode-p 'agent-shell-viewport-edit-mode)
      (call-interactively #'agent-shell-viewport-compose-send))
     (t (user-error "No agent action at point")))))

(define-key doom-leader-map (kbd "a") (make-sparse-keymap))

(map! :leader
      (:prefix ("a" . "agent")
       :desc "Open agent shell" "a" #'agent-shell
       :desc "Toggle agent shell" "t" #'agent-shell-toggle
       :desc "Switch agent shell" "b" #'agent-shell-switch-buffer
       :desc "Reply inline" "r" #'agent-shell-inline-reply
       :desc "Send region" "S" #'agent-shell-send-region
       :desc "Send current file" "f" #'agent-shell-send-file
       :desc "Discuss inline" "p" #'agent-shell-inline
       :desc "Visit / cycle inline previews" "P" #'agent-shell-inline-visit
       :desc "Message without switching" "m" #'agent-shell-inline-message
       :desc "Navigate preview" "n" #'agent-shell-inline-navigate
       :desc "Response actions" "o" #'agent-shell-inline--response-overlay-dispatch
       :desc "Visit / review conversation" "v" #'agent-shell-inline-review
       :desc "Interrupt agent" "x" #'agent-shell-inline-interrupt
       :desc "Scroll response down" "j" #'agent-shell-inline--response-overlay-down
       :desc "Scroll response up" "k" #'agent-shell-inline--response-overlay-up
       :desc "Page response down" "D" #'agent-shell-inline--response-overlay-pagedown
       :desc "Page response up" "U" #'agent-shell-inline--response-overlay-pageup
       (:prefix ("i" . "inputs")
        :desc "Send another file" "f" #'agent-shell-send-other-file
        :desc "Send clipboard image" "i" #'agent-shell-send-clipboard-image
        :desc "Send screenshot" "s" #'agent-shell-send-screenshot
        :desc "Send region or diagnostic" "d" #'agent-shell-send-dwim)
       (:prefix ("N" . "new / resume agent")
        :desc "New agent shell" "n" #'agent-shell-new-shell
        :desc "Resume session" "r" #'agent-shell-resume-session
        :desc "New worktree shell" "w" #'agent-shell-new-worktree-shell)
       :desc "All agent commands" "?" #'josh/agent-shell-command))

(after! (agent-shell-inline evil)
  (define-key agent-shell-inline-prompt-mode-map [remap evil-save-and-close]
              #'agent-shell-inline-write-and-quit)
  (define-key agent-shell-inline-prompt-mode-map [remap evil-quit]
              #'agent-shell-inline-quit)
  (setq agent-shell-inline-key-bindings
        '((agent-shell-inline-send . ":wq")
          (agent-shell-inline-cycle-reference . "SPC m m")
          (agent-shell-inline-append . "SPC m a")
          (agent-shell-inline-switch-buffer . "SPC m b")
          (agent-shell-inline-visit-buffer . "SPC m v")
          (agent-shell-inline-quit . ":q")
          (agent-shell-inline-help . "SPC m h")
          (agent-shell-inline-reply . "SPC a r")
          (agent-shell-inline-navigate . "SPC a n")
          (agent-shell-inline--response-overlay-dispatch . "SPC a o")
          (agent-shell-inline-review . "SPC a v")
          (agent-shell-inline-interrupt . "SPC a x")
          (agent-shell-inline--response-overlay-down . "SPC a j")
          (agent-shell-inline--response-overlay-up . "SPC a k")
          (agent-shell-inline--response-overlay-pagedown . "SPC a D")
          (agent-shell-inline--response-overlay-pageup . "SPC a U")))
  (evil-set-initial-state 'agent-shell-inline-prompt-mode 'insert)
  (map! :map agent-shell-inline-prompt-mode-map
        :n "RET" #'agent-shell-inline-send
        :i "RET" #'newline
        :localleader
        "s" nil
        "c" nil
        :desc "Cycle reference" "m" #'agent-shell-inline-cycle-reference
        :desc "Append without sending" "a" #'agent-shell-inline-append
        :desc "Switch conversation" "b" #'agent-shell-inline-switch-buffer
        :desc "Visit conversation" "v" #'agent-shell-inline-visit-buffer
        :desc "Cancel prompt" "q" #'agent-shell-inline-quit
        :desc "Help" "h" #'agent-shell-inline-help))

(after! (agent-shell evil)
  (evil-set-initial-state 'agent-shell-mode 'normal)
  (evil-set-initial-state 'agent-shell-viewport-view-mode 'normal)
  (evil-set-initial-state 'agent-shell-viewport-edit-mode 'insert)
  (evil-set-initial-state 'agent-shell-diff-mode 'normal)

  (map! :map (agent-shell-mode-map agent-shell-viewport-view-mode-map
             agent-shell-viewport-edit-mode-map)
        :n "RET" #'josh/agent-shell-return
        :localleader
        :desc "All agent commands" "?" #'josh/agent-shell-command
        :desc "Other agent buffer" "o" #'agent-shell-other-buffer)

  (map! :map (agent-shell-mode-map agent-shell-viewport-view-mode-map)
        :n "z a" #'agent-shell-ui-toggle-fragment
        :n "z m" #'agent-shell-ui-toggle-all-fragments
        :localleader
        (:prefix ("f" . "fold")
         :desc "Toggle block" "f" #'agent-shell-ui-toggle-fragment
         :desc "Toggle all blocks" "a" #'agent-shell-ui-toggle-all-fragments)
        (:prefix ("y" . "copy")
         :desc "Region as Markdown" "r" #'agent-shell-copy-as-markdown
         :desc "Code block" "c" #'agent-shell-copy-source-block-at-point
         :desc "Link URL" "l" #'agent-shell-copy-link-url-at-point))

  (map! :map agent-shell-mode-map
        :i "n" #'self-insert-command
        :i "p" #'self-insert-command
        :i "r" #'self-insert-command
        :i "+" #'self-insert-command
        :i "-" #'self-insert-command
        :i "0" #'self-insert-command
        :i "RET" #'newline
        :n "] ]" #'agent-shell-next-item
        :n "[ [" #'agent-shell-previous-item
        :n "TAB" #'agent-shell-next-item
        :n "<backtab>" #'agent-shell-previous-item
        "C-c RET" #'agent-shell-submit
        "C-c S-<return>" #'agent-shell-submit-override
        :localleader
        :desc "Upstream menu" "h" #'agent-shell-help-menu
        :desc "Send / queue prompt" "s" #'agent-shell-submit
        :desc "Override busy submission" "S" #'agent-shell-submit-override
        :desc "Interrupt / reject pending" "x" #'agent-shell-interrupt
        :desc "Compose prompt" "c" #'agent-shell-prompt-compose
        :desc "Quote selection" "r" #'agent-shell-quote-region
        (:prefix ("m" . "session settings")
         :desc "Mode" "m" #'agent-shell-set-session-mode
         :desc "Cycle mode" "c" #'agent-shell-cycle-session-mode
         :desc "Model" "v" #'agent-shell-set-session-model
         :desc "Thought level" "t" #'agent-shell-set-session-thought-level
         :desc "Other ACP option" "o" #'agent-shell-set-session-config-option)
        (:prefix ("p" . "permissions and questions")
         :desc "Latest permission" "p" #'agent-shell-jump-to-latest-permission-button-row
         :desc "Next permission button" "j" #'agent-shell-next-permission-button
         :desc "Previous permission button" "k" #'agent-shell-previous-permission-button
         :desc "Activate button" "RET" #'josh/agent-shell-return
         :desc "Latest question form" "q" #'agent-shell-elicitation-jump-to-latest-form
         :desc "Next question field" "n" #'agent-shell-elicitation-next-field
         :desc "Previous question field" "b" #'agent-shell-elicitation-previous-field
         :desc "Question preview" "v" #'agent-shell-elicitation-toggle-preview)
        (:prefix ("q" . "prompt queue")
         :desc "Queue prompt" "q" #'agent-shell-prompt-queue
         :desc "Remove queued prompt" "d" #'agent-shell-prompt-queue-remove
         :desc "Resume queue" "r" #'agent-shell-prompt-queue-resume
         :desc "Steer current turn" "s" #'agent-shell-prompt-steer)
        (:prefix ("i" . "insert")
         :desc "File" "f" #'agent-shell-insert-file
         :desc "Clipboard / image" "p" #'agent-shell-yank-dwim
         :desc "Shell command output" "!" #'agent-shell-insert-shell-command-output
         :desc "Text drawing" "d" #'agent-shell-artist-insert-text-drawing)
        (:prefix ("b" . "session")
         :desc "Reload same session" "r" #'agent-shell-reload
         :desc "Restart conversation" "R" #'agent-shell-restart
         :desc "Fork session" "f" #'agent-shell-fork
         :desc "Copy session ID" "y" #'agent-shell-copy-session-id
         :desc "Open transcript" "t" #'agent-shell-open-transcript
         :desc "Show usage" "u" #'agent-shell-show-usage
         :desc "Toggle chat labels" "c" #'agent-shell-chat-mode)
        (:prefix ("l" . "logs")
         :desc "ACP logs" "a" #'agent-shell-view-acp-logs
         :desc "Traffic" "t" #'agent-shell-view-traffic
         :desc "Save traffic" "s" #'agent-shell-save-traffic
         :desc "Toggle logging" "l" #'agent-shell-toggle-logging
         :desc "Reset logs" "r" #'agent-shell-reset-logs)
        (:prefix ("y" . "copy")
         :desc "Last response" "y" #'agent-shell-copy-last-output)
        (:prefix ("z" . "image size")
         :desc "Increase" "+" #'agent-shell-image-scale-increase
         :desc "Decrease" "-" #'agent-shell-image-scale-decrease
         :desc "Reset" "0" #'agent-shell-image-scale-reset))

  (map! :map (agent-shell-viewport-view-mode-map agent-shell-viewport-edit-mode-map)
        :localleader
        (:prefix ("m" . "session settings")
         :desc "Mode" "m" #'agent-shell-viewport-set-session-mode
         :desc "Cycle mode" "c" #'agent-shell-viewport-cycle-session-mode
         :desc "Model" "v" #'agent-shell-viewport-set-session-model
         :desc "Thought level" "t" #'agent-shell-viewport-set-session-thought-level)
        (:prefix ("q" . "prompt queue")
         :desc "Queue prompt" "q" #'agent-shell-viewport-prompt-queue
         :desc "Remove queued prompt" "d" #'agent-shell-viewport-prompt-queue-remove
         :desc "Resume queue" "r" #'agent-shell-viewport-prompt-queue-resume)
        (:prefix ("b" . "session")
         :desc "Copy session ID" "y" #'agent-shell-viewport-copy-session-id
         :desc "Open transcript" "t" #'agent-shell-viewport-open-transcript)
        (:prefix ("l" . "logs")
         :desc "ACP logs" "a" #'agent-shell-viewport-view-acp-logs
         :desc "Traffic" "t" #'agent-shell-viewport-view-traffic
         :desc "Save traffic" "s" #'agent-shell-viewport-save-traffic))

  (map! :map agent-shell-viewport-view-mode-map
        :n "] ]" #'agent-shell-viewport-next-item
        :n "[ [" #'agent-shell-viewport-previous-item
        :n "] p" #'agent-shell-viewport-next-page
        :n "[ p" #'agent-shell-viewport-previous-page
        :n "TAB" #'agent-shell-viewport-next-item
        :n "<backtab>" #'agent-shell-viewport-previous-item
        :n "q" #'bury-buffer
        :localleader
        :desc "Upstream viewport menu" "h" #'agent-shell-viewport-help-menu
        :desc "Reply" "r" #'agent-shell-viewport-reply
        :desc "Quote and reply" "R" #'agent-shell-viewport-quote-reply
        :desc "Interrupt / reject pending" "x" #'agent-shell-viewport-interrupt
        :desc "Refresh viewport" "g" #'agent-shell-viewport-refresh
        :desc "Next interaction" "j" #'agent-shell-viewport-next-page
        :desc "Previous interaction" "k" #'agent-shell-viewport-previous-page
        (:prefix ("z" . "image size")
         :desc "Increase" "+" #'agent-shell-markdown-image-scale-increase
         :desc "Decrease" "-" #'agent-shell-markdown-image-scale-decrease
         :desc "Reset" "0" #'agent-shell-markdown-image-scale-reset))

  (map! :map agent-shell-viewport-edit-mode-map
        "C-c RET" #'agent-shell-viewport-compose-send
        "C-c S-<return>" #'agent-shell-viewport-compose-send-override
        :localleader
        :desc "Compose help" "h" #'agent-shell-viewport-compose-help-menu
        :desc "Send / queue prompt" "s" #'agent-shell-viewport-compose-send
        :desc "Override busy submission" "S" #'agent-shell-viewport-compose-send-override
        :desc "Send and show response" "v" #'agent-shell-viewport-compose-send-and-wait-for-response
        :desc "Send and dismiss" "d" #'agent-shell-viewport-compose-send-and-dismiss
        :desc "Cancel composition" "k" #'agent-shell-viewport-compose-cancel
        :desc "Peek at last interaction" "p" #'agent-shell-viewport-compose-peek-last
        (:prefix ("H" . "prompt history")
         :desc "Search" "s" #'agent-shell-viewport-search-history
         :desc "Previous" "k" #'agent-shell-viewport-previous-history
         :desc "Next" "j" #'agent-shell-viewport-next-history))

  (map! :map agent-shell-diff-mode-map
        :n "] c" #'diff-hunk-next
        :n "[ c" #'diff-hunk-prev
        :n "RET" #'agent-shell-diff-open-file
        :n "q" #'kill-current-buffer
        :localleader
        :desc "Accept changes" "a" #'agent-shell-diff-accept-all
        :desc "Reject changes" "r" #'agent-shell-diff-reject-all
        :desc "Visit file" "o" #'agent-shell-diff-open-file
        :desc "Close review" "q" #'kill-current-buffer)

  (map! :map agent-shell-artist-mode-map
        :localleader
        :desc "Insert drawing" "s" #'agent-shell-artist-commit
        :desc "Cancel drawing" "k" #'agent-shell-artist-cancel
        :desc "Drawing tools" "h" #'agent-shell-artist-help
        :desc "Previous drawing" "p" #'agent-shell-artist-previous-history
        :desc "Next drawing" "n" #'agent-shell-artist-next-history))
