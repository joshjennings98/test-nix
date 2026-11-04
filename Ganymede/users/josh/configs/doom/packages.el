;; -*- no-byte-compile: t; -*-
;;; packages.el

;; The module's older pin has a face-inheritance cycle on Emacs 31.
(package! doom-themes :pin "a59202912ad55014e53a685eee6cd94130bdd4fd")
(package! evil-textobj-tree-sitter)
(package! expreg)
(package! shell-maker
  :recipe (:host github :repo "xenodium/shell-maker")
  :pin "b28ee61a2533e408ed180662f83bb84fc8f84ba6")
(package! acp
  :recipe (:host github :repo "xenodium/acp.el")
  :pin "2959da5fa8657da17a78ac6ceef303a50e3e69de")
(package! agent-shell
  :recipe (:host github :repo "xenodium/agent-shell" :files ("*.el" "icons"))
  :pin "ee1f061a111726955ee4d3056862804c8e458c64")
