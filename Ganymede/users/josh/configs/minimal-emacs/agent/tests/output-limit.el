;;; output-limit.el --- Tool preview regression tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(load (expand-file-name "../agent-shell-output-limit.el"
                        (file-name-directory load-file-name)) nil t)

(ert-deftest josh/output-limit-bounds-streams-before-accumulation ()
  (with-temp-buffer
    (cl-letf (((symbol-function 'agent-shell-openai--subscribe-output-cleanup) #'ignore))
      (let ((chunk (make-string 4096 ?x)) result)
        (dotimes (_ 100)
          (let ((notification
                 `((method . "session/update")
                   (params (update (sessionUpdate . "tool_call_update")
                                   (toolCallId . "large")
                                   (_meta (terminal_output_delta (data . ,chunk))))))))
            (setq result (agent-shell-openai--notification-adapter :acp-notification notification))
            (should (equal (map-nested-elt notification '(params update _meta terminal_output_delta data)) chunk))
            (should (<= (length (map-elt agent-shell-openai--terminal-output-snapshots "large"))
                        (+ agent-shell-output-limit--characters (length agent-shell-output-limit--notice))))))
        (should (string-match-p "preview truncated"
                                (agent-shell--tool-call-update-output-markdown
                                 (map-nested-elt result '(params update)))))
        ;; A final summary must replace the preview, including after truncation.
        (agent-shell-openai--notification-adapter
         :acp-notification
         '((method . "session/update")
           (params (update (sessionUpdate . "tool_call_update") (toolCallId . "large")
                           (rawOutput (formatted_output . "Tests failed"))))))
        (should (equal (map-elt agent-shell-openai--terminal-output-snapshots "large") "Tests failed"))
        ;; Other tools still have their own preview budget.
        (agent-shell-openai--notification-adapter
         :acp-notification
         '((method . "session/update")
           (params (update (sessionUpdate . "tool_call_update") (toolCallId . "small")
                           (_meta (terminal_output_delta (data . "ok")))))))
        (should (equal (map-elt agent-shell-openai--terminal-output-snapshots "small") "ok"))))))

(ert-deftest josh/output-limit-bounds-complete-multiline-results ()
  (let* ((text (mapconcat #'identity (make-list 10000 "a short line") "\n"))
         (rendered (agent-shell--tool-call-update-output-markdown
                    `((rawOutput (formatted_output . ,text))))))
    (should (< (length rendered) 33000))
    (should (string-suffix-p agent-shell-output-limit--notice rendered))))
