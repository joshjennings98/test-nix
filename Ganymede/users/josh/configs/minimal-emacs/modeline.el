;;; modeline.el --- A small, composable mode line -*- lexical-binding: t; -*-

;; Uses the component approach from Prot's custom mode-line tutorial.
(defface emacs2-mode-line-state
  '((t :inherit mode-line-emphasis))
  "Evil state in the selected window's mode line."
  :group 'mode-line-faces)

(defun emacs2-mode-line-state-text ()
  "Return a short label for the current Evil state."
  (when (bound-and-true-p evil-local-mode)
    (propertize
     (pcase evil-state
       ('normal "N") ('insert "I") ('visual "V") ('replace "R")
       ('operator "O") ('motion "M") ('emacs "E") (_ "?"))
     'face (if (mode-line-window-selected-p)
               'emacs2-mode-line-state
             'mode-line-inactive)
     'help-echo (format "Evil: %s" evil-state))))

(defun emacs2-mode-line-status-text ()
  "Show unsaved changes and read-only status."
  (let ((modified (buffer-modified-p)))
    (propertize
     (concat (if modified "*" "") (if buffer-read-only "RO" ""))
     'face (if (and modified (mode-line-window-selected-p))
               'warning
             'mode-line-inactive)
     'help-echo (if modified "Unsaved changes" "Read-only buffer"))))

(defun emacs2-mode-line-branch-text ()
  "Return cached VC information, without starting a Git process."
  (when (and (stringp vc-mode) (not (string-empty-p vc-mode)))
    (let ((branch (replace-regexp-in-string "\\`[[:space:]]*Git[:-]" "" vc-mode)))
      ;; A branch name may contain percent signs, which mode lines interpret.
      (propertize (format "  %s" (replace-regexp-in-string "%" "%%" branch t t))
                  'face (if (mode-line-window-selected-p)
                            'mode-line-emphasis
                          'mode-line-inactive)
                  'help-echo "Version-control branch"))))

(defvar-local emacs2-mode-line-state '(:eval (emacs2-mode-line-state-text)))
(defvar-local emacs2-mode-line-status '(:eval (emacs2-mode-line-status-text)))
(defvar-local emacs2-mode-line-buffer
  '(:eval (propertize "%b" 'face (if (mode-line-window-selected-p)
                                      'mode-line-buffer-id
                                    'mode-line-inactive))))
(defvar-local emacs2-mode-line-branch '(:eval (emacs2-mode-line-branch-text)))

(defun emacs2-mode-line-trust-project (event)
  "Trust the project belonging to the mode line clicked in EVENT."
  (interactive "e")
  (with-selected-window (posn-window (event-start event))
    (emacs2-trust-project)))

(defvar emacs2-mode-line-trust-map
  (let ((map (make-sparse-keymap)))
    (define-key map [mode-line mouse-1] #'emacs2-mode-line-trust-project)
    map))

(defvar emacs2-mode-line-trust
  `(:propertize "  Untrusted · Trust project"
    face warning mouse-face mode-line-highlight
    help-echo "Click or press SPC P t to review and trust this project"
    local-map ,emacs2-mode-line-trust-map))
(put 'emacs2-mode-line-trust 'risky-local-variable t)

(dolist (component '(emacs2-mode-line-state emacs2-mode-line-status
                     emacs2-mode-line-buffer emacs2-mode-line-branch))
  (put component 'risky-local-variable t))

(setq-default mode-line-format
              '("%e" " " emacs2-mode-line-state " "
                emacs2-mode-line-status " " emacs2-mode-line-buffer
                " " mode-line-format-right-align
                emacs2-mode-line-branch
                (emacs2-project-untrusted emacs2-mode-line-trust
                 (flymake-mode ("  " flymake-mode-line-exception flymake-mode-line-counters)))
                "  " mode-name " "))
