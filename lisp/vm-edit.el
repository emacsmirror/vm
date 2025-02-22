;;; vm-edit.el --- Editing VM messages  -*- lexical-binding: t; -*-
;;
;; This file is part of VM
;;
;; Copyright (C) 1990, 1991, 1993, 1994, 1997, 2001 Kyle E. Jones
;; Copyright (C) 2003-2006 Robert Widhopf-Fenk
;; Copyright (C) 2024-2025 The VM Developers
;;
;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License along
;; with this program; if not, write to the Free Software Foundation, Inc.,
;; 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

;;; Code:

(require 'vm-macro)
(require 'vm-folder)
(require 'vm-motion)

;;;###autoload
(defun vm-edit-message (&optional prefix-argument)
  "Edit the current message.  Prefix arg means mark as unedited instead.
If editing, the current message is copied into a temporary buffer, and
this buffer is selected for editing.  The major mode of this buffer is
controlled by the variable vm-edit-message-mode.  The hooks specified
in vm-edit-message-hook are run just prior to returning control to the user
for editing.

Use C-c ESC when you have finished editing the message.  The message
will be inserted into its folder replacing the old version of the
message.  If you don't want your edited version of the message to
replace the original, use C-c C-] and the edit will be aborted."
  (interactive "P")
  (vm-follow-summary-cursor)
  (vm-select-folder-buffer-and-validate 1 (vm-interactive-p))
  (vm-error-if-folder-read-only)
  (if (and (vm-virtual-message-p (car vm-message-pointer))
	   (null (vm-virtual-messages-of (car vm-message-pointer))))
      (error "Can't edit unmirrored virtual messages."))
  (if prefix-argument
      (when (vm-edited-flag (car vm-message-pointer))
	(vm-set-edited-flag-of (car vm-message-pointer) nil)
	(vm-update-summary-and-mode-line))
    (let ((mp vm-message-pointer)
	  (offset (save-excursion
		    (if vm-presentation-buffer
			(set-buffer vm-presentation-buffer))
		    (- (point) (vm-headers-of (car vm-message-pointer)))))
	  (edit-buf (vm-edit-buffer-of (car vm-message-pointer)))
	  (folder-buffer (current-buffer)))
      ;; (vm-load-message)
      (vm-retrieve-operable-messages 1 (list (car vm-message-pointer))
				     :fail t)
      (if (and edit-buf (buffer-name edit-buf))
	  (set-buffer edit-buf)
	(save-restriction
	 (widen)
	 (setq edit-buf
	       (generate-new-buffer
		(format "edit of %s's note re: %s"
			(vm-su-full-name (car vm-message-pointer))
			(vm-su-subject (car vm-message-pointer)))))
	 (if (not (featurep 'xemacs))
	     (set-buffer-multibyte nil)) ; for new buffer
	 (vm-set-edit-buffer-of (car mp) edit-buf)
	 (copy-to-buffer edit-buf
			 (vm-headers-of (car mp))
			 (vm-text-end-of (car mp))))
	(set-buffer edit-buf)
	(set-buffer-modified-p nil)	; edit-buf
	(goto-char (point-min))
	(if (< offset 0)
	    (search-forward "\n\n" nil t)
	  (forward-char offset))
	(funcall (or vm-edit-message-mode 'text-mode))
	(set-keymap-parent vm-edit-message-map (current-local-map))
	(use-local-map vm-edit-message-map)
	;; (list (car mp)) because a different message may
	;; later be stuffed into a cons linked that is linked
	;; into the folder's message list.
	(setq vm-message-pointer (list (car mp))
	      vm-mail-buffer folder-buffer
	      vm-system-state 'editing
	      buffer-offer-save t)
	(run-hooks 'vm-edit-message-hook)
	(vm-inform 5
	 (substitute-command-keys
	  "Type \\[vm-edit-message-end] to end edit, \\[vm-edit-message-abort] to abort with no change."))
	)
      (when (and vm-mutable-frame-configuration vm-frame-per-edit
		 (vm-multiple-frames-possible-p))
	(let ((w (vm-get-buffer-window edit-buf)))
	  (if (null w)
	      (progn
		(vm-goto-new-frame 'edit)
		(vm-set-hooks-for-frame-deletion))
	    (save-excursion
	      (select-window w)
	      (and vm-warp-mouse-to-new-frame
		   (vm-warp-mouse-to-frame-maybe (vm-window-frame w)))))))
      (vm-display edit-buf t '(vm-edit-message vm-edit-message-other-frame)
		  (list this-command 'editing-message)))))

;;;###autoload
(defun vm-edit-message-other-frame (&optional prefix)
  "Like vm-edit-message, but run in a newly created frame."
  (interactive "P")
  (if (vm-multiple-frames-possible-p)
      (vm-goto-new-frame 'edit))
  (let ((vm-search-other-frames nil)
	(vm-frame-per-edit nil))
    (vm-edit-message prefix))
  (if (vm-multiple-frames-possible-p)
      (vm-set-hooks-for-frame-deletion)))

;;;###autoload
(defun vm-discard-cached-data (&optional count)
  "Discard cached information about the current message.
When VM gathers information from the headers of a message, it stores it
internally for future reference.  This command causes VM to forget this
information, and VM will be forced to search the headers of the message
again for these data.  VM will also have to decide again which headers
should be displayed and which should not.  Therefore this command is
useful if you change the value of vm-visible-headers or
vm-invisible-header-regexp in the midst of a VM session.

Numeric prefix argument N means to discard data from the current message
plus the next N-1 messages.  A negative N means discard data from the
current message and the previous N-1 messages.

When invoked on marked messages (via `vm-next-command-uses-marks'),
data is discarded only from the marked messages in the current folder.
If applied to collapsed threads in summary and thread operations are
enabled via `vm-enable-thread-operations' then all messages in the
thread have their cached data discarded."
  (interactive "p")
  (or count (setq count 1))
  (vm-follow-summary-cursor)
  (vm-select-folder-buffer-and-validate 1 (vm-interactive-p))
  (let ((mlist (vm-select-operable-messages
		count (vm-interactive-p) "Discard data of")))
    (vm-discard-cached-data-internal mlist (vm-interactive-p) ))
  (vm-display nil nil '(vm-discard-cached-data) '(vm-discard-cached-data))
  (vm-update-summary-and-mode-line))

(defun vm-discard-cached-data-internal (mlist &optional interactive-p)
  (let ((buffers-needing-thread-sort (make-vector 29 0))
	m)
    (while mlist
      (setq m (vm-real-message-of (car mlist)))
      (with-current-buffer (vm-buffer-of m)
	(vm-garbage-collect-message)
	(if (vectorp vm-thread-obarray)
	    (vm-unthread-message-and-mirrors m :message-changing t))
	;; It was a mistake to store the POP & IMAP UID data here but
	;; it's too late to change it now.  So keep the data from
	;; getting wiped.
	(let ((uid (vm-imap-uid-of m))
	      (uid-validity (vm-imap-uid-validity-of m))
	      (headers-flag (vm-headers-to-be-retrieved-of m))
	      (body-flag (vm-body-to-be-retrieved-of m))
	      (body-discard-flag (vm-body-to-be-discarded-of m)))
	  (fillarray (vm-cached-data-of m) nil)
	  (vm-set-imap-uid-of m uid)
	  (vm-set-imap-uid-validity-of m uid-validity)
	  (vm-set-headers-to-be-retrieved-of m headers-flag)
	  (vm-set-body-to-be-retrieved-of m body-flag)
	  (vm-set-body-to-be-discarded-of m body-discard-flag))
	(vm-set-vheaders-of m nil)
	(vm-set-vheaders-regexp-of m nil)
	(vm-set-text-of m nil)
	(vm-set-mime-layout-of m nil)
	(vm-set-mime-encoded-header-flag-of m nil)
	;; FIXME It is slow to do this repeatedly, once for each
	;; message.  Need to do it in bulk.  USR, 2012-03-08
	(if (vectorp vm-thread-obarray)
	    (vm-build-threads (list m)))
	;; (if vm-thread-debug
	;;     (vm-check-thread-integrity))
	(if vm-summary-show-threads
	    (intern (buffer-name) buffers-needing-thread-sort))
	(dolist (v-m (vm-virtual-messages-of m))
	  (when (buffer-name (vm-buffer-of v-m))
	    (with-current-buffer (vm-buffer-of v-m)
	      (vm-set-mime-layout-of v-m nil)
	      (vm-set-mime-encoded-header-flag-of v-m nil)
	      (if (vectorp vm-thread-obarray)
		  (vm-build-threads (list v-m)))
	      (if vm-summary-show-threads
		  (intern (buffer-name) buffers-needing-thread-sort))

	      (if (and vm-presentation-buffer
		       (eq (car vm-message-pointer) v-m))
		  ;; FIXME why is this call to present-current-message
		  ;; needed?  Might be wasteful. USR, 2012-09-22
		  (save-excursion 
		    (vm-present-current-message))))))
	(vm-mark-for-summary-update m)
	(vm-set-stuff-flag-of m t)
	(if (and interactive-p vm-presentation-buffer
		 (eq (car vm-message-pointer) m))
	    (save-excursion (vm-present-current-message)))
	(setq mlist (cdr mlist))))
    (if vm-thread-debug
        (vm-check-thread-integrity))
    ;; Probably not a good idea to sort messages here.
    ;; Reorders the message summary unnecessarily.  USR, 2012-09-22
    ;; (save-excursion
    ;;   (mapatoms (function (lambda (s)
    ;; 			    (set-buffer (get-buffer (symbol-name s)))
    ;; 			    (vm-sort-messages (or vm-ml-sort-keys "activity"))))
    ;; 		buffers-needing-thread-sort))
    ))

;;;###autoload
(defun vm-edit-message-end ()
  "End the edit of a message and copy the result to its folder."
  (interactive)
  (if (null vm-message-pointer)
      (error "This is not a VM message edit buffer."))
  (if (null (buffer-name (vm-buffer-of (car vm-message-pointer))))
      (error "The folder buffer for this message has been killed."))
  (let ((pos-offset (- (point) (point-min))))
    ;; make sure the message ends with a newline
    (goto-char (point-max))
    (and (/= (preceding-char) ?\n) (insert ?\n))
    ;; munge message separators found in the edited message to
    ;; prevent message from being split into several messages.
    (vm-munge-message-separators (vm-message-type-of (car vm-message-pointer))
				 (point-min) (point-max))
    ;; for From_-with-Content-Length recompute the Content-Length header
    (if (eq (vm-message-type-of (car vm-message-pointer))
	    'From_-with-Content-Length)
	(let ((buffer-read-only nil)
	      length)
	  (goto-char (point-min))
	  ;; first delete all copies of Content-Length
	  (while (and (re-search-forward vm-content-length-search-regexp nil t)
		      (null (match-beginning 1))
		      (progn (goto-char (match-beginning 0))
			     (vm-match-header vm-content-length-header)))
	    (delete-region (vm-matched-header-start) (vm-matched-header-end)))
	  ;; now compute the message body length
	  (goto-char (point-min))
	  (search-forward "\n\n" nil 0)
	  (setq length (- (point-max) (point)))
	  ;; insert the header
	  (goto-char (point-min))
	  (insert vm-content-length-header " " (int-to-string length) "\n")))
    (let ((edit-buf (current-buffer))
	  (mp vm-message-pointer))
      (if (not (buffer-modified-p))
	  (vm-inform 5 "No change.")
	(widen)
	(with-current-buffer (vm-buffer-of (vm-real-message-of (car mp)))
	  (if (not (memq (vm-real-message-of (car mp)) vm-message-list))
	      (error "The original copy of this message has been expunged."))
	  (save-restriction
	   (widen)
	   (goto-char (vm-headers-of (vm-real-message-of (car mp))))
	   (let ((vm-message-pointer mp)
		 ;; opoint
		 (buffer-read-only nil))
	     ;; (setq opoint (point))
	     (insert-buffer-substring edit-buf)
	     (delete-region
	      (point) (vm-text-end-of (vm-real-message-of (car mp))))
	     (vm-discard-cached-data-internal (list (car mp))))
	   (vm-set-edited-flag-of (car mp) t)
	   (vm-set-edit-buffer-of (car mp) nil))
	  (set-buffer (vm-buffer-of (car mp)))
	  (if (eq (vm-real-message-of (car mp))
		  (vm-real-message-of (car vm-message-pointer)))
	      (progn
		(vm-present-current-message)
		;; Try to position the cursor in the message
		;; window close to where it was in the edit
		;; window.  This works well for non MIME
		;; messages, but the cursor drifts badly for
		;; MIME and for refilled messages.
		(save-current-buffer
		 (and vm-presentation-buffer
		      (set-buffer vm-presentation-buffer))
		 (save-restriction
		  (save-current-buffer
		   (widen)
		   (let ((osw (selected-window))
			 (new-win (vm-get-visible-buffer-window
				   (current-buffer))))
		     (unwind-protect
			 (if new-win
			     (progn
			       (select-window new-win)
			       (goto-char (vm-headers-of
					   (car vm-message-pointer)))
			       (condition-case nil
				   (forward-char pos-offset)
				 (error nil))))
		       (if (not (eq osw (selected-window)))
			   (select-window osw))))))))
	    (vm-update-summary-and-mode-line))))
      (vm-display edit-buf nil '(vm-edit-message-end)
		  '(vm-edit-message-end reading-message startup))
      (set-buffer-modified-p nil)	; edit-buf
      (kill-buffer edit-buf))))

(defun vm-edit-message-abort ()
  "Abort the edit of a message, forgetting changes to the message."
  (interactive)
  (unless vm-message-pointer
    (error "This is not a VM message edit buffer."))
  (unless (buffer-name 
	   (vm-buffer-of (vm-real-message-of (car vm-message-pointer))))
    (error "The folder buffer for this message has been killed."))
  (vm-set-edit-buffer-of (car vm-message-pointer) nil)
  (vm-display (current-buffer) nil
	      '(vm-edit-message-abort)
	      '(vm-edit-message-abort reading-message startup))
  (set-buffer-modified-p nil)		; edit-buffer
  (kill-buffer (current-buffer))
  (vm-inform 5 "Aborted, no change."))

(provide 'vm-edit)
;;; vm-edit.el ends here
