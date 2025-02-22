;;; vm-folder.el --- VM folder related functions  -*- lexical-binding: t; -*-
;;
;; This file is part of VM
;;
;; Copyright (C) 1989-2001 Kyle E. Jones
;; Copyright (C) 2003-2006 Robert Widhopf-Fenk
;; Copyright (C) 2008-2010 Uday S. Reddy
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
(require 'vm-toolbar)
(eval-when-compile (require 'cl-lib))

;; FIXME: Cyclic dependency.
(provide 'vm-folder)

(require 'vm-delete)
(require 'vm-pop)
(require 'vm-page)

;; vm-xemacs.el is a fake file to fool the Emacs 23 compiler
(declare-function get-itimer "vm-xemacs.el" (name))
(declare-function start-itimer "vm-xemacs.el"
		  (name function value &optional restart is-idle with-args
			&rest function-arguments))
(declare-function set-itimer-restart "vm-xemacs.el" (itimer restart))

(declare-function vm-update-draft-count "vm.el" ())
(declare-function vm "vm.el" 
		  (&optional folder 
			     &key read-only access-method reload revisit))
(declare-function vm-mode "vm.el" (&optional read-only))
		  

;; Operations for vm-folder-access-data

(defsubst vm-folder-pop-maildrop-spec ()
  (aref vm-folder-access-data 0))
(defsubst vm-folder-pop-process ()
  (aref vm-folder-access-data 1))

(defsubst vm-set-folder-pop-maildrop-spec (val)
  (aset vm-folder-access-data 0 val))
(defsubst vm-set-folder-pop-process (val)
  (aset vm-folder-access-data 1 val))

;; the maildrop spec of the imap folder
(defsubst vm-folder-imap-maildrop-spec ()
  (aref vm-folder-access-data 0))
;; current imap process of the folder - each folder has a separate one
(defsubst vm-folder-imap-process ()
  (aref vm-folder-access-data 1))
;; the UIDVALIDITY value of the imap folder on the server
(defsubst vm-folder-imap-uid-validity ()
  (aref vm-folder-access-data 2))
;; the list of uid's and flags of the messages in the imap folder on
;; the server (msg-num . uid . size . flags list)
(defsubst vm-folder-imap-uid-list ()
  (aref vm-folder-access-data 3))	
;; the number of messages in the imap folder on the server
(defsubst vm-folder-imap-mailbox-count ()
  (aref vm-folder-access-data 4))
;; flag indicating whether the imap folder allows writing
(defsubst vm-folder-imap-read-write ()
  (aref vm-folder-access-data 5))
;; flag indicating whether the imap folder allows deleting
(defsubst vm-folder-imap-can-delete ()
  (aref vm-folder-access-data 6))
;; flag indicating whether the imap server has body-peek functionality
(defsubst vm-folder-imap-body-peek ()
  (aref vm-folder-access-data 7))
;; list of permanent flags storable on the imap server
(defsubst vm-folder-imap-permanent-flags ()
  (aref vm-folder-access-data 8))
;; obarray of uid's with message numbers as their values (on the server)
(defsubst vm-folder-imap-uid-obarray ()
  (aref vm-folder-access-data 9))	; obarray(uid, msg-num)
;; obarray of uid's with flags lists as their values (on the server)
(defsubst vm-folder-imap-flags-obarray ()
  (aref vm-folder-access-data 10))	; obarray(uid, (size . flags list))
					; cons-pair shared with imap-uid-list
;; the number of recent messages in the imap folder on the server
(defsubst vm-folder-imap-recent-count ()
  (aref vm-folder-access-data 11))
;; the number of messages in the imap folder on the server, when last retrieved
(defsubst vm-folder-imap-retrieved-count ()
  (aref vm-folder-access-data 12))

(defsubst vm-set-folder-imap-maildrop-spec (val)
  (aset vm-folder-access-data 0 val))
(defsubst vm-set-folder-imap-process (val)
  (aset vm-folder-access-data 1 val))
(defsubst vm-set-folder-imap-uid-validity (val)
  (aset vm-folder-access-data 2 val))
(defsubst vm-set-folder-imap-uid-list (val)
  (aset vm-folder-access-data 3 val))
(defsubst vm-set-folder-imap-mailbox-count (val)
  (aset vm-folder-access-data 4 val))
(defsubst vm-set-folder-imap-read-write (val)
  (aset vm-folder-access-data 5 val))
(defsubst vm-set-folder-imap-can-delete (val)
  (aset vm-folder-access-data 6 val))
(defsubst vm-set-folder-imap-body-peek (val)
  (aset vm-folder-access-data 7 val))
(defsubst vm-set-folder-imap-permanent-flags (val)
  (aset vm-folder-access-data 8 val))
(defsubst vm-set-folder-imap-uid-obarray (val)
  (aset vm-folder-access-data 9 val))
(defsubst vm-set-folder-imap-flags-obarray (val)
  (aset vm-folder-access-data 10 val))
(defsubst vm-set-folder-imap-recent-count (val)
  (aset vm-folder-access-data 11 val))
(defsubst vm-set-folder-imap-retrieved-count (val)
  (aset vm-folder-access-data 12 val))

(defun vm-set-buffer-modified-p (flag &optional buffer)
  "Sets the `buffer-modified-p' of the current folder to FLAG.  Optional
argument BUFFER can ask for it to be done for some other folder. 

This function is deprecated.  Use `vm-mark-folder-modified-p' or
  `vm-unmark-folder-modified-p' instead."
  (if flag
      (vm-mark-folder-modified-p buffer)
    (vm-unmark-folder-modified-p buffer)))

(defun vm-mark-folder-modified-p (&optional buffer)
  "Sets the `buffer-modified-p' flag of the current folder to t.  Optional
argument BUFFER can ask for it to be done for some other folder. 

This function also zeroes `vm-messages-not-on-disk' and schedules the
folder for redisplay."
  (with-current-buffer (or buffer (current-buffer))
    (set-buffer-modified-p t)
    (vm-increment vm-modification-counter)
    (intern (buffer-name) vm-buffers-needing-display-update)
    (setq vm-messages-not-on-disk 0)))

(defun vm-unmark-folder-modified-p (buffer)
  "Sets the `buffer-modified-p' flag of the current folder to nil."
  (with-current-buffer (or buffer (current-buffer))
    (set-buffer-modified-p nil)
    (vm-increment vm-modification-counter)
    (intern (buffer-name) vm-buffers-needing-display-update)))

(defun vm-reset-buffer-modified-p (value buffer)
  "Sets the `buffer-modified-p' flag of BUFFER to VALUE.  This
is not meant for changing the flag for folders.  Use
`vm-mark-folder-modified-p' or `vm-unset-folder-modified-p' instead."
  (with-current-buffer buffer
    (set-buffer-modified-p value)))

(defun vm-restore-buffer-modified-p (value buffer)
  "Restores the `buffer-modified-p' flag of BUFFER to a saved VALUE. 
This is the same as `vm-reset-buffer-modified-p' but represents a
specific intent."  
  (with-current-buffer buffer
    (set-buffer-modified-p value)))

(defun vm-message-position (m)
  "Return a message-pointer pointing to the message M in the
`vm-message-list'." 
  (memq m vm-message-list))

(defun vm-number-messages (&optional start-point end-point)
  "Set the number-of and padded-number-of slots of messages
in vm-message-list.

If non-nil, START-POINT should point to a cons cell in
vm-message-list and the numbering will begin there, else the
numbering will begin at the head of vm-message-list.  If
START-POINT is non-nil the reverse-link-of slot of the message in
the cons must be valid and the message pointed to (if any) must
have a non-nil number-of slot, because it is used to determine
what the starting message number should be.

If non-nil, END-POINT should point to a cons cell in
vm-message-list and the numbering will end with the message just
before this cell.  A nil value means numbering will be done until
the end of vm-message-list is reached."
  (let ((n 1) 
	(message-list vm-message-list))
    (when (and start-point (vm-reverse-link-of (car start-point)))
      (if (null (vm-number-of (car (vm-reverse-link-of (car start-point)))))
	  (vm-warn 0 2 "%s: Bad numbering start-point; please report bug."
		   (buffer-name))
	(setq n (1+ (string-to-number
		     (vm-number-of
		      (car (vm-reverse-link-of (car start-point))))))
	      message-list start-point)))
    (while (not (eq message-list end-point))
      (vm-set-number-of (car message-list) (int-to-string n))
      (vm-set-padded-number-of (car message-list) (format "%3d" n))
      (setq n (1+ n) 
	    message-list (cdr message-list)))
    (or end-point (setq vm-ml-highest-message-number (int-to-string (1- n))))
    (if vm-summary-buffer
	(vm-copy-local-variables vm-summary-buffer
				 'vm-ml-highest-message-number))))

(defun vm-set-numbering-redo-start-point (start-point)
  "Set vm-numbering-redo-start-point to START-POINT if appropriate.
Also mark the current buffer as needing a display update.

START-POINT should be a cons in vm-message-list or just t.
 (t means start from the beginning of vm-message-list.)
If START-POINT is closer to the head of vm-message-list than
vm-numbering-redo-start-point or is equal to t, then
vm-numbering-redo-start-point is set to match it.
If START-POINT is nil, nothing is updated."
  (when start-point
    (intern (buffer-name) vm-buffers-needing-display-update)
    (cond ((eq vm-numbering-redo-start-point t)
	   nil)
	  ((and (consp start-point) (consp vm-numbering-redo-start-point))
	   (let ((mp vm-message-list))
	     (while (and mp
			 (not
			  (or (eq (car mp) (car start-point))
			      (eq (car mp) 
				  (car vm-numbering-redo-start-point)))))
	       (setq mp (cdr mp)))
	     (when (null mp)
	       (error 
		"Something is wrong in vm-set-numbering-redo-start-point"))
	     (when (eq (car mp) (car start-point))
	       (setq vm-numbering-redo-start-point start-point))))
	   (t
	    (setq vm-numbering-redo-start-point start-point)))))

(defun vm-set-numbering-redo-end-point (end-point)
  "Set vm-numbering-redo-end-point to END-POINT if appropriate.
Also mark the current buffer as needing a display update.

END-POINT should be a cons in vm-message-list or just t.
 (t means number all the way to the end of vm-message-list.)
If END-POINT is closer to the end of vm-message-list or is equal
to t, then vm-numbering-redo-start-point is set to match it.
The number-of slot is used to determine proximity to the end of
vm-message-list, so this slot must be valid in END-POINT's message
and the message in the cons pointed to by vm-numbering-redo-end-point.
If END-PIONT is nil, nothing is updated."
  (when end-point
    (intern (buffer-name) vm-buffers-needing-display-update)
    (cond ((eq end-point t)
	   (setq vm-numbering-redo-end-point t))
	  ((and (consp end-point)
		(> (string-to-number
		    (vm-number-of
		     (car end-point)))
		   (string-to-number
		    (vm-number-of
		     (car vm-numbering-redo-end-point)))))
	   (setq vm-numbering-redo-end-point end-point))
	  ((null end-point)
	   (setq vm-numbering-redo-end-point end-point)))))

(defun vm-do-needed-renumbering ()
  "Number messages in vm-message-list as specified by
vm-numbering-redo-start-point and vm-numbering-redo-end-point.

vm-numbering-redo-start-point = t means start at the head
of vm-message-list.
vm-numbering-redo-end-point = t means number all the way to the
end of vm-message-list.

Otherwise the variables' values should be conses in vm-message-list
or nil."
  (when vm-numbering-redo-start-point
    ;; vm-number-messages expects nil for defaults, not t!
    (vm-number-messages (if (consp vm-numbering-redo-start-point)
			    vm-numbering-redo-start-point)
			(if (consp vm-numbering-redo-end-point)
			    vm-numbering-redo-end-point))
    (setq vm-numbering-redo-start-point nil
	  vm-numbering-redo-end-point nil)))

(defun vm-set-summary-redo-start-point (start-point)
  "Set vm-summary-redo-start-point to START-POINT if appropriate.
Also mark the current buffer as needing a display update.

START-POINT should be a cons in vm-message-list or just t.
 (t means start from the beginning of vm-message-list.)
If START-POINT is closer to the head of vm-message-list than
vm-summary-redo-start-point or is equal to t, then
vm-summary-redo-start-point is set to match it.
If START-POINT is nil, nothing is updated."
  (when start-point
    (intern (buffer-name) vm-buffers-needing-display-update)
    (cond ((eq vm-summary-redo-start-point t)
	   nil)
	  ((and (consp start-point) (consp vm-summary-redo-start-point))
	   (let ((mp vm-message-list))
	     (while (and mp (not (or (eq mp start-point)
				     (eq mp vm-summary-redo-start-point))))
	       (setq mp (cdr mp)))
	     (when (null mp)
	       (error "Something is wrong in vm-set-summary-redo-start-point"))
	     (when (eq mp start-point)
	       (setq vm-summary-redo-start-point start-point))))
	  (t
	   (setq vm-summary-redo-start-point start-point)))))

(defun vm-mark-for-summary-update (m &optional dont-kill-cache)
  "Mark message M and all its mirrored mesages for a summary update.
Also mark M's buffer as needing a display update. Any virtual
messages of M and their buffers are similarly marked for update.
If M is a virtual message and virtual mirroring is in effect for
M (i.e. attribute-of eq attributes-of M's real message), M's real
message and its buffer are scheduled for an update.

Optional arg DONT-KILL-CACHE non-nil means don't invalidate the
summary-of slot for any messages marked for update.  This is
meant to be used by functions that update message information
that is not cached in the summary-of slot, e.g. message numbers
and thread indentation."
  (cond ((eq m (vm-real-message-of m))
	 ;; this is a real message.
	 ;; its summary and modeline need to be updated.
	 (unless dont-kill-cache
	   ;; toss the cache.  this also tosses the cache of any
	   ;; virtual messages mirroring this message.  the summary
	   ;; entry cache must be cleared when an attribute of a
	   ;; message that could appear in the summary has changed.
	   (vm-set-decoded-tokenized-summary-of m nil))
	 (when (vm-su-start-of m)
	   (vm-add-to-list m vm-messages-needing-summary-update))
	 (intern (buffer-name (vm-buffer-of m))
		 vm-buffers-needing-display-update)
	 ;; find the virtual messages of this real message that
	 ;; need a summary update.
	 (dolist (v-m (vm-virtual-messages-of m))
	   (when (eq (vm-attributes-of m) (vm-attributes-of v-m))
	     (when (vm-su-start-of v-m)
	       (vm-add-to-list v-m 
			       vm-messages-needing-summary-update))
	     ;; don't trust blindly.  The user could have killed some
	     ;; of these buffers
	     (when (buffer-name (vm-buffer-of v-m))
	       (intern (buffer-name (vm-buffer-of v-m))
		       vm-buffers-needing-display-update)))))
	(t
	 ;; this is a virtual message.
	 ;;
	 ;; if this message has virtual messages then we need to
	 ;; schedule updates for all the virtual messages that
	 ;; share a cache with this message and we need to
	 ;; schedule an update for the underlying real message
	 ;; since we are mirroring it.
	 ;;
	 ;; if there are no virtual messages, then this virtual
	 ;; message is not mirroring its real message so we need
	 ;; only take care of this one message.
	 (if (vm-virtual-messages-of m)
	     (progn
	       ;; schedule updates for all the virtual message which share
	       ;; the same cache as this message.
	       (dolist (v-m (vm-virtual-messages-of m))
		 (when (eq (vm-attributes-of m) (vm-attributes-of v-m))
		   (when (vm-su-start-of v-m)
		     (vm-add-to-list v-m 
				     vm-messages-needing-summary-update))
		   (when (buffer-name (vm-buffer-of v-m))
		     (intern (buffer-name (vm-buffer-of v-m))
			     vm-buffers-needing-display-update))))
	       ;; now take care of the real message
	       (unless dont-kill-cache
		 ;; toss the cache.  this also tosses the cache of
		 ;; any virtual messages sharing the same cache as
		 ;; this message.
		 ;; FIXME does this really toss the cache of virtual
		 ;; mirrors?  USR, 2012-10-14
		 (vm-set-decoded-tokenized-summary-of m nil))
	       (when (vm-su-start-of (vm-real-message-of m))
		 (vm-add-to-list (vm-real-message-of m)
				 vm-messages-needing-summary-update))
	       (intern (buffer-name (vm-buffer-of (vm-real-message-of m)))
		       vm-buffers-needing-display-update))
	   (unless dont-kill-cache
	     (vm-set-virtual-summary-of m nil))
	   (when (vm-su-start-of m)
	     (vm-add-to-list m vm-messages-needing-summary-update))
	   (intern (buffer-name (vm-buffer-of m))
		   vm-buffers-needing-display-update)))))

(defun vm-do-needed-mode-line-update ()
  "Do a modeline update for the current folder buffer.
This means setting up all the various vm-ml attribute variables
in the folder buffer and copying necessary variables to the
folder buffer's summary and presentation buffers, and then
forcing Emacs to update all modelines.

If a virtual folder being updated has no messages, then
erase-buffer is called on its buffer.

If any type of folder is empty, erase-buffer is called
on its presentation buffer, if any."
  ;; XXX This last bit should probably should be moved to
  ;; XXX vm-expunge-folder.

  (if (null vm-message-pointer)
      (progn
	;; erase the leftover message if the folder is really empty.
	(if (eq major-mode 'vm-virtual-mode)
	    (let ((buffer-read-only nil)
		  (omodified (buffer-modified-p)))
	      (unwind-protect
		  (erase-buffer)
		(vm-restore-buffer-modified-p omodified (current-buffer)))))
	(if (and vm-presentation-buffer (buffer-name vm-presentation-buffer))
	    (let ((omodified (buffer-modified-p)))
	      (unwind-protect
		  (with-current-buffer vm-presentation-buffer
		    (let ((buffer-read-only nil))
		      (erase-buffer)))
		(vm-restore-buffer-modified-p omodified (current-buffer))))))
    ;; try to avoid calling vm-su-labels if possible so as to
    ;; avoid loading vm-summary.el.
    (if (vm-decoded-labels-of (car vm-message-pointer))
	(setq vm-ml-labels (vm-su-labels (car vm-message-pointer)))
      (setq vm-ml-labels nil))
    (setq vm-ml-message-number (vm-number-of (car vm-message-pointer)))
    (setq vm-ml-message-new (vm-new-flag (car vm-message-pointer)))
    (setq vm-ml-message-unread (vm-unread-flag (car vm-message-pointer)))
    (setq vm-ml-message-read
	  (and (not (vm-new-flag (car vm-message-pointer)))
	       (not (vm-unread-flag (car vm-message-pointer)))))
    (setq vm-ml-message-edited (vm-edited-flag (car vm-message-pointer)))
    (setq vm-ml-message-filed (vm-filed-flag (car vm-message-pointer)))
    (setq vm-ml-message-written (vm-written-flag (car vm-message-pointer)))
    (setq vm-ml-message-replied (vm-replied-flag (car vm-message-pointer)))
    (setq vm-ml-message-forwarded (vm-forwarded-flag (car vm-message-pointer)))
    (setq vm-ml-message-redistributed (vm-redistributed-flag (car vm-message-pointer)))
    (setq vm-ml-message-deleted (vm-deleted-flag (car vm-message-pointer)))
    (setq vm-ml-message-marked (vm-mark-of (car vm-message-pointer))))
  (if (and vm-summary-buffer (buffer-name vm-summary-buffer))
      (let ((modified (buffer-modified-p)))
	  (vm-copy-local-variables vm-summary-buffer
				   'default-directory
				   'vm-ml-message-new
				   'vm-ml-message-unread
				   'vm-ml-message-read
				   'vm-ml-message-edited
				   'vm-ml-message-replied
				   'vm-ml-message-forwarded
				   'vm-ml-message-filed
				   'vm-ml-message-written
				   'vm-ml-message-deleted
				   'vm-ml-message-marked
                                   'vm-ml-message-redistributed
				   'vm-ml-message-number
				   'vm-ml-highest-message-number
				   'vm-folder-read-only
				   'vm-folder-type
				   'vm-virtual-folder-definition
				   'vm-virtual-mirror
				   'vm-ml-sort-keys
				   'vm-ml-labels
				   'vm-spooled-mail-waiting
				   'vm-message-list)
	  (vm-reset-buffer-modified-p modified vm-summary-buffer)))
  (if (and vm-presentation-buffer (buffer-name vm-presentation-buffer))
      (let ((modified (buffer-modified-p)))
	(vm-copy-local-variables vm-presentation-buffer
				 'default-directory
				 'vm-ml-message-new
				 'vm-ml-message-unread
				 'vm-ml-message-read
				 'vm-ml-message-edited
				 'vm-ml-message-replied
				 'vm-ml-message-forwarded
				 'vm-ml-message-filed
				 'vm-ml-message-written
				 'vm-ml-message-deleted
				 'vm-ml-message-marked
				 'vm-ml-message-number
				 'vm-ml-message-redistributed
				 'vm-ml-highest-message-number
				 'vm-folder-read-only
				 'vm-folder-type
				 'vm-virtual-folder-definition
				 'vm-virtual-mirror
				 'vm-ml-labels
				 'vm-spooled-mail-waiting
				 'vm-message-list)
	(vm-reset-buffer-modified-p modified vm-presentation-buffer)))
  (vm-force-mode-line-update))

(defun vm-update-summary-and-mode-line ()
  "Update summary and mode line for all VM folder and summary buffers.
Really this updates all the visible status indicators.

Message lists are renumbered.
Summary entries are wiped and regenerated.
Mode lines are updated.
Toolbars are updated."
  (save-excursion
    (vm-update-draft-count)
    (mapatoms (function
	       (lambda (b)
		 (setq b (get-buffer (symbol-name b)))
		 (when b
		   (set-buffer b)
		   (intern (buffer-name)
			   vm-buffers-needing-undo-boundaries)
		   (vm-check-for-killed-summary)
		   (when (and vm-use-toolbar (vm-toolbar-support-possible-p))
		     (vm-toolbar-update-toolbar))
		   (when vm-summary-show-threads
		     (vm-build-threads-if-unbuilt))
		   (vm-do-needed-renumbering)
		   (when vm-summary-buffer
		       (vm-do-needed-summary-rebuild))
		   (vm-do-needed-mode-line-update))))
	      vm-buffers-needing-display-update)
    (fillarray vm-buffers-needing-display-update 0))
  (when vm-messages-needing-summary-update
    (let ((n 1)
	  (ms vm-messages-needing-summary-update)
	  m)
      (while ms
	(setq m (car ms))
	(unless (or (eq (vm-deleted-flag m) 'expunged)
		    (equal (vm-message-id-number-of m) "Q"))
	  (vm-update-message-summary (car ms)))
	(if (eq (mod n 10) 0)
	    (vm-inform 7 "%s: Recreating summary... %s" 
		       (buffer-name vm-mail-buffer) n))
	(setq n (1+ n))
	(setq ms (cdr ms)))
      (vm-inform 7 "%s: Recreating summary... done" 
		 (buffer-name vm-mail-buffer))
      (setq vm-messages-needing-summary-update nil)))
  (vm-do-needed-folders-summary-update)
  (vm-force-mode-line-update))

(defun vm-reverse-link-messages ()
  "Set reverse links for all messages in vm-message-list."
  (let ((mp vm-message-list)
	(prev nil))
    (while mp
      (vm-set-reverse-link-of (car mp) prev)
      (setq prev mp mp (cdr mp)))))

(defun vm-match-ordered-header (alist)
  "Try to match a header in ALIST and return the matching cell.
This is used by header ordering code.

ALIST looks like this ((\"From\") (\"To\")).  This function returns
the alist element whose car matches the header starting at point.
The header ordering code uses the cdr of the element
returned to hold headers to be output later."
  (let ((case-fold-search t))
    (catch 'match
      (while alist
	(if (looking-at (car (car alist)))
	    (throw 'match (car alist)))
	(setq alist (cdr alist)))
      nil)))

(defun vm-match-header (&optional header-name)
  "Match a header and save some state information about the matched header.
Optional first arg HEADER-NAME means match the header only
if it matches HEADER-NAME.  HEADER-NAME should be a string
containing a header name.  The string should end with a colon if just
that name should be matched.  A string that does not end in a colon
will match all headers that begin with that string.

State information is stored in vm-matched-header-vector bound to a vector
of this form.

 [ header-start header-end
   header-name-start header-name-end
   header-contents-start header-contents-end ]

Elements are integers.
There are functions to access and use this info."
  (let ((case-fold-search t)
	(header-name-regexp "\\([^ \t\n:]+\\):"))
    (if (if header-name
	    (and (looking-at header-name) (looking-at header-name-regexp))
	  (looking-at header-name-regexp))
	(save-excursion
	  (aset vm-matched-header-vector 0 (point))
	  (aset vm-matched-header-vector 2 (point))
	  (aset vm-matched-header-vector 3 (match-end 1))
	  (goto-char (match-end 0))
	  ;; skip leading whitespace
	  (skip-chars-forward " \t")
	  (aset vm-matched-header-vector 4 (point))
	  (forward-line 1)
	  (while (looking-at "[ \t]")
	    (forward-line 1))
	  (aset vm-matched-header-vector 1 (point))
	  ;; drop the trailing newline
	  (aset vm-matched-header-vector 5 (1- (point)))))))

(defun vm-matched-header ()
  "Returns the header last matched by vm-match-header.
Trailing newline is included."
  (vm-buffer-substring-no-properties (aref vm-matched-header-vector 0)
				     (aref vm-matched-header-vector 1)))

(defun vm-matched-header-name ()
  "Returns the name of the header last matched by vm-match-header."
  (vm-buffer-substring-no-properties (aref vm-matched-header-vector 2)
				     (aref vm-matched-header-vector 3)))

(defun vm-matched-header-contents ()
  "Returns the contents of the header last matched by vm-match-header.
Trailing newline is not included."
  (vm-buffer-substring-no-properties (aref vm-matched-header-vector 4)
				     (aref vm-matched-header-vector 5)))

(defun vm-matched-header-start ()
  "Returns the start position of the header last matched by vm-match-header."
  (aref vm-matched-header-vector 0))

(defun vm-matched-header-end ()
  "Returns the end position of the header last matched by vm-match-header."
  (aref vm-matched-header-vector 1))

(defun vm-matched-header-name-start ()
  "Returns the start position of the name of the header last matched
by vm-match-header."
  (aref vm-matched-header-vector 2))

(defun vm-matched-header-name-end ()
  "Returns the end position of the name of the header last matched
by vm-match-header."
  (aref vm-matched-header-vector 3))

(defun vm-matched-header-contents-start ()
  "Returns the start position of the contents of the header last matched
by vm-match-header."
  (aref vm-matched-header-vector 4))

(defun vm-matched-header-contents-end ()
  "Returns the end position of the contents of the header last matched
by vm-match-header."
  (aref vm-matched-header-vector 5))

(defun vm-get-folder-type (&optional file start end ignore-visited)
  "Return a symbol indicating the folder type of the current buffer.
This function works by examining the beginning of a folder.
If optional arg FILE is present the type of FILE is returned instead.
If FILE is being visited, the type of the buffer is returned.
If optional second and third arg START and END are provided,
vm-get-folder-type will examine the text between those buffer
positions.  START and END default to 1 and (buffer-size) + 1.
If IGNORED-VISITED is non-nil, even if FILE is being visited, its
buffer is ignored and the disk copy of FILE is examined.

Returns
  nil       if folder has no type (empty)
  unknown   if the type is not known to VM
  mmdf      for MMDF folders
  babyl     for BABYL folders
  From_     for BSD UNIX From_ folders
  BellFrom_ for old SysV From_ folders
  From_-with-Content-Length
            for new SysV folders that use the Content-Length header

If vm-trust-From_-with-Content-Length is non-nil,
From_-with-Content-Length is returned if the first message in the
folder has a Content-Length header and the folder otherwise looks
like a From_ folder.

Since BellFrom_ and From_ folders cannot be reliably distinguished
from each other, you must tell VM which one your system uses by
setting the variable vm-default-From_-folder-type to either From_ or
BellFrom_.  For folders that could be From_ or BellFrom_ folders,
the value of vm-default-From_folder-type will be returned."
  (let ((temp-buffer nil)
	(b nil)
	(case-fold-search nil))
    (unwind-protect
	(save-excursion
	  (if file
	      (progn
		(if (not ignore-visited)
		    (setq b (vm-get-file-buffer file)))
		(if b
		    (set-buffer b)
		  (setq temp-buffer (vm-make-work-buffer))
		  (set-buffer temp-buffer)
		  (if (file-readable-p file)
		      (condition-case nil
			  (let ((coding-system-for-read
				    (vm-binary-coding-system)))
			    (insert-file-contents file nil 0 4096))
			(wrong-number-of-arguments
			 (call-process "sed" file temp-buffer nil
				       "-n" "1,/^$/p")))))))
	  (save-excursion
	    (save-restriction
	      (or start (setq start 1))
	      (or end (setq end (1+ (buffer-size))))
	      (widen)
	      (narrow-to-region start end)
	      (goto-char (point-min))
	      (cond ((zerop (buffer-size)) nil)
		    ((looking-at "\n*From ")
		     (if (not vm-trust-From_-with-Content-Length)
			 vm-default-From_-folder-type
		       (let ((case-fold-search t))
			 (re-search-forward vm-content-length-search-regexp
					    nil t))
		       (cond ((match-beginning 1)
			      vm-default-From_-folder-type)
			     ((match-beginning 0)
			      'From_-with-Content-Length)
			     (t vm-default-From_-folder-type))))
		    ((looking-at "\001\001\001\001\n") 'mmdf)
		    ((looking-at "BABYL OPTIONS:") 'babyl)
		    (t 'unknown)))))
      (and temp-buffer (kill-buffer temp-buffer)))))

(defun vm-convert-folder-type (old-type new-type)
  "Convert buffer from OLD-TYPE to NEW-TYPE.
OLD-TYPE and NEW-TYPE should be symbols returned from vm-get-folder-type.
This should be called on non-live buffers like crash boxes.
This will confuse VM if called on a folder buffer in vm-mode."
  (let ((vm-folder-type old-type)
	(pos-list nil)
	beg end)
    (goto-char (point-min))
    (vm-skip-past-folder-header)
    (while (vm-find-leading-message-separator)
      (setq pos-list (cons (point-marker) pos-list))
      (vm-skip-past-leading-message-separator)
      (setq pos-list (cons (point-marker) pos-list))
      (vm-find-trailing-message-separator)
      (setq pos-list (cons (point-marker) pos-list))
      (vm-skip-past-trailing-message-separator)
      (setq pos-list (cons (point-marker) pos-list)))
    (setq pos-list (nreverse pos-list))
    (goto-char (point-min))
    (vm-convert-folder-header old-type new-type)
    (while pos-list
      (setq beg (car pos-list))
      (goto-char (car pos-list))
      (insert-before-markers (vm-leading-message-separator new-type))
      (delete-region (car pos-list) (car (cdr pos-list)))
      (vm-convert-folder-type-headers old-type new-type)
      (setq pos-list (cdr (cdr pos-list)))
      (setq end (marker-position (car pos-list)))
      (goto-char (car pos-list))
      (insert-before-markers (vm-trailing-message-separator new-type))
      (delete-region (car pos-list) (car (cdr pos-list)))
      (goto-char beg)
      (vm-munge-message-separators new-type beg end)
      (setq pos-list (cdr (cdr pos-list))))))

(defun vm-convert-folder-header (old-type new-type)
  "Convert the folder header form OLD-TYPE to NEW-TYPE.
The folder header is the text at the beginning of a folder that
is a legal part of the folder but is not part of the first
message.  This is for dealing with BABYL files."
  (if (eq old-type 'babyl)
      (save-excursion
	(let ((beg (point))
	      (case-fold-search t))
	  (cond ((and (looking-at "BABYL OPTIONS:")
		      (search-forward "\037" nil t))
		 (delete-region beg (point)))))))
  (if (eq new-type 'babyl)
      ;; insert before markers so that message location markers
      ;; for the first message get moved forward.
      (insert-before-markers "BABYL OPTIONS:\nVersion: 5\n\037")))

(defun vm-skip-past-folder-header ()
  "Move point past the folder header.
The folder header is the text at the beginning of a folder that
is a legal part of the folder but is not part of the first
message.  This is for dealing with BABYL files."
  (cond ((eq vm-folder-type 'babyl)
	 (search-forward "\037" nil 0))))

(defun vm-convert-folder-type-headers (old-type new-type)
  "Convert headers in the message around point from OLD-TYPE to NEW-TYPE.
This means to add/delete Content-Length and any other
headers related to folder-type as needed for folder type
conversions.  This function expects point to be at the beginning
of the header section of a message, and it only deals with that
message."
  (let (length)
    ;; get the length now before the content-length headers are
    ;; removed.
    (if (eq new-type 'From_-with-Content-Length)
	(let (start)
	  (save-excursion
	    (save-excursion
	      (search-forward "\n\n" nil 0)
	      (setq start (point)))
	    (let ((vm-folder-type old-type))
	      (vm-find-trailing-message-separator))
	    (setq length (- (point) start)))))
    ;; chop out content-length header if new format doesn't need
    ;; it or if the new format computed his own copy.
    (if (or (eq old-type 'From_-with-Content-Length)
	    (eq new-type 'From_-with-Content-Length))
	(save-excursion
	  (while (and (let ((case-fold-search t))
			(re-search-forward vm-content-length-search-regexp
					   nil t))
		      (null (match-beginning 1))
		      (progn (goto-char (match-beginning 0))
			     (vm-match-header vm-content-length-header)))
	    (delete-region (vm-matched-header-start)
			   (vm-matched-header-end)))))
    ;; insert the content-length header if needed
    (if (eq new-type 'From_-with-Content-Length)
	(save-excursion
	  (insert vm-content-length-header " " (int-to-string length) "\n")))))

(defun vm-munge-message-separators (folder-type start end)
  "Munge message separators of FOLDER-TYPE found between START and END.
This function is used to eliminate message separators for a particular
folder type that happen to occur in a message.  \">\" is prepended to such
separators."
  (save-excursion
    ;; when munging From-type separators it is best to use the
    ;; least forgiving of the folder types, so that we don't
    ;; create folders that other mailers or older versions of VM
    ;; will misparse.
    (if (eq folder-type 'From_)
	(setq folder-type 'BellFrom_))
    (let ((vm-folder-type folder-type))
      (cond ((memq folder-type '(From_ From_-with-Content-Length mmdf
				 BellFrom_ babyl))
	     (setq end (vm-marker end))
	     (goto-char start)
	     (while (and (vm-find-leading-message-separator)
			 (< (point) end))
	       (insert ">"))
	     (set-marker end nil))))))

(defun vm-compatible-folder-p (file)
  "Return non-nil if FILE is a compatible folder with the current buffer.
The current folder must have vm-folder-type initialized.
FILE is compatible if
  - it is empty
  - the current folder is empty
  - the two folder types are equal"
  (let ((type (vm-get-folder-type file)))
    (or (not (and vm-folder-type type))
	(eq vm-folder-type type))))

(defun vm-leading-message-separator (&optional folder-type message
				     for-other-folder)
  "Returns a leading message separator for the current folder.
Defaults to returning a separator for the current folder type.

Optional first arg FOLDER-TYPE means return a separator for that
folder type instead.

Optional second arg MESSAGE should be a message struct.  This is used
generating BABYL separators, because they contain message attributes
and labels that must must be copied from the message.

Optional third arg FOR-OTHER-FOLDER non-nil means that this separator will
be used a `foreign' folder.  This means that the `deleted'
attributes should not be copied for BABYL folders."
  (let ((type (or folder-type vm-folder-type)))
    (cond ((memq type '(From_ From_-with-Content-Length BellFrom_))
	   (concat "From VM " (current-time-string) "\n"))
	  ((eq type 'mmdf)
	   "\001\001\001\001\n")
	  ((eq type 'babyl)
	   (cond (message
		  (concat "\014\n0,"
			  (vm-babyl-attributes-string message for-other-folder)
			  ",\n*** EOOH ***\n"))
		 (t "\014\n0, recent, unseen,,\n*** EOOH ***\n"))))))

(defun vm-trailing-message-separator (&optional folder-type)
  "Returns a trailing message separator for the current folder.
Defaults to returning a separator for the current folder type.

Optional first arg FOLDER-TYPE means return a separator for that
folder type instead."
  (let ((type (or folder-type vm-folder-type)))
    (cond ((eq type 'From_) "\n")
	  ((eq type 'From_-with-Content-Length) "")
	  ((eq type 'BellFrom_) "")
	  ((eq type 'mmdf) "\001\001\001\001\n")
	  ((eq type 'babyl) "\037"))))

(defun vm-folder-header (&optional folder-type label-obarray)
  "Returns a folder header for the current folder.
Defaults to returning a folder header for the current folder type.

Optional first arg FOLDER-TYPE means return a folder header for that
folder type instead.

Optional second arg LABEL-OBARRAY should be an obarray of labels
that have been used in this folder.  This is used for BABYL folders."
  (let ((type (or folder-type vm-folder-type)))
    (cond ((eq type 'babyl)
	   (let ((list nil))
	     (if label-obarray
		 (mapatoms (function
			    (lambda (sym)
			      (setq list (cons sym list))))
			   label-obarray))
	     (if list
		 (format "BABYL OPTIONS:\nVersion: 5\nLabels: %s\n\037"
			 (mapconcat (function symbol-name) list ", "))
	       "BABYL OPTIONS:\nVersion: 5\n\037")))
	  (t ""))))

;; This separator regexp is a bit too permissive.
;; Jose Manuel Garcia-Patos suggests the following
;; "^From .+[@]?.+ .+ [+-]?[0-9][0-9][0-9][0-9]$"
(defvar vm-leading-message-separator-regexp-From_
  "^From .*[0-9]$"
  "Regular expression that matches the leading message separator in
From_ type mail folders.")
(defvar vm-leading-message-separator-regexp-BellFrom_
  "^From .*[0-9]$"
  "Regular expression that matches the leading message separator in
BellFrom_ type mail folders.")
(defvar vm-leading-message-separator-regexp-From_-with-Content-Length
  "\\(^\\|\n+\\)From "
  "Regular expression that matches the leading message separator in
From_-with-Content-Length type mail folders.")
(defvar vm-leading-message-separator-regexp-mmdf
  "^\001\001\001\001"
  "Regular expression that matches the leading message separator in
mmdf_ type mail folders.")


(defun vm-find-leading-message-separator ()
  "Find the next leading message separator in a folder.
Returns non-nil if the separator is found, nil otherwise."
  (cond
   ((eq vm-folder-type 'From_)
    (let ((case-fold-search nil))
      (catch 'done
	(while (re-search-forward  
		vm-leading-message-separator-regexp-From_ nil 'no-error)
	  (goto-char (match-beginning 0))
	  (if (or (< (point) 3)
		  (equal (char-after (- (point) 2)) ?\n))
	      (throw 'done t)
	    (forward-char 1)))
	nil )))
   ((eq vm-folder-type 'BellFrom_)
    (let ((case-fold-search nil))
      (if (re-search-forward 
	   vm-leading-message-separator-regexp-BellFrom_ nil 'no-error)
	  (progn
	    (goto-char (match-beginning 0))
	    t )
	nil )))
   ((eq vm-folder-type 'From_-with-Content-Length)
    (let ((case-fold-search nil))
      (if (re-search-forward 
	   vm-leading-message-separator-regexp-From_-with-Content-Length
	   nil 'no-error)
	  (progn (goto-char (match-end 1)) t)
	nil )))
   ((eq vm-folder-type 'mmdf)
    (let ((case-fold-search nil))
      (if (re-search-forward 
	   vm-leading-message-separator-regexp-mmdf nil 'no-error)
	  (progn
	    (goto-char (match-beginning 0))
	    t )
	nil )))
   ((eq vm-folder-type 'baremessage)
    (goto-char (point-max)))
   ((eq vm-folder-type 'babyl)
    (let ((reg1 "\014\n[01],")
	  (case-fold-search nil))
      (catch 'done
	(while (re-search-forward reg1 nil 'no-error)
	  (goto-char (match-beginning 0))
	  (if (and (not (bobp)) (= (preceding-char) ?\037))
	      (throw 'done t)
	    (forward-char 1)))
	nil )))))

(defun vm-find-trailing-message-separator ()
  "Find the next trailing message separator in a folder."
  (cond
   ((eq vm-folder-type 'From_)
    (vm-find-leading-message-separator)
    (forward-char -1))
   ((eq vm-folder-type 'BellFrom_)
    (vm-find-leading-message-separator))
   ((eq vm-folder-type 'From_-with-Content-Length)
    (let ((reg1 "^From ")
	  content-length
	  (start-point (point))
	  (case-fold-search nil))
      (if (and (let ((case-fold-search t))
		 (re-search-forward vm-content-length-search-regexp nil t))
	       (null (match-beginning 1))
	       (progn (goto-char (match-beginning 0))
		      (vm-match-header vm-content-length-header)))
	  (progn
	    (setq content-length
		  (string-to-number (vm-matched-header-contents)))
	    ;; if search fails, we'll be at point-max
	    ;; if specified content-length is too long, go to point-max
	    (if (search-forward "\n\n" nil 0)
		(if (>= (- (point-max) (point)) content-length)
		    (forward-char content-length)
		  (goto-char (point-max))))
	    ;; Some systems seem to add a trailing newline that's
	    ;; not counted in the Content-Length header.  Allow
	    ;; any number of them to avoid trouble.
	    (skip-chars-forward "\n")))
      (if (or (eobp) (looking-at reg1))
	  nil
	(goto-char start-point)
	(if (re-search-forward reg1 nil 0)
	    (forward-char -5)))))
   ((eq vm-folder-type 'mmdf)
    (vm-find-leading-message-separator))
   ((eq vm-folder-type 'baremessage)
    (goto-char (point-max)))
   ((eq vm-folder-type 'babyl)
    (vm-find-leading-message-separator)
    (forward-char -1))))

(defun vm-skip-past-leading-message-separator ()
  "Move point past a leading message separator at point."
  (cond
   ((memq vm-folder-type '(From_ BellFrom_ From_-with-Content-Length))
    (let ((reg1 "^>From ")
	  (case-fold-search nil))
      (forward-line 1)
      (while (looking-at reg1)
	(forward-line 1))))
   ((eq vm-folder-type 'mmdf)
    (forward-char 5)
    ;; skip >From.  Either SCO's MMDF implementation leaves this
    ;; stuff in the message, or many sysadmins have screwed up
    ;; their mail configuration.  Either way I'm tired of getting
    ;; bug reports about it.
    (let ((reg1 "^>From ")
	  (case-fold-search nil))
      (while (looking-at reg1)
	(forward-line 1))))
   ((eq vm-folder-type 'babyl)
    (search-forward "\n*** EOOH ***\n" nil 0))))

(defun vm-skip-past-trailing-message-separator ()
  "Move point past a trailing message separator at point."
  (cond
   ((eq vm-folder-type 'From_)
    (if (not (eobp))
	(forward-char 1)))
   ((eq vm-folder-type 'From_-with-Content-Length))
   ((eq vm-folder-type 'BellFrom_))
   ((eq vm-folder-type 'mmdf)
    (forward-char 5))
   ((eq vm-folder-type 'babyl)
    (forward-char 1))))

(defun vm-build-message-list ()
  "Build a chain of message structures, stored them in vm-message-list.
Finds the start and end of each message and fills in the relevant
fields in the message structures.

Also finds the beginning of the header section and the end of the
text section and fills in these fields in the message structures.

vm-text-of and vm-vheaders-of fields don't get filled until they
are needed.

If vm-message-list already contained messages, the end of the last
known message is found and then the parsing of new messages begins
there and the message are appended to vm-message-list.

vm-folder-type is initialized here."
  (setq vm-folder-type (vm-get-folder-type))
  (save-excursion
    (let ((tail-cons nil)
	  (n 0)
	  ;; Just for yucks, make the update interval vary.
	  (modulus (+ (% (vm-abs (random)) 11) 25))
	  message last-end)
      (if vm-message-list
	  ;; there are already messages, therefore we're supposed
	  ;; to add to this list.
	  (let ((mp vm-message-list)
		(end (point-min)))
	    ;; first we have to find physical end of the folder
	    ;; prior to the new messages that just came in.
	    (while mp
	      (if (< end (vm-end-of (car mp)))
		  (setq end (vm-end-of (car mp))))
	      (if (not (consp (cdr mp)))
		  (setq tail-cons mp))
	      (setq mp (cdr mp)))
	    (goto-char end))
	;; there are no messages so we're building the whole list.
	;; start from the beginning of the folder.
	(goto-char (point-min))
	;; whine about newlines at the beginning of the folder.
	;; technically I think this is corruption, but there are
	;; too many busted mail-do-fcc's installed out there to
	;; do more than whine.
	(if (and (memq vm-folder-type '(From_ BellFrom_
					From_-with-Content-Length))
		 (= (following-char) ?\n))
	    (vm-warn 0 2 "Warning: newline found at beginning of folder, %s"
		     (or buffer-file-name (buffer-name))))
	(vm-skip-past-folder-header))
      (setq last-end (point))
      ;; parse the messages, set the markers that specify where
      ;; things are.
      (while (vm-find-leading-message-separator)
	(setq message (vm-make-message))
	(vm-set-message-type-of message vm-folder-type)
	(vm-set-message-access-method-of message vm-folder-access-method)
	(vm-set-start-of message (vm-marker (point)))
	(vm-skip-past-leading-message-separator)
	(vm-set-headers-of message (vm-marker (point)))
	(vm-find-trailing-message-separator)
	(vm-set-text-end-of message (vm-marker (point)))
	(vm-skip-past-trailing-message-separator)
	(setq last-end (point))
	(vm-set-end-of message (vm-marker (point)))
	(vm-set-reverse-link-of message tail-cons)
	(if (null tail-cons)
	    (setq vm-message-list (list message)
		  tail-cons vm-message-list)
	  (setcdr tail-cons (list message))
	  (setq tail-cons (cdr tail-cons)))
	(vm-increment n)
	(if (zerop (% n modulus))
	    (vm-inform 7 "%s: Parsing messages... %d" 
		       (buffer-name) n)))
      (if (>= n modulus)
	  (vm-inform 7 "%s: Parsing messages... done"
		       (buffer-name)))
      (if (and (not (= last-end (point-max)))
	       (not (eq vm-folder-type 'unknown)))
	  (vm-warn 1 2 
		   "Warning: garbage found at end of folder, %s, starting at %d"
		   (or buffer-file-name (buffer-name))
		   last-end)))))

(defun vm-build-header-order-alist (vheaders)
  (let ((order-alist (cons nil nil))
	list)
    (setq list order-alist)
    (while vheaders
      (setcdr list (cons (cons (car vheaders) nil) nil))
      (setq list (cdr list) vheaders (cdr vheaders)))
    (cdr order-alist)))

;; Reorder the headers in a message.
;;
;; If a message struct is passed into this function, then we're
;; operating on a message in a folder buffer.  Headers are
;; grouped so that the headers that the user wants to see are at
;; the end of the headers section so we can narrow to them.  This
;; is done according to the preferences specified in
;; vm-visible-header and vm-invisible-header-regexp.  The
;; vheaders field of the message struct is also set.  This
;; function is called on demand whenever a vheaders field is
;; discovered to be nil for a particular message.
;;
;; If the message argument is nil, then we are operating on a
;; freestanding message that is not part of a folder buffer.  The
;; keep-list and discard-regexp parameters are used in this case.
;; Headers not matched by the keep list or matched by the discard
;; list are stripped from the message.  The remaining headers
;; are ordered according to the order of the keep list.

;;;###autoload
(cl-defun vm-reorder-message-headers (message ; &optional
				   &key (keep-list nil)
				   (discard-regexp nil))
  (interactive
   (progn 
     (goto-char (point-min))
     (list nil vm-mail-header-order "NO_MATCH_ON_HEADERS:")))
  (save-excursion
    (when message
      (with-current-buffer (vm-buffer-of message)
	(setq keep-list vm-visible-headers
	      discard-regexp vm-invisible-header-regexp)))
    (save-excursion
      (save-restriction
	(widen)
	;; if there is a cached regexp that points to the already
	;; ordered headers then use it and avoid a lot of work.
	(if (and message (vm-vheaders-regexp-of message))
	    (save-excursion
	      (goto-char (vm-headers-of message))
	      (let ((case-fold-search t))
		(re-search-forward (vm-vheaders-regexp-of message)
				   (vm-text-of message) t))
	      (vm-set-vheaders-of message (vm-marker (match-beginning 0))))
	  ;; oh well, we gotta do it the hard way.
	  ;;
	  ;; header-alist will contain an assoc list version of
	  ;; keep-list.  For messages associated with a folder
	  ;; buffer: when a matching header is found, the
	  ;; header's start and end positions are added to its
	  ;; corresponding assoc cell.  The positions of unwanted
	  ;; headers are remember also so that they can be copied
	  ;; to the top of the message, to be out of sight after
	  ;; narrowing.  Once the positions have all been
	  ;; recorded a new copy of the headers is inserted in
	  ;; the proper order and the old headers are deleted.
	  ;;
	  ;; For free standing messages, unwanted headers are
	  ;; stripped from the message, unremembered.
	  (save-restriction
	   (let ((header-alist (vm-build-header-order-alist keep-list))
		 (buffer-read-only nil)
		 (work-buffer nil)
		 (extras nil)
		 list end-of-header vheader-offset
		 (folder-buffer (current-buffer))
		 ;; This prevents file locking from occuring.  Disabling
		 ;; locking can speed things noticeably if the lock directory
		 ;; is on a slow device.  We don't need locking here because
		 ;; in a mail context reordering headers is harmless.
		 (buffer-file-name nil)
		 (case-fold-search t)
		 (unwanted-list nil)
		 unwanted-tail
		 new-header-start
		 old-header-start
		 (old-buffer-modified-p (buffer-modified-p)))
	     (unwind-protect
		 (progn
		   (if message
		       (progn
			 ;; for babyl folders, keep an untouched
			 ;; copy of the headers between the
			 ;; attributes line and the *** EOOH ***
			 ;; line.
			 (if (and (eq vm-folder-type 'babyl)
				  (null (vm-babyl-frob-flag-of message)))
			     (progn
			       (goto-char (vm-start-of message))
			       (forward-line 2)
			       (vm-set-babyl-frob-flag-of message t)
			       (insert-buffer-substring
				(current-buffer)
				(vm-headers-of message)
				(1- (vm-text-of message)))
			       ;; Yep, messages can come in
			       ;; without the two newlines after
			       ;; the header section.
			       (if (not (eq (char-after (1- (point))) ?\n))
				   (insert ?\n))))
			 (setq work-buffer (vm-make-work-buffer))
			 (set-buffer work-buffer)
			 (insert-buffer-substring
			  folder-buffer
			  (vm-headers-of message)
			  (vm-text-of message))
			 (goto-char (point-min))))
		   (setq old-header-start (point))
		   ;; as we loop through the headers, skip >From
		   ;; lines.  these can occur anywhere in the
		   ;; header section if the message has been
		   ;; manhandled by some dumb delivery agents
		   ;; (SCO and Solaris are the usual suspects.)
		   ;; it's a tough ol' world.
		   (while (progn (while (looking-at ">From ")
				   (forward-line))
				 (and (not (= (following-char) ?\n))
				      (vm-match-header)))
		     (setq end-of-header (vm-matched-header-end)
			   list (vm-match-ordered-header header-alist))
		     ;; don't display/keep this header if
		     ;;  keep-list not matched
		     ;;  and discard-regexp is nil
		     ;;       or
		     ;;  discard-regexp is matched
		     (if (or (and (null list) (null discard-regexp))
			     (and discard-regexp
                                  (not (eq 'none discard-regexp))
                                  discard-regexp (looking-at discard-regexp)))
			 ;; delete the unwanted header if not doing
			 ;; work for a folder buffer, otherwise
			 ;; remember the start and end of the
			 ;; unwanted header so we can copy it
			 ;; later.
			 (if (not message)
			     (delete-region (point) end-of-header)
			   (if (null unwanted-list)
			       (setq unwanted-list
				     (cons (point) (cons end-of-header nil))
				     unwanted-tail unwanted-list)
			     (if (= (point) (car (cdr unwanted-tail)))
				 (setcar (cdr unwanted-tail)
					 end-of-header)
			       (setcdr (cdr unwanted-tail)
				       (cons (point)
					     (cons end-of-header nil)))
			       (setq unwanted-tail (cdr (cdr unwanted-tail)))))
			   (goto-char end-of-header))
		       ;; got a match
		       ;; stuff the start and end of the header
		       ;; into the cdr of the returned alist
		       ;; element.
		       (if list
			   ;; reverse point and end-of-header.
			   ;; list will be nreversed later.
			   (setcdr list (cons end-of-header
					      (cons (point)
						    (cdr list))))
			 ;; reverse point and end-of-header.
			 ;; list will be nreversed later.
			 (setq extras
			       (cons end-of-header
				     (cons (point) extras))))
		       (goto-char end-of-header)))
		   (setq new-header-start (point))
		   (while unwanted-list
		     (insert-buffer-substring (current-buffer)
					      (car unwanted-list)
					      (car (cdr unwanted-list)))
		     (setq unwanted-list (cdr (cdr unwanted-list))))
		   ;; remember the offset of where the visible
		   ;; header start so we can initialize the
		   ;; vm-vheaders-of field later.
		   (if message
		       (setq vheader-offset (- (point) new-header-start)))
		   (while header-alist
		     (setq list (nreverse (cdr (car header-alist))))
		     (while list
		       (insert-buffer-substring (current-buffer)
						(car list)
						(car (cdr list)))
		       (setq list (cdr (cdr list))))
		     (setq header-alist (cdr header-alist)))
		   ;; now the headers that were not explicitly
		   ;; undesirable, if any.
		   (setq extras (nreverse extras))
		   (while extras
		     (insert-buffer-substring (current-buffer)
					      (car extras)
					      (car (cdr extras)))
		     (setq extras (cdr (cdr extras))))
		   (delete-region old-header-start new-header-start)
		   ;; update the folder buffer if we're supposed to.
		   ;; lock out interrupts.
		   (if message
		       (let ((inhibit-quit t))
			 (set-buffer (vm-buffer-of message))
			 (goto-char (vm-headers-of message))
			 (insert-buffer-substring work-buffer)
			 (delete-region (point) (vm-text-of message))
			 (vm-restore-buffer-modified-p ; folder-buffer
			  old-buffer-modified-p (current-buffer)))))
	       (when work-buffer (kill-buffer work-buffer)))
	     (if message
		 (progn
		   (vm-set-vheaders-of message
				       (vm-marker (+ (vm-headers-of message)
						     vheader-offset)))
		   ;; cache a regular expression that can be used to
		   ;; find the start of the reordered header the next
		   ;; time this folder is visited.
		   (goto-char (vm-vheaders-of message))
		   (if (vm-match-header)
		       (vm-set-vheaders-regexp-of
			message
			(concat "^" (vm-matched-header-name) ":"))))))))))))

;; Thunderbird source code files describing the status flags
;; http://mxr.mozilla.org/seamonkey/source/mailnews/base/public/nsMsgMessageFlags.h#45
;; http://mxr.mozilla.org/seamonkey/source/mailnews/base/public/nsMsgMessageFlags.h#108
;; Commentary here:
;; http://www.eyrich-net.org/mozilla/X-Mozilla-Status.html?en

(defun vm-thunderbird-folder-p (folder-path-name)
  (file-exists-p (concat folder-path-name ".msf")))

(defun vm-read-thunderbird-status (message)
  (let (status)
    (setq status (vm-get-header-contents message "X-Mozilla-Status:"))
    (when status
      (setq status (string-to-number status 16))
      ;; read flag
      (vm-set-unread-flag-of message (= 0 (logand status #x0001)))
      ;; answered flag
      (vm-set-replied-flag-of message (not (= 0 (logand status #x0002))))
      ;; flagged flag
      (vm-set-flagged-flag-of message (not (= 0 (logand status #x0004))))
      ;; deleted flag
      (vm-set-deleted-flag-of message (not (= 0 (logand status #x0008))))
      ;; (unless (= 0 (logand status #x0010))  ; subject with "Re:" prefix
      ;; 	nil)
      ;; folded flag
      (vm-set-folded-flag-of message (not (= 0 (logand status #x0020))))
      ;; (unless (= 0 (logand status #x0080))  ; offline article
      ;; 	nil)
      ;; watched flag
      (vm-set-watched-flag-of message (not (= 0 (logand status #x0100))))
      ;; (unless (= 0 (logand status #x0200)) ; authenticated sender
      ;; 	nil)
      ;; (unless (= 0 (logand status #x0400)) ; remote POP article
      ;; 	nil)
      ;; (unless (= 0 (logand status #x0800)) ; queued
      ;; 	nil)
      ;; forwarded
      (vm-set-forwarded-flag-of message (not (= 0 (logand status #x1000)))))

    (setq status (vm-get-header-contents message "X-Mozilla-Status2:"))
    (when status
      (if (> (length status) 4)
	  (progn
	    (setq status (substring status 0 -4)) ; ignore the last 4 hextets,
					; which are assumed to be 0000
	    (setq status (string-to-number status 16)))
	;; handle badly formatted status strings written by older versions
	(setq status (string-to-number status 16))
	(setq status (/ status #x1000)))
      ;; new on the server
      (vm-set-new-flag-of message (not (= 0 (logand status #x0001))))
      ;; ignored thread
      (vm-set-ignored-flag-of message (not (= 0 (logand status #x0004))))
      ;; (unless (= 0 (logand status #x0020)) ; deleted on the server
      ;; 	nil)
      ;; read-receipt requested
      (vm-set-read-receipt-flag-of message (not (= 0 (logand status #x0040)))) 
      ;; read-receipt sent
      (vm-set-read-receipt-sent-flag-of message (not (logand status #x0080)))
      ;; (unless (= 0 (logand status #x0100)) ; template
      ;; 	nil)
      ;; has attachments
      (vm-set-attachments-flag-of message (not (= 0 (logand status #x1000))))
      ;; 	nil)
      ;; (unless (= 0 (logand status #x0E00))
      ;; 	nil)
      ;; FIXME care for message labels
      )

    (vm-mark-for-summary-update message)
    (vm-set-stuff-flag-of message t)))

(defun vm-read-VM-data (message-list)
  "Reads the message attributes and cached header information.

Reads the message attributes and cached header information from the
header portion of the each message, if our X-VM- attributes header is
present.  If the header is not present, assume the message is new,
unless we are being compatible with Berkeley Mail in which case we
also check for a Status header.

If a message already has attributes don't bother checking the
headers.

This function also discovers and stores the position where the
message text begins.

Totals are gathered for use by vm-emit-totals-blurb.

Supports version 4 format of attribute storage, for backward compatibility."
  (save-excursion
    (let ((mp (or message-list vm-message-list))
          (vm-new-count 0)
          (vm-unread-count 0)
          (vm-deleted-count 0)
	  (vm-total-count 0)
	  (vm-bad-cache-count 0)
	  (vm-upgrade-count 0)
	  (modulus (+ (% (vm-abs (random)) 11) 25))
	  (case-fold-search t)
	  oldpoint data cache)
      (while mp
	(vm-increment vm-total-count)
	(if (vm-attributes-of (car mp))
	    ()
	  (goto-char (vm-headers-of (car mp)))
	  ;; find start of text section and save it
	  (search-forward "\n\n" (vm-text-end-of (car mp)) 0)
	  (vm-set-text-of (car mp) (point-marker))
	  ;; now look for our header
	  (goto-char (vm-headers-of (car mp)))
	  (cond
	   ((re-search-forward vm-attributes-header-regexp
			       (vm-text-of (car mp)) t)
	    (goto-char (match-beginning 2))
	    (condition-case ()
		(progn
		  (setq oldpoint (point)
			data (read (current-buffer))
                        cache (cadr data))
		  (when (and (or (not (listp data)) (not (> (length data) 1)))
			     (not (vectorp data)))
		    (error "Bad x-vm-v5-data at %d in buffer %s: %S"
			   oldpoint (buffer-name) data)
		    (sit-for 1))
		  data)
	      (error
	       (vm-warn 1 1
			"Bad x-vm-v5-data header at %d in buffer %s, ignoring"
			oldpoint (buffer-name))
	       (setq data
		     (list
		      (make-vector vm-attributes-vector-length nil)
		      (make-vector vm-cached-data-vector-length nil)
		      nil))
	       ;; In lieu of a valid attributes header
	       ;; assume the message is new.  avoid
	       ;; vm-set-new-flag because it asks for a
	       ;; summary update.
	       (vm-set-new-flag-in-vector (car data) t)))
	    ;; support version 4 format
	    (cond ((vectorp data)
		   (setq data (vm-convert-v4-attributes data))
		   ;; tink the message stuff flag so that if the
		   ;; user saves we get rid of the old v4
		   ;; attributes header.  otherwise we could be
		   ;; dealing with these things for all eternity.
		   (vm-set-stuff-flag-of (car mp) t))
		  (t
		   ;; extend vectors if necessary to accomodate
		   ;; more caching and attributes without alienating
		   ;; other version 5 folders.
		   (cond ((< (length (car data))
			     vm-attributes-vector-length)
			  ;; tink the message stuff flag so that if
			  ;; the user saves we get rid of the old
			  ;; short vector.  otherwise we could be
			  ;; dealing with these things for all
			  ;; eternity.
			  (vm-set-stuff-flag-of (car mp) t)
			  (setcar data (vm-extend-vector
					(car data)
					vm-attributes-vector-length))))
		   (cond ((< (length cache)
			     vm-cached-data-vector-length)
			  ;; tink the message stuff flag so that if
			  ;; the user saves we get rid of the old
			  ;; short vector.  otherwise we could be
			  ;; dealing with these things for all
			  ;; eternity.
			  (vm-set-stuff-flag-of (car mp) t)
			  (setcar (cdr data)
				  (vm-extend-vector
				   cache
				   vm-cached-data-vector-length))
			  (setq cache (cadr data))))))
	    ;; data list might not be long enough for (nth 2 ...)  but
	    ;; that's OK because nth returns nil if you overshoot the
	    ;; end of the list.
            (unless (and (vectorp cache)
			 (>= (length cache) vm-cached-data-vector-length)
			 (or (null (aref cache 7)) (stringp (aref cache 7)))
			 (or (null (aref cache 11)) (stringp (aref cache 11))))
	      (when (zerop vm-bad-cache-count)
		(vm-warn 0 2 "%s: Bad VM cache data: %S" (buffer-name) cache))
	      (vm-set-stuff-flag-of (car mp) t)
	      (vm-increment vm-bad-cache-count)
              (setcar (cdr data)
                      (setq cache 
			    (make-vector vm-cached-data-vector-length nil))))

	    (when (vm-stuff-flag-of (car mp))
	      (vm-increment vm-upgrade-count))
	    (vm-set-decoded-labels-of 
	     (car mp) 
	     (mapcar 'vm-decode-mime-encoded-words-in-string (nth 2 data)))
	    (vm-set-cached-data-of (car mp) cache)
	    (vm-set-attributes-of (car mp) (car data)))
	   ((and vm-berkeley-mail-compatibility
		 (re-search-forward vm-berkeley-mail-status-header-regexp
				    (vm-text-of (car mp)) t))
	    (vm-set-cached-data-of 
	     (car mp) (make-vector vm-cached-data-vector-length nil))
	    (goto-char (match-beginning 1))
	    (vm-set-attributes-of
	     (car mp)
	     (make-vector vm-attributes-vector-length nil))
	    (vm-set-unread-flag (car mp) (not (looking-at ".*R.*")) 'norecord)
	    (vm-increment vm-upgrade-count))
	   (t
	    (vm-set-cached-data-of 
	     (car mp) (make-vector vm-cached-data-vector-length nil))
	    (vm-set-attributes-of
	     (car mp)
	     (make-vector vm-attributes-vector-length nil))
	    ;; In lieu of a valid attributes header
	    ;; assume the message is new.  avoid
	    ;; vm-set-new-flag because it asks for a
	    ;; summary update.
	    (vm-set-new-flag-of (car mp) t)))
	  ;; let babyl attributes override the normal VM
	  ;; attributes header.
	  (cond ((eq vm-folder-type 'babyl)
		 (vm-read-babyl-attributes (car mp))))
          ;; read the status flags of Thunderbird
          (if vm-folder-read-thunderbird-status
              (vm-read-thunderbird-status (car mp))))
	(cond ((vm-deleted-flag (car mp))
	       (vm-increment vm-deleted-count))
	      ((vm-new-flag (car mp))
	       (vm-increment vm-new-count))
	      ((vm-unread-flag (car mp))
	       (vm-increment vm-unread-count)))
	(if (zerop (% vm-total-count modulus))
	    (vm-inform 7 "%s: Reading attributes... %d" (buffer-name)
		       vm-total-count))
	(setq mp (cdr mp)))
      (cond ((> vm-bad-cache-count 0)
	     (vm-warn 0 5 
		      (concat "%s: Bad VM cache data found for %s messages; "
			      "Reset to empty data.")
		      (buffer-name) vm-bad-cache-count)))
      (cond ((> vm-upgrade-count vm-bad-cache-count)
	     (vm-warn 0 1 "%s: Attributes data upgraded for %s messages"
		      (buffer-name) (- vm-upgrade-count vm-bad-cache-count)))
	    ((>= vm-total-count modulus)
	     (vm-inform 7 "%s: Reading attributes... done" (buffer-name))))
      (if (null message-list)
	  (setq vm-totals (list vm-modification-counter
				vm-total-count
				vm-new-count
				vm-unread-count
				vm-deleted-count))))))

(defun vm-read-babyl-attributes (message)
  (let ((case-fold-search t)
	(labels nil)
	(vect (make-vector vm-attributes-vector-length nil)))
    (vm-set-attributes-of message vect)
    (save-excursion
      (goto-char (vm-start-of message))
      ;; skip past ^L\n
      (forward-char 2)
      (vm-set-babyl-frob-flag-of message (if (= (following-char) ?1) t nil))
      ;; skip past 0,
      (forward-char 2)
      ;; loop, noting attributes as we go.
      (while (and (not (eobp)) (not (looking-at ",")))
	(cond ((looking-at " unseen,")
	       (vm-set-unread-flag-of message t))
	      ((looking-at " recent,")
	       (vm-set-new-flag-of message t))
	      ((looking-at " deleted,")
	       (vm-set-deleted-flag-of message t))
	      ((looking-at " answered,")
	       (vm-set-replied-flag-of message t))
	      ((looking-at " forwarded,")
	       (vm-set-forwarded-flag-of message t))
	      ((looking-at " filed,")
	       (vm-set-filed-flag-of message t))
	      ((looking-at " redistributed,")
	       (vm-set-redistributed-flag-of message t))
	      ;; only VM knows about these, as far as I know.
	      ((looking-at " edited,")
	       (vm-set-forwarded-flag-of message t))
	      ((looking-at " written,")
	       (vm-set-forwarded-flag-of message t)))
	(skip-chars-forward "^,")
	(and (not (eobp)) (forward-char 1)))
      (and (not (eobp)) (forward-char 1))
      (while (looking-at " \\([^\000-\040,\177-\377]+\\),")
	(setq labels (cons (vm-buffer-substring-no-properties
			    (match-beginning 1)
			    (match-end 1))
			   labels))
	(goto-char (match-end 0)))
      (vm-set-decoded-labels-of message labels))))

(defun vm-set-default-attributes (message-list)
  (let ((mp (or message-list vm-message-list)) attr access-method cache)
    (while mp
      (setq attr (make-vector vm-attributes-vector-length nil)
	    cache (make-vector vm-cached-data-vector-length nil))
      (vm-set-cached-data-of (car mp) cache)
      (vm-set-attributes-of (car mp) attr)
      ;; make message be new by default, but avoid vm-set-new-flag
      ;; because it asks for a summary update for the message.
      (vm-set-new-flag-of (car mp) t)
      (vm-set-unread-flag-of (car mp) t)
      (setq access-method (vm-message-access-method-of (car mp)))
      (cond ((eq access-method 'imap)
	     (vm-imap-set-default-attributes (car mp)))
	    ((eq access-method 'pop)
	     (vm-pop-set-default-attributes (car mp))))
      ;; since this function is usually called in lieu of reading
      ;; attributes from the buffer, the buffer attributes may be
      ;; untrustworthy.  tink the message stuff flag to force the
      ;; new attributes out if the user saves.
      (vm-set-stuff-flag-of (car mp) t)
      (setq mp (cdr mp)))))

(defun vm-compute-totals ()
  (save-excursion
    (vm-select-folder-buffer)
    (let ((mp vm-message-list)
	  (vm-new-count 0)
	  (vm-unread-count 0)
	  (vm-deleted-count 0)
	  (vm-total-count 0))
      (while mp
	(vm-increment vm-total-count)
	(cond ((vm-deleted-flag (car mp))
	       (vm-increment vm-deleted-count))
	      ((vm-new-flag (car mp))
	       (vm-increment vm-new-count))
	      ((vm-unread-flag (car mp))
	       (vm-increment vm-unread-count)))
	(setq mp (cdr mp)))
      (setq vm-totals (list vm-modification-counter
			    vm-total-count
			    vm-new-count
			    vm-unread-count
			    vm-deleted-count)))))

(defun vm-emit-totals-blurb ()
  (interactive)
  (save-excursion
    (vm-select-folder-buffer-and-validate 0 (vm-interactive-p))
    (let ((folder (buffer-name)))
      (if (not (equal (nth 0 vm-totals) vm-modification-counter))
	  (vm-compute-totals))
      (if (equal (nth 1 vm-totals) 0)
	  (vm-inform 5 "%s: No messages." folder)
	(vm-inform 5 "%s: %d message%s, %d new, %d unread, %d deleted"
		   folder
		   (nth 1 vm-totals) (if (= (nth 1 vm-totals) 1) "" "s")
		   (nth 2 vm-totals)
		   (nth 3 vm-totals)
		   (nth 4 vm-totals))))))

(defun vm-convert-v4-attributes (data)
  (list (apply 'vector
	       (nconc (vm-vector-to-list data)
		      (make-list (- vm-attributes-vector-length
				    (length data))
				 nil)))
	(make-vector vm-cached-data-vector-length nil)))

(defun vm-gobble-last-modified ()
  (let ((case-fold-search t)
	(time nil)
	lim oldpoint)
    (save-excursion
      (save-restriction
       (widen)
       (goto-char (point-min))
       (vm-skip-past-folder-header)
       (vm-skip-past-leading-message-separator)
       (search-forward "\n\n" nil t)
       (setq lim (point))
       (goto-char (point-min))
       (vm-skip-past-folder-header)
       (vm-skip-past-leading-message-separator)
       (if (re-search-forward vm-last-modified-header-regexp lim t)
	   (condition-case ()
	       (progn
		 (setq oldpoint (point)
		       time (read (current-buffer)))
		 (unless (consp time)
		   (error "Bad last-modified header at %d in buffer %s"
			  oldpoint (buffer-name))
		   (sit-for 1))
		 time )
	     (error
	      (vm-warn 1 1 
		       "Bad last-modified header at %d in buffer %s, ignoring"
		       oldpoint (buffer-name))
	      (setq time '(0 0 0)))))))
    time ))

(defun vm-gobble-labels ()
  (let ((case-fold-search t)
	lim)
    (save-excursion
      (save-restriction
       (widen)
       (if (eq vm-folder-type 'babyl)
	   (progn
	     (goto-char (point-min))
	     (vm-skip-past-folder-header)
	     (setq lim (point))
	     (goto-char (point-min))
	     (if (re-search-forward "^Labels:" lim t)
		 (let (string list)
		   (setq string (buffer-substring
				 (point)
				 (progn (end-of-line) (point)))
			 list (vm-parse string
"[\000-\040,\177-\377]*\\([^\000-\040,\177-\377]+\\)[\000-\040,\177-\377]*"))
		   (mapc (function
			  (lambda (s)
			    (intern (downcase s) vm-label-obarray)))
			 list))))
	 (goto-char (point-min))
	 (vm-skip-past-folder-header)
	 (vm-skip-past-leading-message-separator)
	 (search-forward "\n\n" nil t)
	 (setq lim (point))
	 (goto-char (point-min))
	 (vm-skip-past-folder-header)
	 (vm-skip-past-leading-message-separator)
	 (if (re-search-forward vm-labels-header-regexp lim t)
	     (let ((oldpoint (point))
		   list)
	       (condition-case ()
		   (progn
		     (setq list (read (current-buffer)))
		     (unless (listp list)
		       (error "Bad global label list at %d in buffer %s"
			      oldpoint (buffer-name))
		       (sit-for 1))
		     list )
		 (error
		  (vm-warn 1 1 
			   "Bad global label list at %d in buffer %s, ignoring"
			   oldpoint (buffer-name))
		  (setq list nil) ))
	       (vm-startup-apply-labels list))))))
    t ))

(defun vm-startup-apply-labels (labels)
  (mapcar (function (lambda (s) (intern s vm-label-obarray))) labels))

;; Go to the message specified in a bookmark and eat the bookmark.
;; Returns non-nil if successful, nil otherwise.
(defun vm-gobble-bookmark ()
  (let ((case-fold-search t)
	(n nil)
	lim oldpoint)
    (save-excursion
      (save-restriction
       (widen)
       (goto-char (point-min))
       (vm-skip-past-folder-header)
       (vm-skip-past-leading-message-separator)
       (search-forward "\n\n" nil t)
       (setq lim (point))
       (goto-char (point-min))
       (vm-skip-past-folder-header)
       (vm-skip-past-leading-message-separator)
       (if (re-search-forward vm-bookmark-header-regexp lim t)
	   (condition-case ()
	       (progn
		 (setq oldpoint (point)
		       n (read (current-buffer)))
		 (unless (natnump n)
		   (error "Bad bookmark at %d in buffer %s"
			  oldpoint (buffer-name))
		   (sit-for 1))
		 n )
	     (error
	      (vm-warn 1 1 "Bad bookmark at %d in buffer %s, ignoring"
		       oldpoint (buffer-name))
	      (setq n 1))))))
    (vm-startup-apply-bookmark n)
    t ))

(defun vm-startup-apply-bookmark (n)
  (if n
      (vm-record-and-change-message-pointer
       vm-message-pointer (nthcdr (1- n) vm-message-list)
       :present nil)))

(defun vm-gobble-pop-retrieved ()
  (let ((case-fold-search t)
	ob lim oldpoint)
    (save-excursion
      (save-restriction
       (widen)
       (goto-char (point-min))
       (vm-skip-past-folder-header)
       (vm-skip-past-leading-message-separator)
       (search-forward "\n\n" nil t)
       (setq lim (point))
       (goto-char (point-min))
       (vm-skip-past-folder-header)
       (vm-skip-past-leading-message-separator)
       (if (re-search-forward vm-pop-retrieved-header-regexp lim t)
	   (condition-case ()
	       (progn
		 (setq oldpoint (point)
		       ob (read (current-buffer)))
		 (unless (listp ob)
		   (error "Bad pop-retrieved header at %d in buffer %s"
			  oldpoint (buffer-name))
		   (sit-for 1))
		 (setq vm-pop-retrieved-messages ob))
	     (error
	      (vm-warn 1 1 
		       "Bad pop-retrieved header at %d in buffer %s, ignoring"
		       oldpoint (buffer-name)))))))
    t ))

(defun vm-gobble-imap-retrieved ()
  (let ((case-fold-search t)
	ob lim oldpoint)
    (save-excursion
      (save-restriction
       (widen)
       (goto-char (point-min))
       (vm-skip-past-folder-header)
       (vm-skip-past-leading-message-separator)
       (search-forward "\n\n" nil t)
       (setq lim (point))
       (goto-char (point-min))
       (vm-skip-past-folder-header)
       (vm-skip-past-leading-message-separator)
       (if (re-search-forward vm-imap-retrieved-header-regexp lim t)
	   (condition-case ()
	       (progn
		 (setq oldpoint (point)
		       ob (read (current-buffer)))
		 (unless (listp ob)
		   (error "Bad imap-retrieved header at %d in buffer %s"
			  oldpoint (buffer-name))
		   (sit-for 1))
		 (setq vm-imap-retrieved-messages ob))
	     (error
	      (vm-warn 1 1 
		       "Bad imap-retrieved header at %d in buffer %s, ignoring"
		       oldpoint (buffer-name)))))))
    t ))

(defun vm-gobble-visible-header-variables ()
  (save-excursion
    (save-restriction
     (let ((case-fold-search t)
	   lim)
       (widen)
       (goto-char (point-min))
       (vm-skip-past-folder-header)
       (vm-skip-past-leading-message-separator)
       (search-forward "\n\n" nil t)
       (setq lim (point))
       (goto-char (point-min))
       (vm-skip-past-folder-header)
       (vm-skip-past-leading-message-separator)
       (if (re-search-forward vm-vheader-header-regexp lim t)
	   (let (vis invis (got nil))
	     (condition-case ()
		 (setq vis (read (current-buffer))
		       invis (read (current-buffer))
		       got t)
	       (error nil))
	     (if got
		 (vm-startup-apply-header-variables vis invis))))))))

(defun vm-startup-apply-header-variables (vis invis)
  ;; if the variables don't match the values stored when this
  ;; folder was saved, then we have to discard any cached
  ;; vheader info so the user will see the right headers.
  (and (or (not (equal vis vm-visible-headers))
	   (not (equal invis vm-invisible-header-regexp)))
       (let ((mp vm-message-list))
	 (vm-inform 7 "%s: Discarding visible header info..." (buffer-name))
	 (while mp
	   (vm-set-vheaders-regexp-of (car mp) nil)
	   (vm-set-vheaders-of (car mp) nil)
	   (setq mp (cdr mp)))
	 (vm-inform 7 "%s: Discarding visible header info... done" 
		    (buffer-name))
	 )))

;; Read and delete the header that gives the folder's desired
;; message order.
(defun vm-gobble-message-order ()
  (let ((case-fold-search t)
	lim order)
    (save-excursion
      (save-restriction
	(widen)
	(goto-char (point-min))
	(vm-skip-past-folder-header)
	(vm-skip-past-leading-message-separator)
	(search-forward "\n\n" nil t)
	(setq lim (point))
	(goto-char (point-min))
	(vm-skip-past-folder-header)
	(vm-skip-past-leading-message-separator)
	(when (re-search-forward vm-message-order-header-regexp lim t)
	  (let ((oldpoint (point)))
	    (condition-case nil
		(progn
		  (setq order (read (current-buffer)))
		  (unless (listp order)
		    (error "Bad order header at %d in buffer %s"
			   oldpoint (buffer-name))
		    (sit-for 1))
		  order )
	      (error
	       (vm-warn 1 1 
			"Bad order header at %d in buffer %s, ignoring"
			oldpoint (buffer-name))
	       (setq order nil)))
	    (when order
	      (vm-inform 7 "%s: Reordering messages..." (buffer-name))
	      (vm-startup-apply-message-order order)
	      (vm-inform 7 "%s: Reordering messages... done" (buffer-name)))))
	))))

(defun vm-has-message-order ()
  (let ((case-fold-search t)
	lim) ;; order
    (save-excursion
      (save-restriction
	(widen)
	(goto-char (point-min))
	(vm-skip-past-folder-header)
	(vm-skip-past-leading-message-separator)
	(search-forward "\n\n" nil t)
	(setq lim (point))
	(goto-char (point-min))
	(vm-skip-past-folder-header)
	(vm-skip-past-leading-message-separator)
	(re-search-forward vm-message-order-header-regexp lim t)))))

(defun vm-startup-apply-message-order (order)
  (let (list-length v (mp vm-message-list))
    (setq list-length (length vm-message-list)
	  v (make-vector (max list-length (length order)) nil))
    (while (and order mp)
      (condition-case nil
	  (aset v (1- (car order)) (car mp))
	(args-out-of-range nil))
      (setq order (cdr order) mp (cdr mp)))
    ;; lock out interrupts while the message list is in
    ;; an inconsistent state.
    (let ((inhibit-quit t))
      (setq vm-message-list (delq nil (append v mp))
	    vm-message-order-changed nil
	    vm-message-order-header-present t
	    vm-message-pointer (memq (car vm-message-pointer)
				     vm-message-list))
      (vm-set-numbering-redo-start-point t)
      (vm-reverse-link-messages))))

;; Read the header that gives the folder's cached summary format
;; If the current summary format is different, then the cached
;; summary lines are discarded.
(defun vm-gobble-summary ()
  (let ((case-fold-search t)
	summary lim)
    (save-excursion
      (save-restriction
       (widen)
       (goto-char (point-min))
       (vm-skip-past-folder-header)
       (vm-skip-past-leading-message-separator)
       (search-forward "\n\n" nil t)
       (setq lim (point))
       (goto-char (point-min))
       (vm-skip-past-folder-header)
       (vm-skip-past-leading-message-separator)
       (if (re-search-forward vm-summary-header-regexp lim t)
	   (let ((oldpoint (point)))
	     (condition-case ()
		 (setq summary (read (current-buffer)))
	       (error
		(vm-warn 1 1 
			 "Bad summary header at %d in buffer %s, ignoring"
			 oldpoint (buffer-name))
		(setq summary "")))
	     (vm-startup-apply-summary summary)))))))

(defun vm-startup-apply-summary (summary)
  (if (not (equal summary vm-summary-format))
      (if vm-restore-saved-summary-formats
	  (progn
           (make-local-variable 'vm-summary-format)
           (setq vm-summary-format summary))
	(let ((mp vm-message-list))
	  (while mp
	    (vm-set-decoded-tokenized-summary-of (car mp) nil)
	    ;; force restuffing of cache to clear old
	    ;; summary entry cache.
	    (vm-set-stuff-flag-of (car mp) t)
	    (setq mp (cdr mp)))))))

;; Add a X-VM-Storage header
(defun vm-add-storage-header (mp &rest args)
  (save-excursion
    (let ((buffer-read-only nil)
	  opoint)
      (goto-char (vm-headers-of (car mp)))
      (setq opoint (point))
      (insert-before-markers vm-external-storage-header " (")
      (when args (insert-before-markers (format "%s" (car args))))
      (setq args (cdr args))
      (while args
	(insert-before-markers (format " %s" (car args)))
	(setq args (cdr args)))
      (insert-before-markers ")\n")
      (set-marker (vm-headers-of (car mp)) opoint))))


;; This is now replaced by vm-mime-encode-words-in-cache-vector
;;
;; (defun vm-encode-words-in-cache-vector (list)
;;   (vm-mapvector (lambda (e)
;; 		  (if (stringp e)
;; 		      (vm-mime-encode-words-in-string e)
;; 		    e))
;; 		list))

(defun vm-stuff-message-data (m &optional for-other-folder)
  "Stuff the attributes, labels, soft and cached data of the
message M into the folder buffer.  The optional argument
FOR-OTHER-FOLDER indicates <someting unknown>.  USR 2010-03-06"
  (save-excursion
    (save-restriction
     (widen)
     (let ((old-buffer-modified-p (buffer-modified-p))
	   (case-fold-search t)
	   (buffer-read-only nil)
 	   ;; don't truncate the printing of large Lisp objects
 	   (print-length nil)
	   ;; This prevents file locking from occuring.  Disabling
	   ;; locking can speed things noticeably if the lock
	   ;; directory is on a slow device.  We don't need locking
	   ;; here because the user shouldn't care about VM stuffing
	   ;; its own status headers.
	   (buffer-file-name nil))
       (unwind-protect
	   (vm-stuff-message-data-internal m for-other-folder)
	 (vm-restore-buffer-modified-p	; folder-buffer
	  old-buffer-modified-p (current-buffer)))))))

(defun vm-stuff-message-data-internal (m &optional for-other-folder)
  "Stuff the attributes, labels, soft and cached data of the
message M into the folder buffer.  The optional argument
FOR-OTHER-FOLDER indicates <something unknown>.  USR 2010-03-06"
  (let (attributes cache opoint
	(delflag (vm-deleted-flag m)))
    (progn
      ;; don't put this folder's summary entry into another folder.
      (if for-other-folder
	  (vm-set-decoded-tokenized-summary-of m nil)
	(if (vm-su-start-of m)
	    ;; fill the summary cache if it's not done already.
	    (vm-su-decoded-tokenized-summary m)))
      (setq attributes (vm-attributes-of m)
	    cache (vm-cached-data-of m))
      (when (and delflag for-other-folder)
	(vm-set-deleted-flag-in-vector
	 (setq attributes (copy-sequence attributes)) nil))
      (when (eq vm-folder-type 'babyl)
	(vm-stuff-babyl-attributes m for-other-folder))
      (when (eq vm-sync-thunderbird-status t)
	(vm-stuff-thunderbird-status m))
      (goto-char (vm-headers-of m))
      (while (re-search-forward vm-attributes-header-regexp
				(vm-text-of m) t)
	(delete-region (match-beginning 0) (match-end 0)))
      (goto-char (vm-headers-of m))
      (setq opoint (point))
      (insert				; insert-before-markers?
       vm-attributes-header " ("
       (let ((print-escape-newlines t))
	 (prin1-to-string attributes))
       "\n\t"
       (let ((print-escape-newlines t))
	 (prin1-to-string (vm-mime-encode-words-in-cache-vector cache)))
       "\n\t"
       (let ((print-escape-newlines t))
	 (prin1-to-string (vm-decoded-labels-of m)))
       ")\n")
      (set-marker (vm-headers-of m) opoint)
      (cond ((and (eq vm-folder-type 'From_)
		  vm-berkeley-mail-compatibility)
	     (goto-char (vm-headers-of m))
	     (while (re-search-forward
		     vm-berkeley-mail-status-header-regexp
		     (vm-text-of m) t)
	       (delete-region (match-beginning 0) (match-end 0)))
	     (goto-char (vm-headers-of m))
	     (cond ((not (vm-new-flag m))
		    (insert-before-markers
		     vm-berkeley-mail-status-header
		     (if (vm-unread-flag m) "" "R")
		     "O\n")
		    (set-marker (vm-headers-of m) opoint)))))
      (if for-other-folder
	  (vm-set-stuff-flag-of m nil)	  ; same effect as VM 7.19
	(vm-set-stuff-flag-of m nil))	  ; new
      )))


  
(cl-defun vm-stuff-folder-data (&key interactive abort-if-input-pending)
  "Stuff the soft and cached data of all the messages that have the
stuff-flag set in the current folder.
Keyword parameter INTERACTIVE says whether the stuffing is being done
as part of an interactive command.
ABORT-IF-INPUT-PENDING says stuffing should be aborted if there is
pending input.   So, presumably this is non-interactive.  USR 2012-12-22"
  (let ((newlist nil) mp len (n 0) (p 0) (p-last 0)
	(inform-level (if interactive 8 9)))
    ;; stuff the attributes of messages that need it.
    ;; build a list of messages that need their attributes stuffed
    (setq mp vm-message-list)
    (while mp
      (if (vm-stuff-flag-of (car mp))
	  (setq newlist (cons (car mp) newlist)))
      (setq mp (cdr mp)))
    (when newlist
      (setq len (length newlist))
      (vm-inform inform-level "%s: %d message%s to stuff" (buffer-name)
		 len (if (= 1 len) "" "s")))
    ;; now sort the list by physical order so that we
    ;; reduce the amount of gap motion induced by modifying
    ;; the buffer.  what we want to avoid is updating
    ;; message 3, then 234, then 10, then 500, thus causing
    ;; large chunks of memory to be copied repeatedly as
    ;; the gap moves to accomodate the insertions.
    ;; (vm-inform inform-level "%s: Ordering updates..." (buffer-name)) 
					; Pointless
    (let ((vm-key-functions '(vm-sort-compare-physical-order-r)))
      (setq mp (sort newlist 'vm-sort-compare-xxxxxx)))
    (save-excursion
      (save-restriction
       (widen)
       (let ((old-buffer-modified-p (buffer-modified-p))
	     (case-fold-search t)
	     (buffer-read-only nil)
	     ;; don't truncate the printing of large Lisp objects
	     (print-length nil)
	     ;; This prevents file locking from occuring.  Disabling
	     ;; locking can speed things noticeably if the lock
	     ;; directory is on a slow device.  We don't need locking
	     ;; here because the user shouldn't care about VM stuffing
	     ;; its own status headers.
	     (buffer-file-name nil))
	 (unwind-protect
	     (while (and mp 
			 (not (and abort-if-input-pending
			           (input-pending-p))))
	       (vm-stuff-message-data-internal (car mp))
	       (setq n (1+ n))
	       (setq p-last p
		     p (truncate (* 100 n) len))
	       (when (> p p-last)
		 (vm-inform inform-level
			    "%s: Stuffing %d%% complete..." (buffer-name) p))
	       (setq mp (cdr mp)))
	   (vm-restore-buffer-modified-p ; folder-buffer
	    old-buffer-modified-p (current-buffer)))
	 (if mp nil t))))))

;; we can be a bit lazy in this function since it's only called
;; from within vm-stuff-message-data.  we don't worry about
;; restoring the modified flag, setting buffer-read-only, or
;; about not moving point.
(defun vm-stuff-babyl-attributes (m for-other-folder)
  (goto-char (vm-start-of m))
  (forward-char 2)
  (if (vm-babyl-frob-flag-of m)
      (insert "1")
    (insert "0"))
  (delete-char 1)
  (forward-char 1)
  (if (looking-at "\\( [^\000-\040,\177-\377]+,\\)+")
      (delete-region (match-beginning 0) (match-end 0)))
  (if (vm-new-flag m)
      (insert " recent, unseen,")
    (if (vm-unread-flag m)
	(insert " unseen,")))
  (if (and (not for-other-folder) (vm-deleted-flag m))
      (insert " deleted,"))
  (if (vm-replied-flag m)
      (insert " answered,"))
  (if (vm-forwarded-flag m)
      (insert " forwarded,"))
  (if (vm-redistributed-flag m)
      (insert " redistributed,"))
  (if (vm-filed-flag m)
      (insert " filed,"))
  (if (vm-edited-flag m)
      (insert " edited,"))
  (if (vm-written-flag m)
      (insert " written,"))
  (forward-char 1)
  (if (looking-at "\\( [^\000-\040,\177-\377]+,\\)+")
      (delete-region (match-beginning 0) (match-end 0)))
  (mapcar (function (lambda (label) (insert " " label ",")))
	  (vm-decoded-labels-of m)))

(defun vm-babyl-attributes-string (m for-other-folder)
  (concat
   (if (vm-new-flag m)
       " recent, unseen,"
     (if (vm-unread-flag m)
	 " unseen,"))
   (if (and (not for-other-folder) (vm-deleted-flag m))
       " deleted,")
   (if (vm-replied-flag m)
       " answered,")
   (if (vm-forwarded-flag m)
       " forwarded,")
   (if (vm-redistributed-flag m)
       " redistributed,")
   (if (vm-filed-flag m)
       " filed,")
   (if (vm-edited-flag m)
       " edited,")
   (if (vm-written-flag m)
       " written,")))

(defun vm-babyl-labels-string (m)
  (let ((list nil)
	(labels (vm-decoded-labels-of m)))
    (while labels
      (setq list (cons "," (cons (car labels) (cons " " list)))
	    labels (cdr labels)))
    (apply 'concat (nreverse list))))

(defun vm-stuff-virtual-message-data (message)
  (let ((virtual (vm-virtual-message-p message))
	(real-m (vm-real-message-of message)))
    (if (or (not virtual) (and virtual (vm-virtual-messages-of message)))
	(with-current-buffer
	    (vm-buffer-of real-m)
	  (vm-stuff-message-data real-m)))))

(defun vm-stuff-thunderbird-status (message)
  (let (status status2 status2-hi status2-lo)
    (goto-char (vm-headers-of message))
    (if (re-search-forward "^X-Mozilla-Status: \\([ 0-9A-Fa-f]+\\)\n"
			   (vm-text-of message) t)
	(progn
	  (setq status (buffer-substring (match-beginning 1) (match-end 1)))
	  (delete-region (match-beginning 0) (match-end 0))
	  (setq status (string-to-number status 16))
	  ;; clear those bits we are using and keep others ...
	  ;; #xeff0 is (lognot (logior #x1 #x2 #x4 #x8 #x1000))
	  (setq status (logand status #xeff0))
	  )
      (setq status 0))

    (goto-char (vm-headers-of message))
    (if (re-search-forward "^X-Mozilla-Status2: \\([ 0-9A-Fa-f]+\\)\n"
			   (vm-text-of message) t)
	(progn
	  (setq status2 (buffer-substring (match-beginning 1) (match-end 1)))
	  (delete-region (match-beginning 0) (match-end 0))
	  (if (> (length status2) 4)
	      (setq status2-hi (string-to-number (substring status2 0 -4) 16)
		    status2-lo (string-to-number (substring status2 -4 nil) 16))
	    ;; handle badly fomatted status strings written by old
	    ;; versions
	    (setq status2 (string-to-number status2 16)
		  status2-hi (/ status2 #x1000)
		  status2-lo (mod status2 #x1000)))
	  ;; clear those bits we are using and keep others ...
	  ;; #xfffe is (lognot (logior #x1))
	  (setq status2-hi (logand status2-hi #xfffe)))
      (setq status2 0
	    status2-hi 0
	    status2-lo 0))

    (unless (vm-unread-flag message)
      (setq status (logior status #x1)))
    (when (vm-replied-flag message)
      (setq status (logior status #x2)))
    (when (vm-flagged-flag message)
      (setq status (logior status #x4)))
    (when (vm-deleted-flag message)
      (setq status (logior status #x8)))
    (when (vm-folded-flag message)
      (setq status (logior status #x0020)))
    (when (vm-watched-flag message)
      (setq status (logior status #x0100)))
    (when (vm-forwarded-flag message)
      (setq status (logior status #x1000)))
    (when (vm-new-flag message)
      (setq status2-hi (logior status2-hi #x0001)))
    (when (vm-ignored-flag message)
      (setq status2-hi (logior status2-hi #x0004)))
    (when (vm-read-receipt-flag message)
      (setq status2-hi (logior status2-hi #x0040)))
    (when (vm-read-receipt-sent-flag message)
      (setq status2-hi (logior status2-hi #x0080)))
    (when (vm-attachments-flag message)
      (setq status2-hi (logior status2-hi #x1000)))
    (goto-char (vm-headers-of message))
    (insert (format "X-Mozilla-Status: %04x\n" status))
    (insert (format "X-Mozilla-Status2: %04x%04x\n" status2-hi status2-lo))))
  
(defun vm-stuff-labels ()
  (if vm-message-list
      (save-excursion
	(save-restriction
	 (widen)
	 (let ((old-buffer-modified-p (buffer-modified-p))
	       (case-fold-search t)
	       ;; don't truncate the printing of large Lisp objects
	       (print-length nil)
	       ;; This prevents file locking from occuring.  Disabling
	       ;; locking can speed things noticeably if the lock
	       ;; directory is on a slow device.  We don't need locking
	       ;; here because the user shouldn't care about VM stuffing
	       ;; its own status headers.
	       (buffer-file-name nil)
	       (buffer-read-only nil)
	       lim)
	   (if (eq vm-folder-type 'babyl)
	       (progn
		 (goto-char (point-min))
		 (vm-skip-past-folder-header)
		 (delete-region (point) (point-min))
		 (insert-before-markers (vm-folder-header vm-folder-type
							  vm-label-obarray))))
	   (goto-char (point-min))
	   (vm-skip-past-folder-header)
	   (vm-find-leading-message-separator)
	   (vm-skip-past-leading-message-separator)
	   (search-forward "\n\n" nil t)
	   (setq lim (point))
	   (goto-char (point-min))
	   (vm-skip-past-folder-header)
	   (vm-find-leading-message-separator)
	   (vm-skip-past-leading-message-separator)
	   (while (re-search-forward vm-labels-header-regexp lim t)
	     (progn (goto-char (match-beginning 0))
		    (if (vm-match-header vm-labels-header)
			(delete-region (vm-matched-header-start)
				       (vm-matched-header-end)))))
	   ;; To insert or to insert-before-markers, that is the question.
	   ;;
	   ;; If we insert-before-markers we push a header behind
	   ;; vm-headers-of, which is clearly undesirable.  So we
	   ;; just insert.  This will cause the summary header
	   ;; to be visible if there are no non-visible headers,
	   ;; oh well, no way around this.
	   (insert vm-labels-header " "
		   (let ((print-escape-newlines t)
			 (list nil))
		     (mapatoms (function
				(lambda (sym)
				  (setq list (cons (symbol-name sym) list))))
			       vm-label-obarray)
		     (prin1-to-string list))
		   "\n")
	   (vm-restore-buffer-modified-p ; folder-buffer
	    old-buffer-modified-p (current-buffer)))))))

;; Insert a bookmark into the first message in the folder.
(defun vm-stuff-bookmark ()
  (if vm-message-pointer
      (save-excursion
	(save-restriction
	 (widen)
	 (let ((old-buffer-modified-p (buffer-modified-p))
	       (case-fold-search t)
	       ;; This prevents file locking from occuring.  Disabling
	       ;; locking can speed things noticeably if the lock
	       ;; directory is on a slow device.  We don't need locking
	       ;; here because the user shouldn't care about VM stuffing
	       ;; its own status headers.
	       (buffer-file-name nil)
	       (buffer-read-only nil)
	       lim)
	   (goto-char (point-min))
	   (vm-skip-past-folder-header)
	   (vm-find-leading-message-separator)
	   (vm-skip-past-leading-message-separator)
	   (search-forward "\n\n" nil t)
	   (setq lim (point))
	   (goto-char (point-min))
	   (vm-skip-past-folder-header)
	   (vm-find-leading-message-separator)
	   (vm-skip-past-leading-message-separator)
	   (if (re-search-forward vm-bookmark-header-regexp lim t)
	       (progn (goto-char (match-beginning 0))
		      (if (vm-match-header vm-bookmark-header)
			  (delete-region (vm-matched-header-start)
					 (vm-matched-header-end)))))
	   ;; To insert or to insert-before-markers, that is the question.
	   ;;
	   ;; If we insert-before-markers we push a header behind
	   ;; vm-headers-of, which is clearly undesirable.  So we
	   ;; just insert.  This will cause the bookmark header
	   ;; to be visible if there are no non-visible headers,
	   ;; oh well, no way around this.
	   (insert vm-bookmark-header " "
		   (vm-number-of (car vm-message-pointer))
		   "\n")
	   (vm-restore-buffer-modified-p ; folder-buffer
	    old-buffer-modified-p (current-buffer)))))))

(defun vm-stuff-last-modified ()
  (if vm-message-list
      (save-excursion
	(save-restriction
	 (widen)
	 (let ((old-buffer-modified-p (buffer-modified-p))
	       (case-fold-search t)
	       ;; This prevents file locking from occuring.  Disabling
	       ;; locking can speed things noticeably if the lock
	       ;; directory is on a slow device.  We don't need locking
	       ;; here because the user shouldn't care about VM stuffing
	       ;; its own status headers.
	       (buffer-file-name nil)
	       (buffer-read-only nil)
	       lim)
	   (goto-char (point-min))
	   (vm-skip-past-folder-header)
	   (vm-find-leading-message-separator)
	   (vm-skip-past-leading-message-separator)
	   (search-forward "\n\n" nil t)
	   (setq lim (point))
	   (goto-char (point-min))
	   (vm-skip-past-folder-header)
	   (vm-find-leading-message-separator)
	   (vm-skip-past-leading-message-separator)
	   (if (re-search-forward vm-last-modified-header-regexp lim t)
	       (progn (goto-char (match-beginning 0))
		      (if (vm-match-header vm-last-modified-header)
			  (delete-region (vm-matched-header-start)
					 (vm-matched-header-end)))))
	   ;; To insert or to insert-before-markers, that is the question.
	   ;;
	   ;; If we insert-before-markers we push a header behind
	   ;; vm-headers-of, which is clearly undesirable.  So we
	   ;; just insert.  This will cause the last-modified header
	   ;; to be visible if there are no non-visible headers,
	   ;; oh well, no way around this.
	   (insert vm-last-modified-header " "
		   (prin1-to-string (current-time))
		   "\n")
	   (vm-restore-buffer-modified-p ; folder-buffer
	    old-buffer-modified-p (current-buffer)))))))

(defun vm-stuff-pop-retrieved ()
  (if vm-message-list
      (save-excursion
	(save-restriction
	 (widen)
	 (let ((old-buffer-modified-p (buffer-modified-p))
	       (case-fold-search t)
	       ;; This prevents file locking from occuring.  Disabling
	       ;; locking can speed things noticeably if the lock
	       ;; directory is on a slow device.  We don't need locking
	       ;; here because the user shouldn't care about VM stuffing
	       ;; its own status headers.
	       (buffer-file-name nil)
	       (buffer-read-only nil)
	       (print-length nil)
	       (p vm-pop-retrieved-messages)
	       (curbuf (current-buffer))
	       lim)
	   (goto-char (point-min))
	   (vm-skip-past-folder-header)
	   (vm-find-leading-message-separator)
	   (vm-skip-past-leading-message-separator)
	   (search-forward "\n\n" nil t)
	   (setq lim (point))
	   (goto-char (point-min))
	   (vm-skip-past-folder-header)
	   (vm-find-leading-message-separator)
	   (vm-skip-past-leading-message-separator)
	   (if (re-search-forward vm-pop-retrieved-header-regexp lim t)
	       (progn (goto-char (match-beginning 0))
		      (if (vm-match-header vm-pop-retrieved-header)
			  (delete-region (vm-matched-header-start)
					 (vm-matched-header-end)))))
	   ;; To insert or to insert-before-markers, that is the question.
	   ;;
	   ;; If we insert-before-markers we push a header behind
	   ;; vm-headers-of, which is clearly undesirable.  So we
	   ;; just insert.  This will cause the pop-retrieved header
	   ;; to be visible if there are no non-visible headers,
	   ;; oh well, no way around this.
	   (insert vm-pop-retrieved-header)
	   (if (null p)
	       (insert " nil\n")
	     (insert "\n   (\n")
	     (while p
	       (insert "\t")
	       (prin1 (car p) curbuf)
	       (insert "\n")
	       (setq p (cdr p)))
	     (insert "   )\n"))
	   (vm-restore-buffer-modified-p ; folder-buffer
	    old-buffer-modified-p (current-buffer)))))))

(defun vm-stuff-imap-retrieved ()
  (if vm-message-list
      (save-excursion
	(save-restriction
	 (widen)
	 (let ((old-buffer-modified-p (buffer-modified-p))
	       (case-fold-search t)
	       ;; This prevents file locking from occuring.  Disabling
	       ;; locking can speed things noticeably if the lock
	       ;; directory is on a slow device.  We don't need locking
	       ;; here because the user shouldn't care about VM stuffing
	       ;; its own status headers.
	       (buffer-file-name nil)
	       (buffer-read-only nil)
	       (print-length nil)
	       (p vm-imap-retrieved-messages)
	       (curbuf (current-buffer))
	       lim)
	   (goto-char (point-min))
	   (vm-skip-past-folder-header)
	   (vm-find-leading-message-separator)
	   (vm-skip-past-leading-message-separator)
	   (search-forward "\n\n" nil t)
	   (setq lim (point))
	   (goto-char (point-min))
	   (vm-skip-past-folder-header)
	   (vm-find-leading-message-separator)
	   (vm-skip-past-leading-message-separator)
	   (if (re-search-forward vm-imap-retrieved-header-regexp lim t)
	       (progn (goto-char (match-beginning 0))
		      (if (vm-match-header vm-imap-retrieved-header)
			  (delete-region (vm-matched-header-start)
					 (vm-matched-header-end)))))
	   ;; To insert or to insert-before-markers, that is the question.
	   ;;
	   ;; If we insert-before-markers we push a header behind
	   ;; vm-headers-of, which is clearly undesirable.  So we
	   ;; just insert.  This will cause the imap-retrieved header
	   ;; to be visible if there are no non-visible headers,
	   ;; oh well, no way around this.
	   (insert vm-imap-retrieved-header)
	   (if (null p)
	       (insert " nil\n")
	     (insert "\n   (\n")
	     (while p
	       (insert "\t")
	       (prin1 (car p) curbuf)
	       (insert "\n")
	       (setq p (cdr p)))
	     (insert "   )\n"))
	   (vm-restore-buffer-modified-p ; folder-buffer
	    old-buffer-modified-p (current-buffer)))))))

;; Insert the summary format variable header into the first message.
(defun vm-stuff-summary ()
  (if vm-message-list
      (save-excursion
	(save-restriction
	 (widen)
	 (let ((old-buffer-modified-p (buffer-modified-p))
	       (case-fold-search t)
	       ;; don't truncate the printing of large Lisp objects
	       (print-length nil)
	       ;; This prevents file locking from occuring.  Disabling
	       ;; locking can speed things noticeably if the lock
	       ;; directory is on a slow device.  We don't need locking
	       ;; here because the user shouldn't care about VM stuffing
	       ;; its own status headers.
	       (buffer-file-name nil)
	       (buffer-read-only nil)
	       lim)
	   (goto-char (point-min))
	   (vm-skip-past-folder-header)
	   (vm-find-leading-message-separator)
	   (vm-skip-past-leading-message-separator)
	   (search-forward "\n\n" nil t)
	   (setq lim (point))
	   (goto-char (point-min))
	   (vm-skip-past-folder-header)
	   (vm-find-leading-message-separator)
	   (vm-skip-past-leading-message-separator)
	   (while (re-search-forward vm-summary-header-regexp lim t)
	     (progn (goto-char (match-beginning 0))
		    (if (vm-match-header vm-summary-header)
			(delete-region (vm-matched-header-start)
				       (vm-matched-header-end)))))
	   ;; To insert or to insert-before-markers, that is the question.
	   ;;
	   ;; If we insert-before-markers we push a header behind
	   ;; vm-headers-of, which is clearly undesirable.  So we
	   ;; just insert.  This will cause the summary header
	   ;; to be visible if there are no non-visible headers,
	   ;; oh well, no way around this.
	   (insert vm-summary-header " "
		   (let ((print-escape-newlines t))
		     (prin1-to-string vm-summary-format))
		   "\n")
	   (vm-restore-buffer-modified-p ; folder-buffer
	    old-buffer-modified-p (current-buffer)))))))

;; stuff the current values of the header variables for future messages.
(defun vm-stuff-header-variables ()
  (if vm-message-list
      (save-excursion
	(save-restriction
	 (widen)
	 (let ((old-buffer-modified-p (buffer-modified-p))
	       (case-fold-search t)
	       (print-escape-newlines t)
	       lim
	       ;; don't truncate the printing of large Lisp objects
	       (print-length nil)
	       (buffer-read-only nil)
	       ;; This prevents file locking from occuring.  Disabling
	       ;; locking can speed things noticeably if the lock
	       ;; directory is on a slow device.  We don't need locking
	       ;; here because the user shouldn't care about VM stuffing
	       ;; its own status headers.
	       (buffer-file-name nil))
	   (goto-char (point-min))
	   (vm-skip-past-folder-header)
	   (vm-find-leading-message-separator)
	   (vm-skip-past-leading-message-separator)
	   (search-forward "\n\n" nil t)
	   (setq lim (point))
	   (goto-char (point-min))
	   (vm-skip-past-folder-header)
	   (vm-find-leading-message-separator)
	   (vm-skip-past-leading-message-separator)
	   (while (re-search-forward vm-vheader-header-regexp lim t)
	     (progn (goto-char (match-beginning 0))
		    (if (vm-match-header vm-vheader-header)
			(delete-region (vm-matched-header-start)
				       (vm-matched-header-end)))))
	   ;; To insert or to insert-before-markers, that is the question.
	   ;;
	   ;; If we insert-before-markers we push a header behind
	   ;; vm-headers-of, which is clearly undesirable.  So we
	   ;; just insert.  This header will be visible if there
	   ;; are no non-visible headers, oh well, no way around this.
	   (insert vm-vheader-header " "
		   (prin1-to-string vm-visible-headers) " "
		   (prin1-to-string vm-invisible-header-regexp)
		   "\n")
	   (vm-restore-buffer-modified-p ; folder-buffer
	    old-buffer-modified-p (current-buffer)))))))

;; Insert a header into the first message of the folder that lists
;; the folder's message order.
(defun vm-stuff-message-order ()
  (if (cdr vm-message-list)
      (save-excursion
	(save-restriction
	 (widen)
	 (let ((old-buffer-modified-p (buffer-modified-p))
	       (case-fold-search t)
	       ;; This prevents file locking from occuring.  Disabling
	       ;; locking can speed things noticeably if the lock
	       ;; directory is on a slow device.  We don't need locking
	       ;; here because the user shouldn't care about VM stuffing
	       ;; its own status headers.
	       (buffer-file-name nil)
	       lim n
	       (buffer-read-only nil)
	       (mp (copy-sequence vm-message-list)))
	   (setq mp
		 (sort mp
		       (function
			(lambda (p q)
			  (< (vm-start-of p) (vm-start-of q))))))
	   (goto-char (point-min))
	   (vm-skip-past-folder-header)
	   (vm-find-leading-message-separator)
	   (vm-skip-past-leading-message-separator)
	   (search-forward "\n\n" nil t)
	   (setq lim (point))
	   (goto-char (point-min))
	   (vm-skip-past-folder-header)
	   (vm-find-leading-message-separator)
	   (vm-skip-past-leading-message-separator)
	   (while (re-search-forward vm-message-order-header-regexp lim t)
	     (progn (goto-char (match-beginning 0))
		    (if (vm-match-header vm-message-order-header)
			(delete-region (vm-matched-header-start)
				       (vm-matched-header-end)))))
	   ;; To insert or to insert-before-markers, that is the question.
	   ;;
	   ;; If we insert-before-markers we push a header behind
	   ;; vm-headers-of, which is clearly undesirable.  So we
	   ;; just insert.  This header will be visible if there
	   ;; are no non-visible headers, oh well, no way around this.
	   (insert vm-message-order-header "\n\t(")
	   (setq n 0)
	   (while mp
	     (insert (vm-number-of (car mp)))
	     (setq n (1+ n) mp (cdr mp))
	     (and mp (insert
		      (if (zerop (% n 15))
			  "\n\t "
			" "))))
	   (insert ")\n")
	   (setq vm-message-order-changed nil
		 vm-message-order-header-present t)
	   (vm-restore-buffer-modified-p ; folder-buffer
	    old-buffer-modified-p (current-buffer)))))))

;; Remove the message order header.
(defun vm-remove-message-order ()
  (if (cdr vm-message-list)
      (save-excursion
	(save-restriction
	 (widen)
	 (let ((old-buffer-modified-p (buffer-modified-p))
	       (case-fold-search t)
	       lim
	       ;; This prevents file locking from occuring.  Disabling
	       ;; locking can speed things noticeably if the lock
	       ;; directory is on a slow device.  We don't need locking
	       ;; here because the user shouldn't care about VM stuffing
	       ;; its own status headers.
	       (buffer-file-name nil)
	       (buffer-read-only nil))
	   (goto-char (point-min))
	   (vm-skip-past-folder-header)
	   (vm-skip-past-leading-message-separator)
	   (search-forward "\n\n" nil t)
	   (setq lim (point))
	   (goto-char (point-min))
	   (vm-skip-past-folder-header)
	   (vm-skip-past-leading-message-separator)
	   (while (re-search-forward vm-message-order-header-regexp lim t)
	     (progn (goto-char (match-beginning 0))
		    (if (vm-match-header vm-message-order-header)
			(delete-region (vm-matched-header-start)
				       (vm-matched-header-end)))))
	   (setq vm-message-order-header-present nil)
	   (vm-restore-buffer-modified-p ; folder-buffer
	    old-buffer-modified-p (current-buffer)))))))

(defun vm-make-index-file-name ()
  (concat (file-name-directory buffer-file-name)
          "."
          (file-name-nondirectory buffer-file-name)
          vm-index-file-suffix))

(defun vm-read-index-file-maybe ()
  (catch 'done
    (if (or (not (stringp buffer-file-name))
	    (not (stringp vm-index-file-suffix)))
	(throw 'done nil))
    (let* ((index-file (vm-make-index-file-name))
           (mtime-buffer (nth 5 (file-attributes buffer-file-name)))
           (mtime-index (nth 5 (file-attributes index-file))))
      (if (and (file-readable-p index-file)
               (>= (car mtime-index) (car mtime-buffer))
               (>= (car (cdr mtime-index)) (car (cdr mtime-buffer))))
          (vm-read-index-file index-file)
	nil))))

(defun vm-read-index-file (index-file)
  (catch 'done
    (condition-case error-data
	(let ((work-buffer nil))
	  (unwind-protect
	      (let (obj attr-list cache-list location-list label-list
		    validity-check vis invis folder-type
		    bookmark summary labels pop-retrieved imap-retrieved order
		    v m (m-list nil) tail)
		(vm-inform 5 "%s: Reading index file..." (buffer-name))
		(setq work-buffer (vm-make-work-buffer))
		(with-current-buffer work-buffer
		  (insert-file-contents-literally index-file))
		(goto-char (point-min))

		;; check version
		(setq obj (read work-buffer))
		(if (not (eq obj 1))
		    (error "Unsupported index file version: %s" obj))

		;; folder type
		(setq folder-type (read work-buffer))

		;; validity check
		(setq validity-check (read work-buffer))
		(if (null (vm-check-index-file-validity validity-check))
		    (throw 'done nil))

		;; bookmark
		(setq bookmark (read work-buffer))

		;; message order
		(setq order (read work-buffer))

		;; what summary format was used to produce the
		;; folder's summary cache line.
		(setq summary (read work-buffer))

		;; folder-wide list of labels
		(setq labels (read work-buffer))

		;; what vm-visible-headers / vm-invisible-header-regexp
		;; settings were used to order the headers and to
		;; produce the vm-headers-regexp-of slot value.
		(setq vis (read work-buffer))
		(setq invis (read work-buffer))

		;; location offsets
		;; attributes list
		;; cache list
		;; label list
		(setq location-list (read work-buffer))
		(setq attr-list (read work-buffer))
		(setq cache-list (read work-buffer))
		(setq label-list (read work-buffer))
		(while location-list
		  (setq v (car location-list)
			m (vm-make-message))
		  (if (null m-list)
		      (setq m-list (list m)
			    tail m-list)
		    (setcdr tail (list m))
		    (setq tail (cdr tail)))
		  (vm-set-start-of m (vm-marker (aref v 0)))
		  (vm-set-headers-of m (vm-marker (aref v 1)))
		  (vm-set-text-end-of m (vm-marker (aref v 2)))
		  (vm-set-end-of m (vm-marker (aref v 3)))
		  (if (null attr-list)
		      (error "Attribute list is shorter than location list")
		    (setq v (car attr-list))
		    (if (< (length v) vm-attributes-vector-length)
			(setq v (vm-extend-vector
				 v vm-attributes-vector-length)))
		    (vm-set-attributes-of m v))
		  (if (null cache-list)
		      (error "Cache list is shorter than location list")
		    (setq v (car cache-list))
		    (if (< (length v) vm-cached-data-vector-length)
			(setq v (vm-extend-vector v vm-cached-data-vector-length)))
		    (vm-set-cached-data-of m v))
		  (if (null label-list)
		      (error "Label list is shorter than location list")
		    (vm-set-decoded-labels-of m (car label-list)))
		  (setq location-list (cdr location-list)
			attr-list (cdr attr-list)
			cache-list (cdr cache-list)
			label-list (cdr label-list)))

		;; pop retrieved messages
		(setq pop-retrieved (read work-buffer))

		;; imap retrieved messages
		(setq imap-retrieved (read work-buffer))

		(setq vm-message-list m-list
		      vm-folder-type folder-type
		      vm-pop-retrieved-messages pop-retrieved
		      vm-imap-retrieved-messages imap-retrieved)

		(vm-startup-apply-bookmark bookmark)
		(and order (vm-startup-apply-message-order order))
		(if vm-summary-show-threads
		    (progn
		      ;; get numbering of new messages done now
		      ;; so that the sort code only has to worry about the
		      ;; changes it needs to make.
		      (vm-update-summary-and-mode-line)
		      (vm-sort-messages (or vm-ml-sort-keys "activity"))))
		(vm-startup-apply-summary summary)
		(vm-startup-apply-labels labels)
		(vm-startup-apply-header-variables vis invis)

		(vm-inform 5 "%s: Reading index file... done" (buffer-name))
		t )
	    (and work-buffer (kill-buffer work-buffer))))
      (error (vm-warn 1 2 "%s: Index file read of %s signaled: %s"
		      (buffer-name) index-file error-data)
	     (vm-warn 1 2 "%s: Ignoring index file..." (buffer-name))))))

(defun vm-check-index-file-validity (blob)
  (save-excursion
    (widen)
    (catch 'done
      (cond ((not (consp blob))
	     (error "Validity check object not a cons: %s" blob))
	    ((eq (car blob) 'file)
	     (let (ch time time2)
	       (setq blob (cdr blob))
	       (setq time (car blob)
		     time2 (vm-gobble-last-modified))
	       (if (and time2 (> 0 (vm-time-difference time time2)))
		   (throw 'done nil))
	       (setq blob (cdr blob))
	       (while blob
		 (setq ch (char-after (car blob)))
		 (if (or (null ch) (not (eq (vm-char-to-int ch) (nth 1 blob))))
		     (throw 'done nil))
		 (setq blob (cdr (cdr blob)))))
	     t )
	    (t (error "Unknown validity check type: %s" (car blob)))))))

(defun vm-generate-index-file-validity-check ()
  (save-restriction
    (widen)
    (let ((step (max 1 (/ (point-max) 11)))
	  (pos (1- (point-max)))
	  (lim (point-min))
	  (blob nil))
      (while (>= pos lim)
	(setq blob (cons pos (cons (vm-char-to-int (char-after pos)) blob))
	      pos (- pos step)))
      (cons 'file (cons (current-time) blob)))))

(defun vm-write-index-file-maybe ()
  (catch 'done
    (if (not (stringp buffer-file-name))
	(throw 'done nil))
    (if (not (stringp vm-index-file-suffix))
	(throw 'done nil))
    (let ((index-file (vm-make-index-file-name)))
      (vm-write-index-file index-file))))

(defun vm-write-index-file (index-file)
  (let ((work-buffer nil))
    (unwind-protect
	(let ((print-escape-newlines t)
	      (print-length nil)
	      m-list mp m)
	  (vm-inform 7 "%s: Sorting for index file..." (buffer-name))
	  (setq m-list (sort (copy-sequence vm-message-list)
			     (function vm-sort-compare-physical-order)))
	  (vm-inform 6 "%s: Stuffing index file..." (buffer-name))
	  (setq work-buffer (vm-make-work-buffer))

	  (princ ";; index file version\n" work-buffer)
	  (prin1 1 work-buffer)
	  (terpri work-buffer)

	  (princ ";; folder type\n" work-buffer)
	  (prin1 vm-folder-type work-buffer)
	  (terpri work-buffer)

	  (princ
	   ";; timestamp + sample of folder bytes for consistency check\n"
	   work-buffer)
	  (prin1 (vm-generate-index-file-validity-check) work-buffer)
	  (terpri work-buffer)

	  (princ ";; bookmark\n" work-buffer)
	  (princ (if vm-message-pointer
		     (vm-number-of (car vm-message-pointer))
		   "1")
		 work-buffer)
	  (terpri work-buffer)

	  (princ ";; message order\n" work-buffer)
	  (let ((n 0) (mp vm-message-list))
	   (princ "(" work-buffer)
	   (setq n 0)
	   (while mp
	     (if (zerop (% n 15))
		 (princ "\n\t" work-buffer)
	       (princ " " work-buffer))
	     (princ (vm-number-of (car mp)) work-buffer)
	     (setq n (1+ n) mp (cdr mp)))
	   (princ "\n)\n" work-buffer))

	  (princ ";; summary\n" work-buffer)
	  (prin1 vm-summary-format work-buffer)
	  (terpri work-buffer)

	  (princ ";; labels used in this folder\n" work-buffer)
	  (let ((list nil))
	    (mapatoms (function
		       (lambda (sym)
			 (setq list (cons (symbol-name sym) list))))
		      vm-label-obarray)
	    (prin1 list work-buffer))
	  (terpri work-buffer)

	  (princ ";; visible headers\n" work-buffer)
	  (prin1 vm-visible-headers work-buffer)
	  (terpri work-buffer)

	  (princ ";; hidden headers\n" work-buffer)
	  (prin1 vm-invisible-header-regexp work-buffer)
	  (terpri work-buffer)

	  (princ ";; location list\n" work-buffer)
	  (princ "(\n" work-buffer)
	  (setq mp m-list)
	  (while mp
	    (setq m (car mp))
	    (princ "  [" work-buffer)
	    (prin1 (marker-position (vm-start-of m)) work-buffer)
	    (princ " " work-buffer)
	    (prin1 (marker-position (vm-headers-of m)) work-buffer)
	    (princ " " work-buffer)
	    (prin1 (marker-position (vm-text-end-of m)) work-buffer)
	    (princ " " work-buffer)
	    (prin1 (marker-position (vm-end-of m)) work-buffer)
	    (princ "]\n" work-buffer)
	    (setq mp (cdr mp)))
	  (princ ")\n" work-buffer)
	  (princ ";; attribute list\n" work-buffer)
	  (princ "(\n" work-buffer)
	  (setq mp m-list)
	  (while mp
	    (setq m (car mp))
	    (princ "  " work-buffer)
	    (prin1 (vm-attributes-of m) work-buffer)
	    (princ "\n" work-buffer)
	    (setq mp (cdr mp)))
	  (princ ")\n" work-buffer)
	  (princ ";; cache list\n" work-buffer)
	  (princ "(\n" work-buffer)
	  (setq mp m-list)
	  (while mp
	    (setq m (car mp))
	    (princ "  " work-buffer)
	    (prin1 (vm-cached-data-of m) work-buffer)
	    (princ "\n" work-buffer)
	    (setq mp (cdr mp)))
	  (princ ")\n" work-buffer)
	  (princ ";; labels list\n" work-buffer)
	  (princ "(\n" work-buffer)
	  (setq mp m-list)
	  (while mp
	    (setq m (car mp))
	    (princ "  " work-buffer)
	    (prin1 (vm-decoded-labels-of m) work-buffer)
	    (princ "\n" work-buffer)
	    (setq mp (cdr mp)))
	  (princ ")\n" work-buffer)
	  (princ ";; retrieved POP messages\n" work-buffer)
	  (let ((p vm-pop-retrieved-messages))
	    (if (null p)
		(princ "nil\n" work-buffer)
	      (princ "(\n" work-buffer)
	      (while p
		(princ "\t" work-buffer)
		(prin1 (car p) work-buffer)
		(princ "\n" work-buffer)
		(setq p (cdr p)))
	      (princ ")\n" work-buffer)))
	  (princ ";; retrieved IMAP messages\n" work-buffer)
	  (let ((p vm-imap-retrieved-messages))
	    (if (null p)
		(princ "nil\n" work-buffer)
	      (princ "(\n" work-buffer)
	      (while p
		(princ "\t" work-buffer)
		(prin1 (car p) work-buffer)
		(princ "\n" work-buffer)
		(setq p (cdr p)))
	      (princ ")\n" work-buffer)))

	  (princ ";; end of index file\n" work-buffer)

	  (vm-inform 6 "%s: Writing index file..." (buffer-name))
	  (catch 'done
	    (with-current-buffer work-buffer
	      (condition-case data
		  (let ((coding-system-for-write (vm-binary-coding-system))
			(selective-display nil))
		    (write-region (point-min) (point-max) index-file))
		(error
		 (vm-warn 1 2 "%s: Write of %s signaled: %s" 
			  (buffer-name) index-file data)
		 (throw 'done nil))))
	    (vm-error-free-call 'set-file-modes index-file (vm-octal 600))
	    (vm-inform 6 "%s: Writing index file... done" (buffer-name))
	    t ))
      (and work-buffer (kill-buffer work-buffer)))))

(defun vm-delete-index-file ()
  (if (stringp vm-index-file-suffix)
      (let ((index-file (vm-make-index-file-name)))
	(vm-error-free-call 'delete-file index-file))))

(defun vm-change-all-new-to-unread ()
  (let ((mp vm-message-list))
    (while mp
      (if (vm-new-flag (car mp))
	  (progn
	    (vm-set-new-flag (car mp) nil)
	    (vm-set-unread-flag (car mp) t)))
      (setq mp (cdr mp)))))

;;;###autoload
(defun vm-mark-message-unread (&optional count)
  "Mark the current message as unread.  If the message is already
new or unread, then it is left unchanged.

Numeric prefix argument N means to mark the current message plus
the next N-1 messages as unread.  A negative N means mark the
current message and the previous N-1 messages as unread.

When invoked on marked messages (via `vm-next-command-uses-marks'),
all marked messages are affected, other messages are ignored.  If
applied to collapsed threads in summary and thread operations are
enabled via `vm-enable-thread-operations' then all messages in the
thread are affected."
  (interactive "p")
  (or count (setq count 1))
  (vm-follow-summary-cursor)
  (vm-select-folder-buffer-and-validate 1 (vm-interactive-p))
  (let ((mlist (vm-select-operable-messages
		count (vm-interactive-p) "Unread")))
    (while mlist
      (if (and (not (vm-unread-flag (car mlist)))
	       (not (vm-new-flag (car mlist))))
	  (vm-set-unread-flag (car mlist) t))
      (setq mlist (cdr mlist))))
  (vm-display nil nil '(vm-mark-message-unread) '(vm-mark-message-unread))
  (vm-update-summary-and-mode-line))
(defalias 'vm-unread-message 'vm-mark-message-unread)
(defalias 'vm-flag-message-unread 'vm-mark-message-unread)
(make-obsolete 'vm-flag-message-unread 
	       'vm-mark-message-unread "8.2.0")

;;;###autoload
(defun vm-mark-message-read (&optional count)
  "Mark the current message as read, i.e., set the `unread' and `new'
attributes to nil.  If the message is already marked as read, then
it is left unchanged.

Numeric prefix argument N means to unread the current message plus the
next N-1 messages.  A negative N means mark the current message and
the previous N-1 messages as read.

When invoked on marked messages (via `vm-next-command-uses-marks'),
all marked messages are affected, other messages are ignored.  If
applied to collapsed threads in summary and thread operations are
enabled via `vm-enable-thread-operations' then all messages in the
thread are affected."
  (interactive "p")
  (or count (setq count 1))
  (let ((used-marks (eq last-command 'vm-next-command-uses-marks))
        ) ;; (del-count 0)
    (vm-follow-summary-cursor)
    (vm-select-folder-buffer-and-validate 1 (vm-interactive-p))
    (let ((mlist (vm-select-operable-messages
		  count (vm-interactive-p) "Mark as read")))
      (while mlist
	(when (or (vm-unread-flag (car mlist))
		  (vm-new-flag (car mlist)))
	  (vm-set-unread-flag (car mlist) nil)
	  (vm-set-new-flag (car mlist) nil))
	(setq mlist (cdr mlist))))
    (vm-display nil nil '(vm-mark-message-read) '(vm-mark-message-read))
    (vm-update-summary-and-mode-line)
    (when (and vm-move-after-reading (not used-marks))
      (let ((vm-circular-folders (and vm-circular-folders
				      (eq vm-move-after-reading t))))
	(vm-next-message count t executing-kbd-macro)))))
(defalias 'vm-flag-message-read 'vm-mark-message-read)
(make-obsolete 'vm-flag-message-read 
	       'vm-mark-message-read "8.2.0")


;;;###autoload
(defun vm-quit-just-bury ()
  "Bury the current VM folder and its auxiliary buffers.
The folder is not altered and Emacs is still visiting it.  You
can switch back to it with switch-to-buffer or by using the
Buffer Menu."
  (interactive)
  (vm-select-folder-buffer-and-validate 0 (vm-interactive-p))
  (if (not (memq major-mode '(vm-mode vm-virtual-mode)))
      (error "%s must be invoked from a VM buffer." this-command))

  (vm--dlet ((virtual (eq major-mode 'vm-virtual-mode))
	     (no-expunge t)
	     (no-change nil))
    (save-excursion (run-hooks 'vm-quit-hook)))

  (vm-garbage-collect-message)

  (vm-display nil nil '(vm-quit-just-bury)
	      '(vm-quit-just-bury quitting))
  (if vm-summary-buffer
      (vm-display vm-summary-buffer nil nil nil))
  (if vm-summary-buffer
      (vm-bury-buffer vm-summary-buffer))
  (if vm-presentation-buffer-handle
      (vm-display vm-presentation-buffer-handle nil nil nil))
  (if vm-presentation-buffer-handle
      (vm-bury-buffer vm-presentation-buffer-handle))
  (vm-display (current-buffer) nil nil nil)
  (vm-bury-buffer (current-buffer)))

;;;###autoload
(defun vm-quit-just-iconify ()
  "Iconify the frame and bury the current VM folder and summary buffers.
The folder is not altered and Emacs is still visiting it."
  (interactive)
  (vm-select-folder-buffer-and-validate 0 (vm-interactive-p))
  (if (not (memq major-mode '(vm-mode vm-virtual-mode)))
      (error "%s must be invoked from a VM buffer." this-command))

  (vm--dlet ((virtual (eq major-mode 'vm-virtual-mode))
	     (no-expunge t)
	     (no-change nil))
    (save-excursion (run-hooks 'vm-quit-hook)))

  (vm-garbage-collect-message)

  (vm-display nil nil '(vm-quit-just-iconify)
	      '(vm-quit-just-iconify quitting))
  (let ((summary-buffer vm-summary-buffer)
	(pres-buffer vm-presentation-buffer-handle))
    (vm-bury-buffer (current-buffer))
    (if summary-buffer
	(vm-bury-buffer summary-buffer))
    (if pres-buffer
	(vm-bury-buffer pres-buffer))
    (vm-iconify-frame)))

;;;###autoload
(defun vm-quit-no-change ()
  "Quit visiting the current folder and discard any changes made to the folder."
  (interactive)
  (vm-quit t t))

;;;###autoload
(defun vm-quit-no-expunge ()
  "Quit visiting the current folder without expunging deleted
messages.  

The setting of `vm-expunge-before-quit' is ignored."
  (interactive)
  (vm-quit t nil))

(defvar dired-listing-switches)		; defined only in FSF Emacs?

;;;###autoload
(defun vm-quit (&optional no-expunge no-change)
  "Quit visiting the current folder, saving changes.  If the folder is
being visited read-only then changes are not saved.  This behavior
can be customized using `vm-preserve-read-only-folders-on-disk'.

If the customization variable `vm-expunge-before-quit' is set to
  non-nil value then deleted messages are expunged.

Giving a prefix argument overrides the variable and no expunge is
done.

When called internally, the optional argument NO-EXPUNGE says
that the deleted messages should not be expunged (irrespective of
the value of `vm-expunge-before-quit'.  NO-CHANGE says that
changes should be discarded."
  (interactive "P")
  (vm-select-folder-buffer-and-validate 0 (vm-interactive-p))
  (if (not (memq major-mode '(vm-mode vm-virtual-mode)))
      (error "%s must be invoked from a VM buffer." this-command))
  (vm-display nil nil '(vm-quit vm-quit-no-change vm-quit-no-expunge)
	      (list this-command 'quitting))
  (if (and vm-folder-read-only vm-preserve-read-only-folders-on-disk)
      (setq no-change t))
  (let ((virtual (eq major-mode 'vm-virtual-mode))
	(process nil))

    ;; 1. Save folder if necessary
    ;; Why are we saving before expunging?  USR, 2012-11-12
    (unless (or virtual
		(and vm-folder-read-only vm-preserve-read-only-folders-on-disk))
      (cond
       ((and no-change (buffer-modified-p)
	     (or buffer-file-name buffer-offer-save)
	     (not (zerop vm-messages-not-on-disk))
	     ;; Folder may have been saved with C-x C-s and attributes may have
	     ;; been changed after that; in that case vm-messages-not-on-disk
	     ;; would not have been zeroed.  However, all modification flag
	     ;; undos are cleared if VM actually modifies the folder buffer
	     ;; (as opposed to the folder's attributes), so this can be used
	     ;; to verify that there are indeed unsaved messages.
	     (null (assq 'vm-set-buffer-modified-p vm-undo-record-list))
	     (not
	      (y-or-n-p
	       (format
		"%s: %d message%s have not been saved to disk, quit anyway? "
		(buffer-name)
		vm-messages-not-on-disk
		(if (= 1 vm-messages-not-on-disk) "" "s")))))
	(error "Aborted"))
       ((and no-change
	     (or buffer-file-name buffer-offer-save)
	     (buffer-modified-p)
	     vm-confirm-quit
	     (not (y-or-n-p 
		   (format "%s: There are unsaved changes, quit anyway?  "
			   (buffer-name)))))
	(error "Aborted"))
       ((and (eq vm-confirm-quit t)
	     (not (y-or-n-p 
		   (format "%s: Do you really want to quit? "
			   (buffer-name)))))
	(error "Aborted"))))

    ;; 2. Run vm-quit-hook
    (save-excursion (run-hooks 'vm-quit-hook))

    ;; 3. Expunge folder if necessary
    (when vm-expunge-before-quit
      (unless (or virtual
		  no-expunge
		  no-change
		  (not (buffer-modified-p)))
	(vm-expunge-folder)))

    (vm-garbage-collect-message)
    (vm-garbage-collect-folder)

    ;; 4. Save folder if necessary
    (unless (or no-change virtual)
      ;; this could take a while, so give the user some feedback
      (vm-inform 5 "%s: Quitting..." (buffer-name))
      (unless (or vm-folder-read-only (eq major-mode 'vm-virtual-mode))
	(vm-change-all-new-to-unread)))
    (when (and (buffer-modified-p)
	       (or buffer-file-name buffer-offer-save)
	       (not no-change)
	       (not virtual))
      (vm-save-folder))

    ;; 5. Handle virtual folders
    ;;    If this is a virtual folder with component folders, quit the
    ;;    component folders.
    ;;    If there are virtual folders dependent on this one, clear away
    ;;    their virtual copies.
    (vm-virtual-quit no-expunge no-change)

    ;; 6. Kill the folder along with its buffers and processes
    (cond ((and (eq vm-folder-access-method 'pop)
		(setq process (vm-folder-pop-process)))
	   (vm-pop-end-session process))
	  ((and (eq vm-folder-access-method 'imap)
		(setq process (vm-folder-imap-process)))
	   (vm-imap-end-session process))
	  )
    (message "")			; why this?  USR, 2010-05-03

    (let ((summary-buffer vm-summary-buffer)
	  (pres-buffer vm-presentation-buffer-handle)
	  (mail-buffer (current-buffer)))
      (if summary-buffer
	  (progn
	    (vm-display summary-buffer nil nil nil)
	    (kill-buffer summary-buffer)))
      (if pres-buffer
	  (progn
	    (vm-display pres-buffer nil nil nil)
	    (kill-buffer pres-buffer)))
      (set-buffer mail-buffer)
      (vm-display mail-buffer nil nil nil)
      ;; vm-display is not supposed to change the current buffer.
      ;; still it's better to be safe here.
      (set-buffer mail-buffer)
      ;; if folder is selected in the folders summary, force
      ;; selcetion of some other folder.
      (if buffer-file-name
	  (vm-mark-for-folders-summary-update buffer-file-name))
      (vm-delete-auto-save-file-if-necessary)
      ;; this is a hack to suppress another confirmation dialogue
      ;; coming from kill-buffer
      (set-buffer-modified-p nil)	; folder buffer
      (kill-buffer (current-buffer)))
    (vm-update-summary-and-mode-line)))

(defun vm-start-itimers-if-needed ()
  (cond ((and (not (natnump vm-flush-interval))
	      (not (natnump vm-auto-get-new-mail))
	      (not (natnump vm-mail-check-interval))))
	((condition-case _data
	     (progn (require 'itimer) t)
	   (error nil))
	 (when (and (natnump vm-flush-interval) (not (get-itimer "vm-flush")))
	   ;; name function time restart-time
	   ;; ...... idle with-args args
	   (start-itimer "vm-flush" 'vm-flush-itimer-function
			 vm-flush-interval nil))
	 (when (and (natnump vm-auto-get-new-mail)
		    (not (get-itimer "vm-get-mail")))
	   (start-itimer "vm-get-mail" 'vm-get-mail-itimer-function
			 vm-auto-get-new-mail nil))
	 (when (and (natnump vm-mail-check-interval)
		    (not (get-itimer "vm-check-mail")))
	   (start-itimer "vm-check-mail" 'vm-check-mail-itimer-function
			 vm-mail-check-interval nil)))
	((condition-case _data
	     (progn (require 'timer) t)
	   (error nil))
	 (let (timer)
	   (when (and (natnump vm-flush-interval)
		      (not (vm-timer-using 'vm-flush-itimer-function))
		      (setq timer 
			    ;; time restart-time function args
			    (run-at-time vm-flush-interval vm-flush-interval
					 'vm-flush-itimer-function nil)))
	     (timer-set-function timer 'vm-flush-itimer-function
				 (list timer)))
	   (when (and (natnump vm-mail-check-interval)
		      (not (vm-timer-using 'vm-check-mail-itimer-function))
		      (setq timer 
			    (run-at-time vm-mail-check-interval
					 vm-mail-check-interval
					 'vm-check-mail-itimer-function nil)))
	     (timer-set-function timer 'vm-check-mail-itimer-function
				 (list timer)))
	   (when (and (natnump vm-auto-get-new-mail)
		      (not (vm-timer-using 'vm-get-mail-itimer-function))
		      (setq timer 
			    (run-at-time vm-auto-get-new-mail
					 vm-auto-get-new-mail
					 'vm-get-mail-itimer-function nil)))
	     (timer-set-function timer 'vm-get-mail-itimer-function
				 (list timer)))))
	(t
	 (setq vm-flush-interval t
	       vm-auto-get-new-mail t))))

(defvar timer-list)
(defun vm-timer-using (fun)
  (let ((p timer-list)
	(done nil))
    (while (and p (not done))
      (if (eq (aref (car p) 5) fun)
	  (setq done t)
	(setq p (cdr p))))
    p ))

(defvar current-itimer)

;; support for vm-mail-check-interval
;; if timer argument is present, this means we're using the Emacs
;; 'timer package rather than the 'itimer package.
(defun vm-check-mail-itimer-function (&optional timer)
  ;; FSF Emacs sets this non-nil, which means the user can't
  ;; interrupt the check.  Bogus.
  (setq inhibit-quit nil)
  (if (integerp vm-mail-check-interval)
      (if timer
	  (timer-set-time 
	   timer 
	   (timer-relative-time (current-time) vm-mail-check-interval)
	   vm-mail-check-interval)
	(set-itimer-restart current-itimer vm-mail-check-interval))
    ;; user has changed the variable value to something that
    ;; isn't a number, make the timer go away.
    (if timer
	(cancel-timer timer)
      (set-itimer-restart current-itimer nil)))
  (let ((b-list (buffer-list))
	(found-one nil)
	oldval)
    (save-excursion
      (while (and (not (input-pending-p)) b-list)
	(when (buffer-live-p (car b-list))
	  (set-buffer (car b-list))
	  (when (and (eq major-mode 'vm-mode)
		     (setq found-one t)
		     (or (not vm-spooled-mail-waiting)
			 vm-mail-check-always)
		     ;; to avoid reentrance into the pop and imap code
		     (not vm-global-block-new-mail))
	    (setq oldval vm-spooled-mail-waiting)
	    (setq vm-spooled-mail-waiting (vm-check-for-spooled-mail nil t))
	    (unless (eq oldval vm-spooled-mail-waiting)
	      (intern (buffer-name) vm-buffers-needing-display-update)
	      (run-hooks 'vm-spooled-mail-waiting-hook))))
	(setq b-list (cdr b-list))))
    (vm-update-summary-and-mode-line)
    ;; make the timer go away if we didn't encounter a vm-mode buffer.
    (when (and (not found-one) (null b-list))
      (if timer
	  (cancel-timer timer)
	(set-itimer-restart current-itimer nil)))))

;; support for numeric vm-auto-get-new-mail
;; if timer argument is present, this means we're using the Emacs
;; 'timer package rather than the 'itimer package.
(defun vm-get-mail-itimer-function (&optional timer)
  ;; FSF Emacs sets this non-nil, which means the user can't
  ;; interrupt mail retrieval.  Bogus.
  (setq inhibit-quit nil)
  (if (integerp vm-auto-get-new-mail)
      (if timer
	  (timer-set-time 
	   timer
	   (timer-relative-time (current-time) vm-auto-get-new-mail)
	   vm-auto-get-new-mail)
	(set-itimer-restart current-itimer vm-auto-get-new-mail))
    ;; user has changed the variable value to something that
    ;; isn't a number, make the timer go away.
    (if timer
	(cancel-timer timer)
      (set-itimer-restart current-itimer nil)))
  (let ((b-list (buffer-list))
	(found-one nil))
    (while (and (not (input-pending-p)) b-list)
      (save-excursion
	(when (buffer-live-p (car b-list))
	  (set-buffer (car b-list))
	  (when (and (eq major-mode 'vm-mode)
		     (setq found-one t)
		     (not vm-global-block-new-mail)
		     (not vm-block-new-mail)
		     (not vm-folder-read-only)
		     (not (and (not (buffer-modified-p))
			       buffer-file-name
			       (file-newer-than-file-p
				(make-auto-save-file-name)
				buffer-file-name)))
		     (vm-get-spooled-mail nil))
	    ;; don't move the message pointer unless the folder
	    ;; was empty.
	    (if (and (null vm-message-pointer)
		     (vm-thoughtfully-select-message))
		(vm-present-current-message)
	      (vm-update-summary-and-mode-line)))))
      (setq b-list (cdr b-list)))
    ;; make the timer go away if we didn't encounter a vm-mode buffer.
    (when (and (not found-one) (null b-list))
      (if timer
	  (cancel-timer timer)
	(set-itimer-restart current-itimer nil)))))

;; support for numeric vm-flush-interval
;; if timer argument is present, this means we're using the Emacs
;; 'timer package rather than the 'itimer package.
(defun vm-flush-itimer-function (&optional timer)
  (when (integerp vm-flush-interval)
    (if timer
	(timer-set-time 
	 timer
	 (timer-relative-time (current-time) vm-flush-interval)
	 vm-flush-interval)
      (set-itimer-restart current-itimer vm-flush-interval)))
  ;; if no vm-mode buffers are found, we might as well shut down the
  ;; flush itimer.
  (unless (vm-flush-cached-data-all-folders)
    (if timer
	(cancel-timer timer)
      (set-itimer-restart current-itimer nil))))

;; flush cached data in all vm-mode buffers.
;; returns non-nil if any vm-mode buffers were found.
(defun vm-flush-cached-data-all-folders ()
  "Put the cached data for all folders into the X-VM-v5-data headers.
This function is only used in background tasks.  USR 2012-12-22."
  (save-excursion
    (let ((buf-list (buffer-list))
	  (found-one nil))
      (while (and buf-list (not (input-pending-p)))
	(if (not (buffer-live-p (car buf-list)))
	    nil
	  (set-buffer (car buf-list))
	  (cond ((and (eq major-mode 'vm-mode) vm-message-list)
		 (setq found-one t)
		 (if (not (eq vm-modification-counter
			      vm-flushed-modification-counter))
		     (progn
		       (vm-stuff-last-modified)
		       (vm-stuff-pop-retrieved)
		       (vm-stuff-imap-retrieved)
		       (vm-stuff-summary)
		       (vm-stuff-labels)
		       (and vm-message-order-changed
			    (vm-stuff-message-order))
		       (and (vm-stuff-folder-data
			     :interactive nil
			     :abort-if-input-pending t)
			    (setq vm-flushed-modification-counter
				  vm-modification-counter)))))))
	(setq buf-list (cdr buf-list)))
      ;; if we haven't checked them all return non-nil so
      ;; the flusher won't give up trying.
      (or buf-list found-one) )))

;; This allows C-x C-s to do the right thing for VM mail buffers.
;; Note that deleted messages are not expunged.
(defun vm-write-file-hook ()
  (if (and (eq major-mode 'vm-mode) (not vm-inhibit-write-file-hook))
    ;; The save-restriction isn't really necessary here, since
    ;; the stuff routines clean up after themselves, but should remain
    ;; as a safeguard against the time when other stuff is added here.
    (save-restriction
     (let ((buffer-read-only))
       (vm-discard-fetched-messages)
       (vm-inform 7 "%s: Stuffing cached data..." (buffer-name))
       (vm-stuff-folder-data :interactive t :abort-if-input-pending nil)
       (vm-inform 7 "%s: Stuffing cached data... done" (buffer-name))
       (when vm-message-list
	 (when (and vm-folders-summary-database buffer-file-name)
	   (vm-compute-totals)
	   (vm-store-folder-totals buffer-file-name (cdr vm-totals)))
	 ;; get summary cache up-to-date
	 (vm-inform 8 "%s: Stuffing folder data..." (buffer-name))
	 (vm-update-summary-and-mode-line)
	 (vm-stuff-bookmark)
	 (vm-stuff-pop-retrieved)
	 (vm-stuff-imap-retrieved)
	 (vm-stuff-last-modified)
	 (vm-stuff-header-variables)
	 (vm-stuff-labels)
	 (vm-stuff-summary)
	 (when vm-message-order-changed
	   (vm-stuff-message-order))
	 (vm-inform 8 "%s: Stuffing folder data... done" (buffer-name)))
       nil ))))

;;;###autoload
(defun vm-save-buffer (prefix)
  ;; This function hasn't been documented.  Not clear why it is
  ;; different from vm-save-folder.  USR, 2011-04-27
  (interactive "P")
  (vm-select-folder-buffer-and-validate 0 (vm-interactive-p))
  (vm-error-if-virtual-folder)
  ;; FIXME Why not basic-save-buffer?
  (save-buffer prefix)
  (intern (buffer-name) vm-buffers-needing-display-update)
  (setq vm-block-new-mail nil)
  (vm-display nil nil '(vm-save-buffer) '(vm-save-buffer))
  (if (and vm-folders-summary-database buffer-file-name)
      (progn
	(vm-compute-totals)
	(vm-store-folder-totals buffer-file-name (cdr vm-totals))))
  (vm-update-summary-and-mode-line)
  (vm-write-index-file-maybe))

;;;###autoload
(defun vm-write-file ()
  ;; This function hasn't been documented.  Not clear what it does.
  ;; 						  USR, 2011-04-27
  (interactive)
  (vm-select-folder-buffer-and-validate 0 (vm-interactive-p))
  (vm-error-if-virtual-folder)
  (let ((old-buffer-name (buffer-name))
	(oldmodebits (and (fboundp 'default-file-modes)
			  (default-file-modes))))
    (unwind-protect
	(save-excursion
	  (and oldmodebits (set-default-file-modes
			    vm-default-folder-permission-bits))
	  (call-interactively 'write-file))
      (and oldmodebits (set-default-file-modes oldmodebits)))
    (if (and vm-folders-summary-database buffer-file-name)
	(progn
	  (vm-compute-totals)
	  (vm-store-folder-totals buffer-file-name (cdr vm-totals))))
    (if (not (equal (buffer-name) old-buffer-name))
	(progn
	  (vm-check-for-killed-summary)
	  (if vm-summary-buffer
	      (save-excursion
		(let ((name (buffer-name)))
		  (set-buffer vm-summary-buffer)
		  (rename-buffer (format "%s Summary" name) t))))
	  (vm-check-for-killed-presentation)
	  (if vm-presentation-buffer-handle
	      (save-excursion
		(let ((name (buffer-name)))
		  (set-buffer vm-presentation-buffer-handle)
		  (rename-buffer (format "%s Presentation" name) t)))))))
  (intern (buffer-name) vm-buffers-needing-display-update)
  (setq vm-block-new-mail nil)
  (vm-display nil nil '(vm-write-file) '(vm-write-file))
  (vm-update-summary-and-mode-line)
  (vm-write-index-file-maybe))

(defun vm-unblock-new-mail ()
  (setq vm-block-new-mail nil))

;;;###autoload
(defun vm-save-folder-no-expunge (&optional prefix)
  "Save current folder to disk.
Prefix arg is handled the same as for the command `save-buffer'.  

Deleted messages are _not_ expunged irrespective of the variable
`vm-expunge-before-save'.

When applied to a virtual folder, this command runs itself on
each of the underlying real folders associated with the virtual
folder."
  (interactive (list current-prefix-arg))
  (let ((vm-expunge-before-save nil))
    (vm-save-folder prefix)))


;;;###autoload
(defun vm-save-folder (&optional prefix)
  "Save current folder to disk.
Prefix arg is handled the same as for the command `save-buffer'.

If the customization variable `vm-expunge-before-save' is set to
non-nil value then deleted messages are expunged.

When applied to a virtual folder, this command runs itself on
each of the underlying real folders associated with the virtual
folder."
  (interactive (list current-prefix-arg))
  (vm-select-folder-buffer-and-validate 0 (vm-interactive-p))
  (vm-display nil nil '(vm-save-folder) '(vm-save-folder))
  (if (eq major-mode 'vm-virtual-mode)
      (vm-virtual-save-folder prefix)
    (if (buffer-modified-p)
	(let ((buffer-undo-list t)) ;; (mp nil) (newlist nil)
	  (when vm-expunge-before-save
	    (vm-expunge-folder))
	  (cond ((eq vm-folder-access-method 'pop)
		 (vm-pop-synchronize-folder :interactive t 
					    :do-remote-expunges t 
					    :do-local-expunges t 
					    :do-retrieves nil))
		((eq vm-folder-access-method 'imap)
		 (vm-imap-synchronize-folder :interactive t 
					     :do-remote-expunges t 
					     :do-local-expunges t 
					     :do-retrieves nil
					     :save-attributes t)))
	  (vm-discard-fetched-messages)
          ;; remove the message summary file of Thunderbird and force
	  ;; it to rebuild it.  Expect error if Thunderbird is active.
          (let ((msf (concat buffer-file-name ".msf")))
            (if (and (eq vm-sync-thunderbird-status t)
		     (file-exists-p msf))
                (delete-file msf)))
	  ;; stuff the attributes of messages that need it.
	  (vm-inform 7 "%s: Stuffing cached data..." (buffer-name))
	  (vm-stuff-folder-data :interactive t 
				:abort-if-input-pending nil)
	  (vm-inform 7 "%s: Stuffing cached data... done" (buffer-name))
	  ;; stuff bookmark and header variable values
	  (when vm-message-list
	    ;; get summary cache up-to-date
	    (vm-inform 7 "%s: Stuffing folder data..." (buffer-name))
	    (vm-update-summary-and-mode-line)
	    (vm-stuff-bookmark)
	    (vm-stuff-pop-retrieved)
	    (vm-stuff-imap-retrieved)
	    (vm-stuff-last-modified)
	    (vm-stuff-header-variables)
	    (vm-stuff-labels)
	    (vm-stuff-summary)
	    (and vm-message-order-changed
		 (vm-stuff-message-order))
	    (vm-inform 7 "%s: Stuffing folder data... done" (buffer-name)))
	  (vm-inform 5 "%s: Saving folder..." (buffer-name))
	  (let ((vm-inhibit-write-file-hook t)
		(oldmodebits (and (fboundp 'default-file-modes)
				  (default-file-modes))))
	    (unwind-protect
		(progn
		  (and oldmodebits (set-default-file-modes
				    vm-default-folder-permission-bits))
		  ;; FIXME Why not basic-save-buffer?
		  (save-buffer prefix))
	      (and oldmodebits (set-default-file-modes oldmodebits))))
	  (vm-unmark-folder-modified-p (current-buffer)) ; folder buffer
	  ;; clear the modified flag in virtual folders if all the
	  ;; real buffers associated with them are unmodified.
	  (let ((b-list vm-virtual-buffers) rb-list one-modified)
	    (save-excursion
	      (while b-list
		(if (null (cdr (with-current-buffer (car b-list)
				 vm-real-buffers)))
		    (vm-unmark-folder-modified-p (car b-list))
		  (set-buffer (car b-list))
		  (setq rb-list vm-real-buffers one-modified nil)
		  (while rb-list
		    (if (buffer-modified-p (car rb-list))
			(setq one-modified t rb-list nil)
		      (setq rb-list (cdr rb-list))))
		  (if (not one-modified)
		      (vm-unmark-folder-modified-p (car b-list))))
		(setq b-list (cdr b-list)))))
	  (vm-clear-modification-flag-undos)
	  (setq vm-messages-not-on-disk 0)
	  (setq vm-block-new-mail nil)
	  (vm-write-index-file-maybe)
	  (if (and vm-folders-summary-database buffer-file-name)
	      (progn
		(vm-compute-totals)
		(vm-store-folder-totals buffer-file-name (cdr vm-totals))))
	  (vm-update-summary-and-mode-line)
	  (and (zerop (buffer-size))
	       vm-delete-empty-folders
	       buffer-file-name
	       (or (eq vm-delete-empty-folders t)
		   (y-or-n-p (format "%s is empty, remove it? "
				     (or buffer-file-name (buffer-name)))))
	       (condition-case ()
		   (progn
		     (delete-file buffer-file-name)
		     (vm-delete-index-file)
		     (clear-visited-file-modtime)
		     (vm-inform 5 "%s removed" buffer-file-name))
		 ;; no can do, oh well.
		 (error nil)))
	  )
      (vm-inform 5 "%s: No changes need to be saved" (buffer-name)))))

;;;###autoload
(defun vm-save-and-expunge-folder (&optional prefix)
  "Expunge folder, then save it to disk.
Prefix arg is handled the same as for the command `save-buffer'.
Expunge won't be done if folder is read-only.

When applied to a virtual folder, this command works as if you had
run `vm-expunge-folder' followed by `vm-save-folder'."
  (interactive (list current-prefix-arg))
  (vm-select-folder-buffer-and-validate 0 (vm-interactive-p))
  (vm-display nil nil '(vm-save-and-expunge-folder)
	      '(vm-save-and-expunge-folder))
  (if (not vm-folder-read-only)
      (progn
	(vm-inform 6 "%s: Expunging..." (buffer-name))
	(vm-expunge-folder :quiet t)))
  (vm-save-folder prefix))

(defvar inhibit-local-variables) ;; FIXME: Unknown var.  XEmacs, maybe?

;;;###autoload
(defun vm-read-folder (folder &optional remote-spec folder-name)
  "Reads the FOLDER from the file system and creates a buffer.
Returns the buffer created.
Optional argument REMOTE-SPEC gives the maildrop specification for
the server folder that the FOLDER might be caching.
Optional argument FOLDER-NAME gives the name of the folder that should
be used as the name of the buffer."
  ;; Security issue:
  ;; set inhibit-local-variables non-nil to protect
  ;; against letter bombs.
  ;; set enable-local-variables to nil for newer Emacses
  (let ((file (or folder (expand-file-name vm-primary-inbox
					   vm-folder-directory))))
    (if (file-directory-p file)
	;; MH code perhaps... ?
	(error "%s is a directory" file)
      (or (vm-get-file-buffer file)
	  (let ((default-directory
		  (or (and vm-folder-directory
			   (expand-file-name vm-folder-directory))
		      default-directory))
		(inhibit-local-variables t)
		(enable-local-variables nil)
		(enable-local-eval nil)
		;; for Emacs/MULE
		;; disabled because Emacs 23 doesn't like it, and it
		;; is not clear if it does anything at all.  USR, 2010-07-10.
		;; The only place this function is called from is vm,
		;; which takes care of multibyte issues.  TX, 2010-07-03
		;; (default-enable-multibyte-characters nil)

		;; for XEmacs/Mule
		(coding-system-for-read
		 (vm-line-ending-coding-system)))
	    (vm-inform 5 "%s: Reading folder..." (or folder-name file))
	    (let ((buffer (find-file-noselect file t))
		  (hist-item (or remote-spec folder vm-primary-inbox)))
	      (when folder-name
		(with-current-buffer buffer
		  (rename-buffer folder-name t)))
	      ;; update folder history
	      (if (not (equal hist-item (car vm-folder-history)))
		    (setq vm-folder-history
			  (cons hist-item vm-folder-history)))
	      (vm-inform 5 "%s: Reading folder... done" (or folder-name file))
	      buffer))))))

;;;###autoload
(defun vm-revert-buffer ()
"Revert the current folder to its version on the disk.
Same as \\[vm-revert-folder]."
  (interactive)
  (vm-select-folder-buffer-if-possible)
  (let ((access-method vm-folder-access-method) ; preserve these across
	(access-data vm-folder-access-data)	; the revert-buffer opn
	(summary-buffer vm-summary-buffer)
	(pres-buffer vm-presentation-buffer-handle))
    (if summary-buffer
	(progn
	  (vm-display summary-buffer nil nil nil)
	  (kill-buffer summary-buffer)))
    (if pres-buffer
	(progn
	  (vm-display pres-buffer nil nil nil)
	  (kill-buffer pres-buffer)))
    (call-interactively 'revert-buffer)
    (setq vm-folder-access-data access-data) ; restore preserved data
    (setq vm-folder-access-method access-method)
    (vm (current-buffer) :access-method access-method :reload 'reload)))

(defalias 'vm-revert-folder 'vm-revert-buffer)

;;;###autoload
(defun vm-recover-file ()
"Recover the autosave file for the current folder. 
Same as \\[vm-recover-folder]."
  (interactive)
  (vm-select-folder-buffer-if-possible)
  (let ((access-method vm-folder-access-method) ; preserve these across
	(access-data vm-folder-access-data)	; the recover-file opn.
	(summary-buffer vm-summary-buffer)
	(pres-buffer vm-presentation-buffer-handle))
    (if summary-buffer
	(progn
	  (vm-display summary-buffer nil nil nil)
	  (kill-buffer summary-buffer)))
    (if pres-buffer
	(progn
	  (vm-display pres-buffer nil nil nil)
	  (kill-buffer pres-buffer)))
    (call-interactively 'recover-file)
    (setq vm-folder-access-method access-method)
    (setq vm-folder-access-data access-data) ; restore data
    (vm (current-buffer) :access-method access-method :reload 'reload)))

(defalias 'vm-recover-folder 'vm-recover-file)

;; It doesn't seem that any of these recover/reversion handlers are
;; working any more.  Not on GNU Emacs.  USR, 2010-01-23

(defun vm-handle-file-recovery-or-reversion (recovery)
  (if (buffer-live-p vm-summary-buffer)
      (kill-buffer vm-summary-buffer))
  (vm-virtual-quit)
  ;; reset major mode, this will cause vm to start from scratch.
  (setq major-mode 'fundamental-mode)
  ;; If this is a recovery, we can't allow the user to get new
  ;; mail until a real save is performed.  Until then the buffer
  ;; and the disk don't match.
  (if recovery
      (setq vm-block-new-mail t))
  (let ((name (cond ((eq vm-folder-access-method 'pop)
		     (vm-pop-find-name-for-buffer (current-buffer)))
		    ((eq vm-folder-access-method 'imap)
		     (vm-imap-find-spec-for-buffer (current-buffer))))))
    (vm (or name buffer-file-name) :access-method vm-folder-access-method)))

;; detect if a recover-file is being performed
;; and handle things properly.
(defun vm-handle-file-recovery ()
  (if (and (buffer-modified-p)
	   (eq major-mode 'vm-mode)
	   (or (null vm-message-list)
	       (= (vm-end-of (car vm-message-list)) 1)))
      (vm-handle-file-recovery-or-reversion t)))

;; detect if a revert-buffer is being performed
;; and handle things properly.
(defun vm-handle-file-reversion ()
  (if (and (not (buffer-modified-p))
	   (eq major-mode 'vm-mode)
	   (or (null vm-message-list)
	       (= (vm-end-of (car vm-message-list)) 1)))
      (vm-handle-file-recovery-or-reversion nil)))

;; FSF v19.23 revert-buffer doesn't mash all the markers together
;; like v18 and prior v19 versions, so the check in
;; vm-handle-file-reversion doesn't work.  However v19.23 has a
;; hook we can use, after-revert-hook.
(defun vm-after-revert-buffer-hook ()
  (if (eq major-mode 'vm-mode)
      (vm-handle-file-recovery-or-reversion nil)))

;;;###autoload
(defun vm-help ()
  "Display help for various VM activities."
  (interactive)
  (if (eq major-mode 'vm-summary-mode)
      (vm-select-folder-buffer-and-validate 0 (vm-interactive-p)))
  (let ((pop-up-windows (and pop-up-windows 
			     (eq vm-mutable-window-configuration t)))
	(pop-up-frames (and vm-mutable-frame-configuration vm-frame-per-help)))
    (cond
     ((eq last-command 'vm-help)
      (describe-function major-mode))
     ((eq vm-system-state 'previewing)
      (vm-inform 0 "Type SPC to read message, n previews next message   (? gives more help)"))
     ((memq vm-system-state '(showing reading))
      (vm-inform 0 "SPC and b scroll, (d)elete, (s)ave, (n)ext, (r)eply   (? gives more help)"))
     ((eq vm-system-state 'editing)
      (vm-inform 0
       (substitute-command-keys
	"Type \\[vm-edit-message-end] to end edit, \\[vm-edit-message-abort] to abort with no change.")))
     ((eq major-mode 'mail-mode)
      (vm-inform 0
       (substitute-command-keys
	"Type \\[vm-mail-send-and-exit] to send message, \\[kill-buffer] to discard this composition")))
     (t (describe-mode)))))

;;;###autoload
(defun vm-spool-move-mail (source destination)
  (let ((handler (and (fboundp 'find-file-name-handler)
		      (find-file-name-handler source 'vm-spool-move-mail)))
	status error-buffer)
    (if handler
	(funcall handler 'vm-spool-move-mail source destination)
      (setq error-buffer
	    (get-buffer-create
	     (format "*output of %s %s %s*"
		     vm-movemail-program source destination)))
      (with-current-buffer error-buffer
	(erase-buffer))
      (setq status
	    (apply 'call-process
		   (nconc
		    (list vm-movemail-program nil error-buffer t)
		    (copy-sequence vm-movemail-program-switches)
		    (list source destination))))
      (save-current-buffer
	(set-buffer error-buffer)
	(if (and (numberp status) (not (= 0 status)))
	    (insert (format "\n%s exited with code %s\n"
			    vm-movemail-program status)))
	(if (> (buffer-size) 0)
	    (progn
	      (vm-display-buffer error-buffer)
	      (if (and (numberp status) (not (= 0 status)))
		  (error "Failed getting new mail from %s" source)
		(vm-warn 1 2 "Warning: unexpected output from %s"
			 vm-movemail-program)))
	  ;; nag, nag, nag.
	  (kill-buffer error-buffer))
	t ))))

(defun vm-gobble-crash-box (crash-box)
  (save-excursion
    (save-restriction
     (widen)
     (let ((opoint-max (point-max)) crash-buf
	   (buffer-read-only nil)
	   (inbox-buffer-file buffer-file-name)
	   (inbox-folder-type vm-folder-type)
	   (inbox-empty (zerop (buffer-size)))
	   got-mail crash-folder-type
	   (old-buffer-modified-p (buffer-modified-p)))
       (setq crash-buf
	     ;; crash box could contain a letter bomb...
	     ;; force user notification of file variables for v18 Emacses
	     ;; enable-local-variables == nil disables them for newer Emacses
	     (let ((inhibit-local-variables t)
		   (enable-local-variables nil)
		   (enable-local-eval nil)
		   (coding-system-for-read (vm-line-ending-coding-system)))
	       (find-file-noselect crash-box)))
       (if (eq (current-buffer) crash-buf)
	   (error "folder is the same file as crash box, cannot continue"))
       (with-current-buffer crash-buf
	 (setq crash-folder-type (vm-get-folder-type))
	 (if (and crash-folder-type vm-check-folder-types)
	     (cond ((eq crash-folder-type 'unknown)
		    (error "crash box %s's type is unrecognized" crash-box))
		   ((eq inbox-folder-type 'unknown)
		    (error "inbox %s's type is unrecognized"
			   inbox-buffer-file))
		   ((null inbox-folder-type)
		    (if vm-default-folder-type
			(if (not (eq vm-default-folder-type
				     crash-folder-type))
			    (if vm-convert-folder-types
				(progn
				  (vm-convert-folder-type
				   crash-folder-type
				   vm-default-folder-type)
				  ;; so that kill-buffer won't ask a
				  ;; question later...
				  (set-buffer-modified-p nil)) ; crash-buf
			      (error "crash box %s mismatches vm-default-folder-type: %s, %s"
				     crash-box crash-folder-type
				     vm-default-folder-type)))))
		   ((not (eq inbox-folder-type crash-folder-type))
		    (if vm-convert-folder-types
			(progn
			  (vm-convert-folder-type crash-folder-type
						  inbox-folder-type)
			  ;; so that kill-buffer won't ask a
			  ;; question later...
			  (set-buffer-modified-p nil)) ; crash-buf
		      (error "crash box %s mismatches %s's folder type: %s, %s"
			     crash-box inbox-buffer-file
			     crash-folder-type inbox-folder-type)))))
	 ;; toss the folder header if the inbox is not empty
	 (goto-char (point-min))
	 (if (not inbox-empty)
	     (vm-convert-folder-header (or inbox-folder-type
					   vm-default-folder-type)
				       nil)
	   (set-buffer-modified-p nil))) ; crash-buf
       (goto-char (point-max))
       (insert-buffer-substring crash-buf
				1 (1+ (with-current-buffer crash-buf
					(widen)
					(buffer-size))))
       (setq got-mail (/= opoint-max (point-max)))
       (if (not got-mail)
	   nil
	 (let ((coding-system-for-write (vm-binary-coding-system))
	       (selective-display nil))
	   (write-region opoint-max (point-max) buffer-file-name t t))
	 (vm-increment vm-modification-counter)
	 (vm-restore-buffer-modified-p	; folder-buffer
	  old-buffer-modified-p (current-buffer)))
       (kill-buffer crash-buf)
       (if (not (stringp vm-keep-crash-boxes))
	   (vm-error-free-call 'delete-file crash-box)
	 (let ((time (decode-time (current-time)))
	       name)
	   (setq name
		 (expand-file-name (format "Z-%02d-%02d-%02d%02d%02d-%05d"
					   (nth 4 time)
					   (nth 3 time)
					   (nth 2 time)
					   (nth 1 time)
					   (nth 0 time)
					   (% (vm-abs (random)) 100000))
				   vm-keep-crash-boxes))
	   (while (file-exists-p name)
	     (setq name
		   (expand-file-name (format "Z-%02d-%02d-%02d%02d%02d-%05d"
					     (nth 4 time)
					     (nth 3 time)
					     (nth 2 time)
					     (nth 1 time)
					     (nth 0 time)
					     (% (vm-abs (random)) 100000))
				     vm-keep-crash-boxes)))
	   (rename-file crash-box name)))
       got-mail ))))

(defun vm-compute-spool-files (&optional all)
  (let ((fallback-triples nil)
	(crash-box (or vm-crash-box
		       (concat vm-primary-inbox vm-crash-box-suffix)))
	file file-list
	triples)
    (cond ((null (vm-spool-files))
	   (setq triples (list
			  (list vm-primary-inbox
				(concat vm-spool-directory (user-login-name))
				crash-box))))
	  ((stringp (car (vm-spool-files)))
	   (setq triples
		 (mapcar (function
			  (lambda (s) (list vm-primary-inbox s crash-box)))
			 (vm-spool-files))))
	  ((consp (car (vm-spool-files)))
	   (setq triples (vm-spool-files))))
    (setq file-list (if all (mapcar 'car triples) (list buffer-file-name)))
    (while file-list
      (setq file (car file-list))
      (setq file-list (cdr file-list))
      (cond ((and file
		  (consp vm-spool-file-suffixes)
		  (stringp vm-crash-box-suffix))
	     (setq fallback-triples
		   (mapcar (function
			    (lambda (suffix)
			      (list file
				    (concat file suffix)
				    (concat file
					    vm-crash-box-suffix))))
			   vm-spool-file-suffixes))))
      (cond ((and file
		  vm-make-spool-file-name vm-make-crash-box-name)
	     (setq fallback-triples
		   (nconc fallback-triples
			  (list (list file
				      (save-excursion
					(funcall vm-make-spool-file-name
						 file))
				      (save-excursion
					(funcall vm-make-crash-box-name
						 file)))))))))
    (setq triples (append triples fallback-triples))
    triples ))

(defun vm-spool-check-mail (source)
  (let ((handler (find-file-name-handler source 'vm-spool-check-mail)))
    (if handler
	(funcall handler 'vm-spool-check-mail source)
      (let ((size (nth 7 (file-attributes source)))
	    (hash vm-spool-file-message-count-hash)
	    val)
	(setq val (symbol-value (intern-soft source hash)))
	(if (and val (equal size (car val)))
	    (> (nth 1 val) 0)
	  (let ((count (vm-count-messages-in-file source)))
	    (if (null count)
		nil
	      (set (intern source hash) (list size count))
	      (vm-store-folder-totals source (list count 0 0 0))
	      (> count 0))))))))

(defun vm-count-messages-in-file (file &optional quietly)
  (let ((type (vm-get-folder-type file nil nil t))
	(work-buffer nil)
	count)
    (if (or (memq type '(unknown nil)) (null vm-grep-program))
	nil
      (unwind-protect
	  (let (regexp)
	    (save-excursion
	      (setq work-buffer (vm-make-work-buffer))
	      (set-buffer work-buffer)
	      (cond ((memq type '(From_ BellFrom_ From_-with-Content-Length))
		     (setq regexp "^From "))
		    ((eq type 'mmdf)
		     (setq regexp "^\001\001\001\001"))
		    ((eq type 'babyl)
		     (setq regexp "^\037")))
	      (condition-case data
		  (progn
		    (unless quietly 
		      (vm-inform 7 "Counting messages in %s..." file))
		    (call-process vm-grep-program nil t nil "-c" regexp
				  (expand-file-name file))
		    (unless quietly 
		      (vm-inform 7 "Counting messages in %s... done" file)))
		(error (vm-warn 1 2 "Attempt to run %s on %s signaled: %s"
				vm-grep-program file data)
		       (setq vm-grep-program nil)))
	      (setq count (string-to-number (buffer-string)))
	      (cond ((memq type '(From_ BellFrom_ From_-with-Content-Length))
		     t )
		    ((eq type 'mmdf)
		     (setq count (/ count 2)))
		    ((eq type 'babyl)
		     (setq count (1- count))))
	      count ))
	(and work-buffer (kill-buffer work-buffer))))))

(defun vm-movemail-specific-spool-file-p (file)
  (string-match "^po:[^:]+$" file))

(defun vm-check-for-spooled-mail (&optional interactive this-buffer-only)
  (if vm-global-block-new-mail
      nil
    (if (and vm-folder-access-method this-buffer-only)
	(cond ((eq vm-folder-access-method 'pop)
	       (vm-pop-folder-check-mail interactive))
	      ((eq vm-folder-access-method 'imap)
	       (vm-imap-folder-check-mail interactive)))
      (let ((triples (vm-compute-spool-files (not this-buffer-only)))
	    ;; since we could accept-process-output here (POP code),
	    ;; a timer process might try to start retrieving mail
	    ;; before we finish.  block these attempts.
	    (vm-global-block-new-mail t)
	    (vm-pop-ok-to-ask interactive)
	    (vm-imap-ok-to-ask interactive)
	    ;; for string-match calls below
	    (case-fold-search nil)
	    this-buffer crash in maildrop meth
	    (mail-waiting nil))
	(while triples
	  (setq in (expand-file-name (nth 0 (car triples)) vm-folder-directory)
		maildrop (nth 1 (car triples))
		crash (nth 2 (car triples)))
	  (if (vm-movemail-specific-spool-file-p maildrop)
	      ;; spool file is accessible only with movemail
	      ;; so skip it.
	      nil
	    (setq this-buffer (eq (current-buffer) (vm-get-file-buffer in)))
	    (when (or this-buffer (not this-buffer-only))
		  (if (file-exists-p crash)
		      (setq mail-waiting t)
		    (cond ((vm-imap-folder-spec-p maildrop)
			   (setq meth 'vm-imap-check-mail))
			  ((vm-pop-folder-spec-p maildrop)
			   (setq meth 'vm-pop-check-mail))
			  (t (setq meth 'vm-spool-check-mail)))
		    (if (not interactive)
			;; allow no error to be signaled
			(condition-case nil
			    (setq mail-waiting
				  (or mail-waiting
				      (funcall meth maildrop)))
			  (error nil))
		      (setq mail-waiting
			    (or mail-waiting
				(funcall meth maildrop)))))))
	  (setq triples (cdr triples)))
	mail-waiting ))))

(defun vm-get-spooled-mail (&optional interactive)
  "Get new mail for the current folder from its spool file.
The optional argument INTERACTIVE says whether the function can make
interactive queries to the user.  The possible values are t,
`password-only', and nil."
  (if vm-block-new-mail
      (error "Can't get new mail until you save this folder."))
  (cond ((eq vm-folder-access-method 'pop)
	 (vm-pop-synchronize-folder :interactive interactive 
				    :do-retrieves t))
	((eq vm-folder-access-method 'imap)
	 (if vm-imap-sync-on-get
	     (progn
;;	       (vm-imap-synchronize-folder :interactive interactive
;;                                         :save-attributes t)
	       (vm-imap-synchronize-folder :interactive interactive
					   :do-local-expunges t 
					   :do-retrieves t 
					   :save-attributes t 
					   :retrieve-attributes t))
	   (vm-imap-synchronize-folder :interactive interactive 
				       :do-retrieves t)))
	(t (vm-get-spooled-mail-normal interactive))))

(defun vm-get-spooled-mail-normal (&optional interactive)
  (if vm-global-block-new-mail
      nil
    (let ((triples (vm-compute-spool-files))
	  ;; since we could accept-process-output here (POP code),
	  ;; a timer process might try to start retrieving mail
	  ;; before we finish.  block these attempts.
	  (vm-global-block-new-mail t)
	  (vm-pop-ok-to-ask interactive)
	  (vm-imap-ok-to-ask interactive)
	  ;; for string-match calls below
	  (case-fold-search nil)
	  non-file-maildrop crash in safe-maildrop maildrop ;; popdrop
	  retrieval-function
	  (got-mail nil))
      (if (and (not (verify-visited-file-modtime (current-buffer)))
	       (or (null interactive)
		   (not (yes-or-no-p
			 (format
			  "Folder %s changed on disk, discard those changes? "
			  (buffer-name))))))
	  (progn
	    (vm-warn 0 2 
		     "Folder %s changed on disk, consider M-x revert-buffer"
		     (buffer-name))
	    nil )
	(while triples
	  (setq in (expand-file-name (nth 0 (car triples)) vm-folder-directory))
	  (setq maildrop (nth 1 (car triples)))
	  (setq crash (nth 2 (car triples)))
	  (setq safe-maildrop maildrop)
	  (setq non-file-maildrop nil)
	  (cond ((vm-movemail-specific-spool-file-p maildrop)
		 (setq non-file-maildrop t)
		 (setq retrieval-function 'vm-spool-move-mail))
		((vm-imap-folder-spec-p maildrop)
		 (setq non-file-maildrop t)
		 (setq safe-maildrop 
		       (or (vm-imap-account-name-for-spec maildrop)
			   (vm-safe-imapdrop-string maildrop)))
		 (setq retrieval-function 'vm-imap-move-mail))
		((vm-pop-folder-spec-p maildrop)
		 (setq non-file-maildrop t)
		 (setq safe-maildrop 
		       (or (vm-pop-find-name-for-spec maildrop)
			   (vm-safe-popdrop-string maildrop)))
		 (setq retrieval-function 'vm-pop-move-mail))
		(t (setq retrieval-function 'vm-spool-move-mail)))
	  (setq crash (expand-file-name crash vm-folder-directory))
	  (when (eq (current-buffer) (vm-get-file-buffer in))
	    (when (file-exists-p crash)
	      (vm-inform 1 "Recovering messages from %s..." crash)
	      (setq got-mail (or (vm-gobble-crash-box crash) got-mail))
	      (vm-inform 1 "Recovering messages from %s... done" crash))
	    (when (or non-file-maildrop
		      (and (not (equal 0 (nth 7 (file-attributes maildrop))))
			   (file-readable-p maildrop)))
	      (unless non-file-maildrop
		(setq maildrop 
		      (expand-file-name maildrop 
					vm-folder-directory)))
	      (when (if got-mail
			;; don't allow errors to be signaled unless no
			;; mail has been appended to the incore
			;; copy of the folder.  otherwise the
			;; user will wonder where the mail is,
			;; since it is not in the crash box or
			;; the spool file and doesn't _appear_ to
			;; be in the folder either.
			(condition-case error-data
			    (funcall retrieval-function maildrop crash)
			  (error (vm-warn 0 2 "%s signaled: %s"
					  retrieval-function
					  error-data)
				 ;; we don't know if mail was
				 ;; put into the crash box or
				 ;; not, so return t just to be
				 ;; safe.
				 t )
			  (quit (vm-warn 0 2 "quitting from %s..."
					 retrieval-function)
				;; we don't know if mail was
				;; put into the crash box or
				;; not, so return t just to be
				;; safe.
				t ))
		      (funcall retrieval-function maildrop crash))
		(when (vm-gobble-crash-box crash)
		  (setq got-mail t)
		  (when (not non-file-maildrop)
		    (vm-store-folder-totals maildrop
					    '(0 0 0 0)))
		  (vm-inform 5 "Got mail from %s."
			   safe-maildrop)))))
	  (setq triples (cdr triples)))
	;; not really correct, but it is what the user expects to see.
	(setq vm-spooled-mail-waiting nil)
	(intern (buffer-name) vm-buffers-needing-display-update)
	(vm-update-summary-and-mode-line)
	(when got-mail
          (condition-case errmsg
              (run-hooks 'vm-retrieved-spooled-mail-hook)
            (t 
	     (vm-warn 0 2
	      "Ignoring error while running vm-retrieved-spooled-mail-hook. %S"
	      errmsg)))
          (vm-assimilate-new-messages :read-attributes nil))))))

;;;###autoload
(defun vm-folder-name ()
  "Return the current folder's name (local file name, or POP/IMAP
maildrop string)."
  (interactive)
  (if vm-folder-access-method
      (aref vm-folder-access-data 0)
    buffer-file-name))

;; This function is now obsolete.  USR, 2011-12-26
(defun vm-safe-popdrop-string (maildrop)
  "Return a human-readable version of a pop MAILDROP string."
  (or (and (string-match "^\\(pop:\\|pop-ssl:\\|pop-ssh:\\)?\\([^:]*\\):[^:]*:[^:]*:\\([^:]*\\):[^:]*" maildrop)
	   (concat (substring maildrop (match-beginning 3) (match-end 3))
		   "@"
		   (substring maildrop (match-beginning 2) (match-end 2))))
      "???"))

(defun vm-popdrop-sans-password (source)
  "Return popdrop SOURCE, but replace the password by a \"*\"."
  (mapconcat 'identity 
             (append (reverse (cdr (reverse (vm-parse source "\\([^:]*\\):?"))))
                     '("*"))
             ":"))

(defun vm-popdrop-sans-personal-info (source)
  "Return popdrop SOURCE, but replace the login and password by a \"*\"."
  (mapconcat 'identity 
             (append (reverse (cdr (cdr (reverse (vm-parse source "\\([^:]*\\):?")))))
                     '("*" "*"))
             ":"))

;; This function is now obsolete.  USR, 2011-12-26
(defun vm-safe-imapdrop-string (maildrop)
  "Return a human-readable version of an imap MAILDROP string."
  (or (and (string-match "^\\(imap\\|imap-ssl\\|imap-ssh\\):\\([^:]*\\):[^:]*:\\([^:]*\\):[^:]*:\\([^:]*\\):[^:]*" maildrop)
	   (concat (substring maildrop (match-beginning 4) (match-end 4))
		   "@"
		   (substring maildrop (match-beginning 2) (match-end 2))
		   " ["
		   (substring maildrop (match-beginning 3) (match-end 3))
		   "]"))
      "???"))

(defun vm-imapdrop-sans-password (source)
  (let (source-list)
    (setq source-list (vm-parse source "\\([^:]*\\):?"))
    (concat (nth 0 source-list) ":"
	    (nth 1 source-list) ":"
	    (nth 2 source-list) ":"
	    (nth 3 source-list) ":"
	    (nth 4 source-list) ":"
	    (nth 5 source-list) ":" "*")))

(defun vm-imapdrop-sans-password-and-mailbox (source)
  (let (source-list)
    (setq source-list (vm-parse source "\\([^:]*\\):?"))
    (concat (nth 0 source-list) ":"
	    (nth 1 source-list) ":"
	    (nth 2 source-list) ":" "*:"
	    (nth 4 source-list) ":"
	    (nth 5 source-list) ":" "*")))

(defun vm-imapdrop-sans-personal-info (source)
  (let (source-list)
    (setq source-list (vm-parse source "\\([^:]*\\):?"))
    (concat (nth 0 source-list) ":"
	    (nth 1 source-list) ":"
	    (nth 2 source-list) ":" "*:"
	    (nth 4 source-list) ":" "*:" "*")))

(defun vm-maildrop-sans-password (drop)
  (or (and (string-match "^\\(pop:\\|pop-ssl:\\|pop-ssh:\\)?\\([^:]*\\):[^:]*:[^:]*:\\([^:]*\\):[^:]*" drop)
	   (vm-popdrop-sans-password drop))
      (and (string-match "^\\(imap\\|imap-ssl\\|imap-ssh\\):\\([^:]*\\):[^:]*:\\([^:]*\\):[^:]*:\\([^:]*\\):[^:]*" drop)
	   (vm-imapdrop-sans-password drop))
      drop))

(defun vm-maildrop-sans-personal-info (drop)
  (or (and (string-match "^\\(pop:\\|pop-ssl:\\|pop-ssh:\\)?\\([^:]*\\):[^:]*:[^:]*:\\([^:]*\\):[^:]*" drop)
	   (vm-popdrop-sans-personal-info drop))
      (and (string-match "^\\(imap\\|imap-ssl\\|imap-ssh\\):\\([^:]*\\):[^:]*:\\([^:]*\\):[^:]*:\\([^:]*\\):[^:]*" drop)
	   (vm-imapdrop-sans-personal-info drop))
      drop))

(defun vm-maildrop-alist-sans-password (alist)
  (vm-mapcar 
   (lambda (pair-xxx)
     (cons (vm-maildrop-sans-password (car pair-xxx)) (cdr pair-xxx)))
   alist))

(defun vm-maildrop-alist-sans-personal-info (alist)
  (vm-mapcar 
   (lambda (pair-xxx)
     (cons (vm-maildrop-sans-personal-info (car pair-xxx)) (cdr pair-xxx)))
   alist))

;;;###autoload
(defun vm-get-new-mail (&optional arg)
  "Move any new mail that has arrived in any of the spool files for the
current folder into the folder.  New mail is appended to the disk
and buffer copies of the folder.

Prefix arg means to gather mail from a user specified folder, instead of
the usual spool files.  The file name will be read from the minibuffer.
Unlike when getting mail from a spool file, the source file is left
undisturbed after its messages have been copied.

When applied to a virtual folder, this command runs itself on
each of the underlying real folders associated with this virtual
folder.  A prefix argument has no effect when this command is
applied to virtual folder; mail is always gathered from the spool
files."
  (interactive "P")
  (vm-select-folder-buffer-and-validate 0 (vm-interactive-p))
  (vm-error-if-folder-read-only)
  (let* ((folder (buffer-name))
	 (description (if (consp (car (vm-spool-files))) 
					; folder-specific spool files
			  (format "new mail for %s" (buffer-name))
			(format "new mail")))
	 totals-blurb)
    (cond ((eq major-mode 'vm-virtual-mode)
	   (vm-virtual-get-new-mail))
	  ((not (eq major-mode 'vm-mode))
	   (error "Can't get mail for a non-VM folder buffer"))
	  ((null arg)
	   ;; This is redundant now.  USR, 2011-12-26
	   ;; (if (not (eq major-mode 'vm-mode))
	   ;;     (vm-mode))
	   (vm-inform 5 "%s: Checking for %s..." folder description)
	   (if (vm-get-spooled-mail t)
	       (progn
		 ;; say this NOW, before the non-previewers read
		 ;; a message, alter the new message count and
		 ;; confuse themselves.
		 (setq totals-blurb (vm-emit-totals-blurb))
		 (vm-display nil nil '(vm-get-new-mail) '(vm-get-new-mail))
		 (if (vm-thoughtfully-select-message)
		     (vm-present-current-message)
		   (vm-update-summary-and-mode-line))
		 (vm-inform 5 totals-blurb))
	     (vm-inform 5 "%s: No %s" folder description)
	     (and (vm-interactive-p) (vm-sit-for 4) (vm-inform 5 ""))
	     ))
	  (t
	   (let ((buffer-read-only nil)
		 folder mcount)
	     (setq folder (read-file-name "Gather mail from folder: "
					  vm-folder-directory nil t))
	     (if (and vm-check-folder-types
		      (not (vm-compatible-folder-p folder)))
		 (error "Folder %s is not the same format as this folder."
			folder))
	     (save-excursion
	       (save-restriction
		(widen)
		(goto-char (point-max))
		(let ((coding-system-for-read (vm-binary-coding-system)))
		  (insert-file-contents folder))))
	     (setq mcount (length vm-message-list))
	     (if (vm-assimilate-new-messages)
		 (progn
		   ;; say this NOW, before the non-previewers read
		   ;; a message, alter the new message count and
		   ;; confuse themselves.
		   (setq totals-blurb (vm-emit-totals-blurb))
		   (vm-display nil nil '(vm-get-new-mail) '(vm-get-new-mail))
		   (if (vm-thoughtfully-select-message)
		       (vm-present-current-message)
		     (vm-update-summary-and-mode-line))
		   (vm-inform 5 totals-blurb)
		   ;; The gathered messages are actually still on disk
		   ;; unless the user deletes the folder himself.
		   ;; However, users may not understand what happened if
		   ;; the messages go away after a "quit, no save".
		   (setq vm-messages-not-on-disk
			 (+ vm-messages-not-on-disk
			    (- (length vm-message-list)
			       mcount))))
	       (vm-inform 5 "%s: No messages gathered." folder)))))))

;; returns list of new messages if there were any new messages, nil otherwise
(cl-defun vm-assimilate-new-messages (&key
				    (read-attributes t) (run-hooks t)
				    gobble-order labels)
  ;; We are only guessing what this function does.  USR, 2010-05-20
  ;; This is called in a Folder buffer, which already has messages
  ;; loaded into it, but some of the messages (the "new" messages)
  ;; have not been parsed and separated yet.  
  ;; The function first builds a vm-message-list.
  ;; If READ-ATTRIBUTES is non-nil, it reads the message
  ;; attributes in the X-VM-v5-Data headers and stores them.
  ;; If GOBBLE-ORDER is non-nil, it reads the X-VM-Message-Order
  ;; header and uses it to reorder the messages.
  ;; If vm-summary-show-threads is non-nil, it builds threads.
  ;; If vm-ml-sort-keys is non-nil, sorts the messages accordingly.
  ;; If LABELS is non-nil, they are added to the message labels of all 
  ;; the new messages.
  ;; If RUN-HOOKS is t, arrived-message-hook functions are
  ;; called.  Normally, this argument is nil for the first
  ;; time vm-assimilate-new-messages is called in a folder.  It is
  ;; t for subsequent calls when new mail is being incorporated.
  (let ((tail-cons (vm-last vm-message-list))
	b-list new-messages)
    (save-excursion
      (save-restriction
       (widen)
       (vm-build-message-list)
       (when (or (null tail-cons) (cdr tail-cons))
	 (unless vm-assimilate-new-messages-sorted
	   (setq vm-ml-sort-keys nil))
	 (if read-attributes
	     (vm-read-VM-data (cdr tail-cons))
	   (vm-set-default-attributes (cdr tail-cons)))
	 ;; Yuck.  This has to be done here instead of in the
	 ;; vm function because this needs to be done before
	 ;; any initial thread sort (so that if the thread
	 ;; sort matches the saved order the folder won't be
	 ;; modified) but after the message list is created.
	 ;; Since thread sorting is done here this has to be
	 ;; done here too.
	 (when gobble-order
	   (vm-gobble-message-order))
	 (when (or (vectorp vm-thread-obarray)
		   vm-summary-show-threads)
	   ;; may need threads for sorting
	   (vm-build-threads (cdr tail-cons)))))
      (setq new-messages (if tail-cons (cdr tail-cons) vm-message-list))
      (when new-messages
	(vm-set-numbering-redo-start-point new-messages)
	(vm-set-summary-redo-start-point new-messages)))
    ;; Only update the folders summary count here if new messages
    ;; have arrived, not when we're reading the folder for the
    ;; first time, and not if we cannot assume that all the arrived
    ;; messages should be considered new.  Use gobble-order as a
    ;; first time indicator along with the new messages being equal
    ;; to the whole message list.
    (when new-messages
      (if (and (not read-attributes)
	       (or (not (eq new-messages vm-message-list))
		   (null gobble-order)))
	  (vm-modify-folder-totals buffer-file-name 'arrived
				   (length new-messages)))
      ;; copy the new-messages list because sorting might scramble
      ;; it.  Also something the user does when
      ;; vm-arrived-message-hook is run might affect it.
      ;; vm-assimilate-new-messages returns this value so it must
      ;; not be mangled.
      (setq new-messages (copy-sequence new-messages))
      ;; add the labels
      (when (and labels vm-burst-digest-messages-inherit-labels)
	(mapc (lambda (m)
		(vm-set-decoded-labels-of m (copy-sequence labels)))
	      new-messages))
      (when vm-summary-show-threads
	;; get numbering of new messages done now
	;; so that the sort code only has to worry about the
	;; changes it needs to make.
	(vm-update-summary-and-mode-line)
	(vm-sort-messages (or vm-ml-sort-keys 
			      (if vm-summary-show-threads
				  "activity"
				"date"))))
      (when (and run-hooks
		 (or vm-arrived-message-hook vm-arrived-messages-hook))
	;; seems wise to do this so that if the user runs VM
	;; commands here they start with as much of a clean
	;; slate as we can provide, given we're currently deep
	;; in the guts of VM.
	(vm-update-summary-and-mode-line)
	(when (and vm-arrived-message-hook
		   (not (eq vm-folder-access-method 'imap)))
	  (mapc (lambda (m)
		  (vm-run-hook-on-message 'vm-arrived-message-hook m))
		new-messages))
	(run-hooks 'vm-arrived-messages-hook))
      (when vm-virtual-buffers
	(save-excursion
	  (setq b-list vm-virtual-buffers)
	  (while b-list
	    ;; buffer might be dead
	    (when (buffer-name (car b-list))
	      (let (tail-cons)
		(set-buffer (car b-list))
		(setq tail-cons (vm-last vm-message-list))
		(vm-build-virtual-message-list new-messages)
		(when (or (null tail-cons) (cdr tail-cons))
		  (if (not vm-assimilate-new-messages-sorted)
		      (setq vm-ml-sort-keys nil))
		  (if (vectorp vm-thread-obarray)
		      (vm-build-threads (cdr tail-cons)))
		  (vm-set-summary-redo-start-point
		   (or (cdr tail-cons) vm-message-list))
		  (vm-set-numbering-redo-start-point
		   (or (cdr tail-cons) vm-message-list))
		  (unless vm-message-pointer
		    (setq vm-message-pointer vm-message-list
			  vm-need-summary-pointer-update t)
		    (if vm-message-pointer
			(vm-present-current-message)))
		  (when vm-summary-show-threads
		    (vm-update-summary-and-mode-line)
		    (vm-sort-messages (or vm-ml-sort-keys "activity")))
		  )))
	    (setq b-list (cdr b-list)))))
      (when vm-ml-sort-keys
	(vm-sort-messages vm-ml-sort-keys)))
    new-messages ))

(defun vm-select-operable-messages (count 
				    &optional interactive op-description)
  "Return a list of all marked messages, messages indicated by
the COUNT or messages in a collapsed thread, in that
order.  

Marked messages are returned only if the previous command was
`vm-next-command-uses-marks'.  

COUNT is used if it is non-nil and different from 1 or
INTERACTIVE is nil.  In that case, a number of messages around
`vm-message-pointer' equal to (abs count) are returned, either
backward (if COUNT is negative) or forward (if positive).  If
COUNT is zero, then all messages in the folder are returned.

If INTERACTIVE is t and the current operation is a thread operation
invoked in a Summary buffer, then all the messages in the thread are
returned. 

Otherwise, if COUNT is 1, then the current message is returned.  If
COUNT is nil then no messages are returned.

OP-DESCRIPTION is a string describing the opeartion being peformed,
which is used in interactive confirmations."
  (cond ((eq last-command 'vm-next-command-uses-marks)
	 (vm-marked-messages))
	((and count (not (= count 1)))
	 (let ((direction (if (< count 0) 'backward 'forward))
	       (count (vm-abs count))
	       (vm-message-pointer vm-message-pointer) ; why this?
	       mlist)
	   (if (= count 0)
	       (setq mlist (copy-sequence vm-message-list))
	     (unless (eq vm-circular-folders t)
	       (vm-check-count count))
	     (while (not (zerop count))
	       (setq mlist (cons (car vm-message-pointer) mlist))
	       (vm-decrement count)
	       (unless (zerop count)
		 (vm-move-message-pointer direction))))
	   (nreverse mlist)))
	((and interactive
	      (vm-summary-operation-p)
	      vm-summary-enable-thread-folding
	      vm-summary-show-threads
	      vm-enable-thread-operations
	      (vm-thread-root-p (vm-current-message))
	      (vm-collapsed-root-p (vm-current-message))
	      (or (eq vm-enable-thread-operations t)
		  (y-or-n-p 
		   (format "%s: %s all messages in thread? " 
			   (buffer-name) op-description))))
	 (vm-thread-subtree (vm-current-message)))
	((null count)
	 nil)
	(t
	 (list (vm-current-message)))
	))

(defun vm-display-startup-message ()
  (if (sit-for 5)
      (let ((lines vm-startup-message-lines))
	(vm-inform 8 "VM %s. Type ? for help." (vm-version))
	(setq vm-startup-message-displayed t)
	(while (and (sit-for 4) lines)
	  (vm-inform 8 (substitute-command-keys (car lines)))
	  (setq lines (cdr lines)))))
  (vm-inform 8 ""))

;;;###autoload
(defun vm-toggle-read-only ()
  "If the current VM folder is read-only, make it modifiable.

This command can also be used to make a modifiable folder read-only.
However it is unsafe to do so because any previous modifications will
be discarded when the folder is quit.  You should first save the
current changes of the folder before making it read-only."
  (interactive)
  (vm-select-folder-buffer-and-validate 0 (vm-interactive-p))
  (if vm-folder-read-only
      (setq vm-folder-read-only nil)
    (if (or (not (buffer-modified-p))
	    (y-or-n-p 
	     (concat "It is unsafe to make the folder read-only. "
		     "Proceed? ")))
	(setq vm-folder-read-only t)
      (error "Aborted")))
  (intern (buffer-name) vm-buffers-needing-display-update)
  (vm-inform 5 "Folder is now %s"
	   (if vm-folder-read-only "read-only" "modifiable"))
  (vm-display nil nil '(vm-toggle-read-only) '(vm-toggle-read-only))
  (vm-update-summary-and-mode-line))

(defvar scroll-in-place)

;; this does the real major mode scutwork.
(defun vm-mode-internal (&optional access-method reload)
  "Turn on vm-mode in the current buffer.
ACCESS-METHOD is either `pop' or `imap' for server folders.
If RELOAD is non-Nil, then the folder is being recovered.  So,
folder-access-data should be preserved."
  (widen)
  (make-local-variable 'require-final-newline)
  ;; don't kill local variables, as there is some state we'd like to
  ;; keep.  rather than non-portably marking the variables we
  ;; want to keep, just avoid calling kill-local-variables and
  ;; reset everything that needs to be reset.
  (setq
   major-mode 'vm-mode
   mode-line-format vm-mode-line-format
   mode-name "VM"
   ;; must come after the setting of major-mode
   mode-popup-menu (and vm-use-menus
			(vm-menu-support-possible-p)
			(vm-menu-mode-menu))
   buffer-read-only t
   ;; If the user quits a vm-mode buffer, the default action is
   ;; to kill the buffer.  Make a note that we should offer to
   ;; save this buffer even if it has no file associated with it.
   ;; We have no idea of the value of the data in the buffer
   ;; before it was put into vm-mode.
   buffer-offer-save t
   require-final-newline nil
   ;; don't let CR's in folders be mashed into LF's because of a
   ;; stupid user setting.
   selective-display nil
   vm-thread-obarray 'bonk
   vm-thread-subject-obarray 'bonk
   vm-label-obarray (make-vector 29 0)
   vm-last-message-pointer nil
   vm-modification-counter 0
   vm-message-list nil
   vm-message-pointer nil
   vm-message-order-changed nil
   vm-message-order-header-present nil
   vm-imap-retrieved-messages nil
   vm-pop-retrieved-messages nil
   vm-summary-buffer nil
   vm-system-state nil
   vm-undo-record-list nil
   vm-undo-record-pointer nil
   vm-virtual-buffers (vm-link-to-virtual-buffers)
   vm-folder-type (vm-get-folder-type))
  (when (not reload)
    (cond ((eq access-method 'pop)
	   (setq vm-folder-access-method 'pop)
	   (setq vm-folder-access-data 
		 (make-vector vm-folder-pop-access-data-length nil)))
	  ((eq access-method 'imap)
	   (setq vm-folder-access-method 'imap)
	   (setq vm-folder-access-data 
		 (make-vector vm-folder-imap-access-data-length nil)))))
  (use-local-map vm-mode-map)
  ;; if the user saves after M-x recover-file, let them get new
  ;; mail again.
  (add-hook 'after-save-hook 'vm-unblock-new-mail nil t)
  (when (vm-menu-support-possible-p)
    (vm-menu-install-menus))
  (add-hook 'kill-buffer-hook 'vm-garbage-collect-folder)
  (add-hook 'kill-buffer-hook 'vm-garbage-collect-message)
  ;; avoid the XEmacs file dialog box.
  (defvar use-dialog-box)
  (make-local-variable 'use-dialog-box)
  (setq use-dialog-box nil)
  ;; mail folders are precious.  protect them by default.
  (make-local-variable 'file-precious-flag)
  (setq file-precious-flag vm-folder-file-precious-flag)
  ;; scroll in place messes with scroll-up and this loses
  (make-local-variable 'scroll-in-place)
  (setq scroll-in-place nil)
  (run-hooks 'vm-mode-hook)
  ;; compatibility
  (run-hooks 'vm-mode-hooks))

(defun vm-link-to-virtual-buffers ()
  "If there are visited virtual folders that depend on the current
real folder, then link them to the current folder and update their
contents." 
  (let ((b-list (buffer-list))
	(vbuffers nil)
	(folder-buffer (current-buffer))
	folders folder clauses)
    (save-excursion
      (while b-list
	(set-buffer (car b-list))
	(cond ((eq major-mode 'vm-virtual-mode)
	       (setq clauses (cdr vm-virtual-folder-definition))
	       (while clauses
		 (setq folders (car (car clauses)))
		 (while folders
		   (setq folder (car folders))
		   (if (eq folder-buffer 
			   (or (and (stringp folder)
				    (vm-get-file-buffer
				     (expand-file-name folder 
						       vm-folder-directory)))
			       (and (listp folder)
				    (eval folder))))
		       (setq vbuffers (cons (car b-list) vbuffers)
			     vm-real-buffers (cons folder-buffer
						   vm-real-buffers)
			     folders nil
			     clauses nil))
		   (setq folders (cdr folders)))
		 (setq clauses (cdr clauses)))))
	(setq b-list (cdr b-list)))
      vbuffers )))

;;;###autoload
(defun vm-change-folder-type (type)
  "Change folder type to TYPE.
TYPE may be one of the following symbol values:

    From_
    From_-with-Content-Length
    BellFrom_
    mmdf
    babyl

Interactively TYPE will be read from the minibuffer."
  (interactive
   (let ((this-command this-command)
	 (last-command last-command)
	 (types vm-supported-folder-types))
     (save-current-buffer
       (vm-select-folder-buffer)
       (vm-error-if-virtual-folder)
       (setq types (vm-delqual (symbol-name vm-folder-type)
			       (copy-sequence types)))
       (list (intern (vm-read-string "Change folder to type: " types))))))
  (vm-select-folder-buffer-and-validate 1 (vm-interactive-p))
  (vm-error-if-virtual-folder)
  (if (not (memq type '(From_ BellFrom_ From_-with-Content-Length mmdf babyl)))
      (error "Unknown folder type: %s" type))
  (if (or (null vm-folder-type)
	  (eq vm-folder-type 'unknown))
      (error "Current folder's type is unknown, can't change it."))
  (let ((mp vm-message-list)
	(buffer-read-only nil)
	(old-type vm-folder-type)
	;; no interruptions
	(inhibit-quit t)
	(n 0)
	;; Just for laughs, make the update interval vary.
	(modulus (+ (% (vm-abs (random)) 11) 5))
	text-end) ;; opoint
    (save-excursion
      (save-restriction
       (widen)
       (setq vm-folder-type type)
       (goto-char (point-min))
       (vm-convert-folder-header old-type type)
       (while mp
	 (goto-char (vm-start-of (car mp)))
	 ;; (setq opoint (point))
	 (insert (vm-leading-message-separator type (car mp)))
	 (if (> (vm-headers-of (car mp)) (vm-start-of (car mp)))
	     (delete-region (point) (vm-headers-of (car mp)))
	   (set-marker (vm-headers-of (car mp)) (point))
	   ;; if headers-of == start-of then so could vheaders-of
	   ;; and text-of.  clear them to force a recompute.
	   (vm-set-vheaders-of (car mp) nil)
	   (vm-set-text-of (car mp) nil))
	 (vm-convert-folder-type-headers old-type type)
	 (goto-char (vm-text-end-of (car mp)))
	 (setq text-end (point))
	 (insert-before-markers (vm-trailing-message-separator type))
	 (delete-region (vm-text-end-of (car mp)) (vm-end-of (car mp)))
	 (set-marker (vm-text-end-of (car mp)) text-end)
	 (goto-char (vm-headers-of (car mp)))
	 (vm-munge-message-separators type (vm-headers-of (car mp))
				      (vm-text-end-of (car mp)))
	 (vm-set-byte-count-of (car mp) nil)
	 (vm-set-babyl-frob-flag-of (car mp) nil)
	 (vm-set-message-type-of (car mp) type)
	 ;; Technically we should mark each message for a
	 ;; summary update since the message byte counts might
	 ;; have changed.  But I don't think anyone cares that
	 ;; much and the summary regeneration would make this
	 ;; process slower.
	 (setq mp (cdr mp) n (1+ n))
	 (if (zerop (% n modulus))
	     (vm-inform 5 "Converting... %d" n))))))
  (vm-clear-modification-flag-undos)
  (intern (buffer-name) vm-buffers-needing-display-update)
  (vm-update-summary-and-mode-line)
  (vm-inform 5 "Conversion complete.")
  ;; message separator strings may have leaked into view
  (if (> (point-max) (vm-text-end-of (car vm-message-pointer)))
      (narrow-to-region (point-min) (vm-text-end-of (car vm-message-pointer))))
  (vm-display nil nil '(vm-change-folder-type) '(vm-change-folder-type)))

(defun vm-register-global-garbage-files (files)
  "Add global garbage collection actions to delete all of FILES."
  (while files
    (setq vm-global-garbage-alist
	  (cons (cons (car files) 'delete-file)
		vm-global-garbage-alist)
	  files (cdr files))))

(defun vm-garbage-collect-global ()
  "Carry out all the registered global garbage collection actions."
  (save-excursion
    (while vm-global-garbage-alist
      (condition-case nil
	  (funcall (cdr (car vm-global-garbage-alist))
		   (car (car vm-global-garbage-alist)))
	(error nil))
      (setq vm-global-garbage-alist (cdr vm-global-garbage-alist)))))

(defun vm-register-folder-garbage-files (files)
  "Add folder garbage collection actions to delete all of FILES."
  (vm-register-global-garbage-files files)
  (save-excursion
    (vm-select-folder-buffer)
    (while files
      (setq vm-folder-garbage-alist
	    (cons (cons (car files) 'delete-file)
		  vm-folder-garbage-alist)
	    files (cdr files)))))

(defun vm-register-folder-garbage (action garbage)
  "Add a folder garbage-collection action to carry out ACTION on
argument GARBAGE."
  (save-excursion
    (vm-select-folder-buffer)
    (setq vm-folder-garbage-alist
	  (cons (cons garbage action)
		vm-folder-garbage-alist))))

(defun vm-garbage-collect-folder ()
  "Carry out all the folder garbage-collection actions."
  (save-excursion
    (while vm-folder-garbage-alist
      (condition-case nil
	  (funcall (cdr (car vm-folder-garbage-alist))
		   (car (car vm-folder-garbage-alist)))
	(error nil))
      (setq vm-folder-garbage-alist (cdr vm-folder-garbage-alist)))))

(defun vm-register-fetched-message (m)
  "Register real message M as having been fetched into its folder
temporarily.  Such fetched messages are discarded before the
folder is saved."
  (save-current-buffer
    (set-buffer (vm-buffer-of m))
    ;; m should have retrieve=nil, i.e., already retrieved
    (vm-assert (vm-body-retrieved-of m))
    (let ((vm-folder-read-only nil)
	  (modified (buffer-modified-p)))
      (if (memq m vm-fetched-messages)
	  (progn
	    ;; at the moment, this case doesn't arise.  USR, 2010-06-11
	    ;; move m to the rear
	    (setq vm-fetched-messages
		  (delq m vm-fetched-messages))
	    (setq vm-fetched-messages	; add-to-list is no good on XEmacs
		  (nconc vm-fetched-messages (list m))))

	(if vm-external-fetched-message-limit
	    (while (>= vm-fetched-message-count
		       vm-external-fetched-message-limit)
	      (let ((mm (car vm-fetched-messages)))
		;; These tests should always come out true, but we are
		;; not confident.  A lot could have happened since the
		;; message was first loaded.
		(when (and (vm-body-retrieved-of mm)
			   (vm-body-to-be-discarded-of mm))
		    (vm-discard-real-message-body mm))
		(vm-unregister-fetched-message mm))))
	(setq vm-fetched-messages
	      (nconc vm-fetched-messages (list m)))
	(vm-increment vm-fetched-message-count)
	(vm-set-body-to-be-discarded-of m t)
	(vm-restore-buffer-modified-p
	 modified (vm-buffer-of m))))))

(defun vm-unregister-fetched-message (m)
  "Unregister a real message M as a fetched message.  If M was never
registered as a fetched message, then there is no effect."
  (save-current-buffer
    (set-buffer (vm-buffer-of m))
    (let ((vm-folder-read-only nil))
      (setq vm-fetched-messages (delq m vm-fetched-messages))
      (vm-decrement vm-fetched-message-count)
      (vm-set-body-to-be-discarded-of m nil))))

(defun vm-discard-fetched-messages ()
  "Discard the message bodies of all the fetched messages in the
current folder."
  (while vm-fetched-messages
    (let ((m (car vm-fetched-messages))
	  (vm-folder-read-only nil))
      (vm-discard-real-message-body m)
      (vm-set-body-to-be-discarded-of m nil))
    (setq vm-fetched-messages (cdr vm-fetched-messages)))
  (setq vm-fetched-message-count 0))

(defun vm-register-message-garbage-files (files)
  "Add message garbage collection actions to delete all of FILES."
  (vm-register-folder-garbage-files files)
  (save-excursion
    (vm-select-folder-buffer)
    (while files
      (setq vm-message-garbage-alist
	    (cons (cons (car files) 'delete-file)
		  vm-message-garbage-alist)
	    files (cdr files)))))

(defun vm-register-message-garbage (action garbage)
  "Add a message garbage-collection action to carry out ACTION on
argument GARBAGE."
  (vm-register-folder-garbage action garbage)
  (save-excursion
    (vm-select-folder-buffer)
    (setq vm-message-garbage-alist
	  (cons (cons garbage action)
		vm-message-garbage-alist))))

(defun vm-garbage-collect-message ()
  "Carry out all the folder garbage-collection actions."
  (save-excursion
    (while vm-message-garbage-alist
      (condition-case nil
	  (funcall (cdr (car vm-message-garbage-alist))
		   (car (car vm-message-garbage-alist)))
	(error nil))
      (setq vm-message-garbage-alist (cdr vm-message-garbage-alist)))))

(add-hook 'before-save-hook #'vm-write-file-hook)     ;FIXME: Buffer-local!
(add-hook 'find-file-hook #'vm-handle-file-recovery)  ;FIXME: Buffer-local!
(add-hook 'find-file-hook #'vm-handle-file-reversion) ;FIXME: Buffer-local!

(add-hook 'after-revert-hook #'vm-after-revert-buffer-hook) ;FIXME: Buffer-local!

(defun vm-message-can-be-external (m)
  "Check if the message M can be used in external (headers-only) mode."
  (and (eq (vm-message-access-method-of m) 'imap)
       (or (eq vm-enable-external-messages t)
	   (memq 'imap vm-enable-external-messages))
       ))

;;;###autoload
(defun vm-load-message (&optional count)
  "Load the message by retrieving its body from its
permanent location.  Currently this facility is only available for IMAP
folders.

With a prefix argument COUNT, the current message and the next 
COUNT - 1 messages are loaded.  A negative argument means
the current message and the previous |COUNT| - 1 messages are
loaded.

When invoked on marked messages (via `vm-next-command-uses-marks'),
only marked messages are loaded, other messages are ignored.  If
applied to collapsed threads in summary and thread operations are
enabled via `vm-enable-thread-operations' then all messages in the
thread are loaded."
  (interactive "p")
  (if (vm-interactive-p)
      (vm-follow-summary-cursor))
  (vm-select-folder-buffer-and-validate 1 (vm-interactive-p))
  (vm-error-if-folder-read-only)
  (when (null count) (setq count 1))
  (let ((mlist (vm-select-operable-messages
		count (vm-interactive-p) "Load"))
	;; (errors 0)
	(n 0)
	;; fetch-method
	m mm
	(need-refresh (not (vm-body-retrieved-of (vm-current-message)))))
    (setq count 0)
    (unwind-protect
	(save-excursion
	  (vm-inform 8 "Retrieving message body...")
	  (while mlist
	    (setq m (car mlist))
	    (setq mm (vm-real-message-of m))
	    (set-buffer (vm-buffer-of mm))
	    (if (vm-body-retrieved-of mm)
		(when (vm-body-to-be-discarded-of mm)
		  (vm-unregister-fetched-message mm)
		  (setq count (1+ count)))
	      ;; else retrieve the body
	      (setq n (1+ n))
	      (vm-inform 8 "Retrieving message body... %s" n)
	      (vm-retrieve-real-message-body mm)
	      (setq count (1+ count))
	      (when (> n 0)
		(vm-inform 8 "Retrieving message body... done")))
	    (setq mlist (cdr mlist)))
      (intern (buffer-name) vm-buffers-needing-display-update)
      ;; FIXME - is this needed?  Is it correct?
      (vm-display nil nil '(vm-load-message vm-refresh-message)
		  (list this-command))	
      (when (> count 0) (vm-mark-folder-modified-p))
      (vm-update-summary-and-mode-line))
      (when need-refresh
	(vm-preview-current-message))
      (if (= count 1)
	  (vm-inform 5 "Message body loaded")
	(vm-inform 5 "%s message bodies loaded" 
		   (if (= count 0) "No" count))))
    ))

;;;###autoload
(defun vm-retrieve-operable-messages (&optional count mlist
						&key fail)
  "Retrieve the current \"operable\" messages from their
permanent locations for temporary use.  Currently this facility is
only available for IMAP folders.  If FAIL is non-nil then any errors
during retrieval cause failure.

If COUNT and MLIST or both nil, then the \"operable\" message is just
the current message, and it is retrieved.

If the optional argument MLIST is non-nil, then the messages in
MLIST are retrieved.  Otherwise, the following applies.

With a positive integer argument COUNT, the current message and
the next COUNT - 1 messages are retrieved.  A negative argument
means the current message and the previous |COUNT| - 1 messages
are retrieved.  If COUNT is 0, then all the messages in the current
folder are retrieved.

When invoked on marked messages (via `vm-next-command-uses-marks'),
only marked messages are retrieved, other messages are ignored.  If
applied to collapsed threads in summary and thread operations are
enabled via `vm-enable-thread-operations' then all messages in the
thread are retrieved."
  (save-current-buffer
    (vm-select-folder-buffer-and-validate 1 (vm-interactive-p))
    (when (null count) (setq count 1))
    (let (;; (used-marks (eq last-command 'vm-next-command-uses-marks))
	  (vm-external-fetched-message-limit nil)
	  ;; (errors 0)
	  (n 0)
	  ;; fetch-method
	  m mm)
      ;;     (if (not used-marks) 
      ;; 	(setq mlist (list (car vm-message-pointer))))
      (unless mlist
	(setq mlist (vm-select-operable-messages
		     count (vm-interactive-p) "Retrieve")))
      (save-excursion
	(while mlist
	  (setq m (car mlist))
	  (setq mm (vm-real-message-of m))
	  (set-buffer (vm-buffer-of mm))
	  (when (vm-body-to-be-retrieved-of mm)
	    (setq n (1+ n))
	    (vm-inform 8 "Retrieving message body... %s" n)
	    (vm-retrieve-real-message-body mm :register t :fail fail))
	  (setq mlist (cdr mlist)))
	(when (> n 0)
	  (vm-inform 8 "Retrieving message body... done")
	  (intern (buffer-name) vm-buffers-needing-display-update)
	  (when (vm-interactive-p)
	    (vm-update-summary-and-mode-line))))
      )))

(cl-defun vm-retrieve-real-message-body (mm &key
					  (fetch nil) (register nil) 
					  (fail nil))
  "Retrieve the body of a real message MM from its external
source and insert it into the Folder buffer.  

If FETCH is non-nil, then the retrieval is for a temporary
message fetch.  If REGISTER is non-nil, then register it as a
fetched message If FAIL is non-nil, then fail for any errors
during retrieval.

Gives an error if unable to retrieve message."
  (if (not (eq (vm-message-access-method-of mm) 'imap))
      (message "External messages currently available only for imap folders.")
    (with-current-buffer (vm-buffer-of mm)
      (save-restriction
       (widen)
       (narrow-to-region (marker-position (vm-headers-of mm)) 
			 (marker-position (vm-text-end-of mm)))
       (let ((fetch-method (vm-message-access-method-of mm))
	     (vm-folder-read-only (and vm-folder-read-only (not fetch)))
	     (inhibit-read-only t)
	     ;; (buffer-read-only nil)    ; seems redundant
	     (buffer-undo-list t)	; why this?  USR, 2010-06-11
	     (modified (buffer-modified-p))
	     (fetch-result nil)
	     (testing 0))
	 (goto-char (vm-text-of mm))
	 ;; Check to see that we are at the right place
	 (vm-assert (save-excursion (forward-line -1) (looking-at "\n")))
	 (vm-increment testing)

	 (delete-region (point) (point-max))
	 ;; Remember that this does I/O and accept-process-output,
	 ;; allowing concurrent threads to run!!!  USR, 2010-07-11
	 (condition-case err
	     (setq fetch-result
		   (apply (intern (format "vm-fetch-%s-message" fetch-method))
			  mm nil))
	   (error 
	    (if fail
		(error "Unable to load message; %s"
		       (error-message-string err))
	      (vm-warn 0 0 "Unable to load message; %s" 
		       (error-message-string err)))))
	 (when fetch-result
	   (vm-assert (eq (point) (marker-position (vm-text-of mm))))
	   (vm-increment testing)
	   ;; delete the new headers
	   (delete-region 
	    (vm-text-of mm)
	    (or (re-search-forward "\n\n" (point-max) t) (point-max)))
	   (vm-assert (eq (point) (marker-position (vm-text-of mm))))
	   (vm-increment testing)
	   ;; fix markers now
	   (set-marker (vm-text-end-of mm) (point-max))
	   (vm-assert (eq (point) (marker-position (vm-text-of mm))))
	   (vm-assert (save-excursion (forward-line -1) (looking-at "\n")))
	   (vm-increment testing)
	   ;; now care for the layout of the message
	   (vm-set-mime-layout-of mm (vm-mime-parse-entity-safe mm))
	   ;; update the message data
	   (vm-set-body-to-be-retrieved-flag mm nil)
	   (vm-set-body-to-be-discarded-flag mm nil)
	   (vm-set-line-count-of mm nil)
	   (vm-set-byte-count-of mm nil)
	   ;; update the virtual messages
	   (vm-update-virtual-messages mm :message-changing nil)
	   (vm-restore-buffer-modified-p modified (vm-buffer-of mm))

	   (vm-assert (eq (point) (marker-position (vm-text-of mm))))
	   (vm-assert (save-excursion (forward-line -1) (looking-at "\n")))
	   (vm-increment testing)
	   (when register
	     (vm-register-fetched-message mm))))))))

;;;###autoload
(defun vm-refresh-message ()
  "Reload the message body from its permanent location.  Currently
this facilty is only available for IMAP folders."
  (interactive)
  (vm-unload-message 1 t)
  (vm-load-message)
  (vm-set-edited-flag-of (vm-current-message) nil)
  (intern (buffer-name) vm-buffers-needing-display-update)
  (let ((vm-preview-lines nil))
    (vm-present-current-message)))

;;;###autoload
(defun vm-unload-message (&optional count physical)
  "Unload the message body, i.e., delete it from the folder
buffer.  It can be retrieved again in future from its permanent
external location.  Currently this facility is only available for
IMAP folders.

With a prefix argument COUNT, the current message and the next 
COUNT - 1 messages are unloaded.  A negative argument means
the current message and the previous |COUNT| - 1 messages are
unloaded.

When invoked on marked messages (via `vm-next-command-uses-marks'), only 
marked messages are unloaded, other messages are ignored.  If
applied to collapsed threads in summary and thread operations are
enabled via `vm-enable-thread-operations' then all messages in
the thread are unloaded.

If the optional argument PHYSICAL is non-nil, then the message is
physically discarded.  Otherwise, the discarding may be delayed until
the folder is saved."
  (interactive "p")
  (if (vm-interactive-p)
      (vm-follow-summary-cursor))
  (vm-select-folder-buffer-and-validate 1 (vm-interactive-p))
  (vm-error-if-folder-read-only)
  (when (null count) 
    (setq count 1))
  (let ((mlist (vm-select-operable-messages
		count (vm-interactive-p) "Unload"))
	(buffer-undo-list t)
	;; (errors 0)
	m mm)
    (save-excursion
      (setq count 0)
      (while mlist
	(setq m (car mlist))
	(setq mm (vm-real-message-of m))
	(set-buffer (vm-buffer-of mm))
	(cond ((null (vm-message-can-be-external mm)))
	      ((vm-body-to-be-retrieved-of mm))
	      ((vm-body-to-be-discarded-of mm)
	       (when physical
		 (vm-discard-real-message-body mm)
		 (setq count (1+ count))))
	      (t
	       (if physical
		   (vm-discard-real-message-body mm)
		 ;; Register the message as fetched instead of actually
		 ;; discarding the message
		 (vm-register-fetched-message mm))
	       (setq count (1+ count))))
	(setq mlist (cdr mlist))))
    (if (= count 1) 
	(vm-inform 5 "Message body discarded")
      (vm-inform 5 "%s message bodies discarded" 
		 (if (= count 0) "No" count)))
    (vm-mark-folder-modified-p)
    (vm-update-summary-and-mode-line)
    ))

(defun vm-discard-real-message-body (mm)
  "Discard the real message body of MM from its Folder buffer."
  (if (not (vm-message-can-be-external mm))
      (vm-set-body-to-be-discarded-flag mm nil)
    (save-current-buffer
      (set-buffer (vm-buffer-of mm))
      (save-restriction
       (widen)
       (let ((inhibit-read-only t)
	     ;; (buffer-read-only nil)     ; seems redundant
	     (modified (buffer-modified-p)))
	 (goto-char (vm-text-of mm))
	 ;; Check to see that we are at the right place
	 (if (or (bobp)
		 (save-excursion (forward-line -1) (looking-at "\n")))
	     (progn
	       (delete-region (point) (vm-text-end-of mm))
	       (vm-set-mime-layout-of mm nil)
	       (vm-set-body-to-be-retrieved-flag mm t)
	       (vm-set-body-to-be-discarded-flag mm nil)
	       (vm-set-line-count-of mm nil)
	       (vm-update-virtual-messages mm :message-changing nil)
	       (vm-restore-buffer-modified-p modified (vm-buffer-of mm)))
	   (if (y-or-n-p
		(concat "VM internal error: "
			"headers of a message have been corrupted. "
			"Continue? "))
	       (progn
		 (vm-warn 1 5 (concat "The damaged message, with UID %s, "
				      "is left in the folder")
			  (vm-imap-uid-of mm))
		 (vm-set-body-to-be-discarded-flag mm nil))
	     (error "Aborted operation")))
	 )))))


;;; vm-folder.el ends here
