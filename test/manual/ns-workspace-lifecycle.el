;;; ns-workspace-lifecycle.el --- Log macOS workspace notifications -*- lexical-binding: t; -*-

(defconst emacs-workspace-test-log
  (or (getenv "EMACS_WORKSPACE_TEST_LOG")
      (expand-file-name "EmacsWorkspaceLifecycle.log" "~/Library/Logs/")))

(dolist (hook '(ns-workspace-will-sleep-hook
                ns-workspace-did-wake-hook
                ns-workspace-will-power-off-hook
                ns-workspace-session-did-resign-active-hook))
  (unless (boundp hook)
    (error "This Emacs does not define %s" hook)))

(defun emacs-workspace-test-record (event)
  (with-temp-buffer
    (insert (format-time-string "%Y-%m-%dT%H:%M:%S%z")
            "\t" event
            "\tpid=" (number-to-string (emacs-pid))
            "\temacs=" emacs-version
            "\n")
    (write-region (point-min) (point-max)
                  emacs-workspace-test-log 'append 'silent)))

(add-hook 'ns-workspace-will-sleep-hook
          (apply-partially #'emacs-workspace-test-record "will-sleep"))
(add-hook 'ns-workspace-did-wake-hook
          (apply-partially #'emacs-workspace-test-record "did-wake"))
(add-hook 'ns-workspace-will-power-off-hook
          (apply-partially #'emacs-workspace-test-record "will-power-off"))
(add-hook 'ns-workspace-session-did-resign-active-hook
          (apply-partially #'emacs-workspace-test-record
                           "session-did-resign-active"))

(emacs-workspace-test-record "test-start")
(set-frame-name "Emacs NSWorkspace lifecycle test")

;;; ns-workspace-lifecycle.el ends here
