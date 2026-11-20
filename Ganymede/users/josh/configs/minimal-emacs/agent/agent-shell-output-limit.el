;;; agent-shell-output-limit.el --- Bound tool output previews -*- lexical-binding: t; -*-

(require 'agent-shell)
(require 'agent-shell-openai)

(defconst agent-shell-output-limit--characters 32768
  "Maximum tool output characters retained for display.
This affects Emacs previews and transcripts, not the agent's tool result.")

(defconst agent-shell-output-limit--notice
  "\n[Tool output preview truncated. Redirect large output to a file.]\n")

(defun agent-shell-output-limit--text (text)
  "Bound TEXT before Agent Shell renders it."
  (if (> (length text) agent-shell-output-limit--characters)
      (concat (substring text 0 agent-shell-output-limit--characters)
              agent-shell-output-limit--notice)
    text))

(defun agent-shell-output-limit--notification (original &rest arguments)
  "Bound streamed deltas before ORIGINAL accumulates and formats them."
  (let* ((notification (copy-tree (plist-get arguments :acp-notification)))
         (update (map-nested-elt notification '(params update)))
         (delta (map-nested-elt update '(_meta terminal_output_delta data)))
         (id (map-elt update 'toolCallId)))
    (when (and (equal (map-elt update 'sessionUpdate) "tool_call_update")
               (stringp delta) (stringp id))
      (let* ((previous (map-elt agent-shell-openai--terminal-output-snapshots id))
             (remaining (max 0 (- agent-shell-output-limit--characters
                                  (length previous)))))
        (setf (alist-get 'data (alist-get 'terminal_output_delta (alist-get '_meta update)))
              (cond
               ((> (length previous) agent-shell-output-limit--characters) "")
               ((> (length delta) remaining)
                (concat (substring delta 0 remaining) agent-shell-output-limit--notice))
               (t delta)))))
    (apply original (plist-put arguments :acp-notification notification))))

(advice-add 'agent-shell--tool-call-update-output-markdown :filter-return
            #'agent-shell-output-limit--text)
(advice-add 'agent-shell-openai--notification-adapter :around
            #'agent-shell-output-limit--notification)

(provide 'agent-shell-output-limit)
