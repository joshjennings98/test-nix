;;; emacs2-agent-keys.el --- Agent bindings without Doom macros -*- lexical-binding: t; -*-

(defun emacs2-agent-local-keys (mode-map bindings)
  "Attach local-leader BINDINGS to MODE-MAP."
  (let ((map (or (lookup-key mode-map (kbd "C-c m")) (make-sparse-keymap))))
    (emacs2-agent-bindings map bindings)
    (define-key mode-map (kbd "C-c m") map)
    (evil-define-key* '(normal motion visual) mode-map (kbd "SPC m") map)))

(define-key agent-shell-inline-prompt-mode-map [remap evil-save-and-close]
            #'agent-shell-inline-write-and-quit)
(define-key agent-shell-inline-prompt-mode-map [remap evil-quit] #'agent-shell-inline-quit)
(setq agent-shell-inline-key-bindings
      '((agent-shell-inline-send . ":wq")
        (agent-shell-inline-cycle-reference . "SPC m m")
        (agent-shell-inline-append . "SPC m a")
        (agent-shell-inline-switch-buffer . "SPC m b")
        (agent-shell-inline-select-session . "SPC a S")
        (agent-shell-inline-approve . "SPC a y")
        (agent-shell-inline-approve-all . "SPC a Y")
        (agent-shell-inline-latest-reply . "SPC a g")
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

(dolist (mode '(agent-shell-mode agent-shell-viewport-view-mode agent-shell-diff-mode
                agent-shell-permission-transient-details-mode))
  (evil-set-initial-state mode 'normal))
(dolist (mode '(agent-shell-inline-prompt-mode agent-shell-viewport-edit-mode))
  (evil-set-initial-state mode 'insert))

(evil-define-key* 'normal agent-shell-inline-prompt-mode-map (kbd "RET") #'agent-shell-inline-send)
(evil-define-key* 'insert agent-shell-inline-prompt-mode-map (kbd "RET") #'newline)
(emacs2-agent-local-keys
 agent-shell-inline-prompt-mode-map
 '(("m" . agent-shell-inline-cycle-reference) ("a" . agent-shell-inline-append)
   ("b" . agent-shell-inline-switch-buffer) ("v" . agent-shell-inline-visit-buffer)
   ("q" . agent-shell-inline-quit) ("h" . agent-shell-inline-help)))

(dolist (key '("q" "<escape>" "C-g"))
  (evil-define-key* 'normal agent-shell-permission-transient-details-mode-map (kbd key) #'quit-window))

(dolist (map (list agent-shell-mode-map agent-shell-viewport-view-mode-map
                   agent-shell-viewport-edit-mode-map))
  (evil-define-key* 'normal map (kbd "RET") #'emacs2-agent-return)
  (emacs2-agent-local-keys map '(("?" . emacs2-agent-command) ("o" . agent-shell-other-buffer))))

(dolist (map (list agent-shell-mode-map agent-shell-viewport-view-mode-map))
  (evil-define-key* 'normal map
    (kbd "z a") #'agent-shell-ui-toggle-fragment
    (kbd "z m") #'agent-shell-ui-toggle-all-fragments)
  (emacs2-agent-local-keys
   map '(("f f" . agent-shell-ui-toggle-fragment) ("f a" . agent-shell-ui-toggle-all-fragments)
         ("y r" . agent-shell-copy-as-markdown) ("y c" . agent-shell-copy-source-block-at-point)
         ("y l" . agent-shell-copy-link-url-at-point))))

(dolist (key '("n" "p" "r" "+" "-" "0"))
  (evil-define-key* 'insert agent-shell-mode-map (kbd key) #'self-insert-command))
(evil-define-key* 'insert agent-shell-mode-map (kbd "RET") #'newline)
(evil-define-key* 'normal agent-shell-mode-map
  (kbd "] ]") #'agent-shell-next-item (kbd "[ [") #'agent-shell-previous-item
  (kbd "TAB") #'agent-shell-next-item (kbd "<backtab>") #'agent-shell-previous-item)
(define-key agent-shell-mode-map (kbd "C-c RET") #'agent-shell-submit)
(define-key agent-shell-mode-map (kbd "C-c S-<return>") #'agent-shell-submit-override)
(define-key agent-shell-mode-map (kbd "C-c C-p") #'agent-shell-permission-transient-menu)
(emacs2-agent-local-keys
 agent-shell-mode-map
 '(("h" . agent-shell-help-menu) ("s" . agent-shell-submit) ("S" . agent-shell-submit-override)
   ("x" . agent-shell-interrupt) ("c" . agent-shell-prompt-compose) ("r" . agent-shell-quote-region)
   ("m m" . agent-shell-set-session-mode) ("m c" . agent-shell-cycle-session-mode)
   ("m v" . agent-shell-set-session-model) ("m t" . agent-shell-set-session-thought-level)
   ("m o" . agent-shell-set-session-config-option)
   ("p p" . agent-shell-permission-transient-menu) ("p j" . agent-shell-next-permission-button)
   ("p k" . agent-shell-previous-permission-button) ("p RET" . emacs2-agent-return)
   ("p q" . agent-shell-elicitation-jump-to-latest-form) ("p n" . agent-shell-elicitation-next-field)
   ("p b" . agent-shell-elicitation-previous-field) ("p v" . agent-shell-elicitation-toggle-preview)
   ("q q" . agent-shell-prompt-queue) ("q d" . agent-shell-prompt-queue-remove)
   ("q r" . agent-shell-prompt-queue-resume) ("q s" . agent-shell-prompt-steer)
   ("i f" . agent-shell-insert-file) ("i p" . agent-shell-yank-dwim)
   ("i !" . agent-shell-insert-shell-command-output) ("i d" . agent-shell-artist-insert-text-drawing)
   ("b r" . agent-shell-reload) ("b R" . agent-shell-restart) ("b f" . agent-shell-fork)
   ("b y" . agent-shell-copy-session-id) ("b t" . agent-shell-open-transcript)
   ("b u" . agent-shell-show-usage) ("b c" . agent-shell-chat-mode)
   ("l a" . agent-shell-view-acp-logs) ("l t" . agent-shell-view-traffic)
   ("l s" . agent-shell-save-traffic) ("l l" . agent-shell-toggle-logging) ("l r" . agent-shell-reset-logs)
   ("y y" . agent-shell-copy-last-output)
   ("z +" . agent-shell-image-scale-increase) ("z -" . agent-shell-image-scale-decrease)
   ("z 0" . agent-shell-image-scale-reset)))

(dolist (map (list agent-shell-viewport-view-mode-map agent-shell-viewport-edit-mode-map))
  (emacs2-agent-local-keys
   map '(("m m" . agent-shell-viewport-set-session-mode) ("m c" . agent-shell-viewport-cycle-session-mode)
         ("m v" . agent-shell-viewport-set-session-model) ("m t" . agent-shell-viewport-set-session-thought-level)
         ("q q" . agent-shell-viewport-prompt-queue) ("q d" . agent-shell-viewport-prompt-queue-remove)
         ("q r" . agent-shell-viewport-prompt-queue-resume)
         ("b y" . agent-shell-viewport-copy-session-id) ("b t" . agent-shell-viewport-open-transcript)
         ("l a" . agent-shell-viewport-view-acp-logs) ("l t" . agent-shell-viewport-view-traffic)
         ("l s" . agent-shell-viewport-save-traffic))))

(evil-define-key* 'normal agent-shell-viewport-view-mode-map
  (kbd "] ]") #'agent-shell-viewport-next-item (kbd "[ [") #'agent-shell-viewport-previous-item
  (kbd "] p") #'agent-shell-viewport-next-page (kbd "[ p") #'agent-shell-viewport-previous-page
  (kbd "TAB") #'agent-shell-viewport-next-item (kbd "<backtab>") #'agent-shell-viewport-previous-item
  (kbd "q") #'bury-buffer)
(emacs2-agent-local-keys
 agent-shell-viewport-view-mode-map
 '(("h" . agent-shell-viewport-help-menu) ("r" . agent-shell-viewport-reply)
   ("R" . agent-shell-viewport-quote-reply) ("x" . agent-shell-viewport-interrupt)
   ("g" . agent-shell-viewport-refresh) ("j" . agent-shell-viewport-next-page)
   ("k" . agent-shell-viewport-previous-page)
   ("z +" . agent-shell-markdown-image-scale-increase) ("z -" . agent-shell-markdown-image-scale-decrease)
   ("z 0" . agent-shell-markdown-image-scale-reset)))

(define-key agent-shell-viewport-edit-mode-map (kbd "C-c RET") #'agent-shell-viewport-compose-send)
(define-key agent-shell-viewport-edit-mode-map (kbd "C-c S-<return>") #'agent-shell-viewport-compose-send-override)
(emacs2-agent-local-keys
 agent-shell-viewport-edit-mode-map
 '(("h" . agent-shell-viewport-compose-help-menu) ("s" . agent-shell-viewport-compose-send)
   ("S" . agent-shell-viewport-compose-send-override) ("v" . agent-shell-viewport-compose-send-and-wait-for-response)
   ("d" . agent-shell-viewport-compose-send-and-dismiss) ("k" . agent-shell-viewport-compose-cancel)
   ("p" . agent-shell-viewport-compose-peek-last)
   ("H s" . agent-shell-viewport-search-history) ("H k" . agent-shell-viewport-previous-history)
   ("H j" . agent-shell-viewport-next-history)))

(evil-define-key* 'normal agent-shell-diff-mode-map
  (kbd "] c") #'diff-hunk-next (kbd "[ c") #'diff-hunk-prev
  (kbd "RET") #'agent-shell-diff-open-file
  (kbd "q") #'kill-current-buffer (kbd "<escape>") #'kill-current-buffer (kbd "C-g") #'kill-current-buffer)
(emacs2-agent-local-keys
 agent-shell-diff-mode-map
 '(("a" . agent-shell-diff-accept-all) ("r" . agent-shell-diff-reject-all)
   ("o" . agent-shell-diff-open-file) ("q" . kill-current-buffer)))
(emacs2-agent-local-keys
 agent-shell-artist-mode-map
 '(("s" . agent-shell-artist-commit) ("k" . agent-shell-artist-cancel)
   ("h" . agent-shell-artist-help) ("p" . agent-shell-artist-previous-history)
   ("n" . agent-shell-artist-next-history)))

(provide 'emacs2-agent-keys)
