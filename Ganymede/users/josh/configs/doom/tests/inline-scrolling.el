;;; inline-scrolling.el --- Inline and pixel scrolling regressions -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'pixel-scroll)
(load (expand-file-name "../agent-shell-inline.el" (file-name-directory load-file-name)) nil t)

(defmacro josh/with-scroll-preview (&rest body)
  "Run BODY with a preview and source text below it in a temporary window."
  (declare (indent 0))
  `(save-window-excursion
     (with-temp-buffer
       (switch-to-buffer (current-buffer))
       (dotimes (i 20) (insert (format "Source line %d\n" i)))
       (goto-char (point-min))
       (forward-line 15)
       (let* ((window (selected-window))
              (overlay (make-overlay (line-beginning-position) (line-end-position)))
              (make-cursor-line-fully-visible nil)
              (agent-shell-inline--response-overlay-mode t))
         (overlay-put overlay 'agent-shell-inline t)
         (overlay-put overlay 'after-string (concat "\n" (mapconcat #'identity (make-list 16 "Inline reply") "\n")))
         (overlay-put overlay 'agent-shell-inline-scroll-index 0)
         (set-window-start window (overlay-end overlay) t)
         (goto-char (overlay-end overlay))
         (forward-line 2)
         ,@body))))

(ert-deftest josh/inline-wheel-stays-in-reply-at-both-boundaries ()
  (dolist (kind '(wheel-up wheel-down))
    (dolist (below '(nil t))
      (josh/with-scroll-preview
       (unless below (goto-char (overlay-start overlay)))
       (let ((event (list kind (list window (overlay-end overlay) '(0 . 0) 0)))
             requested)
         (cl-letf (((symbol-function 'agent-shell-inline--response-overlay-at-point) (lambda () overlay))
                   ((symbol-function 'agent-shell-inline--response-overlay-scroll-to)
                    (lambda (index _overlay) (setq requested index)))
                   ((symbol-function 'pixel-scroll-precision)
                    (lambda (&rest _) (ert-fail "Reply scrolled the document")))
                   ((symbol-function 'mwheel-scroll)
                    (lambda (&rest _) (ert-fail "Reply scrolled the document"))))
           (agent-shell-inline--response-overlay-wheel event)
           (should (= requested (if (eq kind 'wheel-up) -1 1)))))))))

(ert-deftest josh/inline-scroll-measurement-restores-preview-after-error ()
  (with-temp-buffer
    (insert "Anchor\n")
    (let ((overlay (make-overlay 1 7)))
      (overlay-put overlay 'after-string "Reply")
      (should-error
       (agent-shell-inline--measure-without-previews
        (list overlay)
        (lambda ()
          (should-not (overlay-get overlay 'after-string))
          (error "Measurement failed"))))
      (should (equal (overlay-get overlay 'after-string) "Reply")))))

(ert-deftest josh/inline-pixel-real-display-passes-preview-with-cursor-below ()
  (skip-unless (display-graphic-p))
  (josh/with-scroll-preview
   (redisplay t)
   (dotimes (_ 100)
     (condition-case nil
         (pixel-scroll-precision-scroll-down 15)
       (end-of-buffer nil))
     (redisplay t))
   (should (> (window-start) (overlay-end overlay)))
   (dotimes (_ 100)
     (let ((start (window-start)) (offset (window-vscroll nil t)))
       (condition-case nil
           (pixel-scroll-precision-scroll-up 15)
         (beginning-of-buffer nil))
       (redisplay t)
       (should (or (< (window-start) start)
                   (and (= (window-start) start)
                        (<= (window-vscroll nil t) offset))))))
   (should (< (window-start) (overlay-start overlay)))))

(ert-deftest josh/inline-pixel-movement-remains-exact-through-resizing-preview ()
  (skip-unless (display-graphic-p))
  (dolist (scenario '((nil nil) (t nil) (nil t) (t t)))
    (let ((resize (car scenario)) (wrapped (cadr scenario)))
      (save-window-excursion
	(with-temp-buffer
          (switch-to-buffer (current-buffer))
          (dotimes (i 100) (insert (format "Source line %d\n" i)))
          (goto-char (point-min))
          (forward-line 50)
          (when wrapped
            (visual-line-mode 1)
            (insert (make-string 240 ?W)))
          (let* ((overlay (make-overlay (line-beginning-position) (line-end-position)))
		 (below (save-excursion (forward-line 1) (point)))
		 (agent-shell-inline--response-overlay-mode t))
            (overlay-put overlay 'agent-shell-inline t)
            (overlay-put overlay 'after-string
			 (concat "\n" (mapconcat #'identity (make-list 8 "Inline reply") "\n")))
            (goto-char below)
            (forward-line 2)
            (set-window-start nil below t)
            (redisplay t)
            (dolist (direction '(1 -1))
              (dotimes (i 80)
		(when (and resize (= direction 1) (memq i '(10 30)))
                  (overlay-put overlay 'after-string
                               (concat "\n" (mapconcat #'identity
                                                       (make-list (if (= i 10) 16 8) "Resized reply") "\n")))
                  (redisplay t))
		(let* ((position (posn-at-point below))
                       (before (and position (cdr (posn-x-y position)))))
                  (should before)
                  (if (= direction 1)
                      (pixel-scroll-precision-scroll-up 7)
                    (pixel-scroll-precision-scroll-down 7))
                  (redisplay t)
                  (let ((after (posn-at-point below)))
                    (should after)
                    (ert-info ((format "resize=%s direction=%s step=%s before=%s start=%s offset=%s"
                                       resize direction i before (window-start) (window-vscroll nil t)))
                      (should (= (- (cdr (posn-x-y after)) before) (* direction 7))))))))))))))
