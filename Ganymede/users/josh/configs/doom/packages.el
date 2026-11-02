;; -*- no-byte-compile: t; -*-
;;; packages.el

;; The module's older pin has a face-inheritance cycle on Emacs 31.
(package! doom-themes :pin "a59202912ad55014e53a685eee6cd94130bdd4fd")
(package! evil-textobj-tree-sitter)
(package! expreg)
(package! gptel-agent
  :recipe (:host github :repo "karthink/gptel-agent")
  :pin "2fbe4f6c71a6a1355c647ce90151c8c2bc1c4bdf")
(package! gptel-inline
  :recipe (:host github :repo "karthink/gptel-inline")
  :pin "7a74fda2ed420c5967437f80c4eeb5a7d52a6314")
