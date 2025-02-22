;;; vm-sort.el ---  Sorting and moving messages inside VM  -*- lexical-binding: t; -*-
;;
;; This file is part of VM
;;
;; Copyright (C) 1993, 1994 Kyle E. Jones
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


;;; Code

(require 'vm-macro)
(require 'vm-vars)
(require 'vm-misc)
(require 'vm-minibuf)
(require 'vm-folder)
(require 'vm-summary)
(require 'vm-motion)
(require 'vm-window)
(eval-when-compile (require 'cl-lib))

(declare-function vm-sort-insert-auto-folder-names "vm-avirtual" ())

;;;###autoload
(defun vm-move-message-forward (count)
  "Move a message forward in a VM folder.
Prefix arg COUNT causes the current message to be moved COUNT messages forward.
A negative COUNT causes movement to be backward instead of forward.
COUNT defaults to 1.  The current message remains selected after being
moved.

If vm-move-messages-physically is non-nil, the physical copy of
the message in the folder is moved.  A nil value means just
change the presentation order and leave the physical order of
the folder undisturbed."
  (interactive "p")
  (vm-follow-summary-cursor)
  (vm-select-folder-buffer-and-validate 1 (vm-interactive-p))
  (if vm-move-messages-physically
      (vm-error-if-folder-read-only))
  (vm-display nil nil '(vm-move-message-forward
			vm-move-message-backward
			vm-move-message-forward-physically
			vm-move-message-backward-physically)
	      (list this-command))
  (let* ((ovmp vm-message-pointer) vmp-prev ovmp-prev
	 (vm-message-pointer vm-message-pointer)
	 (direction (if (> count 0) 'forward 'backward))
	 (count (vm-abs count)))
    (while (not (zerop count))
      (vm-move-message-pointer direction)
      (vm-decrement count))
    (if (> (string-to-number (vm-number-of (car vm-message-pointer)))
	   (string-to-number (vm-number-of (car ovmp))))
	(setq vm-message-pointer (cdr vm-message-pointer)))
    (if (eq vm-message-pointer ovmp)
	()
      (if (null vm-message-pointer)
	  (setq vmp-prev (vm-last vm-message-list))
	(setq vmp-prev (vm-reverse-link-of (car vm-message-pointer))))
      (setq ovmp-prev (vm-reverse-link-of (car ovmp)))
      ;; lock out interrupts to preserve message list integrity.
      (let ((inhibit-quit t))
	(if ovmp-prev
	    (progn
	      (setcdr ovmp-prev (cdr ovmp))
	      (and (cdr ovmp)
		   (vm-set-reverse-link-of (car (cdr ovmp)) ovmp-prev)))
	  (setq vm-message-list (cdr ovmp))
	  (vm-set-reverse-link-of (car vm-message-list) nil))
	(if vmp-prev
	    (progn
	      (setcdr vmp-prev ovmp)
	      (vm-set-reverse-link-of (car ovmp) vmp-prev))
	  (setq vm-message-list ovmp)
	  (vm-set-reverse-link-of (car vm-message-list) nil))
	(setcdr ovmp vm-message-pointer)
	(and vm-message-pointer
	     (vm-set-reverse-link-of (car vm-message-pointer) ovmp))
	(if (and vm-move-messages-physically
		 (not (eq major-mode 'vm-virtual-mode)))
	    (vm-physically-move-message (car ovmp) (car vm-message-pointer)))
	(setq vm-ml-sort-keys nil)
	(if (not vm-folder-read-only)
	    (progn
	      (setq vm-message-order-changed t)
	      (vm-mark-folder-modified-p (current-buffer))
	      (vm-clear-modification-flag-undos))))
      (cond ((null ovmp-prev)
	     (setq vm-numbering-redo-start-point vm-message-list
		   vm-numbering-redo-end-point vm-message-pointer
		   vm-summary-pointer (car vm-message-list)))
	    ((null vmp-prev)
	     (setq vm-numbering-redo-start-point vm-message-list
		   vm-numbering-redo-end-point (cdr ovmp-prev)
		   vm-summary-pointer (car ovmp-prev)))
	    ((or (not vm-message-pointer)
		 (< (string-to-number (vm-number-of (car ovmp-prev)))
		    (string-to-number (vm-number-of (car vm-message-pointer)))))
	     (setq vm-numbering-redo-start-point (cdr ovmp-prev)
		   vm-numbering-redo-end-point (cdr ovmp)
		   vm-summary-pointer (car (cdr ovmp-prev))))
	    (t
	     (setq vm-numbering-redo-start-point ovmp
		   vm-numbering-redo-end-point (cdr ovmp-prev)
		   vm-summary-pointer (car ovmp-prev))))
      (if vm-summary-buffer
	  (let (list mp)
	    (vm-copy-local-variables vm-summary-buffer 'vm-summary-pointer)
	    (setq vm-need-summary-pointer-update t)
	    (setq mp vm-numbering-redo-start-point)
	    (while (not (eq mp vm-numbering-redo-end-point))
	      (vm-mark-for-summary-update (car mp))
	      (setq list (cons (car mp) list)
		    mp (cdr mp)))
	    (vm-mapc
	     (function
	      (lambda (m p)
		(vm-set-su-start-of m (car p))
		(vm-set-su-end-of m (car (cdr p)))))
	     (setq list (nreverse list))
	     (sort
	      (mapcar
	       (function
		(lambda (p)
		  (list (vm-su-start-of p) (vm-su-end-of p))))
	       list)
	      (function
	       (lambda (p q)
		 (< (car p) (car q))))))))))
  (if vm-move-messages-physically
      ;; clip region is messed up
      (vm-present-current-message)
    (vm-update-summary-and-mode-line)))

;;;###autoload
(defun vm-move-message-backward (count)
  "Move a message backward in a VM folder.
Prefix arg COUNT causes the current message to be moved COUNT
messages backward.  A negative COUNT causes movement to be
forward instead of backward.  COUNT defaults to 1.  The current
message remains selected after being moved.

If vm-move-messages-physically is non-nil, the physical copy of
the message in the folder is moved.  A nil value means just
change the presentation order and leave the physical order of
the folder undisturbed."
  (interactive "p")
  (vm-move-message-forward (- count)))

;;;###autoload
(defun vm-move-message-forward-physically (count)
  "Like vm-move-message-forward but always move the message physically."
  (interactive "p")
  (let ((vm-move-messages-physically t))
    (vm-move-message-forward count)))

;;;###autoload
(defun vm-move-message-backward-physically (count)
  "Like vm-move-message-backward but always move the message physically."
  (interactive "p")
  (let ((vm-move-messages-physically t))
    (vm-move-message-backward count)))

;; move message m to be before m-dest
;; and fix up the location markers afterwards.
;; m better not equal m-dest.
;; of m-dest is nil, move m to the end of buffer.
;;
;; consider carefully the effects of insertion on markers
;; and variables containg markers before you modify this code.
(defun vm-physically-move-message (m m-dest)
  (save-excursion
    (save-restriction
     (widen)

     ;; Make sure vm-headers-of and vm-text-of are non-nil in
     ;; their slots before we try to move them.  (Simply
     ;; referencing the slot with their slot function is
     ;; sufficient to guarantee this.)  Otherwise, they be
     ;; initialized in the middle of the message move and get the
     ;; offset applied to them twice by way of a relative offset
     ;; from one of the other location markers that has already
     ;; been moved.
     ;;
     ;; Also, and more importantly, vm-vheaders-of might run
     ;; vm-reorder-message-headers, which can add text to
     ;; message.  This MUST NOT happen after offsets have been
     ;; computed for the message move or varying levels of chaos
     ;; will ensue.  In the case of BABYL files, where
     ;; vm-reorder-message-headers can add a lot of new text,
     ;; folder curroption can be massive.
     (vm-text-of m)
     (vm-vheaders-of m)

     (let ((dest-start (if m-dest (vm-start-of m-dest) (point-max)))
	   (buffer-read-only nil)
	   offset doomed-start doomed-end)
       (goto-char dest-start)
       (insert-buffer-substring (current-buffer) (vm-start-of m) (vm-end-of m))
       (setq doomed-start (marker-position (vm-start-of m))
	     doomed-end (marker-position (vm-end-of m))
	     offset (- (vm-start-of m) dest-start))
       (set-marker (vm-start-of m) (- (vm-start-of m) offset))
       (set-marker (vm-headers-of m) (- (vm-headers-of m) offset))
       (set-marker (vm-text-end-of m) (- (vm-text-end-of m) offset))
       (set-marker (vm-end-of m) (- (vm-end-of m) offset))
       (set-marker (vm-text-of m) (- (vm-text-of m) offset))
       (set-marker (vm-vheaders-of m) (- (vm-vheaders-of m) offset))
       ;; now fix the start of m-dest since it didn't
       ;; move forward with its message.
       (and m-dest (set-marker (vm-start-of m-dest) (vm-end-of m)))
       ;; delete the old copy of the message
       (delete-region doomed-start doomed-end)))))

;;;###autoload
(defun vm-so-sortable-datestring (m)
  "Returns the date string of M.  The date returned is obtained from
the \"Date\" header of the message, if it exists, or the date the
message was received in VM.  If `vm-sort-messages-by-delivery-date' is
non-nil, then the \"Delivery-Date\" header is used instead of the
\"Date\" header." 
  (or (vm-sortable-datestring-of m)
      (progn
	(vm-set-sortable-datestring-of
	 m
	 (condition-case nil
	     (vm-timezone-make-date-sortable
	      (or (if vm-sort-messages-by-delivery-date
		      (vm-get-header-contents m "Delivery-Date:")
		    (vm-get-header-contents m "Date:"))
		  (vm-grok-From_-date m)
		  "Thu, 1 Jan 1970 00:00:00 GMT"))
	   (error "1970010100:00:00")))
	(vm-sortable-datestring-of m))))

;;;###autoload
(defun vm-so-sortable-subject (m)
  "Returns the subject string of M, after stripping redundant prefixes
and suffixes, which is suitable for sorting by subject.  The string is
MIME-decoded with possible text properties."
  (or (vm-decoded-sortable-subject-of m)
      (progn
	(vm-set-decoded-sortable-subject-of 
	 m (vm-so-trim-subject (vm-su-decoded-subject m)))
	(vm-decoded-sortable-subject-of m))))

(defun vm-so-trim-subject (subject)
  "Given SUBJECT string (which should be MIME-decoded with
possible text properties), returns a modified string after
stripping redundant prefixes and suffixes as suitable for sorting
by subject."
  (let ((case-fold-search t)
	(tag-end nil))
    (catch 'done
      (while t
	(cond ((and vm-subject-ignored-prefix
		    (string-match vm-subject-ignored-prefix subject)
		    (zerop (match-beginning 0)))
	       (setq subject (substring subject (match-end 0))))
	      ((and vm-subject-tag-prefix
		    (string-match vm-subject-tag-prefix subject)
		    (zerop (match-beginning 0))
		    (setq tag-end (match-end 0))
		    (not (and vm-subject-tag-prefix-exceptions
			      (string-match 
			       vm-subject-tag-prefix-exceptions subject)
			      (zerop (match-beginning 0)))))
	       (setq subject (substring subject tag-end)))
	      (t
	       (throw 'done nil)))))
    (setq subject (vm-with-string-as-temp-buffer
		   subject
		   (function vm-collapse-whitespace)))
    (if (and vm-subject-ignored-suffix
	     (string-match vm-subject-ignored-suffix subject)
	     (= (match-end 0) (length subject)))
	(setq subject (substring subject 0 (match-beginning 0))))
    (if (and vm-subject-significant-chars
	     (natnump vm-subject-significant-chars)
	     (< vm-subject-significant-chars (length subject)))
	(setq subject
	      (substring subject 0 vm-subject-significant-chars)))
    subject ))

(defvar vm-sort-compare-header nil
  "the header to sort on.")

(defvar vm-sort-compare-header-history nil)

;;;###autoload
(defun vm-sort-messages (keys &optional lets-get-physical)
  "Sort message in a folder by the specified KEYS.
KEYS is a string of sort keys, separated by spaces or tabs.  If
messages compare equal by the first key, the second key will be
compared and so on.  When called interactively the keys will be
read from the minibuffer.  Valid keys are

\"date\"		\"reversed-date\"
\"activity\" 		\"reversed-activity\"
\"author\"		\"reversed-author\"
\"full-name\"		\"reversed-full-name\"
\"subject\"		\"reversed-subject\"
\"recipients\"		\"reversed-recipients\"
\"line-count\"		\"reversed-line-count\"
\"byte-count\"		\"reversed-byte-count\"
\"physical-order\"	\"reversed-physical-order\"
\"spam-score\"		\"reversed-spam-score\"

Optional second arg (prefix arg interactively) means the sort
should change the physical order of the messages in the folder.
Normally VM changes presentation order only, leaving the
folder in the order in which the messages arrived."
  (interactive
   (let ((last-command last-command)
	 (this-command this-command))
   (list (vm-read-string (if (or current-prefix-arg
				 vm-move-messages-physically)
			     "Physically sort messages by: "
			   "Sort messages by: ")
			 vm-supported-sort-keys t)
	 current-prefix-arg)))
  (vm-select-folder-buffer-and-validate 0 (vm-interactive-p))
  ;; only squawk if interactive.  The thread display uses this
  ;; function and doesn't expect errors.
  (if (vm-interactive-p)
      (vm-error-if-folder-empty))
  ;; ditto
  (if (and (vm-interactive-p) (or vm-move-messages-physically lets-get-physical))
      (vm-error-if-folder-read-only))

  (vm-display nil nil '(vm-sort-messages) '(vm-sort-messages))
  (let (key-list key-funcs key ml-keys
	physical-order-list old-message-list new-message-list mp-old mp-new
	old-start
	;; doomed-start doomed-end offset
	(order-did-change nil)
	virtual
	physical
        auto-folder-p)
    (setq key-list (vm-parse keys "[ \t]*\\([^ \t,]+\\)")
	  ml-keys (and key-list (mapconcat (function identity) key-list "/"))
	  key-funcs nil
	  old-message-list vm-message-list
	  virtual (eq major-mode 'vm-virtual-mode)
	  physical (and (or lets-get-physical
			    vm-move-messages-physically)
			(not vm-folder-read-only)
			(not virtual)))
    (unless key-list
      (error "No sort keys specified."))
    (while key-list
      (setq key (car key-list))
      (cond ((equal key "auto-folder")
             (setq auto-folder-p t)
             (setq key-funcs (cons 'vm-sort-compare-auto-folder key-funcs)))
	    ((equal key "author")
	     (setq key-funcs (cons 'vm-sort-compare-author key-funcs)))
	    ((equal key "reversed-author")
	     (setq key-funcs (cons 'vm-sort-compare-author-r key-funcs)))
	    ((equal key "full-name")
	     (setq key-funcs (cons 'vm-sort-compare-full-name key-funcs)))
	    ((equal key "reversed-full-name")
	     (setq key-funcs (cons 'vm-sort-compare-full-name-r key-funcs)))
	    ((equal key "date")
	     (setq key-funcs (cons 'vm-sort-compare-date key-funcs)))
	    ((equal key "reversed-date")
	     (setq key-funcs (cons 'vm-sort-compare-date-r key-funcs)))
	    ((equal key "activity")
	     (setq vm-summary-show-threads t)
	     (setq key-funcs (cons 'vm-sort-compare-activity
				   key-funcs)))
	    ((equal key "reversed-activity")
	     (setq vm-summary-show-threads t)
	     (setq key-funcs (cons 'vm-sort-compare-activity-r 
				   key-funcs)))
	    ;; ((equal key "thread-oldest-date")
	    ;;  (setq vm-summary-show-threads t)
	    ;;  (setq key-funcs (cons 'vm-sort-compare-thread-oldest-date
	    ;; 			   key-funcs)))
	    ;; ((equal key "reversed-thread-oldest-date")
	    ;;  (setq vm-summary-show-threads t)
	    ;;  (setq key-funcs (cons 'vm-sort-compare-thread-oldest-date-r 
	    ;; 			   key-funcs)))
	    ((equal key "subject")
	     (setq key-funcs (cons 'vm-sort-compare-subject key-funcs)))
	    ((equal key "reversed-subject")
	     (setq key-funcs (cons 'vm-sort-compare-subject-r key-funcs)))
	    ((equal key "recipients")
	     (setq key-funcs (cons 'vm-sort-compare-recipients key-funcs)))
	    ((equal key "reversed-recipients")
	     (setq key-funcs (cons 'vm-sort-compare-recipients-r key-funcs)))
	    ((equal key "byte-count")
	     (setq key-funcs (cons 'vm-sort-compare-byte-count key-funcs)))
	    ((equal key "reversed-byte-count")
	     (setq key-funcs (cons 'vm-sort-compare-byte-count-r key-funcs)))
	    ((equal key "line-count")
	     (setq key-funcs (cons 'vm-sort-compare-line-count key-funcs)))
	    ((equal key "reversed-line-count")
	     (setq key-funcs (cons 'vm-sort-compare-line-count-r key-funcs)))
	    ((equal key "spam-score")
	     (setq key-funcs (cons 'vm-sort-compare-spam-score key-funcs)))
	    ((equal key "reversed-spam-score")
	     (setq key-funcs (cons 'vm-sort-compare-spam-score-r key-funcs)))
	    ((equal key "physical-order")
	     (setq key-funcs (cons 'vm-sort-compare-physical-order key-funcs)))
	    ((equal key "reversed-physical-order")
	     (setq key-funcs (cons 'vm-sort-compare-physical-order-r 
				   key-funcs)))
            ((equal key "header")
             (setq vm-sort-compare-header nil)
             (setq key-funcs (cons 'vm-sort-compare-header key-funcs)))
	    ((equal key "thread")
	     (vm-build-threads-if-unbuilt)
	     (vm-build-thread-lists)
	     (setq key-funcs (cons 'vm-sort-compare-thread key-funcs)))
	    (t
             (let ((compare (intern (format "vm-sort-compare-%s" key))))
               (if (functionp compare)
                   (setq key-funcs (cons compare key-funcs))
                 (error "Unknown key: %s" key)))))
      (setq key-list (cdr key-list)))
    (setq key-funcs (nreverse key-funcs))
    ;; if this is not a thread sort and threading is enabled,
    ;; then disable threading and make sure the whole summary is
    ;; regenerated (to recalculate %I everywhere).
    (when vm-summary-show-threads
      (vm-build-threads-if-unbuilt)
      (vm-build-thread-lists)
      (setq key-funcs (cons 'vm-sort-compare-thread key-funcs)))
    (vm-inform 7 "%s: Sorting messages..." (buffer-name))
    (let ((vm-key-functions key-funcs))
      (setq new-message-list (sort (copy-sequence old-message-list)
				   'vm-sort-compare-xxxxxx))
      ;; only need to do this sort if we're going to physically
      ;; move messages later.
      (if physical
	  (setq vm-key-functions '(vm-sort-compare-physical-order)
		physical-order-list (sort (copy-sequence old-message-list)
					  'vm-sort-compare-xxxxxx))))
    (vm-inform 7 "%s: Sorting messages... done" (buffer-name))
    (let ((inhibit-quit t))
      (setq mp-old old-message-list
	    mp-new new-message-list)
      (while mp-new
	(if (eq (car mp-old) (car mp-new))
	    (setq mp-old (cdr mp-old)
		  mp-new (cdr mp-new))
	  (setq order-did-change t)
	  ;; unless a full redo has been requested, the numbering
	  ;; start point now points to a cons in the old message
	  ;; list.  therefore we just change the variable
	  ;; directly to avoid the list scan that
	  ;; vm-set-numbering-redo-start-point does.
	  (cond ((not (eq vm-numbering-redo-start-point t))
		 (setq vm-numbering-redo-start-point mp-new
		       vm-numbering-redo-end-point nil)))
	  (if vm-summary-buffer
	      (progn
		(setq vm-need-summary-pointer-update t)
		;; same logic as numbering reset above...
		(cond ((not (eq vm-summary-redo-start-point t))
		       (setq vm-summary-redo-start-point mp-new)))
		;; start point of this message's summary is now
		;; wrong relative to where it is in the
		;; message list.  fix it and the summary rebuild
		;; will take care of the rest.
		(vm-set-su-start-of (car mp-new)
				    (vm-su-start-of (car mp-old)))))
	  (setq mp-new nil)))
      (if (and physical (vm-has-message-order))
	  (let ((buffer-read-only nil))
	    ;; the folder is being physically ordered so we don't
	    ;; need a message order header to be stuffed, nor do
	    ;; we need to retain one in the folder buffer.  so we
	    ;; strip out any existing message order header and
	    ;; say there are no changes to prevent a message
	    ;; order header from being stuffed later.
	    (vm-remove-message-order)
	    (setq vm-message-order-changed nil)
	    (vm-inform 6 "%s: Moving messages... " (buffer-name))
	    (widen)
	    (setq mp-old physical-order-list
		  mp-new new-message-list)
	    (setq old-start (vm-start-of (car mp-old)))
	    (while mp-new
	      (if (< (vm-start-of (car mp-old)) old-start)
		  ;; already moved this message
		  (setq mp-old (cdr mp-old))
		(if (eq (car mp-old) (car mp-new))
		    (setq mp-old (cdr mp-old)
			  mp-new (cdr mp-new))
		  ;; move message
		  (vm-physically-move-message (car mp-new) (car mp-old))
		  ;; record start position.  if vm-start-of
		  ;; mp-old ever becomes less than old-start
		  ;; we're running into messages that have
		  ;; already been moved.
		  (setq old-start (vm-start-of (car mp-old)))
		  ;; move mp-new but not mp-old because we moved
		  ;; mp-old down one message by inserting a
		  ;; message in front of it.
		  (setq mp-new (cdr mp-new)))))
	    (vm-inform 6 "%s: Moving messages... done" (buffer-name))
	    (vm-mark-folder-modified-p (current-buffer))
	    (vm-clear-modification-flag-undos))
	(if (and order-did-change (not vm-folder-read-only))
	    (progn
	      (setq vm-message-order-changed t)
	      ;; only viewing order changed here
	      ;; (vm-mark-folder-modified-p (current-buffer))
	      (vm-clear-modification-flag-undos))))
      (setq vm-ml-sort-keys ml-keys)
      (intern (buffer-name) vm-buffers-needing-display-update)
      (cond (order-did-change
	     (setq vm-message-list new-message-list)
	     (vm-reverse-link-messages)
	     (if vm-message-pointer
		 (setq vm-message-pointer
		       (or (cdr (vm-reverse-link-of (car vm-message-pointer)))
			   vm-message-list)))
	     (if vm-last-message-pointer
		 (setq vm-last-message-pointer
		       (or (cdr (vm-reverse-link-of
				 (car vm-last-message-pointer)))
			   vm-message-list))))))
    (if (and vm-message-pointer
	     order-did-change
	     (or lets-get-physical vm-move-messages-physically))
	;; clip region is most likely messed up
	(vm-present-current-message)
      (vm-update-summary-and-mode-line))

    (if auto-folder-p
        (vm-sort-insert-auto-folder-names))))

;;;###autoload
(defun vm-sort-compare-xxxxxx (msg1 msg2)
  "Compare MSG1 and MSG2 to determine which should precede the
other in the sort order according to `vm-key-functions'.  Returns a
boolean value (`t' or `nil'). 

`vm-key-functions' is a list of \"key-functions\" that compare
the two messages to see if one should precede the other.  They
return `t' if MSG1 should precede MSG2, `nil' if MSG2 should
precede MSG1, and '=' if neither is the case.  In the last case, the
two messages are regarded as equivalent as per the particular
key-function and the remaining key-functions are tried to resolve the
tie.   (This amounts to a lexicographic combination of the sort-orders
in `vm-key-functions'.)

`vm-sort-compare-thread' is special if it occurs in
`vm-key-functions'.  It determines the oldest different ancestors
of MSG1 and MSG2, which are then compared using the remaining
key-functions.

If all the key-functions return `=' (signifying that MSG1 and
MSG2 are equivalent according to all the key-functions), then the
messages are compared by the physical order to break the tie.
So, this function always returns a boolean value, never `='."
  (if (and vm-summary-debug
	   (or (member (vm-number-of msg1) vm-summary-traced-messages)
	       (member (vm-number-of msg2) vm-summary-traced-messages)))
      (debug "traced message"))
  (let ((key-funcs vm-key-functions) 
	result
	(m1 msg1) (m2 msg2))
    (catch 'done
      (unless key-funcs
	(throw 'done nil))
      (when (eq (car key-funcs) 'vm-sort-compare-thread)
	(setq result (vm-sort-compare-thread m1 m2))
	(if (consp result)
	    (progn
	      (setq m1 (car result)
		    m2 (cdr result)
		    key-funcs (cdr key-funcs))
	      (if (or (null m1) (null m2))
		  (progn (if vm-summary-debug (debug "null message"))
			 (throw 'done t))))
	  (throw 'done result)))
      (while key-funcs
	(if (eq '= (setq result (funcall (car key-funcs) m1 m2)))
	    (setq key-funcs (cdr key-funcs))
	  (throw 'done result)))
      ;; if all else fails try physical order
      (if (eq m1 m2)
	  nil
	(vm-sort-compare-physical-order m1 m2)))))

(defun vm-sort-compare-thread (m1 m2)
  "Returns a cons-pair of messages representing the oldest different
ancestors of M1 and M2 in thread-tree.  This is justified by the property
that, if P1 and P2 are the oldest different ancestors of M1 and M2, then

  M1 precedes M2 in the threaded-sort order if and only if 
		P1 precedes P2 in the normal sort order.
"
  (let ((root1 (vm-thread-root-sym m1))
	(root2 (vm-thread-root-sym m2))
	(list1 (vm-thread-list m1))
	(list2 (vm-thread-list m2))
	;; (criterion (if vm-sort-threads-by-youngest-date 
	;; 	       'youngest-date
	;; 	     'oldest-date))
	p1 p2) ;; d1 d2
    (catch 'done
      (cond 
	    ;; ((not (eq (car list1) (car list2)))
	    ;;  ;; different reference threads
	    ;;  (let ((date1 (vm-th-thread-date-of (car list1) criterion))
	    ;; 	   (date2 (vm-th-thread-date-of (car list2) criterion)))
	    ;;    (cond ((string-lessp date1 date2) t)
	    ;; 	     ((string-equal date1 date2)
	    ;; 	      (string-lessp (format "%s" root1) (format "%s" root2)))
	    ;; 	     (t nil))))
	    ((eq (car list1) (car list2))
	     ;; within the same reference thread
	     (setq list1 (cdr list1) list2 (cdr list2))
	     (if (not vm-sort-subthreads)
		 ;; no further sorting for internal messages of threads
		 (when (and list1 list2)
		   (throw 'done (cons m1 m2)))
	       (while (and list1 list2)
		 (setq p1 (car list1) p2 (car list2))
		 (cond ((null (vm-th-message-of p1))
			(setq list1 (cdr list1)))
		       ((null (vm-th-message-of p2))
			(setq list2 (cdr list2)))
		       ((string-equal p1 p2)
			(setq list1 (cdr list1)
			      list2 (cdr list2)))
		       (t
			(throw 'done 
			       (cons (vm-th-message-of p1)
				     (vm-th-message-of p2)))))))
	     (cond (list1 nil)			; list2=nil, m2 ancestor of m1
		   (list2 t)			; list1=nil, m1 ancestor of m2
		   ((not (eq (vm-thread-symbol m1) ; m1 and m2 different
			     (vm-thread-symbol m2)))
		    (cons m1 m2))
		   ((eq m1 (vm-th-message-of (vm-thread-symbol m1)))
		    t)			; list1=list2=nil, m2 copy of m1
		   (t nil)))		;; list1=list2=nil, m1 copy of m2
	    ((eq root1 root2)
	     ;; within the same subject thread
	     (while (null (vm-th-message-of (car list1)))
	       (setq list1 (cdr list1)))
	     (while (null (vm-th-message-of (car list2)))
	       (setq list2 (cdr list2)))
	     (cons (vm-th-message-of (car list1))
		   (vm-th-message-of (car list2))))
	    ((not (eq root1 root2))
	     ;; different threads
	     (cons (vm-th-message-of root1)
		   (vm-th-message-of root2)))
	    ))))

(defun vm-sort-compare-author (m1 m2)
  (let ((s1 (vm-su-from m1))
	(s2 (vm-su-from m2)))
    (cond ((string-lessp s1 s2) t)
	  ((string-equal s1 s2) '=)
	  (t nil))))

(defun vm-sort-compare-author-r (m1 m2)
  (let ((s1 (vm-su-from m1))
	(s2 (vm-su-from m2)))
    (cond ((string-lessp s1 s2) nil)
	  ((string-equal s1 s2) '=)
	  (t t))))

(defun vm-sort-compare-full-name (m1 m2)
  (let ((s1 (vm-su-full-name m1))
	(s2 (vm-su-full-name m2)))
    (cond ((string-lessp s1 s2) t)
	  ((string-equal s1 s2) '=)
	  (t nil))))

(defun vm-sort-compare-full-name-r (m1 m2)
  (let ((s1 (vm-su-full-name m1))
	(s2 (vm-su-full-name m2)))
    (cond ((string-lessp s1 s2) nil)
	  ((string-equal s1 s2) '=)
	  (t t))))

(defun vm-sort-compare-date (m1 m2)
  (let ((s1 (vm-so-sortable-datestring m1))
	(s2 (vm-so-sortable-datestring m2)))
    (cond ((string-lessp s1 s2) t)
	  ((string-equal s1 s2) '=)
	  (t nil))))

(defun vm-sort-compare-date-r (m1 m2)
  (let ((s1 (vm-so-sortable-datestring m1))
	(s2 (vm-so-sortable-datestring m2)))
    (cond ((string-lessp s1 s2) nil)
	  ((string-equal s1 s2) '=)
	  (t t))))

(defun vm-sort-compare-activity (m1 m2)
  (let ((d1 (vm-th-youngest-date-of (vm-thread-symbol m1)))
	(d2 (vm-th-youngest-date-of (vm-thread-symbol m2))))
    (cond ((string-lessp d1 d2) t)
	  ((string-equal d1 d2) '=)
	  (t nil))))

(defun vm-sort-compare-activity-r (m1 m2)
  (let ((d1 (vm-th-youngest-date-of (vm-thread-symbol m1)))
	(d2 (vm-th-youngest-date-of (vm-thread-symbol m2))))
    (cond ((string-lessp d1 d2) nil)
	  ((string-equal d1 d2) '=)
	  (t t))))

;; (defun vm-sort-compare-thread-oldest-date (m1 m2)
;;   (let ((d1 (vm-th-oldest-date-of (vm-thread-symbol m1)))
;; 	(d2 (vm-th-oldest-date-of (vm-thread-symbol m2))))
;;     (cond ((string-lessp d1 d2) t)
;; 	  ((string-equal d1 d2) '=)
;; 	  (t nil))))

;; (defun vm-sort-compare-thread-oldest-date-r (m1 m2)
;;   (let ((d1 (vm-th-oldest-date-of (vm-thread-symbol m1)))
;; 	(d2 (vm-th-oldest-date-of (vm-thread-symbol m2))))
;;     (cond ((string-lessp d1 d2) nil)
;; 	  ((string-equal d1 d2) '=)
;; 	  (t t))))

(defun vm-sort-compare-recipients (m1 m2)
  (let ((s1 (vm-su-to-cc m1))
	(s2 (vm-su-to-cc m2)))
    (cond ((string-lessp s1 s2) t)
	  ((string-equal s1 s2) '=)
	  (t nil))))

(defun vm-sort-compare-recipients-r (m1 m2)
  (let ((s1 (vm-su-to-cc m1))
	(s2 (vm-su-to-cc m2)))
    (cond ((string-lessp s1 s2) nil)
	  ((string-equal s1 s2) '=)
	  (t t))))

(defun vm-sort-compare-addressees (m1 m2)
  (let ((s1 (vm-su-to m1))
	(s2 (vm-su-to m2)))
    (cond ((string-lessp s1 s2) t)
	  ((string-equal s1 s2) '=)
	  (t nil))))

(defun vm-sort-compare-addressees-r (m1 m2)
  (let ((s1 (vm-su-to m1))
	(s2 (vm-su-to m2)))
    (cond ((string-lessp s1 s2) nil)
	  ((string-equal s1 s2) '=)
	  (t t))))

(defun vm-sort-compare-subject (m1 m2)
  (let ((s1 (vm-so-sortable-subject m1))
	(s2 (vm-so-sortable-subject m2)))
    (cond ((string-lessp s1 s2) t)
	  ((string-equal s1 s2) '=)
	  (t nil))))

(defun vm-sort-compare-subject-r (m1 m2)
  (let ((s1 (vm-so-sortable-subject m1))
	(s2 (vm-so-sortable-subject m2)))
    (cond ((string-lessp s1 s2) nil)
	  ((string-equal s1 s2) '=)
	  (t t))))

(defun vm-sort-compare-line-count (m1 m2)
  (let ((n1 (string-to-number (vm-su-line-count m1)))
	(n2 (string-to-number (vm-su-line-count m2))))
    (cond ((< n1 n2) t)
	  ((= n1 n2) '=)
	  (t nil))))

(defun vm-sort-compare-line-count-r (m1 m2)
  (let ((n1 (string-to-number (vm-su-line-count m1)))
	(n2 (string-to-number (vm-su-line-count m2))))
    (cond ((> n1 n2) t)
	  ((= n1 n2) '=)
	  (t nil))))

(defun vm-sort-compare-byte-count (m1 m2)
  (let ((n1 (string-to-number (vm-su-byte-count m1)))
	(n2 (string-to-number (vm-su-byte-count m2))))
    (cond ((< n1 n2) t)
	  ((= n1 n2) '=)
	  (t nil))))

(defun vm-sort-compare-byte-count-r (m1 m2)
  (let ((n1 (string-to-number (vm-su-byte-count m1)))
	(n2 (string-to-number (vm-su-byte-count m2))))
    (cond ((> n1 n2) t)
	  ((= n1 n2) '=)
	  (t nil))))

(defun vm-sort-compare-spam-score (m1 m2)
  (let ((s1 (vm-su-spam-score m1))
	(s2 (vm-su-spam-score m2)))
    (cond ((< s1 s2) t)
	  ((= s1 s2) '=)
	  (t nil))))

(defun vm-sort-compare-spam-score-r (m1 m2)
  (let ((s1 (vm-su-spam-score m1))
	(s2 (vm-su-spam-score m2)))
    (cond ((< s1 s2) nil)
	  ((= s1 s2) '=)
	  (t t))))

;;;###autoload
(defun vm-sort-compare-physical-order (m1 m2)
  (let ((r1 (vm-real-message-of m1))
	(r2 (vm-real-message-of m2))
	n1 n2)
    (if (and r1 r2 
	     (setq n1 (marker-position (vm-start-of r1)))
	     (setq n2 (marker-position (vm-start-of r2))))
	(cond ((< n1 n2) t)
	      ((= n1 n2) '=)
	      (t nil))
      '=)))

;;;###autoload
(defun vm-sort-compare-physical-order-r (m1 m2)
  (let ((n1 (vm-start-of m1))
	(n2 (vm-start-of m2)))
    (cond ((> n1 n2) t)
	  ((= n1 n2) '=)
	  (t nil))))

(add-to-list 'vm-supported-sort-keys "header")

(defun vm-get-headers-of (m &optional headers)
  (save-excursion
    (save-restriction
      (widen)
     (let ((end (vm-text-of m)))
       (set-buffer (vm-buffer-of m))
       (goto-char (vm-start-of m))
       (while (re-search-forward "^[^: \n\t]+:" end t)
         (cl-pushnew (match-string 0) headers :test #'equal))
       headers))))

(defun vm-sort-compare-header (m1 m2)
  (if (null vm-sort-compare-header)
      (setq vm-sort-compare-header
            (completing-read
	     ;; prompt
             (if (car vm-sort-compare-header-history)
                 (format "Sort hy header (%s): "
                         (car vm-sort-compare-header-history))
               "Sort hy header: ")
	     ;; collection
             (mapcar (lambda (h) (list h))
                     (vm-get-headers-of m2 (vm-get-headers-of m1)))
	     ;; predicate, require-match, initial-input
             nil nil nil
	     ;; hist
             'vm-sort-compare-header-history
	     ;; default
             (car vm-sort-compare-header-history)))
    (string< (vm-get-header-contents m1 vm-sort-compare-header)
             (vm-get-header-contents m2 vm-sort-compare-header))))

(provide 'vm-sort)
;;; vm-sort.el ends here
