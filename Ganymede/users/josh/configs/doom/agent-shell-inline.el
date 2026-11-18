;;; agent-shell-inline.el --- Inline conversations backed by Agent Shell  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Karthik Chikmagalur

;; Author: Karthik Chikmagalur <karthikchikmagalur@gmail.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1") (agent-shell "0.91.1"))
;; Keywords: comm
;; URL: https://github.com/karthink/gptel-inline

;; SPDX-License-Identifier: GPL-3.0-or-later

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Adapted from Karthik Chikmagalur's gptel-inline.el on 2026-11-03:
;; https://github.com/karthink/gptel-inline/blob/master/gptel-inline.el
;; Upstream file SHA256: 6afce84950b17ed32498e8979226227b7812424b11915032cd594153c405ca3c
;; The reference selection, overlay presentation, scrolling and mouse UI are
;; derived from that file.  The session, prompt and request lifecycle use
;; Agent Shell instead.  No gptel package is needed.
;;
;; Prompts are separate editable buffers, not indirect shell buffers.  Agent
;; Shell owns the conversation, ACP transport, tools, authentication and review.
;; Responses stream beside the source without displaying the shell.  Permissions
;; show a review indicator and can be reviewed from the source window when the
;; local permission transient is enabled. Question forms use the conversation.
;; Only one inline request per shell is allowed; busy shells leave drafts intact.
;; Clearing a preview stops following it, while interrupt explicitly cancels.
;;
;; This file is independent of Doom.  Doom bindings belong in keys.el.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'map)
(require 'project)
(require 'button)
(require 'mwheel)
(require 'agent-shell)

(declare-function agent-shell-permission-transient-menu "agent-shell-permission-transient")
(declare-function agent-shell-permission-transient--buffer-pending-count "agent-shell-permission-transient")
(declare-function agent-shell-permission-transient--request-shell-buffer "agent-shell-permission-transient")
(declare-function agent-shell-permission-transient--request-pending-p "agent-shell-permission-transient")
(declare-function agent-shell-permission-transient--option "agent-shell-permission-transient")
(declare-function agent-shell-permission-transient--respond "agent-shell-permission-transient")
(defvar agent-shell-permission-transient--queue)

(declare-function gfm-mode "markdown-mode")
(declare-function org-escape-code-in-string "org-src")
(declare-function org-element-lineage-map "org-element-ast")
(declare-function org-element-context "org-element")
(declare-function org-element-type "org-element-ast")
(declare-function org-element-begin "org-element")
(declare-function org-element-end "org-element")

(defgroup agent-shell-inline nil
  "Inline conversations backed by Agent Shell."
  :group 'agent-shell)

(defcustom agent-shell-inline-display-prompt-action
  '((display-buffer-below-selected)
    (window-height . 0.33)
    (dedicated . t))
  "Display action used to show the `agent-shell-inline' prompt buffer.

See `display-buffer' for details."
  :type display-buffer--action-custom-type
  :group 'agent-shell-inline)

(defcustom agent-shell-inline-display-buffer-action
  '((display-buffer-pop-up-window))
  "Display action used to show the chat buffer.

See `display-buffer' for details."
  :type display-buffer--action-custom-type
  :group 'agent-shell-inline)

(defcustom agent-shell-inline-reference-types
  '((prog-mode defun sexp line window buffer)
    (org-mode link paragraph plain-list section headline window buffer)
    (text-mode url line sentence paragraph window page buffer)
    (t url line paragraph window buffer))
  "Things at point to offer as a reference for `agent-shell-inline'.
This is an alist mapping a major (derived) mode to a list of objects.
Any object recognized by `thing-at-point' is valid, along with two
extras:

- window -- visible text in the window
- buffer -- entire buffer

For Org mode only, these can also be org-element elements instead."
  :type '(alist :key-type symbol :value-type (repeat symbol))
  :group 'agent-shell-inline)

(defvar-keymap agent-shell-inline-map
  :doc "Keymap used in `agent-shell-inline' prompt buffers."
  "C-c RET" #'agent-shell-inline-send
  "C-c SPC" #'agent-shell-inline-cycle-reference
  "C-c ?" #'agent-shell-inline-help
  "C-c C-a" #'agent-shell-inline-append
  "C-c C-k" #'agent-shell-inline-quit
  "C-c C-b" #'agent-shell-inline-switch-buffer
  "C-c C-v" #'agent-shell-inline-visit-buffer)

(defcustom agent-shell-inline-response-overlay-height 16
  "Height in lines of the response popup.
This can also be a function of no arguments that returns a height as
an integer (lines) or float (fraction of frame height)."
  :type '(choice (natnum :tag "Number of lines")
                 (float :tag "Fraction of frame height")
                 (function :tag "Function returning int or float"))
  :group 'agent-shell-inline)


;;;; Internal variables
(defvar-local agent-shell-inline--reference-type nil
  "Current reference type being highlighted.
Set by `agent-shell-inline-cycle-reference' and used to determine text
bounds when cycling through possible reference types.")

(defvar-local agent-shell-inline--context nil
  "Context plist for the current `agent-shell-inline' session.
Contains at least the keys :marker, :reference-ov, and :response-ov.")

(defconst agent-shell-inline--hrule
  (concat "\n" (propertize "\n" 'face '(:inherit shadow :underline t :extend t))))

(defvar-local agent-shell-inline--last nil
  "Last chat buffer used for `agent-shell-inline', buffer-local to the origin buffer.")

(defvar agent-shell-inline--recent nil
  "Inline conversations ordered by most recent message, across source buffers.")

(defun agent-shell-inline--response-overlay-height ()
  "Compute the response overlay height from `agent-shell-inline-response-overlay-height'."
  (cl-etypecase agent-shell-inline-response-overlay-height
    (function (funcall agent-shell-inline-response-overlay-height))
    (natnum agent-shell-inline-response-overlay-height)
    (float (floor (* agent-shell-inline-response-overlay-height (frame-height))))))

;; KLUDGE: This logic is hard to follow
(defun agent-shell-inline--reference-bounds (origin &optional type)
  "Return the bounds and type of reference for the buffer location at ORIGIN.

ORIGIN is a marker in the origin buffer.  Optional TYPE is the reference
type to use; if nil, the first matching type from
`agent-shell-inline-reference-types' is used.  Returns (TYPE . (START . END))."
  (with-current-buffer (marker-buffer origin)
    (cond
     ((save-excursion
        (goto-char origin)
        (let* ((objects
                (cl-some (lambda (mode-list)
                           (and (or (eq (car mode-list) t)
                                    (derived-mode-p (car mode-list)))
                                (cdr mode-list)))
                         agent-shell-inline-reference-types)))
          (push 'none objects)
          (when (use-region-p) (push 'region objects))
          ;; objects is (region none &rest ...)
          (let ((tail objects) head next-type bounds)
            (while (and tail (or (null next-type) (null bounds)))
              (setq head (pop tail))
              (cond
               ((null type) (setq next-type head)) ;start cycling
               ((eq type head)
                (setq next-type (or (car tail) (car objects)))))
              (when next-type
                (setq bounds
                      (cond
                       ((and (eq next-type 'region) (use-region-p)
                             (cons (region-beginning) (region-end))))
                       ((eq next-type 'none) (list nil nil))
                       ((and (eq next-type 'window)
                             (and-let* ((win (car (cl-sort
                                                   (get-buffer-window-list (current-buffer))
                                                   #'> :key #'window-use-time))))
                               (cons (window-start win) (window-end win)))))
                       ((bounds-of-thing-at-point next-type))
                       ((and (derived-mode-p 'org-mode)
                             (org-element-lineage-map
                                 (org-element-context)
                                 (lambda (node) (when (eq next-type (org-element-type node))
                                             (cons (org-element-begin node)
                                                   (org-element-end node))))
                               nil t t)))))
                (unless bounds (setq type next-type)))) ;cycle until we find a type + bounds
            (cons next-type bounds))))))))

(defun agent-shell-inline--reference-text (origin-buf reference-ov &optional org-block)
  "Build a human-readable context string from the reference overlay.
ORIGIN-BUF is the buffer containing the reference.  REFERENCE-OV is the
overlay marking the reference region.  When ORG-BLOCK is non-nil, wrap
the text in an Org source block instead of a Markdown fenced block."
  (when (and (buffer-live-p origin-buf)
             (overlayp reference-ov)
             (overlay-buffer reference-ov))
    (with-current-buffer (overlay-buffer reference-ov)
      (let* ((beg (overlay-start reference-ov))
             (end (overlay-end reference-ov))
             (filename (buffer-file-name))
             (lstart (line-number-at-pos beg))
             (lend (line-number-at-pos end))
             (content (buffer-substring-no-properties beg end)))
        (concat
         (format "\n\nIn buffer \"%s\"" origin-buf)
         (and filename (format " (file \"%s\")" (abbreviate-file-name filename)))
         (format ", lines %d - %d:\n" lstart lend)
         (if org-block
             (concat "#+begin_src " (replace-regexp-in-string "-\\(?:ts-\\)?mode$" "" (symbol-name major-mode)) "\n"
                     (org-escape-code-in-string content) "\n#+end_src\n\n")
           (concat "``` " (replace-regexp-in-string "-\\(?:ts-\\)?mode$" "" (symbol-name major-mode)) "\n"
                   content "\n```\n\n"))
         (and-let* ((links (agent-shell-inline--text-props beg end)))
           (concat "\nHyperlinks in region:\n"
                   (string-join links "\n"))))))))

(defun agent-shell-inline--text-props (beg end)
  "Collect shr-url and image-url text properties between BEG and END.
Returns a list of URL strings found in the region."
  (when (> end beg)
    (let (match results)
      (save-excursion
        (goto-char beg)
        (while (and (setq match (text-property-search-forward 'shr-url))
                    (< (point) end))
          (push (prop-match-value match) results))
        (while (and (setq match (text-property-search-forward 'image-url))
                    (< (point) end))
          (push (prop-match-value match) results)))
      (nreverse results))))

(defvar-keymap agent-shell-inline-response-overlay-map
  :doc "Keymap for mouse actions on response overlay."
  "<down-mouse-1>" #'agent-shell-inline--response-overlay-drag
  "<mouse-1>"      #'agent-shell-inline--focus-from-click
  "<mouse-4>"      #'agent-shell-inline--response-overlay-wheel
  "<wheel-up>"     #'agent-shell-inline--response-overlay-wheel
  "<mouse-5>"      #'agent-shell-inline--response-overlay-wheel
  "<wheel-down>"   #'agent-shell-inline--response-overlay-wheel
  "<wheel-left>"   #'ignore
  "<wheel-right>"  #'ignore
  "S-<wheel-up>"   #'ignore
  "S-<wheel-down>" #'ignore
  "S-<mouse-4>"    #'ignore
  "S-<mouse-5>"    #'ignore)

(defvar-keymap agent-shell-inline--response-overlay-mode-map
  :doc "Keymap used on response overlays."
  "C-c C-o" #'agent-shell-inline--response-overlay-dispatch)

(define-minor-mode agent-shell-inline--response-overlay-mode
  "Minor mode for controlling `agent-shell-inline' overlays."
  :lighter ""
  :keymap agent-shell-inline--response-overlay-mode-map
  :interactive nil)

(defun agent-shell-inline--response-overlay-set-scroll-index (ov index)
  "Set the scroll INDEX for buffer-based response overlay OV.
Clamps INDEX to the valid range based on source buffer line count."
  (let* ((height (overlay-get ov 'agent-shell-inline-height))
         (len (length (agent-shell-inline--response-lines ov)))
         (max-index (max 0 (- len height))))
    (overlay-put ov 'agent-shell-inline-scroll-index (min (max 0 index) max-index))))

;;;;;; Response overlay manipulation commands
(defun agent-shell-inline--drag-anchor-y (window)
  "Return the pixel Y below the source line at point in WINDOW.
Call with the dragged preview's display string temporarily removed."
  (+ (cdr (window-text-pixel-size window (window-start window)
                                  (line-end-position) nil nil 'header-line))
     (window-tab-line-height window)
     (- (window-vscroll window t))))

(defun agent-shell-inline--drag-position (overlay window y)
  "Return the source line nearest pixel Y in WINDOW, excluding OVERLAY."
  (agent-shell-inline--measure-without-previews
   (list overlay)
   (lambda ()
     (with-current-buffer (window-buffer window)
       (save-excursion
         (goto-char (window-start window))
         (beginning-of-line)
         (let ((best (point))
               distance done)
           (while (not done)
             (let* ((height (agent-shell-inline--drag-anchor-y window))
                    (difference (abs (- height y))))
               (when (or (null distance) (< difference distance))
                 (setq best (point) distance difference))
               (setq done (or (>= height y) (/= (forward-line 1) 0)))))
           best))))))

(defun agent-shell-inline--response-overlay-drag (event)
  "Move the preview with EVENT, preserving the pointer's grab offset."
  (interactive "e")
  (let* ((start (event-start event))
         (window (posn-window start))
         (last-input-event event)
         (overlay (agent-shell-inline--focus-from-click event))
         (mouse-autoselect-window nil))
    (when overlay
      (let ((offset
             (- (cdr (posn-x-y start))
                (agent-shell-inline--measure-without-previews
                 (list overlay)
                 (lambda ()
                   (with-current-buffer (window-buffer window)
                     (save-excursion
                       (goto-char (overlay-start overlay))
                       (agent-shell-inline--drag-anchor-y window))))))))
        (track-mouse
          (let ((track-mouse 'dragging)
                next)
            (while (progn (setq next (read-event)) (mouse-movement-p next))
              (let* ((position (event-end next))
                     (target (posn-window position)))
                (when (window-live-p target)
                  (with-selected-window target
                    (save-excursion
                      (goto-char (agent-shell-inline--drag-position
                                  overlay target (- (cdr (posn-x-y position)) offset)))
                      (move-overlay overlay (line-beginning-position)
                                    (line-end-position) (current-buffer))
                      (agent-shell-inline--setup-response-overlay-keymap overlay)
                      (agent-shell-inline--focus-preview overlay)))
                  (redisplay t))))))))))

(defun agent-shell-inline--response-overlay-scroll-to (index response-ov)
  "Scroll RESPONSE-OV to display line INDEX and re-render."
  (when (and (overlayp response-ov) (overlay-buffer response-ov))
    (agent-shell-inline--response-overlay-set-scroll-index response-ov index)
    (agent-shell-inline--response-overlay-render response-ov)))

(defvar-local agent-shell-inline--selected-preview nil
  "Preview selected for keyboard actions in this buffer.")

(defvar agent-shell-inline--focused-preview nil
  "Preview whose faint session name is shown in bold.")

(defun agent-shell-inline--focus-preview (overlay)
  "Focus OVERLAY without moving point or selecting its window."
  (when (and (overlayp overlay) (overlay-buffer overlay))
    (let ((previous agent-shell-inline--focused-preview))
      (with-current-buffer (overlay-buffer overlay)
        (setq agent-shell-inline--selected-preview overlay)
        (let ((shell (plist-get (overlay-get overlay 'agent-shell-inline) :buffer)))
          (when (agent-shell-inline--shell-p shell)
            (setq agent-shell-inline--last shell
                  agent-shell-inline--recent (cons shell (delq shell agent-shell-inline--recent))))))
      (setq agent-shell-inline--focused-preview overlay)
      (unless (eq previous overlay)
        (when (and (overlayp previous) (overlay-buffer previous))
          (agent-shell-inline--response-overlay-render previous))
        (agent-shell-inline--response-overlay-render overlay))))
  overlay)

(defun agent-shell-inline--focus-from-click (event)
  "Focus the preview under EVENT without moving its source view."
  (interactive "e")
  (let* ((last-input-event event)
         (window (posn-window (event-start event)))
         (overlay (agent-shell-inline--response-overlay-at-point)))
    (when (and overlay (window-live-p window))
      (select-window window)
      (agent-shell-inline--focus-preview overlay))))

(defun agent-shell-inline--response-overlay-at-point ()
  "Return the mouse target without focusing it, or the selected keyboard preview."
  (let* ((mouse (or (mouse-event-p last-input-event)
                    (and (consp last-input-event)
                         (memq (event-basic-type last-input-event)
                               '(wheel-up wheel-down mouse-4 mouse-5)))))
         (position (and mouse (event-start last-input-event)))
         (window (if mouse (posn-window position) (selected-window)))
         (text (and mouse (posn-string position)))
         (target (and text (get-text-property (cdr text) 'agent-shell-inline-overlay (car text)))))
    (if (and (overlayp target) (overlay-buffer target))
        target
      (when (windowp window)
        (with-selected-window window
          (let* ((point (if mouse (posn-point position) (point)))
                 (selected agent-shell-inline--selected-preview)
                 (nearest (and (not mouse) (overlayp selected)
                               (eq (overlay-buffer selected) (current-buffer)) selected))
                 distance)
            (unless nearest
              (when (integer-or-marker-p point)
                (dolist (overlay (overlays-in (point-min) (point-max)))
                  (when (overlay-get overlay 'agent-shell-inline)
                    (let ((delta (max 0 (- (overlay-start overlay) point) (- point (overlay-end overlay)))))
                      (when (or (null distance) (< delta distance)
                                (and (= delta distance) (> (overlay-start overlay) (overlay-start nearest))))
                        (setq nearest overlay distance delta)))))))
            (if mouse nearest (agent-shell-inline--focus-preview nearest))))))))

(defun agent-shell-inline--measure-without-previews (previews measure &rest args)
  "Call MEASURE with ARGS, excluding PREVIEWS' virtual rows temporarily."
  (let ((strings (mapcar (lambda (overlay)
                           (cons overlay (overlay-get overlay 'after-string)))
                         previews)))
    (unwind-protect
        (progn
          (dolist (entry strings) (overlay-put (car entry) 'after-string nil))
          (apply measure args))
      (dolist (entry strings) (overlay-put (car entry) 'after-string (cdr entry))))))

(defun agent-shell-inline--scroll-down-position (scroll delta)
  "Call SCROLL by DELTA without resetting pixels at a preview's anchor."
  (if (not agent-shell-inline--response-overlay-mode)
      (funcall scroll delta)
    (let* ((start (window-start))
           (end (save-excursion (goto-char start) (line-end-position)))
           (previews (cl-remove-if-not
                      (lambda (overlay)
                        (and (overlay-get overlay 'agent-shell-inline)
                             (overlay-get overlay 'after-string)))
                      (overlays-in start (min (point-max) (1+ end)))))
           (position (symbol-function 'posn-at-point)))
      (if (not previews)
          (funcall scroll delta)
        (cl-letf (((symbol-function 'posn-at-point)
                   (lambda (&optional pos window)
                     (if (and pos (> pos start)
                              (seq-some (lambda (overlay) (= pos (overlay-end overlay))) previews))
                         ;; String rows all map to the anchor.  Measure its
                         ;; actual text row, including wrapped source lines.
                         (list (or window (selected-window)) pos
                               (cons 0 (cdr (agent-shell-inline--measure-without-previews
                                             (seq-filter (lambda (overlay) (= pos (overlay-end overlay))) previews)
                                             #'window-text-pixel-size
                                             window start pos nil nil nil t)))
                               0)
                       (funcall position pos window)))))
          (funcall scroll delta))))))
(defun agent-shell-inline--scroll-up-measure (scroll delta)
  "Call SCROLL by DELTA without counting an already traversed preview twice."
  (let* ((start (window-start))
         (previews (and agent-shell-inline--response-overlay-mode
                        (> delta (window-vscroll nil t))
                        (cl-remove-if-not
                         (lambda (overlay)
                           (and (overlay-get overlay 'agent-shell-inline)
                                (= (overlay-end overlay) start)
                                (overlay-get overlay 'after-string)))
                         (overlays-in (max (point-min) (1- start)) (min (point-max) (1+ start)))))))
    (if (not previews)
        (funcall scroll delta)
      (let ((measure (symbol-function 'window-text-pixel-size)))
        (cl-letf (((symbol-function 'window-text-pixel-size)
                   (lambda (&rest args)
                     (if (and (consp (nth 1 args))
                              (equal (car (nth 1 args)) start)
                              (equal (nth 2 args) start))
                         (apply #'agent-shell-inline--measure-without-previews previews measure args)
                       (apply measure args)))))
          (funcall scroll delta))))))
(with-eval-after-load 'pixel-scroll
  (advice-add 'pixel-scroll-precision-scroll-down-page :around
              #'agent-shell-inline--scroll-down-position)
  (advice-add 'pixel-scroll-precision-scroll-up-page :around
              #'agent-shell-inline--scroll-up-measure))

(defun agent-shell-inline--move-past-preview (move count &rest args)
  "Retry stalled line MOVE past an inline preview using buffer lines.
Normal visual movement, including Magit's selection handling, runs first."
  (let ((start (point)))
    (prog1 (apply move count args)
      (when (and agent-shell-inline--response-overlay-mode
                 (/= count 0)
                 (= start (point))
                 (cl-some (lambda (overlay)
                            (and (overlay-get overlay 'agent-shell-inline)
                                 (overlay-get overlay 'after-string)))
                          (overlays-in (line-beginning-position)
                                       (min (point-max) (1+ (line-end-position))))))
        (let ((line-move-visual nil)
              (auto-window-vscroll nil))
          (apply move count args))))))

(advice-add 'line-move :around #'agent-shell-inline--move-past-preview)

(defun agent-shell-inline--response-overlay-wheel (event)
  "Scroll only the reply under EVENT, clamping at either end."
  (interactive "e")
  (let* ((last-input-event event)
         (overlay (agent-shell-inline--response-overlay-at-point))
         (index (and overlay (or (overlay-get overlay 'agent-shell-inline-scroll-index) 0)))
         (delta (if (memq (event-basic-type event) '(mouse-4 wheel-up)) -1 1)))
    (when overlay
      (agent-shell-inline--response-overlay-scroll-to (+ index delta) overlay))))

(defun agent-shell-inline--response-overlay-down (&optional response-ov)
  "Scroll RESPONSE-OV down by one line."
  (interactive (list (agent-shell-inline--response-overlay-at-point)))
  (when response-ov
    (agent-shell-inline--response-overlay-scroll-to
     (1+ (or (overlay-get response-ov 'agent-shell-inline-scroll-index) 0)) response-ov)))

(defun agent-shell-inline--response-overlay-up (&optional response-ov)
  "Scroll RESPONSE-OV up by one line."
  (interactive (list (agent-shell-inline--response-overlay-at-point)))
  (when response-ov
    (agent-shell-inline--response-overlay-scroll-to
     (1- (or (overlay-get response-ov 'agent-shell-inline-scroll-index) 0)) response-ov)))

(defun agent-shell-inline--response-overlay-pagedown (&optional response-ov)
  "Scroll RESPONSE-OV down by one page (its full height)."
  (interactive (list (agent-shell-inline--response-overlay-at-point)))
  (when response-ov
    (agent-shell-inline--response-overlay-scroll-to
     (+ (or (overlay-get response-ov 'agent-shell-inline-scroll-index) 0)
        (overlay-get response-ov 'agent-shell-inline-height))
     response-ov)))

(defun agent-shell-inline--response-overlay-pageup (&optional response-ov)
  "Scroll RESPONSE-OV up by one page (its full height)."
  (interactive (list (agent-shell-inline--response-overlay-at-point)))
  (when response-ov
    (agent-shell-inline--response-overlay-scroll-to
     (- (or (overlay-get response-ov 'agent-shell-inline-scroll-index) 0)
        (overlay-get response-ov 'agent-shell-inline-height))
     response-ov)))

(defun agent-shell-inline--response-overlay-resize (response-ov delta)
  "Resize RESPONSE-OV height by DELTA lines.
DELTA is a positive or negative integer.  Any other value resets the height."
  (interactive (list (agent-shell-inline--response-overlay-at-point)
                     (prefix-numeric-value current-prefix-arg)))
  (when response-ov
    (overlay-put response-ov 'agent-shell-inline-height
                 (if (integerp delta)
                     (max 2 (+ delta (overlay-get response-ov 'agent-shell-inline-height)))
                   (agent-shell-inline--response-overlay-height)))
    (agent-shell-inline--response-overlay-render response-ov)))

(defun agent-shell-inline-cycle-reference (&optional origin interactivep)
  "Cycle the reference type for ORIGIN and highlight it.
When called interactively (INTERACTIVEP), you can continue cycling with
. (period)."
  (interactive (list nil t))
  (when-let* ((origin-marker
               (or origin (plist-get agent-shell-inline--context :marker)))
              (origin-buf (marker-buffer origin-marker))
              ((buffer-live-p origin-buf)))
    (pcase-let ((`(,type ,start . ,end)
                 (agent-shell-inline--reference-bounds
                  origin-marker agent-shell-inline--reference-type)))
      (setq agent-shell-inline--reference-type type)

      (prog1
          (if-let* ((reference-ov (plist-get agent-shell-inline--context :reference-ov))
                    ((overlayp reference-ov)))
              (progn
                (if (and start end (> end start))
                    (move-overlay reference-ov start end origin-buf)
                  (delete-overlay reference-ov)
                  (plist-put agent-shell-inline--context :reference-ov nil))
                reference-ov)
            (when (and start end (> end start))
              (let ((ov (make-overlay start end origin-buf)))
                (overlay-put ov 'face 'secondary-selection)
                (overlay-put ov 'priority 100)
                (overlay-put ov 'evaporate t)
                (plist-put agent-shell-inline--context :reference-ov ov)
                ov)))
        (when interactivep
          (set-transient-map
           (define-keymap
             "." #'agent-shell-inline-cycle-reference
             "C-g" (lambda () (interactive) (agent-shell-inline-clear-reference)))
           nil nil "Repeat or clear with %k"))))))


;;;; Agent Shell backend

(defvar-local agent-shell-inline--active nil
  "Response overlay following the current inline request in this shell.")

(defun agent-shell-inline--shell-p (buffer)
  "Return non-nil when BUFFER is a live Agent Shell conversation."
  (and (buffer-live-p buffer)
       (with-current-buffer buffer (derived-mode-p 'agent-shell-mode))))

(defun agent-shell-inline--resolve-shell (&optional buffer)
  "Resolve BUFFER, the last conversation or a shell in the current project.
Create a shell without displaying it when the project has no conversation."
  (let ((shell (or buffer
                   (and (agent-shell-inline--shell-p agent-shell-inline--last)
                        agent-shell-inline--last)
                   (and (derived-mode-p 'agent-shell-mode) (current-buffer))
                   (car (agent-shell-project-buffers)))))
    (when shell
      (setq shell (get-buffer shell))
      (unless (agent-shell-inline--shell-p shell)
        (user-error "The selected Agent Shell conversation is no longer available")))
    (unless shell
      ;; Agent Shell 0.91.1 has no public project-start API with no-display.
      (setq shell (agent-shell--new-shell
                   :location (if-let* ((project (project-current nil)))
                                 (project-root project)
                               default-directory)
                   :no-display t)))
    (setq agent-shell-inline--last shell
          agent-shell-inline--recent (cons shell (delq shell agent-shell-inline--recent)))
    shell))

(defun agent-shell-inline--available-p (shell)
  "Check whether SHELL can accept an inline request, or explain why not."
  (unless (agent-shell-inline--shell-p shell)
    (user-error "The conversation has been closed; choose another shell"))
  (with-current-buffer shell
    (when (or (memq (agent-shell-status) '(busy blocked))
              (and (overlayp agent-shell-inline--active)
                   (overlay-buffer agent-shell-inline--active)))
      (user-error "Agent is busy; keep this draft, or visit the conversation to queue it"))))

(defun agent-shell-inline--detach (overlay)
  "Unsubscribe OVERLAY and release its pending submission."
  (when-let* ((timer (overlay-get overlay 'agent-shell-inline-render-timer)))
    (cancel-timer timer)
    (overlay-put overlay 'agent-shell-inline-render-timer nil))
  (when-let* ((timer (overlay-get overlay 'agent-shell-inline-timer)))
    (cancel-timer timer)
    (overlay-put overlay 'agent-shell-inline-timer nil))
  (let* ((context (overlay-get overlay 'agent-shell-inline))
         (shell (plist-get context :buffer)))
    (when (buffer-live-p shell)
      (with-current-buffer shell
        (when-let* ((token (plist-get context :subscription)))
          (agent-shell-unsubscribe :subscription token))
        (when (eq agent-shell-inline--active overlay)
          (setq agent-shell-inline--active nil))))
    (setf (plist-get context :subscription) nil
          (plist-get context :pending) nil)))

(defun agent-shell-inline--finish (overlay status)
  "Finish the current turn with STATUS; keep OVERLAY following its conversation."
  (let* ((context (overlay-get overlay 'agent-shell-inline))
         (shell (plist-get context :buffer)))
    (when-let* ((timer (overlay-get overlay 'agent-shell-inline-timer)))
      (cancel-timer timer)
      (overlay-put overlay 'agent-shell-inline-timer nil))
    (setf (plist-get context :started) nil
          (plist-get context :pending) nil)
    (when (buffer-live-p shell)
      (with-current-buffer shell
        (when (eq agent-shell-inline--active overlay)
          (setq agent-shell-inline--active nil)))))
  (overlay-put overlay 'agent-shell-inline-activity nil)
  (overlay-put overlay 'agent-shell-inline-status status)
  (agent-shell-inline--response-overlay-render overlay))

(defun agent-shell-inline--check-activity (overlay)
  "Check OVERLAY's transport without a separate waiting animation."
  (let* ((context (overlay-get overlay 'agent-shell-inline))
         (shell (plist-get context :buffer)))
    (cond
     ((not (overlay-buffer overlay)) (agent-shell-inline--detach overlay))
     ((not (buffer-live-p shell))
      (agent-shell-inline--finish overlay "Conversation closed")
      (agent-shell-inline--detach overlay))
     (t
      (with-current-buffer shell
        (let ((process (map-nested-elt agent-shell--state '(:client :process))))
          (cond
           ((and (plist-get context :started) (not (and process (process-live-p process))))
            (agent-shell-inline--finish overlay "Disconnected — visit conversation"))
           ((and (plist-get context :started) (eq (agent-shell-status) 'ready))
            (agent-shell-inline--finish overlay "Stopped — visit conversation")))))))))

(defun agent-shell-inline--start-following (overlay prompt)
  "Follow newly submitted PROMPT in OVERLAY, retaining browsed history."
  (let* ((context (overlay-get overlay 'agent-shell-inline))
         (shell (plist-get context :buffer)))
    (setf (plist-get context :started) t
          (plist-get context :prompt) prompt)
    (with-current-buffer (plist-get context :src) (erase-buffer))
    (overlay-put overlay 'agent-shell-inline-interaction-index
                 (with-current-buffer shell (max 0 (1- (length (shell-maker-history))))))
    (overlay-put overlay 'agent-shell-inline-history-total
                 (1+ (overlay-get overlay 'agent-shell-inline-interaction-index)))
    (overlay-put overlay 'agent-shell-inline-message-group nil)
    (overlay-put overlay 'agent-shell-inline-review nil)
    (overlay-put overlay 'agent-shell-inline-status "Working")
    (overlay-put overlay 'agent-shell-inline-activity nil)
    (overlay-put overlay 'agent-shell-inline-last-event (float-time))
    (unless (overlay-get overlay 'agent-shell-inline-history-index)
      (overlay-put overlay 'agent-shell-inline-scroll-index 0))
    (unless (overlay-get overlay 'agent-shell-inline-timer)
      (overlay-put overlay 'agent-shell-inline-timer
                   (run-at-time 1 1 #'agent-shell-inline--check-activity overlay)))))

(defun agent-shell-inline--submit-pending (overlay)
  "Submit the pending prompt for OVERLAY once the shell is initialised."
  (let* ((context (overlay-get overlay 'agent-shell-inline))
         (shell (plist-get context :buffer))
         (text (plist-get context :pending)))
    (when (and text (buffer-live-p shell)
               (agent-shell-initialized-p :shell-buffer shell))
      (with-current-buffer shell
        (when (memq (agent-shell-status) '(busy blocked))
          (user-error "Agent became busy before the inline prompt could be sent"))
        ;; Clear first: synchronous callbacks must not submit this text twice.
        (setf (plist-get context :pending) nil
              (plist-get context :started) t)
        (overlay-put overlay 'agent-shell-inline-status "Working")
        (overlay-put overlay 'agent-shell-inline-interaction-index (length (shell-maker-history)))
        (agent-shell-insert :text (concat "\n\n" text) :submit t :no-focus t :shell-buffer shell)
        (when-let* ((previous (plist-get context :previous-preview)))
          (agent-shell-inline-clear-response-overlay previous)
          (setf (plist-get context :previous-preview) nil))))))

(defun agent-shell-inline--on-event (overlay event)
  "Update OVERLAY from an Agent Shell EVENT, without changing window focus."
  (if (not (buffer-live-p (overlay-buffer overlay)))
      (agent-shell-inline--detach overlay)
    (let* ((context (overlay-get overlay 'agent-shell-inline))
           (data (map-elt event :data))
           (kind (map-elt event :event)))
      (unless (eq kind 'idle)
        (overlay-put overlay 'agent-shell-inline-last-event (float-time)))
      (when (memq kind '(input-submitted turn-complete))
        (overlay-put overlay 'agent-shell-inline-history-total
                     (with-current-buffer (plist-get context :buffer) (length (shell-maker-history)))))
      (when (or (plist-get context :started) (plist-get context :pending) (eq kind 'clean-up))
	(pcase kind
          ('input-submitted
           (agent-shell-inline--start-following overlay (map-elt data :prompt)))
          ('init-finished
           (condition-case err
               (agent-shell-inline--submit-pending overlay)
             (error
              (agent-shell-inline--update-response-overlay
               (format "\nCould not send: %s\n\nUnsent prompt:\n%s"
                       (error-message-string err) (plist-get context :prompt)) overlay)
              (agent-shell-inline--finish overlay "Not sent"))))
          ('agent-message-chunk
           (when (and (plist-get context :started) (stringp (map-elt data :text-chunk)))
             ;; The pinned event API omits message boundaries.  Its group counter
             ;; advances before this event, including after thoughts and tools.
             (let ((group (with-current-buffer (plist-get context :buffer)
                            (map-elt agent-shell--state :chunked-group-count))))
               (when (and (overlay-get overlay 'agent-shell-inline-message-group)
                          (not (equal group (overlay-get overlay 'agent-shell-inline-message-group))))
		 (agent-shell-inline--update-response-overlay "\n\n" overlay))
               (overlay-put overlay 'agent-shell-inline-message-group group))
             (agent-shell-inline--update-response-overlay (map-elt data :text-chunk) overlay)))
          ('tool-call-update
           (unless (overlay-get overlay 'agent-shell-inline-review)
             (let* ((title (or (map-nested-elt data '(:tool-call :title)) "working"))
                    (preview (replace-regexp-in-string
                              "[\n\r\t]+" " " (substring title 0 (min 160 (length title))))))
               (overlay-put overlay 'agent-shell-inline-status
                            (format "Tool: %s" (truncate-string-to-width preview 100 nil nil "…"))))))
          ((or 'permission-request 'elicitation-request)
           (overlay-put overlay 'agent-shell-inline-review kind)
           (overlay-put overlay 'agent-shell-inline-status "Review required — SPC a v")
           (when (eq overlay (buffer-local-value 'agent-shell-inline--active
                                                 (plist-get context :buffer)))
             (message "Agent needs your input; use agent-shell-inline-review or SPC a v")))
          ((or 'permission-response 'elicitation-response)
           (let ((pending (and (bound-and-true-p agent-shell-permission-transient-mode)
                               (> (agent-shell-permission-transient--buffer-pending-count
                                   (plist-get context :buffer) (map-elt data :request-id)) 0))))
             (overlay-put overlay 'agent-shell-inline-review (and pending 'permission-request))
             (overlay-put overlay 'agent-shell-inline-status
                          (if pending "Review required — SPC a v" "Working"))))
          ('turn-complete
           (when (plist-get context :started)
             (overlay-put overlay 'agent-shell-inline-review nil)
             (agent-shell-inline--finish
              overlay (format "Finished: %s" (or (map-elt data :stop-reason) "done")))))
          ('error
           (agent-shell-inline--update-response-overlay
            (format "\nAgent error: %s" (or (map-elt data :message) "unknown error")) overlay)
           (when (plist-get context :pending)
             (agent-shell-inline--update-response-overlay
              (format "\n\nUnsent prompt:\n%s" (plist-get context :prompt)) overlay))
           (agent-shell-inline--finish overlay "Error — visit conversation"))
          ('session-selection-cancelled
           (agent-shell-inline--finish overlay "Session selection cancelled"))
          ('clean-up
           (agent-shell-inline--finish overlay "Conversation closed")
           (agent-shell-inline--detach overlay))))
      (if (eq kind 'agent-message-chunk)
          (when (plist-get context :started) (agent-shell-inline--schedule-render overlay))
        (agent-shell-inline--response-overlay-render overlay)))))

(defun agent-shell-inline--send (text context)
  "Send TEXT using CONTEXT and return the inline response overlay."
  (let ((shell (plist-get context :buffer)))
    (agent-shell-inline--available-p shell)
    (when (and (string-empty-p (string-trim text))
               (with-current-buffer shell
                 (or (not comint-last-prompt)
                     (string-empty-p
                      (string-trim (buffer-substring-no-properties
                                    (cdr comint-last-prompt) (point-max)))))))
      (user-error "Enter a prompt or select reference text first"))
    (setq context (copy-sequence context))
    (setf (plist-get context :marker) (copy-marker (plist-get context :marker)))
    ;; The prompt owns the temporary highlight; TEXT already includes its contents.
    (setf (plist-get context :reference-ov) nil)
    (let ((overlay (agent-shell-inline--setup-response-overlay context)))
      (setq context (overlay-get overlay 'agent-shell-inline))
      (setf (plist-get context :pending) text
            (plist-get context :prompt) text)
      (with-current-buffer shell (setq agent-shell-inline--active overlay))
      (setf (plist-get context :subscription)
            (agent-shell-subscribe-to
             :shell-buffer shell
             :on-event (lambda (event) (agent-shell-inline--on-event overlay event))))
      (condition-case err
          (agent-shell-inline--submit-pending overlay)
        (error
         (agent-shell-inline-clear-response-overlay overlay)
         (signal (car err) (cdr err))))
      (setq agent-shell-inline--recent
            (cons shell (delq shell agent-shell-inline--recent)))
      overlay)))

;;;; Overlay presentation and lifecycle

(defcustom agent-shell-inline-key-bindings nil
  "Preferred command bindings to display in headers and the options panel.
Each entry is a command and its key description.  These describe bindings
provided by the editor configuration; they do not install bindings."
  :type '(alist :key-type function :value-type string)
  :group 'agent-shell-inline)

(defun agent-shell-inline--key-description (command)
  "Return a highlighted key description for COMMAND."
  (propertize
   (or (alist-get command agent-shell-inline-key-bindings)
       (when-let* ((key (where-is-internal command
                                         (list agent-shell-inline-map
                                               agent-shell-inline--response-overlay-mode-map) t)))
         (key-description key))
       (format "M-x %s" command))
   'face 'help-key-binding))

(defun agent-shell-inline--click (event)
  "Run EVENT's displayed action, including within a transient map."
  (interactive "e")
  (let* ((text (posn-string (event-start event)))
         (map (and text (get-text-property (cdr text) 'keymap (car text))))
         (command (lookup-key (or map agent-shell-inline-response-overlay-map)
                              (vector (car event)))))
    (when (commandp command)
      (if (memq command '(agent-shell-inline--response-overlay-drag
                          agent-shell-inline--focus-from-click))
          (funcall command event)
        (let ((last-input-event event))
          (call-interactively command))))))

(defun agent-shell-inline--pending-permissions (overlay)
  "Return a snapshot of OVERLAY's conversation permissions that allow once."
  (when (bound-and-true-p agent-shell-permission-transient-mode)
    (let ((shell (plist-get (overlay-get overlay 'agent-shell-inline) :buffer)))
      (seq-filter
       (lambda (request)
         (and (eq shell (agent-shell-permission-transient--request-shell-buffer request))
              (agent-shell-permission-transient--option request "allow_once")))
       agent-shell-permission-transient--queue))))

(defun agent-shell-inline-approve (overlay &optional all)
  "Approve the oldest pending request in OVERLAY, or the current snapshot if ALL."
  (interactive (list (agent-shell-inline--response-overlay-at-point) current-prefix-arg))
  (let ((requests (agent-shell-inline--pending-permissions overlay)))
    (unless requests (user-error "No pending permissions that allow once"))
    (dolist (request (if all requests (list (car requests))))
      (when (agent-shell-permission-transient--request-pending-p request)
        (agent-shell-permission-transient--respond request "allow_once")))
    (agent-shell-inline--response-overlay-render overlay)))

(defun agent-shell-inline-approve-all (overlay)
  "Approve the current pending-permission snapshot for OVERLAY."
  (interactive (list (agent-shell-inline--response-overlay-at-point)))
  (agent-shell-inline-approve overlay t))

(defun agent-shell-inline--response-button (label action)
  "Make only the highlighted shortcut in LABEL run interactive ACTION."
  (let ((map (make-sparse-keymap))
        (plain-map (make-sparse-keymap))
        (text (copy-sequence label))
        (position 0))
    (set-keymap-parent map agent-shell-inline-response-overlay-map)
    (set-keymap-parent plain-map agent-shell-inline-response-overlay-map)
    (dolist (key '([down-mouse-1] [header-line down-mouse-1]))
      (define-key map key #'ignore)
      (define-key plain-map key #'ignore))
    (define-key plain-map [down-mouse-1] #'agent-shell-inline--response-overlay-drag)
    (dolist (key '([mouse-1] [header-line mouse-1]))
      (define-key map key action)
      (define-key plain-map key #'ignore))
    (define-key plain-map [mouse-1] #'agent-shell-inline--focus-from-click)
    ;; Plain labels select or drag the preview, but never run its actions.
    (add-text-properties 0 (length text)
                         (list 'keymap plain-map 'pointer 'arrow 'mouse-face nil 'help-echo nil) text)
    (while (< position (length text))
      (let ((end (next-single-property-change position 'face text (length text))))
        (when (eq (get-text-property position 'face text) 'help-key-binding)
          (add-text-properties position end
                               (list 'keymap map 'mouse-face 'highlight 'pointer 'hand
                                     'help-echo "Click to run this action") text))
        (setq position end)))
    text))

(defun agent-shell-inline--response-overlay-header (overlay &optional up down)
  "Return the status and navigation header for OVERLAY, with UP and DOWN hints."
  (format "%s%s%s%s%s%s | %s"
          (if (and up (not (string-empty-p up)))
              (agent-shell-inline--response-button
               (propertize up 'face 'help-key-binding) (lambda () (interactive) (agent-shell-inline--response-overlay-up overlay)))
            "")
          (if (and down (not (string-empty-p down)))
              (agent-shell-inline--response-button
               (propertize down 'face 'help-key-binding) (lambda () (interactive) (agent-shell-inline--response-overlay-down overlay)))
            "")
          (if-let* ((activity (overlay-get overlay 'agent-shell-inline-activity)))
              (concat (propertize activity 'face 'shadow) " ")
            "")
          (if-let* ((index (overlay-get overlay 'agent-shell-inline-history-index)))
              (format "Reply %s/%s | Live: %s" (1+ index)
                      (overlay-get overlay 'agent-shell-inline-history-total)
                      (overlay-get overlay 'agent-shell-inline-status))
            (or (overlay-get overlay 'agent-shell-inline-status) "Starting agent"))
          (if (agent-shell-inline--pending-permissions overlay)
              (concat " | "
                      (agent-shell-inline--response-button
                       (format "Approve: %s" (agent-shell-inline--key-description 'agent-shell-inline-approve))
                       (lambda () (interactive) (agent-shell-inline-approve overlay)))
                      " / "
                      (agent-shell-inline--response-button
                       (format "Approve all: %s" (agent-shell-inline--key-description 'agent-shell-inline-approve-all))
                       (lambda () (interactive) (agent-shell-inline-approve overlay t))))
            "")
          (let ((newer (- (or (overlay-get overlay 'agent-shell-inline-history-total) 0)
                          (1+ (or (overlay-get overlay 'agent-shell-inline-history-index)
                                  (overlay-get overlay 'agent-shell-inline-interaction-index) -1)))))
            (if (> newer 0)
                (concat " | " (agent-shell-inline--response-button
                               (format "%d newer · Latest reply: %s" newer
                                       (agent-shell-inline--key-description 'agent-shell-inline-latest-reply))
                               (lambda () (interactive) (agent-shell-inline-latest-reply overlay))))
              ""))
          (or (overlay-get overlay 'agent-shell-inline-header)
              (mapconcat
               #'identity
               (list
                (agent-shell-inline--response-button
                 (format "reply: %s" (agent-shell-inline--key-description 'agent-shell-inline-reply))
                 (lambda () (interactive) (agent-shell-inline overlay)))
                (agent-shell-inline--response-button
                 (format "navigate: %s" (agent-shell-inline--key-description 'agent-shell-inline-navigate))
                 (lambda () (interactive) (agent-shell-inline-navigate overlay)))
                (agent-shell-inline--response-button
                 (format "more: %s" (agent-shell-inline--key-description 'agent-shell-inline--response-overlay-dispatch))
                 (lambda () (interactive) (agent-shell-inline--response-overlay-dispatch overlay))))
               ", "))))

(defun agent-shell-inline--update-response-overlay (chunk overlay)
  "Append streamed CHUNK to OVERLAY's Markdown preview."
  (when-let* (((overlay-buffer overlay))
              (source (plist-get (overlay-get overlay 'agent-shell-inline) :src))
              ((buffer-live-p source)))
    (with-current-buffer source
      (goto-char (point-max))
      (insert chunk))))

(defun agent-shell-inline--schedule-render (overlay)
  "Coalesce streamed chunks into one refresh per tenth of a second."
  (unless (overlay-get overlay 'agent-shell-inline-render-timer)
    (overlay-put overlay 'agent-shell-inline-render-timer
                 (run-at-time 0.1 nil #'agent-shell-inline--response-overlay-render overlay))))

(defun agent-shell-inline--display-source (overlay)
  "Return the buffer displayed by OVERLAY, including a browsed history entry."
  (or (overlay-get overlay 'agent-shell-inline-history-source)
      (plist-get (overlay-get overlay 'agent-shell-inline) :src)))

(defun agent-shell-inline--show-live (overlay)
  "Return OVERLAY to its own live response without changing the conversation."
  (when-let* ((history (overlay-get overlay 'agent-shell-inline-history-source)))
    (when (buffer-live-p history) (kill-buffer history)))
  (overlay-put overlay 'agent-shell-inline-history-source nil)
  (overlay-put overlay 'agent-shell-inline-history-index nil)
  (overlay-put overlay 'agent-shell-inline-scroll-index 0)
  (agent-shell-inline--response-overlay-render overlay))

(defun agent-shell-inline-latest-reply (&optional overlay)
  "Show the latest reply in OVERLAY's conversation, following it if still busy."
  (interactive (list (agent-shell-inline--response-overlay-at-point)))
  (unless (and (overlayp overlay) (overlay-buffer overlay))
    (user-error "No inline response here"))
  (let* ((context (overlay-get overlay 'agent-shell-inline))
         (shell (plist-get context :buffer)))
    (unless (agent-shell-inline--shell-p shell)
      (user-error "This conversation has been closed"))
    (let* ((history (with-current-buffer shell (shell-maker-history)))
           (latest (car (last history)))
           (busy (with-current-buffer shell (memq (agent-shell-status) '(busy blocked))))
           (active (buffer-local-value 'agent-shell-inline--active shell))
           (group (and (overlayp active) (overlay-get active 'agent-shell-inline-message-group)))
           (review (and (overlayp active) (overlay-get active 'agent-shell-inline-review)))
           (active-source (and (overlayp active) (overlay-buffer active)
                               (plist-get (overlay-get active 'agent-shell-inline) :src)))
           (text (if (and busy (buffer-live-p active-source))
                     (with-current-buffer active-source (buffer-string))
                   (if latest (agent-shell-inline--history-response (cdr latest)) ""))))
      (agent-shell-inline--show-live overlay)
      (agent-shell-inline--finish overlay (if latest "Latest reply" "Ready"))
      (with-current-buffer (plist-get context :src) (erase-buffer))
      (setf (plist-get context :prompt) (car latest))
      (overlay-put overlay 'agent-shell-inline-interaction-index (and latest (1- (length history))))
      (overlay-put overlay 'agent-shell-inline-history-total (length history))
      (overlay-put overlay 'agent-shell-inline-review nil)
      (overlay-put overlay 'agent-shell-inline-message-group nil)
      (when (and busy latest)
        (agent-shell-inline--start-following overlay (car latest))
        (overlay-put overlay 'agent-shell-inline-message-group group)
        (overlay-put overlay 'agent-shell-inline-review review))
      (agent-shell-inline--update-response-overlay text overlay)
      (agent-shell-inline--response-overlay-render overlay))))

(defun agent-shell-inline-select-session (overlay &optional name)
  "Choose NAME for OVERLAY, or for the current inline draft."
  (interactive (list (agent-shell-inline--response-overlay-at-point)))
  (if (and (null overlay) (derived-mode-p 'agent-shell-inline-prompt-mode))
      (if name
          (agent-shell-inline-switch-buffer name)
        (call-interactively #'agent-shell-inline-switch-buffer))
    (unless (and (overlayp overlay) (overlay-buffer overlay))
      (user-error "No inline response here"))
    (let* ((name (or name (completing-read "Conversation: "
					   (cons "New agent shell" (mapcar #'buffer-name (agent-shell-buffers)))
					   nil t)))
           (shell (if (equal name "New agent shell")
                      (with-current-buffer (overlay-buffer overlay)
			(agent-shell--new-shell :location default-directory :no-display t))
                    (get-buffer name)))
           (context (overlay-get overlay 'agent-shell-inline)))
      (unless (agent-shell-inline--shell-p shell)
	(user-error "Conversation is no longer available"))
      (agent-shell-inline--focus-preview overlay)
      (setq agent-shell-inline--recent (cons shell (delq shell agent-shell-inline--recent)))
      (unless (eq shell (plist-get context :buffer))
	(when-let* ((exit (overlay-get overlay 'agent-shell-inline-navigation-exit)))
          (funcall exit))
	(agent-shell-inline--detach overlay)
	(setf (plist-get context :buffer) shell
              (plist-get context :started) nil
              (plist-get context :previous-preview) nil)
	(agent-shell-inline-latest-reply overlay)
	(setf (plist-get context :subscription)
              (agent-shell-subscribe-to
               :shell-buffer shell
               :on-event (lambda (event) (agent-shell-inline--on-event overlay event))))))))

(defun agent-shell-inline--move-history (overlay direction)
  "Show the adjacent conversation reply in OVERLAY, moving by DIRECTION."
  (unless (and (overlayp overlay) (overlay-buffer overlay))
    (user-error "No inline response here"))
  (let* ((context (overlay-get overlay 'agent-shell-inline))
         (shell (plist-get context :buffer))
         (live-index (overlay-get overlay 'agent-shell-inline-interaction-index)))
    (unless (and (buffer-live-p shell) live-index)
      (user-error "Conversation history is not available yet"))
    (let* ((history (with-current-buffer shell (shell-maker-history)))
           (prompt (string-trim (or (plist-get context :prompt) "")))
           (index (+ direction (or (overlay-get overlay 'agent-shell-inline-history-index)
                                   live-index))))
      (when (> live-index (length history))
        (user-error "Conversation history has changed; open a new inline preview"))
      ;; Failed or still-starting requests may be absent from shell history.
      ;; Keep the original preview as a navigable entry in either case.
      (unless (equal prompt (car (nth live-index history)))
        (setq history (append (seq-take history live-index)
                              (list (cons prompt nil))
                              (nthcdr live-index history))))
      (cond
       ((< index 0) (message "First reply"))
       ((>= index (length history)) (message "Latest reply"))
       ((= index live-index) (agent-shell-inline--show-live overlay))
       (t
        (let ((buffer (or (overlay-get overlay 'agent-shell-inline-history-source)
                          (generate-new-buffer " *agent-shell-inline-history*"))))
          (with-current-buffer buffer
            (agent-shell-inline--prepare-response-buffer)
            (erase-buffer)
            (insert (agent-shell-inline--history-response (cdr (nth index history))))
            (font-lock-ensure))
          (overlay-put overlay 'agent-shell-inline-history-source buffer)
          (overlay-put overlay 'agent-shell-inline-history-index index)
          (overlay-put overlay 'agent-shell-inline-history-total (length history))
          (overlay-put overlay 'agent-shell-inline-scroll-index 0)
          (agent-shell-inline--response-overlay-render overlay)))))))

(defun agent-shell-inline--history-response (response)
  "Extract only agent message bodies from a propertised shell RESPONSE.
The pinned Agent Shell identifies message fragments by their qualified ID.
Read these properties and restore Markdown before removing shell styling."
  (let ((response (or response ""))
        (position 0)
        previous-id chunks messages)
    (while (< position (length response))
      (let* ((state (get-text-property position 'agent-shell-ui-state response))
             (id (map-elt state :qualified-id))
             (end (min (next-single-property-change position 'agent-shell-ui-state response (length response))
                       (next-single-property-change position 'agent-shell-ui-section response (length response)))))
        (when (and (stringp id) (string-suffix-p "-agent_message_chunk" id)
                   (eq (get-text-property position 'agent-shell-ui-section response) 'body))
          (unless (equal id previous-id)
            (when chunks
              (push (apply #'concat (nreverse chunks)) messages))
            (setq chunks nil previous-id id))
          (push (substring response position end) chunks))
        (setq position end)))
    (when chunks (push (apply #'concat (nreverse chunks)) messages))
    (if messages
        (mapconcat (lambda (message)
                     (with-temp-buffer
                       (insert message)
                       (string-trim
                        (agent-shell-markdown-reconstruct (point-min) (point-max)))))
                   (nreverse messages) "\n\n")
      "No agent message text is available for this turn. Visit the conversation to review it.")))

(defun agent-shell-inline--prepare-response-buffer ()
  "Set up the current buffer for live and historical Markdown replies."
  (unless (derived-mode-p 'markdown-mode)
    (if (require 'markdown-mode nil t)
        (progn
          (delay-mode-hooks (gfm-mode))
          (markdown-toggle-markup-hiding 1)
          (markdown-toggle-fontify-code-blocks-natively 1))
      (text-mode))))

(defun agent-shell-inline-previous-message (&optional overlay)
  "Show the previous conversation reply in OVERLAY."
  (interactive (list (agent-shell-inline--response-overlay-at-point)))
  (agent-shell-inline--move-history overlay -1))

(defun agent-shell-inline-next-message (&optional overlay)
  "Show the next existing conversation reply in OVERLAY."
  (interactive (list (agent-shell-inline--response-overlay-at-point)))
  (agent-shell-inline--move-history overlay 1))

(defun agent-shell-inline-navigate (&optional overlay)
  "Temporarily use j/k to scroll and J/K to browse conversation replies.
C-d/C-u scroll pages; g returns to this preview's live reply.
Esc or q exits.  Any other editing command exits and runs normally."
  (interactive (list (agent-shell-inline--response-overlay-at-point)))
  (let* ((overlay (or overlay (agent-shell-inline--response-overlay-at-point)))
         (window (selected-window))
         (origin (current-buffer))
         (map (make-sparse-keymap))
         hints
         commands)
    (unless (and (overlayp overlay) (overlay-buffer overlay))
      (user-error "No inline response here"))
    (agent-shell-inline--focus-preview overlay)
    (when-let* ((exit (overlay-get overlay 'agent-shell-inline-navigation-exit)))
      (funcall exit))
    (dolist (entry `(("j" "down" ,(lambda () (interactive) (agent-shell-inline--response-overlay-down overlay)))
                     ("k" "up" ,(lambda () (interactive) (agent-shell-inline--response-overlay-up overlay)))
                     ("J" "newer" ,(lambda () (interactive) (agent-shell-inline-next-message overlay)))
                     ("K" "older" ,(lambda () (interactive) (agent-shell-inline-previous-message overlay)))
                     ("C-d" "page down" ,(lambda () (interactive) (agent-shell-inline--response-overlay-pagedown overlay)))
                     ("C-u" "page up" ,(lambda () (interactive) (agent-shell-inline--response-overlay-pageup overlay)))
                     ("g" "live" ,(lambda () (interactive) (agent-shell-inline--show-live overlay)))))
      (define-key map (kbd (car entry)) (nth 2 entry))
      (push (agent-shell-inline--response-button
             (format "%s %s" (propertize (car entry) 'face 'help-key-binding)
                     (cadr entry))
             (nth 2 entry)) hints)
      (push (nth 2 entry) commands))
    (define-key map [down-mouse-1] #'agent-shell-inline--click)
    (define-key map [mouse-1] #'agent-shell-inline--click)
    (push #'agent-shell-inline--click commands)
    (dolist (key '("q" "ESC" "<escape>" "C-g"))
      (define-key map (kbd key) #'ignore))
    (push (agent-shell-inline--response-button
           (concat (propertize "Esc/q" 'face 'help-key-binding) " exit")
           (lambda ()
             (interactive)
             (when-let* ((exit (overlay-get overlay 'agent-shell-inline-navigation-exit)))
               (funcall exit)))) hints)
    (overlay-put overlay 'agent-shell-inline-header (string-join (nreverse hints) " · "))
    (agent-shell-inline--response-overlay-render overlay)
    (overlay-put
     overlay 'agent-shell-inline-navigation-exit
     (set-transient-map
      map
      (lambda ()
        (and (overlay-buffer overlay) (eq (selected-window) window)
             (eq (current-buffer) origin)
             (or (memq this-command commands)
                 (and (eq this-command 'ignore) (mouse-event-p last-command-event)))))
      (lambda ()
        (overlay-put overlay 'agent-shell-inline-navigation-exit nil)
        (when (overlay-buffer overlay)
          (overlay-put overlay 'agent-shell-inline-header nil)
          (agent-shell-inline--response-overlay-render overlay)))))
    (message "j/k scroll · J/K newer/older · C-d/C-u page · g live · Esc/q exit")))

(defun agent-shell-inline--preview-width (overlay)
  "Return the available column width for OVERLAY's display."
  (let ((windows (get-buffer-window-list (overlay-buffer overlay) nil t)))
    (max 1 (1- (if windows
                   (apply #'min (mapcar #'window-body-width windows))
                 (window-body-width))))))

(defun agent-shell-inline--wrap-lines (text width)
  "Wrap display TEXT to WIDTH columns, retaining its text properties."
  (let (lines)
    (dolist (line (split-string text "\n"))
      (while (> (string-width line) width)
        (let* ((prefix (truncate-string-to-width line width))
               (cut (max 1 (length prefix))))
          (when (and (string-match "[ \t]+[^ \t]*\\'" prefix)
                     (> (match-beginning 0) 0))
            (setq cut (match-beginning 0)))
          (push (substring line 0 cut) lines)
          (setq line (substring line cut))
          (when (string-match "\\`[ \t]+" line)
            (setq line (substring line (match-end 0))))))
      (push line lines))
    (nreverse lines)))

(defun agent-shell-inline--response-lines (overlay)
  "Return fontified response lines wrapped to OVERLAY's visible window width.
Only the display copy is wrapped; the response buffer retains the agent's text."
  (let* ((source (agent-shell-inline--display-source overlay))
         (width (agent-shell-inline--preview-width overlay))
         (key (when (buffer-live-p source)
                (list source (buffer-chars-modified-tick source) width)))
         (cached (overlay-get overlay 'agent-shell-inline-wrapped-lines)))
    (if (and cached (equal key (car cached)))
        (cdr cached)
      (let ((lines (when (buffer-live-p source)
                     (with-current-buffer source (font-lock-ensure))
                     (agent-shell-inline--wrap-lines
                      (with-current-buffer source (buffer-string)) width))))
        (overlay-put overlay 'agent-shell-inline-wrapped-lines (cons key lines))
        lines))))

(defun agent-shell-inline--render-source-previews (&rest _)
  "Refresh inline wrapping after the source window layout changes."
  (dolist (overlay (overlays-in (point-min) (point-max)))
    (when (overlay-get overlay 'agent-shell-inline)
      (agent-shell-inline--response-overlay-render overlay))))

(defun agent-shell-inline--response-overlay-render (overlay)
  "Render a scrollable slice of OVERLAY's accumulated response."
  (when-let* ((timer (overlay-get overlay 'agent-shell-inline-render-timer)))
    (cancel-timer timer)
    (overlay-put overlay 'agent-shell-inline-render-timer nil))
  (when-let* ((origin (overlay-buffer overlay))
              ((buffer-live-p origin))
              (source (agent-shell-inline--display-source overlay))
              ((buffer-live-p source)))
    (let* ((height (overlay-get overlay 'agent-shell-inline-height))
           (wrapped (agent-shell-inline--response-lines overlay))
           (lines (length wrapped))
           (index (min (or (overlay-get overlay 'agent-shell-inline-scroll-index) 0)
                       (max 0 (- lines height))))
           (text (mapconcat #'identity (seq-subseq wrapped index (min lines (+ index height))) "\n"))
           (width (agent-shell-inline--preview-width overlay))
           (shell (plist-get (overlay-get overlay 'agent-shell-inline) :buffer))
           (name (if (buffer-live-p shell) (buffer-name shell) "Closed conversation"))
           (header (agent-shell-inline--response-overlay-header
                    overlay (if (> index 0) "↑ " "")
                    (if (< (+ index height) lines) "↓ " "")))
           (session (agent-shell-inline--response-button
                     (format "%s · %s" (propertize name 'face
                                                    (if (eq overlay agent-shell-inline--focused-preview)
                                                        '(bold shadow)
                                                      'shadow))
                             (agent-shell-inline--key-description 'agent-shell-inline-select-session))
                     (lambda () (interactive) (agent-shell-inline-select-session overlay))))
           (display (concat
                     (propertize agent-shell-inline--hrule 'keymap agent-shell-inline-response-overlay-map)
                     (string-join (agent-shell-inline--wrap-lines header width) "\n")
                     (propertize (concat "\n" text agent-shell-inline--hrule)
                                 'keymap agent-shell-inline-response-overlay-map 'pointer 'hand)
                     (string-join (agent-shell-inline--wrap-lines session width) "\n"))))
      (add-text-properties 0 (length display) (list 'agent-shell-inline-overlay overlay) display)
      (overlay-put overlay 'agent-shell-inline-scroll-index index)
      (overlay-put overlay 'after-string display))))

(defun agent-shell-inline--setup-response-overlay (context)
  "Create a preview for CONTEXT, retaining its predecessor until submission."
  (let* ((marker (plist-get context :marker))
         (previous (plist-get context :response-ov))
         (previous-buffer (and (overlayp previous) (overlay-buffer previous)))
         (origin (or previous-buffer (marker-buffer marker)))
         (position (if previous-buffer (overlay-start previous) marker))
         (height (if previous-buffer
                     (overlay-get previous 'agent-shell-inline-height)
                   (max 2 (agent-shell-inline--response-overlay-height))))
         (source (generate-new-buffer " *agent-shell-inline-response*"))
         overlay)
    (unless (buffer-live-p origin)
      (kill-buffer source)
      (user-error "The source buffer has been closed"))
    (with-current-buffer source
      (agent-shell-inline--prepare-response-buffer))
    (with-current-buffer origin
      (save-excursion
        (goto-char position)
        (setq overlay (make-overlay (line-beginning-position) (line-end-position))))
      (add-hook 'kill-buffer-hook #'agent-shell-inline--clear-source nil t)
      (add-hook 'window-size-change-functions #'agent-shell-inline--render-source-previews nil t)
      (agent-shell-inline--response-overlay-mode 1))
    (setq context (append (list :subscription nil :pending nil :prompt nil
                               :started nil)
                          context))
    (setf (plist-get context :previous-preview) previous
          (plist-get context :src) source
          (plist-get context :response-ov) overlay)
    (overlay-put overlay 'agent-shell-inline context)
    (overlay-put overlay 'agent-shell-inline-height height)
    (overlay-put overlay 'agent-shell-inline-scroll-index 0)
    (overlay-put overlay 'agent-shell-inline-status "Starting agent")
    (overlay-put overlay 'priority 65)
    (overlay-put overlay 'keymap agent-shell-inline-response-overlay-map)
    (agent-shell-inline--focus-preview overlay)
    (agent-shell-inline--response-overlay-render overlay)
    overlay))

(defun agent-shell-inline--setup-response-overlay-keymap (_overlay &optional buffer)
  "Enable preview controls in BUFFER after dragging a preview there."
  (with-current-buffer (or buffer (current-buffer))
    (add-hook 'kill-buffer-hook #'agent-shell-inline--clear-source nil t)
    (add-hook 'window-size-change-functions #'agent-shell-inline--render-source-previews nil t)
    (agent-shell-inline--response-overlay-mode 1)))

(defun agent-shell-inline--clear-source ()
  "Release previews when their source buffer is killed."
  (dolist (overlay (overlays-in (point-min) (point-max)))
    (when (overlay-get overlay 'agent-shell-inline)
      (agent-shell-inline-clear-response-overlay overlay))))

(defun agent-shell-inline-clear-response-overlay (&optional overlay abort)
  "Clear OVERLAY, or the nearest preview; with ABORT also interrupt its agent."
  (interactive (list (agent-shell-inline--response-overlay-at-point) current-prefix-arg))
  (when (overlayp overlay)
    (when-let* ((exit (overlay-get overlay 'agent-shell-inline-navigation-exit)))
      (funcall exit))
    (let* ((context (overlay-get overlay 'agent-shell-inline))
           (origin (overlay-buffer overlay))
           (shell (plist-get context :buffer)))
      (when (and abort (agent-shell-inline--shell-p shell))
        (unless (agent-shell-inline--interrupt-overlay overlay)
          (user-error "Interruption cancelled")))
      (agent-shell-inline--detach overlay)
      (when-let* ((marker (plist-get context :marker))) (set-marker marker nil))
      (when-let* ((reference (plist-get context :reference-ov))) (delete-overlay reference))
      (when-let* ((source (plist-get context :src)) ((buffer-live-p source))) (kill-buffer source))
      (when-let* ((history (overlay-get overlay 'agent-shell-inline-history-source))
                  ((buffer-live-p history)))
        (kill-buffer history))
      (delete-overlay overlay)
      (when (eq agent-shell-inline--focused-preview overlay)
        (setq agent-shell-inline--focused-preview nil))
      (when (buffer-live-p origin)
        (with-current-buffer origin
          (when (eq agent-shell-inline--selected-preview overlay)
            (setq agent-shell-inline--selected-preview nil))
          (unless (cl-some (lambda (item) (overlay-get item 'agent-shell-inline))
                           (overlays-in (point-min) (point-max)))
            (agent-shell-inline--response-overlay-mode -1)))))))

(defun agent-shell-inline-interrupt ()
  "Interrupt the conversation associated with the current prompt or preview."
  (interactive)
  (if-let* ((overlay (agent-shell-inline--response-overlay-at-point)))
      (agent-shell-inline--interrupt-overlay overlay)
    (user-error "No inline response to interrupt")))

(defun agent-shell-inline--interrupt-overlay (overlay)
  "Cancel OVERLAY's pending or active request, returning non-nil if accepted."
  (let* ((context (overlay-get overlay 'agent-shell-inline))
         (shell (plist-get context :buffer)))
    (cond
     ((plist-get context :pending)
      (agent-shell-inline--finish overlay "Cancelled before sending")
      t)
     ((not (plist-get context :subscription)) t)
     ((agent-shell-inline--shell-p shell)
      (with-current-buffer shell
        (when (agent-shell-interrupt-confirmed-p)
          (agent-shell-interrupt t)
          (agent-shell-inline--finish overlay "Interrupted")
          t))))))

(defun agent-shell-inline-review (&optional overlay)
  "Review the nearest preview's permissions or visit its conversation."
  (interactive)
  (let* ((overlay (or overlay (agent-shell-inline--response-overlay-at-point)))
         (kind (and overlay (overlay-get overlay 'agent-shell-inline-review)))
         (shell (or (and overlay (plist-get (overlay-get overlay 'agent-shell-inline) :buffer))
                    (plist-get agent-shell-inline--context :buffer)
                    agent-shell-inline--last)))
    (if (and (bound-and-true-p agent-shell-permission-transient-mode)
             shell
             (> (agent-shell-permission-transient--buffer-pending-count shell) 0))
        (progn
          (when-let* ((exit (and overlay (overlay-get overlay 'agent-shell-inline-navigation-exit))))
            (funcall exit))
          (agent-shell-permission-transient-menu shell))
      (agent-shell-inline-visit-buffer shell)
      (pcase kind
        ('permission-request (agent-shell-jump-to-latest-permission-button-row))
        ('elicitation-request (agent-shell-elicitation-jump-to-latest-form))))))

(defun agent-shell-inline-copy-response (&optional overlay)
  "Copy the entire response, including lines outside the visible preview."
  (interactive)
  (let* ((overlay (or overlay (agent-shell-inline--response-overlay-at-point)))
         (source (and overlay (agent-shell-inline--display-source overlay))))
    (unless (buffer-live-p source) (user-error "No inline response to copy"))
    (kill-new (with-current-buffer source (buffer-substring-no-properties (point-min) (point-max))))
    (message "Response copied")))

(defun agent-shell-inline--response-overlay-dispatch (overlay)
  "Show clickable and keyboard actions for OVERLAY."
  (interactive (list (agent-shell-inline--response-overlay-at-point)))
  (unless (and (overlayp overlay) (overlay-buffer overlay))
    (user-error "No inline response here"))
  (agent-shell-inline--focus-preview overlay)
  (when-let* ((exit (overlay-get overlay 'agent-shell-inline-navigation-exit)))
    (funcall exit))
  (let ((map (make-sparse-keymap))
        (window (selected-window))
        (origin (current-buffer))
        hints commands exit)
    (dolist (entry
             `(("n" "navigate" ,(lambda () (agent-shell-inline-navigate overlay)))
               ("r" "reply" ,(lambda () (agent-shell-inline overlay)))
               ("v" "visit/review" ,(lambda () (agent-shell-inline-review overlay)))
               ("y" "copy" ,(lambda () (agent-shell-inline-copy-response overlay)))
               ("c" "clear" ,(lambda () (agent-shell-inline-clear-response-overlay overlay)))
               ("x" "interrupt" ,(lambda () (agent-shell-inline--interrupt-overlay overlay)))
               ("+" "+height" ,(lambda () (agent-shell-inline--response-overlay-resize overlay 3)) t)
               ("-" "-height" ,(lambda () (agent-shell-inline--response-overlay-resize overlay -3)) t)
               ("0" "reset height" ,(lambda () (agent-shell-inline--response-overlay-resize overlay 'reset)) t)
               ("q" "quit" ignore)))
      (let* ((action (nth 2 entry))
             (keep (nth 3 entry))
             (command (lambda ()
                        (interactive)
                        (unless keep (funcall exit))
                        (funcall action))))
        (define-key map (kbd (car entry)) command)
        (push command commands)
        (push (agent-shell-inline--response-button
               (format "%s %s" (propertize (car entry) 'face 'help-key-binding)
                       (cadr entry))
               command) hints)))
    (define-key map [down-mouse-1] #'agent-shell-inline--click)
    (define-key map [mouse-1] #'agent-shell-inline--click)
    (push #'agent-shell-inline--click commands)
    (define-key map (kbd "=") (lookup-key map (kbd "+")))
    (dolist (key '("ESC" "<escape>" "C-g"))
      (define-key map (kbd key) (lookup-key map (kbd "q"))))
    (overlay-put overlay 'agent-shell-inline-header (string-join (nreverse hints) "  "))
    (agent-shell-inline--response-overlay-render overlay)
    (setq exit
          (set-transient-map
           map
           (lambda ()
             (and (overlay-buffer overlay) (eq (selected-window) window)
                  (eq (current-buffer) origin)
                  (or (memq this-command commands)
                      (and (eq this-command 'ignore) (mouse-event-p last-command-event)))))
           (lambda ()
             (overlay-put overlay 'agent-shell-inline-navigation-exit nil)
             (when (overlay-buffer overlay)
               (overlay-put overlay 'agent-shell-inline-header nil)
               (agent-shell-inline--response-overlay-render overlay)))))
    (overlay-put overlay 'agent-shell-inline-navigation-exit exit)))

;;;; Prompt UI

(defvar agent-shell-inline-prompt-mode-map agent-shell-inline-map)

(defvar-local agent-shell-inline--help-buffer nil
  "Options panel belonging to this prompt.")

(defun agent-shell-inline--prompt-control (prompt label command)
  "Make highlighted text in LABEL run COMMAND in PROMPT's window."
  (agent-shell-inline--response-button
   label
   (lambda ()
     (interactive)
     (unless (buffer-live-p prompt)
       (user-error "This inline draft has been closed"))
     (let* ((clicked (and (mouse-event-p last-input-event)
                          (posn-window (event-start last-input-event))))
            (window (or (and (window-live-p clicked) (eq (window-buffer clicked) prompt) clicked)
                        (get-buffer-window prompt t))))
       (when window (select-window window))
       (with-current-buffer prompt (call-interactively command))))))

(defun agent-shell-inline--prompt-header ()
  "Fit clickable prompt shortcuts to the window, shortening details as needed."
  (let* ((prompt (current-buffer))
         (shell (plist-get agent-shell-inline--context :buffer))
         (name (if (buffer-live-p shell) (buffer-name shell) "No conversation"))
         (window (if (eq (window-buffer) prompt) (selected-window)
                   (or (get-buffer-window prompt t) (selected-window))))
         (width (max 0 (- (window-body-width window t)
                          (* 2 (frame-char-width (window-frame window)))))))
    (cl-labels
        ((control (label command)
           (agent-shell-inline--prompt-control
            prompt
            (if label
                (format "%s: %s" label (agent-shell-inline--key-description command))
              (agent-shell-inline--key-description command))
            command))
         (pixels (text)
           (let ((display (copy-sequence text)))
             (add-face-text-property 0 (length display) 'header-line t display)
             (string-pixel-width display prompt)))
         (fits (text) (<= (pixels text) width))
         (aligned (session controls)
           (concat session
                   (propertize " " 'display
                               `(space :align-to
                                       (- right (,(+ (pixels controls)
                                                      (frame-char-width (window-frame window)))))))
                   controls))
         (with-session (controls)
           (let ((low 1) (high (string-width name)) best)
             (while (<= low high)
               (let* ((columns (/ (+ low high) 2))
                      (short-name (truncate-string-to-width name columns nil nil "…"))
                      (session (concat "in " (control short-name
                                                     'agent-shell-inline-select-session))))
                 (if (fits (concat session "  " controls))
                     (setq best session low (1+ columns))
                   (setq high (1- columns)))))
             (when best (aligned best controls)))))
      (let* ((essentials (string-join (list (control "Send" 'agent-shell-inline-send)
                                           (control "Cancel" 'agent-shell-inline-quit)
                                           (control "Help" 'agent-shell-inline-help)) ", "))
             (details (concat (control (format "Including %s" (or agent-shell-inline--reference-type 'none))
                                       'agent-shell-inline-cycle-reference)
                              ", " essentials))
             (compact (string-join (list (control nil 'agent-shell-inline-send)
                                        (control nil 'agent-shell-inline-quit)
                                        (control nil 'agent-shell-inline-help)) "  "))
             (help (control nil 'agent-shell-inline-help)))
        (concat " " (or (with-session details)
                         (with-session essentials)
                         (and (fits essentials) (aligned "" essentials))
                         (and (fits compact) (aligned "" compact))
                         (aligned "" help))
                " ")))))

(define-derived-mode agent-shell-inline-prompt-mode text-mode "Agent Inline"
  "Compose a prompt for an Agent Shell conversation without visiting it."
  (visual-line-mode 1)
  (setq-local header-line-format '(:eval (agent-shell-inline--prompt-header)))
  (add-hook 'kill-buffer-hook #'agent-shell-inline--clear-prompt nil t))

(defun agent-shell-inline-clear-reference ()
  "Remove the highlighted source reference from this prompt."
  (when-let* ((overlay (plist-get agent-shell-inline--context :reference-ov)))
    (delete-overlay overlay))
  (setq agent-shell-inline--reference-type nil)
  (when agent-shell-inline--context
    (setf (plist-get agent-shell-inline--context :reference-ov) nil)))

(defun agent-shell-inline--clear-prompt ()
  "Release source references belonging to a discarded prompt."
  (agent-shell-inline--hide-help)
  (when agent-shell-inline--context
    (agent-shell-inline-clear-reference)
    (when-let* ((marker (plist-get agent-shell-inline--context :marker)))
      (set-marker marker nil))))

;;;###autoload
(defun agent-shell-inline-continue-recent ()
  "Show the latest reply and compose in the last selected inline conversation.
Reuse its history across source buffers without creating a new conversation."
  (interactive)
  (setq agent-shell-inline--recent
        (seq-filter #'agent-shell-inline--shell-p agent-shell-inline--recent))
  (let ((shell (or (car agent-shell-inline--recent)
                   ;; Recover associations when loaded into an existing Emacs.
                   (seq-some (lambda (buffer)
                               (let ((last (buffer-local-value 'agent-shell-inline--last buffer)))
                                 (and (agent-shell-inline--shell-p last) last)))
                             (buffer-list)))))
    (unless shell (user-error "No previous inline conversation is open; use SPC a p first"))
    (agent-shell-inline--continue-shell shell)))

(defun agent-shell-inline-continue-session (name)
  "Choose NAME and open a new inline preview and draft at point."
  (interactive
   (list (completing-read "Conversation: "
                          (cons "New agent shell" (mapcar #'buffer-name (agent-shell-buffers)))
                          nil t)))
  (let ((shell (if (equal name "New agent shell")
                   (agent-shell--new-shell :location default-directory :no-display t)
                 (get-buffer name))))
    (unless (agent-shell-inline--shell-p shell)
      (user-error "Conversation is no longer available"))
    (agent-shell-inline--continue-shell shell)))

(defun agent-shell-inline--continue-shell (shell)
  "Create a fresh preview and composer for SHELL at point."
  (let* ((overlay (agent-shell-inline--setup-response-overlay
                   (list :marker (point-marker) :window (selected-window) :buffer shell)))
         (context (overlay-get overlay 'agent-shell-inline)))
    (agent-shell-inline-latest-reply overlay)
    (setf (plist-get context :subscription)
          (agent-shell-subscribe-to
           :shell-buffer shell
           :on-event (lambda (event) (agent-shell-inline--on-event overlay event))))
    (agent-shell-inline overlay shell)))

;;;###autoload
(defun agent-shell-inline (&optional continue-overlay shell)
  "Compose inline, reusing SHELL or the source's project conversation.
With a prefix argument, reuse the nearest CONTINUE-OVERLAY for a follow-up."
  (interactive (list (and current-prefix-arg (agent-shell-inline--response-overlay-at-point))))
  (when (and (overlayp continue-overlay) (overlay-buffer continue-overlay))
    (agent-shell-inline--focus-preview continue-overlay))
  (let* ((origin (point-marker))
         (window (selected-window))
         (shell (agent-shell-inline--resolve-shell
                 (or shell (and (overlayp continue-overlay)
                                (plist-get (overlay-get continue-overlay 'agent-shell-inline) :buffer)))))
         (prompt (generate-new-buffer "*agent-shell-inline-prompt*")))
    (with-current-buffer prompt
      (agent-shell-inline-prompt-mode)
      (setq default-directory (buffer-local-value 'default-directory (marker-buffer origin)))
      (setq agent-shell-inline--context
            (list :marker origin :window window :buffer shell :reference-ov nil
                  :response-ov continue-overlay))
      (agent-shell-inline-cycle-reference origin))
    (pop-to-buffer prompt agent-shell-inline-display-prompt-action)
    prompt))

(defun agent-shell-inline-cycle ()
  "Select the next inline preview in the current buffer, revealing it if needed."
  (interactive)
  (agent-shell-inline--cycle-previews (list (current-buffer))))

(defun agent-shell-inline-visit ()
  "Select the next inline preview across all buffers, revealing it if needed."
  (interactive)
  (agent-shell-inline--cycle-previews
   (sort (buffer-list) (lambda (a b) (string-lessp (buffer-name a) (buffer-name b))))))

(defun agent-shell-inline--cycle-previews (buffers)
  "Cycle previews in BUFFERS, preserving their buffer and source order."
  (let (previews)
    (dolist (buffer buffers)
      (with-current-buffer buffer
        (save-restriction
          (widen)
          (setq previews
                (nconc previews
                       (sort (seq-filter (lambda (ov) (overlay-get ov 'agent-shell-inline))
                                         (overlays-in (point-min) (point-max)))
                             (lambda (a b) (< (overlay-start a) (overlay-start b)))))))))
    (unless previews
      (user-error "No inline previews in these buffers"))
    (let* ((selected agent-shell-inline--selected-preview)
           (current (and (memq selected previews)
                         (eq (overlay-buffer selected) (current-buffer)) selected))
           (overlay (or (cadr (memq current previews)) (car previews))))
      (agent-shell-inline--visit-preview overlay))))

(defun agent-shell-inline--visit-preview (overlay)
  "Select OVERLAY, revealing it only when it is outside the current view."
  (let* ((buffer (overlay-buffer overlay))
         (window (if (eq (window-buffer) buffer)
                     (selected-window)
                   (get-buffer-window buffer)))
         (visible (and window (pos-visible-in-window-p (overlay-end overlay) window))))
    (if window (select-window window) (pop-to-buffer-same-window buffer))
    (agent-shell-inline--focus-preview overlay)
    (unless visible
      (set-window-hscroll nil 0)
      (when (or (< (overlay-start overlay) (point-min)) (> (overlay-start overlay) (point-max)))
        (widen))
      (goto-char (overlay-start overlay))
      (agent-shell-inline--response-overlay-render overlay)
      (let ((height (1+ (cl-count ?\n (or (overlay-get overlay 'after-string) "")))))
        (recenter (max 0 (/ (- (window-body-height) height) 2)))))))

(defun agent-shell-inline-reply ()
  "Compose a reply to the inline preview selected by the current position."
  (interactive)
  (let ((overlay (agent-shell-inline--response-overlay-at-point)))
    (unless overlay
      (user-error "No inline response here"))
    (agent-shell-inline overlay)))

(defun agent-shell-inline--prompt-text ()
  "Return this prompt's source reference followed by its editable text."
  (unless (derived-mode-p 'agent-shell-inline-prompt-mode)
    (user-error "Use this command in an inline prompt"))
  (let* ((context agent-shell-inline--context)
         (marker (plist-get context :marker)))
    (concat (agent-shell-inline--reference-text
             (marker-buffer marker) (plist-get context :reference-ov))
            (buffer-substring-no-properties (point-min) (point-max)))))

(defun agent-shell-inline-quit (&optional keep)
  "Close the inline prompt.  With KEEP, append its text without submitting."
  (interactive "P")
  (unless (derived-mode-p 'agent-shell-inline-prompt-mode)
    (user-error "No inline prompt here"))
  (when keep (agent-shell-inline-append t))
  (let* ((prompt (current-buffer))
         (window (get-buffer-window prompt)))
    (if window (quit-window t window) (kill-buffer prompt))))

(defun agent-shell-inline-append (&optional no-quit)
  "Append prompt and reference to the shell's input without submitting it.
With NO-QUIT keep an empty prompt open to collect another part."
  (interactive "P")
  (let* ((text (agent-shell-inline--prompt-text))
         (shell (plist-get agent-shell-inline--context :buffer)))
    (agent-shell-inline--available-p shell)
    (unless (agent-shell-initialized-p :shell-buffer shell)
      (user-error "Agent is still starting; keep this draft and retry shortly"))
    (with-current-buffer shell
      (agent-shell-insert :text text :submit nil :no-focus t :shell-buffer shell))
    (erase-buffer)
    (agent-shell-inline-clear-reference)
    (unless no-quit (agent-shell-inline-quit))))

(defun agent-shell-inline-send ()
  "Send this prompt with its reference and display the response at the source."
  (interactive)
  (let* ((text (agent-shell-inline--prompt-text))
         (context agent-shell-inline--context)
         (source-window (plist-get context :window)))
    (agent-shell-inline--send text context)
    (agent-shell-inline-quit)
    (when (window-live-p source-window) (select-window source-window))))

(defun agent-shell-inline-write-and-quit ()
  "Send a non-empty inline draft, or close an empty composer."
  (interactive)
  (unless (derived-mode-p 'agent-shell-inline-prompt-mode)
    (user-error "No inline prompt here"))
  (if (string-empty-p (string-trim (buffer-string)))
      (agent-shell-inline-quit)
    (agent-shell-inline-send)))

;;;###autoload
(defun agent-shell-inline-message (text &optional shell)
  "Send TEXT from the minibuffer to SHELL without displaying the conversation.
Reuse the nearest preview in this buffer, even when it is off-screen.
With explicit SHELL, only reuse a preview belonging to that conversation.
Without a preview, show the response at point.  Attach no source reference."
  (interactive (list (read-string "Message to agent: ")))
  (let* ((previews
          (seq-filter
           (lambda (overlay)
             (let ((context (overlay-get overlay 'agent-shell-inline)))
               (and context
                    (or (not shell) (eq (get-buffer shell) (plist-get context :buffer))))))
           (overlays-in (point-min) (point-max))))
         (selected (agent-shell-inline--response-overlay-at-point))
         (preview (or (and (memq selected previews) selected)
                      (car (sort previews
                                 (lambda (a b)
                                   (< (abs (- (point) (overlay-start a)))
                                      (abs (- (point) (overlay-start b))))))))))
    (agent-shell-inline--send
     text (list :marker (point-marker)
                :buffer (agent-shell-inline--resolve-shell
                         (or shell (and preview
                                        (plist-get (overlay-get preview 'agent-shell-inline) :buffer))))
                :response-ov preview))))

(defun agent-shell-inline-switch-buffer (name)
  "Retarget the current inline prompt to the conversation named NAME."
  (interactive
   (list (completing-read "Conversation: "
                          (cons "New agent shell" (mapcar #'buffer-name (agent-shell-buffers)))
                          nil t)))
  (unless (derived-mode-p 'agent-shell-inline-prompt-mode)
    (user-error "Switch conversations from an inline prompt"))
  (let* ((marker (plist-get agent-shell-inline--context :marker))
         (origin (marker-buffer marker))
         (shell (if (equal name "New agent shell")
                    (agent-shell--new-shell :location default-directory :no-display t)
                  (get-buffer name))))
    (unless (agent-shell-inline--shell-p shell)
      (user-error "Conversation is no longer available"))
    (unless (eq shell (plist-get agent-shell-inline--context :buffer))
      (setf (plist-get agent-shell-inline--context :buffer) shell
            (plist-get agent-shell-inline--context :response-ov)
            (when (buffer-live-p origin)
              (with-current-buffer origin
                (let ((previews
                       (seq-filter
                        (lambda (overlay)
                          (eq shell (plist-get (overlay-get overlay 'agent-shell-inline) :buffer)))
                        (overlays-in (point-min) (point-max)))))
                  (car (sort previews
                             (lambda (a b)
                               (< (abs (- marker (overlay-start a)))
                                  (abs (- marker (overlay-start b))))))))))))
    (setq agent-shell-inline--recent (cons shell (delq shell agent-shell-inline--recent)))
    (when (buffer-live-p origin)
      (with-current-buffer origin (setq agent-shell-inline--last shell)))
    (force-mode-line-update t)))

(defun agent-shell-inline-visit-buffer (&optional shell)
  "Visit SHELL, or the conversation associated with this prompt or preview.
Use C-g to restore the previous window layout."
  (interactive)
  (let* ((overlay (agent-shell-inline--response-overlay-at-point))
         (shell (or shell (plist-get agent-shell-inline--context :buffer)
                    (and overlay (plist-get (overlay-get overlay 'agent-shell-inline) :buffer))
                    agent-shell-inline--last))
         (configuration (current-window-configuration)))
    (unless (agent-shell-inline--shell-p shell) (user-error "No live conversation associated with this buffer"))
    (pop-to-buffer shell agent-shell-inline-display-buffer-action)
    (set-transient-map
     (define-keymap "<remap> <keyboard-quit>"
       (lambda () (interactive) (set-window-configuration configuration)))
     (lambda () (eq (current-buffer) shell)) nil "C-g: return to source")))

(defun agent-shell-inline--hide-help ()
  "Close this prompt's options panel and release its attached window."
  (when (buffer-live-p agent-shell-inline--help-buffer)
    (when-let* ((window (get-buffer-window agent-shell-inline--help-buffer)))
      (when-let* ((root (window-atom-root window)))
        (set-window-parameter root 'window-atom nil)
        (window--atom-check))
      (quit-window nil window))
    (kill-buffer agent-shell-inline--help-buffer))
  (setq agent-shell-inline--help-buffer nil))

(defun agent-shell-inline-help ()
  "Toggle the options panel above the current inline prompt."
  (interactive)
  (unless (derived-mode-p 'agent-shell-inline-prompt-mode)
    (user-error "Open an inline prompt to view its options"))
  (if (and (buffer-live-p agent-shell-inline--help-buffer)
           (get-buffer-window agent-shell-inline--help-buffer))
      (agent-shell-inline--hide-help)
    (unless (buffer-live-p agent-shell-inline--help-buffer)
      (setq agent-shell-inline--help-buffer (generate-new-buffer "*agent-shell-inline-help*")))
    (let ((shell (plist-get agent-shell-inline--context :buffer))
          (prompt (current-buffer)))
      (with-current-buffer agent-shell-inline--help-buffer
        (let ((inhibit-read-only t))
          (erase-buffer)
          (setq-local truncate-lines t
                      cursor-type nil
                      mode-line-format nil)
          (insert (propertize "Agent Shell Inline — options\n\n" 'face 'outline-3))
          (insert (format "%-20s  %s\n"
                          (propertize "Keybinding" 'face 'bold)
                          (propertize "Command" 'face 'bold)))
          (dolist (entry
                   `((agent-shell-inline-send "Send prompt and respond inline")
                     (agent-shell-inline-cycle-reference "Include context around point; repeat with .")
                     (agent-shell-inline-append "Append prompt + context; prefix argument keeps prompt open")
                     (agent-shell-inline-visit-buffer
                      ,(format "Visit active conversation [%s]"
                               (propertize (or (and (buffer-live-p shell) (buffer-name shell)) "NONE")
                                           'face 'font-lock-escape-face)))
                     (agent-shell-inline-switch-buffer "Change conversation, or start a new one")
                     (agent-shell-inline-quit "Cancel and quit")
                     (agent-shell-inline-help "Toggle this options panel")))
            (insert (format "%-20s  %s\n"
                            (agent-shell-inline--prompt-control
                             prompt (agent-shell-inline--key-description (car entry)) (car entry))
                            (cadr entry))))
          (goto-char (point-max))
          (insert (format "\nResponse: %s reply, %s actions, %s navigate\n"
                          (substring-no-properties (agent-shell-inline--key-description 'agent-shell-inline-reply))
                          (substring-no-properties (agent-shell-inline--key-description 'agent-shell-inline--response-overlay-dispatch))
                          (substring-no-properties (agent-shell-inline--key-description 'agent-shell-inline-navigate))))
          (insert "Navigation: j/k scroll, J/K newer/older replies, C-d/C-u page, g live, Esc/q exit.\n")
          (when (bound-and-true-p evil-mode)
            (insert (format "\nPress Esc, then %s to send. Insert-state RET adds a newline.\n"
                            (agent-shell-inline--prompt-control
                             prompt (agent-shell-inline--key-description 'agent-shell-inline-send)
                             'agent-shell-inline-send))))
          (insert "\nRequests share conversation history; choose a new conversation for a fresh start.\n")
          (insert "Visit the conversation for tools and review; C-g returns to your source layout.\n")
          (goto-char (point-min))
          (setq buffer-read-only t))))
    (display-buffer agent-shell-inline--help-buffer
                    '(display-buffer-in-atom-window
                      (side . above)
                      (window-parameters . ((mode-line-format . none)
                                            (no-other-window . t)))
                      (window-height . fit-window-to-buffer)
                      (dedicated . t)))))

(provide 'agent-shell-inline)
;;; agent-shell-inline.el ends here
