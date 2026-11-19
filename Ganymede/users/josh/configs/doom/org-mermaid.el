;;; org-mermaid.el --- Mermaid diagrams in Org -*- lexical-binding: t; -*-

(require 'org)
;; mermaid-mode also defines a Babel executor.  Load ob-mermaid afterwards so
;; its configuration-file support is used consistently, including after C-c '.
(require 'mermaid-mode)
(require 'ob-mermaid)

(setq ob-mermaid-cli-path "mmdc"
      ob-mermaid-default-config-file
      (expand-file-name "mermaid-config.json"
                        (file-name-directory (or load-file-name buffer-file-name))))
(add-to-list 'org-babel-load-languages '(mermaid . t))
(add-to-list 'org-src-lang-modes '("mermaid" . mermaid))
(add-hook 'org-babel-after-execute-hook #'org-link-preview-refresh)

(provide 'org-mermaid)
;;; org-mermaid.el ends here
