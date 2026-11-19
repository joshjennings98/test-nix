;;; completion.el --- Completion and search -*- lexical-binding: t; -*-

(use-package vertico
  :demand t
  :config (vertico-mode 1))

(use-package orderless
  :demand t
  :config
  (setq completion-styles '(orderless basic)
        completion-category-defaults nil
        completion-category-overrides '((file (styles partial-completion orderless))))
  (setq orderless-matching-styles '(orderless-literal orderless-regexp orderless-flex)))

(use-package marginalia
  :demand t
  :config (marginalia-mode 1))

(use-package corfu
  :demand t
  :config
  (setq corfu-auto t corfu-cycle t corfu-auto-delay 0.2)
  (global-corfu-mode 1)
  (require 'corfu-popupinfo)
  (corfu-popupinfo-mode 1))

(use-package cape
  :demand t
  :config
  (add-hook 'completion-at-point-functions #'cape-file t)
  (add-hook 'completion-at-point-functions #'cape-dabbrev t))

(use-package consult
  :commands (consult-buffer consult-ripgrep consult-line consult-recent-file
             consult-project-buffer consult-yank-pop)
  :init
  (setq xref-show-xrefs-function #'consult-xref
        xref-show-definitions-function #'consult-xref
        xref-prompt-for-identifier nil)
  :bind (("C-s" . consult-line)
         ("M-y" . consult-yank-pop)))

(use-package consult-xref :commands consult-xref)
(use-package consult-imenu :commands (consult-imenu consult-imenu-multi))
(use-package consult-flymake :commands consult-flymake)

(use-package embark
  :bind (("C-." . embark-act)
         ("C-;" . embark-dwim)
         ("C-h B" . embark-bindings)))

(use-package embark-consult
  :after (embark consult)
  :demand t
  :hook (embark-collect-mode . consult-preview-at-point-mode))
