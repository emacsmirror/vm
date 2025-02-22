;;; vm-imap.el ---  Simple IMAP4 (RFC 2060) client for VM  -*- lexical-binding: t; -*-
;;
;; This file is part of VM
;;
;; Copyright (C) 1998, 2001, 2003 Kyle E. Jones
;; Copyright (C) 2003-2006 Robert Widhopf-Fenk
;; Copyright (C) 2006 Robert P. Goldman
;; Copyright (C) 2008-2011 Uday S. Reddy
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
(require 'vm-misc)
(require 'vm-motion)
(require 'vm-reply)                     ;vm-mail-mode-remove-header
(require 'sendmail)
(require 'utf7)
(eval-when-compile (require 'cl-lib))

(declare-function vm-session-initialization 
		  "vm.el" ())
(declare-function vm-submit-bug-report 
		  "vm.el" (&optional pre-hooks post-hooks))
(declare-function open-network-stream 
		  "subr.el" (name buffer host service &rest parameters))
;; (declare-function vm-imap-make-session 
;; 		  "vm-imap.el" (source interactive &key 
;; 				     (folder-buffer nil)
;; 				     (purpose nil)
;; 				     (retry nil)))

(defvar selectable-only) ;; FIXME: Add `vm-' prefix!

;;; To-Do  (USR)
;; - Need to ensure that new imap sessions get created as and when needed.

;; ------------------------------------------------------------------------
;; The IMAP session protocol
;; ------------------------------------------------------------------------

;; movemail: Folder-specific IMAP sessions are created and destroyed
;; for each get-new-mail.  (Same as in VM 7.19)
;;
;; expunge: expunge-imap-messages creates and destroys sessions.
;; checkmail: check-for-mail also creates and destroys sessions.

;; checkmail: check-for-mail also creates and destroys sessions.

;; IMAP-FCC: Rob F's save-composition creates and destroys its own sessions.

;; folders: imap-folder-completion-list creates and destroys (?) sessions.

;; create, delete folder, rename folder, folders: They are also
;; created and destroyed at a global level for operations like
;; create-mailbox.  (VM 7.19 didn't destroy them in the end, but we
;; do.)

;; general operation: synchronize-folder creates an IMAP session but
;; leaves it active.  Since session is linked to the folder buffer,
;; the folder can use it for other operations like fetch-imap-message
;; and copy-message.  The next time a synchronize-folder is done, this
;; session is killed and a fresh session is created.

;; ------------------------------------------------------------------------
;;; Utilities
;; ------------------------------------------------------------------------


;;
;; vm-folder-access-data
;;
;; See the info manual section on "Folder Internals" for the structure
;; of the data stored here.
;;
;; The following functions are based on cached folder-access-data.
;; They will only function when the IMAP process is "valid" and the
;; server message data is non-nil.

(defun vm-folder-imap-msn-uid (n)
  "Returns the UID of the message sequence number N on the IMAP
server, using cached data."
  (let ((cell (assq n (vm-folder-imap-uid-list))))
    (nth 1 cell)))

(defun vm-folder-imap-msn-size (n)
  "Returns the message size of the message sequence number N on the
IMAP server, using cached data."
  (let ((cell (assq n (vm-folder-imap-uid-list))))
    (nth 2 cell)))

(defun vm-folder-imap-msn-flags (n)
  "Returns the message flags of the message sequence number N on the
IMAP server, using cached data."
  (let ((cell (assq n (vm-folder-imap-uid-list))))
    (nthcdr 2 cell)))

(defun vm-folder-imap-message-msn (m)
  "Returns the message sequence number of message M on the IMAP
server, using cached data."
  (let ((uid-key (intern (vm-imap-uid-of m) (vm-folder-imap-uid-obarray))))
    (and (boundp uid-key) (symbol-value uid-key))))

(defun vm-folder-imap-message-size (m)
  "Returns the size of the message M on the IMAP server (as a string),
using cached data."
  (let ((uid-key (intern (vm-imap-uid-of m) (vm-folder-imap-flags-obarray))))
    (and (boundp uid-key) (car (symbol-value uid-key)))))

(defun vm-folder-imap-message-flags (m)
  "Returns the flags of the message M on the IMAP server,
using cached data."
  (let ((uid-key (intern (vm-imap-uid-of m) (vm-folder-imap-flags-obarray))))
    (and (boundp uid-key) (cdr (symbol-value uid-key)))))

(defun vm-folder-imap-uid-msn (uid)
  "Returns the message sequence number of message with UID on the IMAP
server, using cached data."
  (let ((uid-key (intern uid (vm-folder-imap-uid-obarray))))
    (and (boundp uid-key) (symbol-value uid-key))))

(defun vm-folder-imap-uid-message-size (uid)
  "Returns the size of the message with UID on the IMAP server (as a
string), using cached data."
  (let ((uid-key (intern uid (vm-folder-imap-flags-obarray))))
    (and (boundp uid-key) (car (symbol-value uid-key)))))

(defun vm-folder-imap-uid-message-flags (uid)
  "Returns the flags of the message with UID on the IMAP server,
using cached data."
  (let ((uid-key (intern uid (vm-folder-imap-flags-obarray))))
    (and (boundp uid-key) (cdr (symbol-value uid-key)))))

;; Status indicator vector
;; timer
(defsubst vm-imap-status-timer (o) (aref o 0))
;; whether the current status has been reported already
(defsubst vm-imap-status-did-report (o) (aref o 1))
;; mailbox specification
(defsubst vm-imap-status-mailbox (o) (aref o 2))
;; message number (count) of the message currently being retrieved
(defsubst vm-imap-status-currmsg (o) (aref o 3))
;; total number of mesasges that need to be retrieved in this round
(defsubst vm-imap-status-maxmsg (o) (aref o 4))
;; amount of the current message that has been retrieved
(defsubst vm-imap-status-got (o) (aref o 5))
;; size of the current message
(defsubst vm-imap-status-need (o) (aref o 6))
;; Data for the message last reported
(defsubst vm-imap-status-last-mailbox (o) (aref o 7))
(defsubst vm-imap-status-last-currmsg (o) (aref o 8))
(defsubst vm-imap-status-last-maxmsg (o) (aref o 9))
(defsubst vm-imap-status-last-got (o) (aref o 10))
(defsubst vm-imap-status-last-need (o) (aref o 11))

(defsubst vm-set-imap-status-timer (o val) (aset o 0 val))
(defsubst vm-set-imap-status-did-report (o val) (aset o 1 val))
(defsubst vm-set-imap-status-mailbox (o val) (aset o 2 val))
(defsubst vm-set-imap-status-currmsg (o val) (aset o 3 val))
(defsubst vm-set-imap-status-maxmsg (o val) (aset o 4 val))
(defsubst vm-set-imap-status-got (o val) (aset o 5 val))
(defsubst vm-set-imap-status-need (o val) (aset o 6 val))
(defsubst vm-set-imap-status-last-mailbox (o val) (aset o 7 val))
(defsubst vm-set-imap-status-last-currmsg (o val) (aset o 8 val))
(defsubst vm-set-imap-status-last-maxmsg (o val) (aset o 9 val))
(defsubst vm-set-imap-status-last-got (o val) (aset o 10 val))
(defsubst vm-set-imap-status-last-need (o val) (aset o 11 val))

(defun vm-imap-start-status-timer ()
  (let ((blob (make-vector 12 nil))
	timer)
    (setq timer (run-with-timer 2 2 #'vm-imap-report-retrieval-status blob))
    (vm-set-imap-status-timer blob timer)
    blob ))

(defun vm-imap-stop-status-timer (status-blob)
  (if (vm-imap-status-did-report status-blob)
      (vm-inform 6 ""))
  (if (fboundp 'disable-timeout)
      (disable-timeout (vm-imap-status-timer status-blob))
    (cancel-timer (vm-imap-status-timer status-blob))))

(defun vm-imap-report-retrieval-status (o)
  (condition-case _err
      (progn 
	(vm-set-imap-status-did-report o t)
	(cond ((null (vm-imap-status-got o)) t)
	      ;; should not be possible, but better safe...
	      ((not (eq (vm-imap-status-mailbox o) 
			(vm-imap-status-last-mailbox o))) 
	       t)
	      ((not (eq (vm-imap-status-currmsg o) 
			(vm-imap-status-last-currmsg o)))
	       t)
	      (t 
	       (vm-inform 7 "Retrieving message %d (of %d) from %s, %s..."
			(vm-imap-status-currmsg o)
			(vm-imap-status-maxmsg o)
			(vm-imap-status-mailbox o)
			(if (vm-imap-status-need o)
			    (format "%d%%%s"
				    (truncate (* 100 (vm-imap-status-got o))
					      (vm-imap-status-need o))
				    (if (eq (vm-imap-status-got o)
					    (vm-imap-status-last-got o))
					" (stalled)"
				      ""))
			  "100%")
			)))
	(vm-set-imap-status-last-mailbox o (vm-imap-status-mailbox o))
	(vm-set-imap-status-last-currmsg o (vm-imap-status-currmsg o))
	(vm-set-imap-status-last-maxmsg o (vm-imap-status-maxmsg o))
	(vm-set-imap-status-last-got o (vm-imap-status-got o))
	(vm-set-imap-status-last-need o (vm-imap-status-need o)))
    (error nil)))

;; For logging IMAP sessions

(defvar vm-imap-log-sessions nil
  "* Boolean flag to turn on or off logging of IMAP sessions.  Meant
  for debugging IMAP server interactions.")

(defvar vm-imap-tokens nil
  "Internal variable used to store a trail of the lexical and parsing
activity carried out on the IMAP process output.  Used for debugging
purposes.")

(defsubst vm-imap-init-log ()
  (setq vm-imap-tokens nil))

(defsubst vm-imap-log-token (token)
  (if vm-imap-log-sessions
      (setq vm-imap-tokens (cons token vm-imap-tokens))))
  
(defsubst vm-imap-log-tokens (tokens)
  (if vm-imap-log-sessions
      (setq vm-imap-tokens (append (nreverse tokens) vm-imap-tokens))))

;; For verification of session protocol
;; Possible values are 
;; 'active - active session present
;; 'valid - message sequence numbers are valid 
;;	validity is preserved by FETCH, STORE and SEARCH operations
;; 'inactive - session is inactive

;; (defvar vm-imap-session-type nil)  ; moved to vm-vars.el

(defsubst vm-imap-session-type:set (type)
  (setq vm-imap-session-type type))

(defsubst vm-imap-session-type:make-active ()
  (if (eq vm-imap-session-type 'inactive)
      (setq vm-imap-session-type 'active)))

(defsubst vm-imap-session-type:assert (type)
  (vm-assert (eq vm-imap-session-type type)))

(defsubst vm-imap-folder-session-type:assert (type)
  (with-current-buffer (process-buffer (vm-folder-imap-process))
    (vm-assert (eq vm-imap-session-type type))))

(defsubst vm-imap-session-type:assert-active ()
  (vm-assert (or (eq vm-imap-session-type 'active) 
		 (eq vm-imap-session-type 'valid))))

;; Handling mailbox names and maildrop specs

(defsubst vm-imap-quote-string (string)
  (vm-with-string-as-temp-buffer string 'vm-imap-quote-buffer))

(defun vm-imap-quote-buffer ()
  (goto-char (point-min))
  (insert "\"")
  (while (re-search-forward "[\"\\]" nil t)
    (forward-char -1)
    (insert "\\")
    (forward-char 1))
  (goto-char (point-max))
  (insert "\""))

(defsubst vm-imap-quote-mailbox-name (name)
  (vm-imap-quote-string (utf7-encode name t)))

(defsubst vm-imap-encode-mailbox-name (name)
  (utf7-encode name t))

(defsubst vm-imap-decode-mailbox-name (name)
  (utf7-decode name t))

;;;###autoload
(defun vm-imap-make-filename-for-spec (spec)
  "Returns a cache file name appropriate for the IMAP maildrop
specification SPEC."
  (let (md5)
    (setq spec (vm-imap-normalize-spec spec))
    (setq md5 (vm-md5-string spec))
    (expand-file-name (concat "imap-cache-" md5)
		      (or vm-imap-folder-cache-directory
			  vm-folder-directory
			  (getenv "HOME")))))

;;;###autoload
(defun vm-imap-normalize-spec (spec)
  (let (comps)
    (setq comps (vm-imap-parse-spec-to-list spec))
    (setcar (vm-last comps) "*")		; scrub password
    (setcar comps "imap")		; standardise protocol name
    (setcar (nthcdr 2 comps) "*")	; scrub portnumber
    (setcar (nthcdr 4 comps) "*")	; scrub authentication method
    (setq spec (mapconcat (function identity) comps ":"))
    spec ))

;;;###autoload
(defun vm-imap-account-name-for-spec (spec)
  "Returns the IMAP account name for maildrop specification SPEC, by
looking up `vm-imap-account-alist' or nil if there is no such account."
  (let ((alist vm-imap-account-alist)
	comps account-comps)
    (setq comps (vm-imap-parse-spec-to-list spec))
    (catch 'return
    (while alist
      (setq account-comps (vm-imap-parse-spec-to-list (car (car alist))))
      (if (and (equal (nth 1 comps) (nth 1 account-comps)) ; host
	       (equal (nth 5 comps) (nth 5 account-comps))) ; login
	  (throw 'return (cadr (car alist)))
	(setq alist (cdr alist))))
    nil)))

;;;###autoload
(defun vm-imap-folder-name-for-spec (spec)
  "Returns the IMAP folder name for maildrop specification SPEC, by
looking up `vm-imap-account-alist' or nil if there is no such account."
  (let ((alist vm-imap-account-alist)
	comps account-comps)
    (setq comps (vm-imap-parse-spec-to-list spec))
    (catch 'return
    (while alist
      (setq account-comps (vm-imap-parse-spec-to-list (car (car alist))))
      (if (and (equal (nth 1 comps) (nth 1 account-comps)) ; host
	       (equal (nth 5 comps) (nth 5 account-comps))) ; login
	  (throw 'return (nth 3 comps))
	(setq alist (cdr alist))))
    nil)))

;;;###autoload
(defun vm-imap-folder-for-spec (spec)
  "Returns the IMAP folder for maildrop specification SPEC in the
format account:mailbox."
  (let (comps account-comps (alist vm-imap-account-alist))
    (setq comps (vm-imap-parse-spec-to-list spec))
    (catch 'return
    (while alist
      (setq account-comps (vm-imap-parse-spec-to-list (car (car alist))))
      (if (and (equal (nth 1 comps) (nth 1 account-comps)) ; host
	       (equal (nth 5 comps) (nth 5 account-comps))) ; login
	  (throw 'return (concat (cadr (car alist)) ":" (nth 3 comps)))
	(setq alist (cdr alist))))
    nil)))

;;;###autoload
(defun vm-imap-spec-for-account (account)
  "Returns the IMAP maildrop spec for ACCOUNT, by looking up
`vm-imap-account-alist' or nil if there is no such account."
  (car (rassoc (list account) vm-imap-account-alist)))

;;;###autoload
(defun vm-imap-parse-spec-to-list (spec)
  "Parses the IMAP maildrop specification SPEC and returns a list of
its components."
  (let ((list (vm-parse spec "\\([^:]+\\):?" 1 6)))
    ;; (append (butlast list 4)
    ;;         (cons (utf7-decode (nth 3 list) t)
    ;;               (last list 3)))
    list
    ))

;;;###autoload
(defun vm-imap-encode-list-to-spec (list)
  "Convert a LIST of components into a maildrop specification."
    (mapconcat 'identity list ":")
  ;; (mapconcat 'identity
  ;;            (append (butlast list 4)
  ;;                    (cons (utf7-encode (nth 3 list) t)
  ;;                          (last list 3)))
  ;;            ":")
  )

;;;###autoload
(defun vm-imap-spec-for-mailbox (spec mailbox)
  "Return a modified version of the maildrop specification SPEC
for accessing MAILBOX."
  (let ((list (vm-parse spec "\\([^:]+\\):?" 1 6)))
    (mapconcat 'identity 
	       (append (vm-elems 3 list) (cons mailbox (nthcdr 4 list)))
	       ":")))

(defun vm-imap-spec-list-to-host-alist (spec-list)
  (let (host-alist spec) ;;  host
    (while spec-list
      (setq spec (vm-imapdrop-sans-password-and-mailbox (car spec-list)))
      (setq host-alist (cons
			(list
			 (nth 1 (vm-imap-parse-spec-to-list spec))
			 spec)
			host-alist)
	    spec-list (cdr spec-list)))
    host-alist ))

;; Simple macros

(defsubst vm-imap-delete-message (process n)
  (vm-imap-delete-messages process n n))

(if (fboundp 'define-error)
    (progn
      (define-error 'vm-imap-protocol-error "IMAP protocol error")
      (define-error 'vm-imap-normal-error "IMAP error" 'vm-imap-protocol-error)
      )
  (put 'vm-imap-protocol-error 'error-conditions
       '(vm-imap-protocol-error error))
  (put 'vm-imap-protocol-error 'error-message "IMAP protocol error")
  (put 'vm-imap-normal-error 'error-conditions
       '(vm-imap-protocol-error vm-imap-normal-error error))
  (put 'vm-imap-normal-error 'error-message "IMAP error")
  )

(defsubst vm-imap-protocol-error (&rest args)
  (let ((local (make-local-variable 'vm-imap-keep-trace-buffer)))
    (unless (symbol-value local) (set local 1)))
  (signal 'vm-imap-protocol-error (list (apply 'format args))))

(defsubst vm-imap-normal-error (&rest args)
  (let ((local (make-local-variable 'vm-imap-keep-trace-buffer)))
    (unless (symbol-value local) (set local 1)))
  (signal 'vm-imap-normal-error (list (apply 'format args))))

(defsubst vm-imap-capability (cap &optional process)
  (if process
      (with-current-buffer (process-buffer process)
	(memq cap vm-imap-capabilities))
    (memq cap vm-imap-capabilities)))

(defsubst vm-imap-auth-method (auth)
  (memq auth vm-imap-auth-methods))

(defsubst vm-accept-process-output (process)
  "Accept output from PROCESS.  

The variable `vm-imap-server-timeout' specifies how many seconds
to wait before timing out.  If a timeout occurs, an exception is
thrown.  In such a situation, typically VM cannot proceed."
  ;; protect against possible buffer change due to bug in Emacs
  (let ((buf (current-buffer))
	(got-output (accept-process-output process vm-imap-server-timeout)))
    (if got-output
	(when (not (equal (current-buffer) buf))
	  (when (string-lessp "24" emacs-version)
	    ;; the Emacs bug should have been fixed in version 24
	    (vm-warn 0 2 
	     "Emacs process output error: Buffer changed to %s" 
	     (current-buffer)))
	  ;; recover from the bug
	  (set-buffer buf))
      (vm-imap-protocol-error "Timed out for response from the IMAP server"))))


;; (defvar vm-imap-connection-mode 'online)  ; moved to vm-vars.el


;; -----------------------------------------------------------------------
;;; IMAP Spool
;; 
;; -- Functions that treat IMAP mailboxes as spools to get mail
;; -- into local buffers and subsequently expunge on the server.
;; -- USR thinks this is obsolete functionality that should not be
;; -- used. Use 'IMAP folders' instead.
;;
;; handler methods:
;; vm-imap-move-mail: (string & string) -> bool
;; vm-imap-check-mail: string -> void
;;
;; interactive commands:
;; vm-expunge-imap-messages: () -> void
;;
;; vm-imap-prune-retrieval-entries: (string & list &
;;				     (retrieval-entry -> bool) -> list
;; vm-imap-clear-invalid-retrieval-entries: (string & list & string) -> list
;; ------------------------------------------------------------------------


(defsubst vm-imap-fetch-message (process n use-body-peek 
					   &optional headers-only)
  "Fetch IMAP message with sequence number N via PROCESS, which
must be a network connection to an IMAP server.  If the optional
argument HEADERS-ONLY is non-nil, then only the headers are
retrieved."
  (vm-imap-fetch-messages process n n use-body-peek headers-only))

(defun vm-imap-fetch-messages (process beg end use-body-peek 
				       &optional headers-only) 
  "Fetch IMAP message with sequence numbers in the range BEG and
END via PROCESS, which must be a network connection to an IMAP
server.  If the optional argument HEADERS-ONLY is non-nil, then
only the headers are retrieved."
  (let ((fetchcmd
         (if headers-only
             (if use-body-peek "(BODY.PEEK[HEADER])" "(RFC822.HEADER)")
           (if use-body-peek "(BODY.PEEK[])" "(RFC822.PEEK)"))))
    (vm-imap-send-command process (format "FETCH %d:%d %s" beg end fetchcmd))))

(defsubst vm-imap-fetch-uid-message (process uid use-body-peek 
					   &optional headers-only)
  "Fetch IMAP message with UID via PROCESS, which must be a
network connection to an IMAP server.  If the optional argument
HEADERS-ONLY is non-nil, then only the headers are retrieved."
  (let ((fetchcmd
         (if headers-only
             (if use-body-peek "(BODY.PEEK[HEADER])" "(RFC822.HEADER)")
           (if use-body-peek "(BODY.PEEK[])" "(RFC822.PEEK)"))))
    (vm-imap-send-command 
     process (format "UID FETCH %s:%s %s" uid uid fetchcmd))))

;; Our goal is to drag the mail from the IMAP maildrop to the crash box.
;; just as if we were using movemail on a spool file.
;; We remember which messages we have retrieved so that we can
;; leave the message in the mailbox, and yet not retrieve the
;; same messages again and again.

;;;###autoload
(defun vm-imap-move-mail (source destination)
  "move-mail function for IMAP folders.  SOURCE is the IMAP mail box
from which mail is to be moved and DESTINATION is the VM folder."
  ;;--------------------------
  (vm-buffer-type:set 'folder)
  ;;--------------------------
  (let ((process nil)
	(m-per-session vm-imap-messages-per-session)
	(b-per-session vm-imap-bytes-per-session)
	(handler (find-file-name-handler source 'vm-imap-move-mail))
	(folder (or (vm-imap-folder-for-spec source)
		    (vm-safe-imapdrop-string source)))
	(statblob nil)
	(msgid (list nil nil (vm-imapdrop-sans-password source) 'uid))
	(imap-retrieved-messages vm-imap-retrieved-messages)
	(did-delete nil)
	(did-retain nil)
	(source-nopwd (vm-imapdrop-sans-password source))
	use-body-peek auto-expunge x select source-list uid
	can-delete read-write uid-validity
	mailbox mailbox-count message-size response ;; recent-count
	n (retrieved 0) retrieved-bytes process-buffer)
    (setq auto-expunge 
	  (cond ((setq x (assoc source vm-imap-auto-expunge-alist))
		 (cdr x))
		((setq x (assoc source-nopwd vm-imap-auto-expunge-alist))
		 (cdr x))
		(vm-imap-expunge-after-retrieving
		 t)
		((member source vm-imap-auto-expunge-warned)
		 nil)
		(t
		 (vm-warn 6 1 
			  "Warning: IMAP folder is not set to auto-expunge")
		 (setq vm-imap-auto-expunge-warned
		       (cons source vm-imap-auto-expunge-warned))
		 nil)))

    (unwind-protect
	(catch 'end-of-session
	  (when handler
	    (throw 'end-of-session
		   (funcall handler 'vm-imap-move-mail source destination)))
	  (setq process 
		(vm-imap-make-session source vm-imap-ok-to-ask 
				      :folder-buffer (current-buffer)
				      :purpose "movemail"))
	  (or process (throw 'end-of-session nil))
	  (setq process-buffer (process-buffer process))
	  (with-current-buffer process-buffer
	    ;;--------------------------------
	    (vm-buffer-type:enter 'process)
	    ;;--------------------------------
	    ;; find out how many messages are in the box.
	    (setq source-list (vm-parse source "\\([^:]+\\):?")
		  mailbox (nth 3 source-list))
	    (setq select (vm-imap-select-mailbox process mailbox t))
	    (setq mailbox-count (nth 0 select)
		  ;; recent-count (nth 1 select)
		  uid-validity (nth 2 select)
		  read-write (nth 3 select)
		  can-delete (nth 4 select)
		  use-body-peek (vm-imap-capability 'IMAP4REV1))
	    ;;--------------------------------
	    (vm-imap-session-type:set 'valid)
	    ;;--------------------------------
	    ;; The session type is not really "valid" because the uid
	    ;; and flags data has not been obtained.  But since
	    ;; move-mail uses a short, bursty session, the effect is
	    ;; that of a valid session throughout.

	    ;; sweep through the retrieval list, removing entries
	    ;; that have been invalidated by the new UIDVALIDITY
	    ;; value.
	    (setq imap-retrieved-messages
		  (vm-imap-clear-invalid-retrieval-entries
		   source-nopwd
		   imap-retrieved-messages
		   uid-validity))
	    ;; loop through the maildrop retrieving and deleting
	    ;; messages as we go.
	    (setq n 1 retrieved-bytes 0)
	    (setq statblob (vm-imap-start-status-timer))
	    (vm-set-imap-status-mailbox statblob folder)
	    (vm-set-imap-status-maxmsg statblob mailbox-count)
	    (while (and (<= n mailbox-count)
			(or (not (natnump m-per-session))
			    (< retrieved m-per-session))
			(or (not (natnump b-per-session))
			    (< retrieved-bytes b-per-session)))
	      (catch 'skip
		(vm-set-imap-status-currmsg statblob n)
		(let (list)
		  (setq list (vm-imap-get-uid-list process n n))
		  (setq uid (cdr (car list)))
		  (setcar msgid uid)
		  (setcar (cdr msgid) uid-validity)
		  (when (member msgid imap-retrieved-messages)
		    (if vm-imap-ok-to-ask
			(vm-inform 
			 7 
			 "Skipping message %d (of %d) from %s (retrieved already)..."
			 n mailbox-count folder))
		    (throw 'skip t)))
		(setq message-size (vm-imap-get-message-size process n))
		(vm-set-imap-status-need statblob message-size)
		(when (and (integerp vm-imap-max-message-size)
			   (> message-size vm-imap-max-message-size)
			   (progn
			     (setq response
				   (if vm-imap-ok-to-ask
				       (vm-imap-ask-about-large-message
					process message-size n)
				     'skip))
			     (not (eq response 'retrieve))))
		  (cond ((and read-write can-delete (eq response 'delete))
			 (vm-inform 6 "Deleting message %d..." n)
			 (vm-imap-delete-message process n)
			 (setq did-delete t))
			(vm-imap-ok-to-ask
			 (vm-inform 7 "Skipping message %d..." n))
			(t 
			 (vm-inform 
			  5
			  "Skipping message %d in %s, too large (%d > %d)..."
			  n folder message-size vm-imap-max-message-size)))
		  (throw 'skip t))
		(vm-inform 7 "Retrieving message %d (of %d) from %s..."
			 n mailbox-count folder)
                (vm-imap-fetch-message process n
				       use-body-peek nil) ; no headers-only
                (vm-imap-retrieve-to-target process destination
					    statblob use-body-peek) 
		(vm-imap-read-ok-response process)
                (vm-inform 7 "Retrieving message %d (of %d) from %s...done"
                         n mailbox-count folder)
		(vm-increment retrieved)
		(and b-per-session
		     (setq retrieved-bytes (+ retrieved-bytes message-size)))
		(if auto-expunge
		    ;; The user doesn't want the messages kept in the mailbox.
		    (when (and read-write can-delete)
		      (vm-imap-delete-message process n)
		      (setq did-delete t))
		  ;; If message retained on the server, record the UID
		  (setq imap-retrieved-messages
			(cons (copy-sequence msgid) imap-retrieved-messages))
		  (setq did-retain t)))
	      (vm-increment n))
	    (when did-delete
	      ;; CLOSE forces an expunge and avoids the EXPUNGE
	      ;; responses.
	      (vm-imap-send-command process "CLOSE")
	      (vm-imap-read-ok-response process)
	      ;;----------------------------------
	      (vm-imap-session-type:set 'inactive)
	      ;;----------------------------------
	      )
	    (not (equal retrieved 0))	; return result
	    ))
      ;; unwind-protections
      ;;-------------------
      (vm-buffer-type:exit)
      ;;-------------------
      (when did-retain
	(setq vm-imap-retrieved-messages imap-retrieved-messages)
	(when (eq vm-flush-interval t)
	  (vm-stuff-imap-retrieved))
	(vm-mark-folder-modified-p (current-buffer)))
      (when statblob 
	(vm-imap-stop-status-timer statblob))
      (when process
	(vm-imap-end-session process))
      )))

(defun vm-imap-check-mail (source)
  "Check if there is new mail on the IMAP server mailbox SOURCE.
Returns a boolean value."
  ;;--------------------------
  (vm-buffer-type:set 'folder)
  ;;--------------------------
  (let ((process nil)
	(handler (find-file-name-handler source 'vm-imap-check-mail))
	(retrieved vm-imap-retrieved-messages)
	(imapdrop (vm-imapdrop-sans-password source))
	(count 0)
	msg-count uid-validity ;; recent-count
	x response select mailbox source-list
	) ;; result
    (unwind-protect
	(prog1
	    (save-excursion		; = save-current-buffer?
	      ;;----------------------------
	      (vm-buffer-type:enter 'process)
	      ;;----------------------------
	      (catch 'end-of-session
		(when handler
		  (throw 'end-of-session
			 (funcall handler 'vm-imap-check-mail source)))
		(setq process 
		      (vm-imap-make-session source nil 
					    :folder-buffer (current-buffer)
					    :purpose "checkmail"))
		(unless process (throw 'end-of-session nil))
		(set-buffer (process-buffer process))
		(setq source-list (vm-parse source "\\([^:]+\\):?")
		      mailbox (nth 3 source-list))
		(setq select (vm-imap-select-mailbox process mailbox t)
		      msg-count (car select)
		      ;; recent-count (nth 1 select)
		      uid-validity (nth 2 select))
		(when (zerop msg-count)
		  (vm-store-folder-totals source '(0 0 0 0))
		  (throw 'end-of-session nil))
		;; sweep through the retrieval list, removing entries
		;; that have been invalidated by the new UIDVALIDITY
		;; value.
		(setq retrieved
		  (vm-imap-clear-invalid-retrieval-entries imapdrop
							   retrieved
							   uid-validity))
		(setq response (vm-imap-get-uid-list process 1 msg-count))
		(if (null response)
		    nil
		  (if (null (car response))
		      ;; (nil . nil) is returned if there are no
		      ;; messages in the mailbox.
		      (progn
			(vm-store-folder-totals source '(0 0 0 0))
			(throw 'end-of-session nil))
		    (while response
		      (if (not (and (setq x (assoc (cdr (car response))
						   retrieved))
				    (equal (nth 1 x) imapdrop)
				    (eq (nth 2 x) 'uid)))
			  (vm-increment count))
		      (setq response (cdr response))))
		  (vm-store-folder-totals source (list count 0 0 0))
		  (throw 'end-of-session (not (eq count 0))))
		(not (equal 0 (car select)))))

	  (setq vm-imap-retrieved-messages retrieved))

      ;; unwind-protections
      ;;-------------------
      (vm-buffer-type:exit)
      ;;-------------------
      (when process 
	(vm-imap-end-session process)
	;; (vm-imap-dump-uid-and-flags-data)
	))))

(defun vm-expunge-imap-messages ()
  "Deletes all messages from IMAP mailbox that have already been retrieved
into the current folder.  VM sets the \\Deleted flag on all such messages
on all the relevant IMAP servers and then immediately expunges."
  (interactive)
  (vm-follow-summary-cursor)
  (vm-select-folder-buffer-and-validate 0 (vm-interactive-p))
  (vm-error-if-virtual-folder)
  (let ((process nil)
	(source nil)
	(trouble nil)
	(delete-count 0)
	(vm-global-block-new-mail t)
	(vm-imap-ok-to-ask t)
	(did-delete nil)
	msg-count can-delete read-write uid-validity
	select-response source-list folder uid-alist mailbox data mp match)
    (unwind-protect
	(save-excursion			; save-current-buffer?
	  ;;------------------------
	  (vm-buffer-type:duplicate)
	  ;;------------------------
	  (setq vm-imap-retrieved-messages
		(sort vm-imap-retrieved-messages
		      (function 
		       (lambda (a b)
			 (cond ((string-lessp (nth 2 a) (nth 2 b)) t)
			       ((string-lessp (nth 2 b) (nth 2 a)) nil)
			       ((string-lessp (nth 1 a) (nth 1 b)) t)
			       ((string-lessp (nth 1 b) (nth 1 a)) nil)
			       ((string-lessp (nth 0 a) (nth 0 b)) t)
			       (t nil))))))
	  (setq mp vm-imap-retrieved-messages)
	  (while mp
	    (catch 'replay
	      (condition-case error-data
		  (progn
		    (setq data (car mp))
		    (when (not (equal source (nth 2 data)))
		      (when process
			(when did-delete
			  (vm-imap-send-command process "CLOSE")
			  (vm-imap-read-ok-response process)
			  ;;----------------------------------
			  (vm-imap-session-type:set 'inactive)
			  ;; (vm-imap-dump-uid-and-flags-data)
			  ;;----------------------------------
			  )
			(vm-imap-end-session process)
				
			(setq process nil
			      did-delete nil))
		      (setq source (nth 2 data))
		      (setq folder (or (vm-imap-folder-for-spec source)
				       (vm-safe-imapdrop-string source)))
		      (condition-case error-data
			  (progn
			    (vm-inform 6 "Opening IMAP session to %s..."
				     folder)
			    (setq process 
				  (vm-imap-make-session 
				   source vm-imap-ok-to-ask 
				   :folder-buffer (current-buffer)
				   :purpose "expunge"))
			    (if (null process)
				(signal 'vm-imap-protocol-error nil))
			    ;;--------------------------
			    (vm-buffer-type:set 'process)
			    ;;--------------------------
			    (set-buffer (process-buffer process))
			    (setq source-list (vm-parse source
							"\\([^:]+\\):?")
				  mailbox (nth 3 source-list)
				  select-response (vm-imap-select-mailbox
						   process mailbox t)
				  msg-count (car select-response)
				  uid-validity (nth 2 select-response)
				  read-write (nth 3 select-response)
				  can-delete (nth 4 select-response))
			    (setq mp
				  (vm-imap-clear-invalid-retrieval-entries
				   source mp uid-validity))
			    (unless (eq data (car mp))
				;; this entry must have been
				;; discarded as invalid, so
				;; skip it and process the
				;; entry that is now at the
				;; head of the list.
				(throw 'replay t))
			    (unless can-delete
			      (error "Can't delete messages in mailbox %s, skipping..." mailbox))
			    (unless read-write
			      (error "Mailbox %s is read-only, skipping..." mailbox))
			    (vm-inform 6 "Expunging messages in %s..." folder))
			(error
			 (if (cdr error-data)
			     (apply 'message (cdr error-data))
			   (vm-warn 0 2
			    "Couldn't open IMAP session to %s, skipping..."
			    folder))
			 (setq trouble (cons folder trouble))
			 (while (equal (nth 1 (car mp)) source)
			   (setq mp (cdr mp)))
			 (throw 'replay t)))
		      (when (zerop msg-count)
			(while (equal (nth 1 (car mp)) source)
			  (setq mp (cdr mp)))
			(throw 'replay t))
		      (setq uid-alist (vm-imap-get-uid-list
				       process 1 msg-count))
		      (vm-imap-session-type:make-active))
		    (when (setq match (rassoc (car data) uid-alist))
		      (vm-imap-delete-message process (car match))
		      (setq did-delete t)
		      (vm-increment delete-count)))
		(error
		 (setq trouble (cons folder trouble))
		 (vm-warn 0 2 "Something signaled: %s"
			  (prin1-to-string error-data))
		 (vm-inform 0 "Skipping rest of mailbox %s..." folder)
		 (sleep-for 2)
		 (while (equal (nth 2 (car mp)) source)
		   (setq mp (cdr mp)))
		 (throw 'replay t)))
	      (setq mp (cdr mp))))
	  (when did-delete
	    (vm-imap-send-command process "CLOSE")
	    (vm-imap-read-ok-response process)
	    ;;----------------------------------
	    (vm-imap-session-type:set 'inactive)
	    ;; (vm-imap-dump-uid-and-flags-data)
	    ;;----------------------------------
	    )
	  (if trouble
	      (progn
		;;--------------------------
		(vm-buffer-type:set 'scratch)
		;;--------------------------
		(set-buffer (get-buffer-create "*IMAP Expunge Trouble*"))
		(setq buffer-read-only nil)
		(erase-buffer)
		(insert (format "%s IMAP message%s expunged.\n\n"
				(if (zerop delete-count) "No" delete-count)
				(if (= delete-count 1) "" "s")))
		(insert "VM had problems expunging messages from:\n")
		(setq trouble (nreverse trouble))
		(setq mp trouble)
		(while mp
		  (insert "   " (car mp) "\n")
		  (setq mp (cdr mp)))
		(setq buffer-read-only t)
		(display-buffer (current-buffer)))
	    (vm-inform 5 "%s IMAP message%s expunged."
		     (if (zerop delete-count) "No" delete-count)
		     (if (= delete-count 1) "" "s"))))
      ;; unwind-protections
      ;;-------------------
      (vm-buffer-type:exit)
      ;;-------------------
      (when process (vm-imap-end-session process)))
    (unless trouble 
      (setq vm-imap-retrieved-messages nil)
      (when (> delete-count 0)
	(vm-mark-folder-modified-p (current-buffer))))))

(defun vm-prune-imap-retrieved-list (source)
  "Prune the X-VM-IMAP-Retrieved header of the current folder by
examining which messages are still present in SOURCE.  SOURCE
should be a maildrop folder on an IMAP server.         USR, 2011-04-06"
  (interactive
   (let ((this-command this-command)
	 (last-command last-command))
     (vm-follow-summary-cursor)
     (save-current-buffer
       (vm-session-initialization)
       (vm-select-folder-buffer)
       (vm-error-if-folder-empty)
       (list (vm-read-imap-folder-name 
	      "Prune messages from IMAP folder: " t nil nil)))))
  (vm-follow-summary-cursor)
  (vm-select-folder-buffer-and-validate 0 (vm-interactive-p))
  (vm-display nil nil '(vm-prune-imap-retrieved-list) 
	      '(vm-prune-imap-retrieved-list))
  ;;--------------------------
  (vm-buffer-type:set 'folder)
  ;;--------------------------
  (let* ((imapdrop (vm-imapdrop-sans-password source))
	 (process (vm-imap-make-session 
		   imapdrop nil :folder-buffer (current-buffer)
		   :purpose "list"))
	 (uid-obarray (make-vector 67 0))
	 mailbox select mailbox-count uid-validity
	 list retrieved-count pruned-count)
    (unwind-protect
	(with-current-buffer (process-buffer process)
	  ;;-----------------------------
	  (vm-buffer-type:enter 'process)
	  ;;-----------------------------
	  (setq mailbox (nth 3 (vm-parse source "\\([^:]+\\):?")))
	  (setq select (vm-imap-select-mailbox process mailbox t)
		mailbox-count (nth 0 select)
		uid-validity (nth 2 select))
	  (unless (eq mailbox-count 0)
	    (setq list (vm-imap-get-message-data-list process 1 mailbox-count)))
	  (mapc (lambda (tuple)
		  (set (intern (cadr tuple) uid-obarray) (car tuple)))
		list))
      ;; unwind-protections
      ;;-----------------------------
      (vm-buffer-type:exit)
      ;;-----------------------------
      (when process (vm-imap-end-session process)))
    (setq retrieved-count (length vm-imap-retrieved-messages))
    (setq vm-imap-retrieved-messages
     (vm-imap-prune-retrieval-entries 
      imapdrop vm-imap-retrieved-messages
      (lambda (tuple) 
	(and (equal (nth 1 tuple) uid-validity)
	     (intern-soft (car tuple) uid-obarray)))))
    (setq pruned-count (- retrieved-count (length vm-imap-retrieved-messages)))
    (if (= pruned-count 0)
	(vm-inform 5 "No messages to be pruned")
      (vm-mark-folder-modified-p)
      (vm-update-summary-and-mode-line)
      (vm-inform 5 "%d message%s pruned" 
	       pruned-count (if (= pruned-count 1) "" "s")))
    ))
    
(defun vm-imap-prune-retrieval-entries (source retrieved pred)
  "Prune RETRIEVED (a copy of `vm-imap-retrieved-messages') by
keeping only those messages from SOURCE that satisfy PRED.
SOURCE must be an IMAP maildrop spec without password info.  
                                                   USR, 2011-04-06"
  (let ((list retrieved)
	(prev nil))
    (setq source (vm-imap-normalize-spec source))
    (while list
      (if (and (equal source (vm-imap-normalize-spec (nth 2 (car list))))
	       (not (apply pred (car list) nil)))
	  (if prev
	      (setcdr prev (cdr list))
	    (setq retrieved (cdr retrieved)))
	(setq prev list))
      (setq list (cdr list)))
    retrieved ))


(defun vm-imap-clear-invalid-retrieval-entries (source retrieved uid-validity)
  "Remove from RETRIEVED (a copy of `vm-imap-retrieved-messages')
all the entries for the password-free maildrop spec SOURCE which
do not match the given UID-VALIDITY.              USR, 2010-05-24"
  (vm-imap-prune-retrieval-entries
   source retrieved
   (lambda (tuple) (equal (nth 1 tuple) uid-validity))))

(defun vm-imap-recorded-uid-validity ()
  "Return the UID-VALIDITY value recorded in the X-IMAP-Retrieved header
of the current folder, or nil if none has been recorded."
  (let ((pos (vm-find vm-imap-retrieved-messages
		      (lambda (record) (nth 1 record)))))
    (and pos
	 (nth 1 (nth pos vm-imap-retrieved-messages)))))



;; --------------------------------------------------------------------
;;; Server-side
;;
;; vm-establish-new-folder-imap-session: 
;;	(&optional interactive string) -> process
;; vm-re-establish-folder-imap-session: 
;;	(&optional interactive string) -> process
;; vm-establish-writable-imap-session: 
;;	(maildrop &optional interactive string) -> process
;;
;; -- Functions to handle the interaction with the IMAP server
;;
;; vm-imap-make-session: (folder interactive
;;			  &key :folder-buffer buffer 
;;			       :purpose string :retry bool) -> process
;; vm-imap-end-session: (process &optional buffer) -> void
;; vm-imap-check-connection: process -> void
;;
;; -- mailbox operations
;; vm-imap-mailbox-list: (process & bool) -> string list
;; vm-imap-create-mailbox: (process & string &optional bool) -> void
;; vm-imap-delete-mailbox: (process & string) -> void
;; vm-imap-rename-mailbox: (process & string & string) -> void
;; 
;; -- lower level I/O
;; vm-imap-send-command: (process command &optional tag no-tag) ->
;; 				void
;; vm-imap-select-mailbox: (process & mailbox &optional bool bool) -> 
;;				(int int uid-validity bool bool (flag list))
;; vm-imap-read-capability-response: process -> ?
;; vm-imap-read-greeting: process -> ? [exceptions]
;; vm-imap-read-ok-response: process -> ? [exceptions]
;; vm-imap-read-response: process -> server-resonse [exceptions]
;; vm-imap-read-response-and-verify: process -> server-resopnse
;; vm-imap-read-boolean-response: process -> ? [exceptions]
;; vm-imap-read-object: (process &optinal bool) -> ? [exceptions]
;; vm-imap-response-matches: (string &rest symbol) -> bool
;; vm-imap-response-bail-if-server-says-farewell: 
;;			response -> void + 'end-of-session exception
;; vm-imap-protocol-error: *&rest
;;
;; -- message opeations
;; vm-imap-retrieve-uid-and-flags-data: () -> void
;; vm-imap-dump-uid-and-flags-data: () -> void
;; vm-imap-dump-uid-seq-num-data: () -> void
;; vm-imap-get-uid-list: (process & int & int) -> (int . uid) list
;; vm-imap-get-message-data-list: (process & int & int) ->
;;					(int . uid . string list) list
;; vm-imap-get-message-data: (process & vm-message) -> 
;;					(int . uid . string list)
;; vm-imap-save-message-flags: (process & int &optional bool) -> void
;; vm-imap-get-message-size: (process & int) -> int
;; vm-imap-get-uid-message-size: (process & uid) -> int
;; vm-imap-save-message: (process & int & string?) -> void
;; vm-imap-delete-message: (process & int) -> void
;;
;; vm-imap-ask-about-large-message: (process int int) -> ?
;; vm-imap-retrieve-to-target: (process target statblob bodypeek) -> bool
;; 
;; -- to be phased out
;; vm-imap-get-message-flags: 
;;	(process & vm-message &optional norecord:bool) -> 
;; --------------------------------------------------------------------


;; The IMAP sessions work as follows:

;; Generally, sessions are created for get-new-mail, save-folder and
;; vm-imap-synchronize operations.  All these operations read the
;; uid-and-flags-data and cache it internally.  At this stage, the
;; IMAP session is said to be "valid", i.e., message numbers stored in
;; the cache are valid.  As long as FETCH and STORE operations are
;; performed, the session remains valid.

;; When other IMAP operations are performed, the server can send
;; EXPUNGE responses and invalidate the cached message sequence
;; numbers.  In this state, the IMAP session is "active", but not
;; "valid".  Only UID-based commands can be issued in this state.


;;;###autoload
(cl-defun vm-imap-make-session (source interactive &key
				     (folder-buffer nil)
				     (purpose nil)
				     (retry nil))
  "Create a new IMAP session for the IMAP mail box SOURCE, attached to
the current folder.
INTERACTIVE says the operation has been invoked interactively.  The
possible values are t, `password-only', and nil.
and the optional argument PURPOSE is inserted in the process
buffer for tracing purposes.  Optional argument RETRY says
whether this call is a retry.

Returns the process or nil if the session could not be created."
  (let ((shutdown nil)		   ; whether process is to be shutdown
	;; (folder-buffer (current-buffer))
	(folder-type (if folder-buffer
			 (with-current-buffer folder-buffer
			   vm-folder-type)))
	process ooo success
	(folder (or (vm-imap-folder-for-spec source)
		    (vm-safe-imapdrop-string source)))
	(coding-system-for-read (vm-binary-coding-system))
	(coding-system-for-write (vm-binary-coding-system))
	(use-ssl nil)
	(use-ssh nil)
	(session-name "IMAP")
	(process-connection-type nil)
	greeting
	protocol host port mailbox auth user pass ;; authinfo
	source-list imap-buffer source-nopwd-nombox)
    (vm-imap-log-token 'make)
    ;; parse the maildrop
    (setq source-list (vm-parse source "\\([^:]*\\):?" 1 7)
	  protocol (car source-list)
	  host (nth 1 source-list)
	  port (nth 2 source-list)
	  ;; mailbox (nth 3 source-list)
	  auth (nth 4 source-list)
	  user (nth 5 source-list)
	  pass (nth 6 source-list)
	  source-nopwd-nombox (vm-imapdrop-sans-password-and-mailbox source))
    (cond ((equal auth "preauth") t)
	  ((equal protocol "imap-ssl")
	   (setq use-ssl t
		 session-name "IMAP over SSL"))
	  ((equal protocol "imap-ssh")
	   (setq use-ssh t
		 session-name "IMAP over SSH")))
    (vm-imap-check-for-server-spec 
     source host port auth user pass use-ssl use-ssh)
    (setq port (string-to-number port))
    ;; Try to get password from auth-sources
    (when (and (equal pass "*") (not (equal auth "preauth")))
      (setq pass (vm-imap-get-password 
		  folder source-nopwd-nombox user host port 
		  interactive purpose)))
    ;; get the trace buffer
    (setq imap-buffer
	  (vm-make-work-buffer 
	   (vm-make-trace-buffer-name session-name host)))
    (vm-imap-log-token imap-buffer)

    (unwind-protect
	(catch 'end-of-session
	  (with-current-buffer imap-buffer
	    ;;----------------------------
	    (vm-buffer-type:enter 'process)
	    ;;----------------------------
	    (setq vm-mail-buffer folder-buffer)
	    (setq vm-folder-type (or folder-type vm-default-folder-type))
	    (buffer-disable-undo imap-buffer)
	    (make-local-variable 'vm-imap-read-point)
	    ;; clear the trace buffer of old output
	    (erase-buffer)
	    ;; Tell MULE not to mess with the text.
	    (if (fboundp 'set-buffer-file-coding-system)
		(set-buffer-file-coding-system (vm-binary-coding-system) t))
	    (if (equal auth "preauth")
		(setq process
		      (run-hook-with-args-until-success 
		       'vm-imap-session-preauth-hook
		       host port mailbox user pass)))
	    (if (processp process)
		(set-process-buffer process (current-buffer))
	      (insert "Starting " session-name
		      " session " (current-time-string) "\r\n")
	      (insert (format "-- connecting to %s:%s\r\n" host port))
	      ;; open the connection to the server
	      (condition-case err
		  (with-timeout 
		      ((or vm-imap-server-timeout 1000)
		       (error (format "Timed out opening connection to %s"
				      host)))
		    (cond 
		     (use-ssl
		      (if (null vm-stunnel-program)
			  (setq process 
				(open-network-stream session-name
						     imap-buffer
						     host port
						     :type 'tls))
			(vm-setup-stunnel-random-data-if-needed)
			(setq process
			      (apply 'start-process session-name imap-buffer
				     vm-stunnel-program
				     (nconc (vm-stunnel-configuration-args host
									   port)
					    vm-stunnel-program-switches)))))
		     (use-ssh
		      (setq process (open-network-stream
				     session-name imap-buffer
				     "127.0.0.1"
				     (vm-setup-ssh-tunnel host port))))
		     (t
		      (setq process (open-network-stream session-name
							 imap-buffer
							 host port)))))
		(error
		 (vm-warn 0 1 "%s" (error-message-string err))
		 (setq shutdown t)
		 (throw 'end-of-session nil))))
	    (setq shutdown t)
	    (setq vm-imap-read-point (point))
	    (vm-process-kill-without-query process)
	    (when (null (setq greeting (vm-imap-read-greeting process)))
	      (delete-process process)	; why here?  USR
	      (throw 'end-of-session nil))
	    (insert-before-markers 
	     (format "-- connected for %s\r\n" purpose))
	    (set (make-local-variable 'vm-imap-session-done) nil)
	    ;; record server capabilities
	    (vm-imap-send-command process "CAPABILITY")
	    (if (null (setq ooo (vm-imap-read-capability-response process)))
		(throw 'end-of-session nil))
	    (set (make-local-variable 'vm-imap-capabilities) (car ooo))
	    (set (make-local-variable 'vm-imap-auth-methods) (nth 1 ooo))
	    ;; authentication
	    (cond 
	     ((equal auth "login")
	      ;; LOGIN must be supported by all imap servers,
	      ;; no need to check for it in CAPABILITIES.
	      (vm-imap-send-command 
	       process
	       (format "LOGIN %s %s" 
		       (vm-imap-quote-string user) (vm-imap-quote-string pass)))
	      (unless (vm-imap-read-ok-response process)
		(vm-inform 0 "IMAP login failed for %s" folder)
		(vm-imap-forget-password source-nopwd-nombox host port)
		;; don't sleep unless we're running synchronously.
		(if vm-imap-ok-to-ask	; (eq interactive t) ?
		    (sleep-for 2))
		(throw 'end-of-session nil))
	      (unless (assoc source-nopwd-nombox vm-imap-passwords)
		(setq vm-imap-passwords (cons (list source-nopwd-nombox pass)
					      vm-imap-passwords)))
	      (setq success t)
	      ;;--------------------------------
	      (vm-imap-session-type:set 'active))
	      ;;--------------------------------
	     ((equal auth "cram-md5")
	      (if (not (vm-imap-auth-method 'CRAM-MD5))
		  (error "CRAM-MD5 authentication unsupported by this server"))
	      (let ((ipad (make-string 64 54))
		    (opad (make-string 64 92))
		    (command "AUTHENTICATE CRAM-MD5")
		    (secret (concat
			     pass
			     (make-string (max 0 (- 64 (length pass))) 0)))
		    response p challenge answer)
		(vm-imap-send-command process command)
		(setq response 
		      (vm-imap-read-response-and-verify process command))
		(cond ((vm-imap-response-matches response '+ 'atom)
		       (setq p (cdr (nth 1 response))
			     challenge (buffer-substring (nth 0 p) (nth 1 p))
			     challenge (vm-mime-base64-decode-string
					challenge)))
		      (t
		       (vm-imap-protocol-error
			"Don't understand AUTHENTICATE response")))
		(setq answer
		      (concat
		       user " "
		       (vm-md5-string
			(concat
			 (vm-xor-string secret opad)
			 (vm-md5-raw-string 
			  (concat
			   (vm-xor-string secret ipad) challenge)))))
		      answer (vm-mime-base64-encode-string answer))
		(vm-imap-send-command process answer nil t)
		(unless (vm-imap-read-ok-response process)
		  (vm-inform 0 "IMAP password for %s incorrect" folder)
		  ;; don't sleep unless we're running synchronously.
		  (if vm-imap-ok-to-ask	; (eq interactive t)?
		      (sleep-for 2))
		  (throw 'end-of-session nil))
		(setq success t)
		(unless (assoc source-nopwd-nombox vm-imap-passwords)
		  (setq vm-imap-passwords (cons (list source-nopwd-nombox pass)
						vm-imap-passwords)))
		;;-------------------------------
		(vm-imap-session-type:set 'active)))
		;;-------------------------------
	     ((equal auth "preauth")
	      (unless (eq greeting 'preauth)
		(vm-inform 0 "IMAP session was not pre-authenticated")
		;; don't sleep unless we're running synchronously.
		(if vm-imap-ok-to-ask	; (eq interactive t)?
		    (sleep-for 2))
		(throw 'end-of-session nil))
	      (setq success t)
	      ;;-------------------------------
	      (vm-imap-session-type:set 'active)
	      ;;-------------------------------
	      )
	     (t (error "Don't know how to authenticate using %s" auth)))
	    (setq shutdown nil)))
      ;; unwind-protection
      ;;-------------------
      (vm-buffer-type:exit)
      ;;-------------------
      (when shutdown
	  (vm-imap-end-session process imap-buffer))
      (vm-tear-down-stunnel-random-data))
    
    (if success
	process
      ;; try again if possible, treat it as non-interactive the next time
      ;; disable auth-sources as well
      (unless retry
	(let ((auth-sources nil))
	  (vm-imap-make-session source interactive 
				:folder-buffer folder-buffer
				:purpose purpose
				:retry t))))))

(defun vm-imap-get-password (folder source user host port ask-password purpose)
  "Get the password for the IMAP FOLDER at the server SOURCE.  The
additional arguments USER, HOST and PORT are also passed in for
convenience.  The password is obtained from VM's internal password
cache, the auth-source package or by interactively querying the user.  
The argument ASK-PASSWORD says whether the interactive querying should
be done.  The argument PURPOSE is a string displayed to the user in
case of errors."
  (let ((pass (car (cdr (assoc source vm-imap-passwords))))
	authinfo)
    (when (and (null pass)
	       (boundp 'auth-sources)
	       (fboundp 'auth-source-user-or-password))
      (cond ((and (setq authinfo
			(auth-source-user-or-password
			 '("login" "password")
			 (vm-imap-account-name-for-spec source)
			 port))
		  (equal user (car authinfo)))
	     (setq pass (cadr authinfo)))
	    ((and (setq authinfo
			(auth-source-user-or-password
			 '("login" "password")
			 host port))
		  (equal user (car authinfo)))
	     (setq pass (cadr authinfo)))))
    (while (and (null pass) ask-password)
      (setq pass
	    (read-passwd (format "IMAP password for %s: " folder)))
      (when (equal pass "")
	(vm-warn 0 2 "Password cannot be empty")
	(setq pass nil)))
    (when (null pass)
      (error "Need password for %s for %s" folder purpose))
    pass))

(defun vm-imap-forget-password (source host port)
  "Forget the cached password for the IMAP account corresponding to
SOURCE, and also for HOST at PORT.  The forgetting is done inside VM
as well in auth-source (if it is being used)."
  (setq vm-imap-passwords
	(vm-delete (lambda (pair)
		     (equal (car pair) source))
		   vm-imap-passwords))
  (when (fboundp 'auth-source-forget-user-or-password)
    (auth-source-forget-user-or-password 
     '("login" "password")
     (vm-imap-account-name-for-spec source) port)
    (auth-source-forget-user-or-password 
     '("login" "password")
     host port))
  )

(defun vm-imap-check-for-server-spec (source host port auth user pass 
					     _use-ssl use-ssh)
  (when (null host)
    (error "No host in IMAP maildrop specification, \"%s\"" source))
  (when (or (null port) (not (string-match "^[0-9]+$" port)))
    (error "No port in IMAP maildrop specification, \"%s\"" source))
  (when (null auth)
    (error "No authentication method in IMAP maildrop specification, \"%s\"" 
	   source))
  (when (null user)
    (error "No user in IMAP maildrop specification, \"%s\"" source))
  (when (null pass)
    (error "No password in IMAP maildrop specification, \"%s\"" source))
  ;; (when use-ssl
  ;;   (if (null vm-stunnel-program)
  ;; 	(error "vm-stunnel-program must be non-nil to use IMAP over SSL.")))
  (when use-ssh
    (if (null vm-ssh-program)
	(error "vm-ssh-program must be non-nil to use IMAP over SSH.")))
  )



;;;###autoload
(defun vm-imap-end-session (process &optional imap-buffer keep-buffer)
  "Kill the IMAP session represented by PROCESS.  PROCESS could
be nil or be already closed. Optional argument IMAP-BUFFER specifies
the process-buffer. If the optional argument KEEP-BUFFER is
non-nil, the process buffer is retained, otherwise it is killed
as well."
  (vm-imap-log-token 'end-session)
  (when (and process (null imap-buffer))
    (setq imap-buffer (process-buffer process)))
  (when (and process (memq (process-status process) '(open run))
	     (buffer-live-p (process-buffer process)))
    (unwind-protect
      (with-current-buffer imap-buffer
	;;----------------------------
	(vm-buffer-type:enter 'process)
	;;----------------------------
	;; vm-imap-end-session might have already been called on
	;; this process, so don't logout and schedule the killing
	;; the process again if it's already been done.
	(unwind-protect
	    (condition-case nil
		(if vm-imap-session-done
		    ;;-------------------------------------
		    ;; Don't bother checking because it might fail if
		    ;; the user typed C-g.
		    ;; (vm-imap-session-type:assert 'inactive)
		    ;;-------------------------------------
		    nil
		  (vm-inform 6 "%s: Closing IMAP session to %s..."
			     (if vm-mail-buffer
				 (buffer-name vm-mail-buffer) 
			       "vm")
			     "server")
		  (vm-imap-send-command process "LOGOUT")
		  ;; we don't care about the response.
		  ;; avoid waiting for it because some servers misbehave.
		  ;; (vm-imap-read-ok-response process)
		  )
	      (vm-imap-protocol-error ; handler
	       nil)		      ; ignore errors 
	      (error nil))	      ; handler
	  ;; unwind-protections
	  (setq vm-imap-session-done t)
	  ;;----------------------------------
	  (vm-imap-session-type:set 'inactive)
	  ;;----------------------------------
	  ;; This is just for tracing purposes
	  (goto-char (point-max))
	  (insert "\r\n\r\n\r\n"
		  "ending IMAP session " (current-time-string) "\r\n")
	  ;; Schedule killing of the process after a delay to allow
	  ;; any output to be received first
	  (if (fboundp 'add-async-timeout)
	      (add-async-timeout 2 'delete-process process)
	    (run-at-time 2 nil 'delete-process process))))
      ;; unwind-protections
      ;;----------------------------------
      (vm-buffer-type:exit)
      ;;----------------------------------
      ))
  (when (and imap-buffer (buffer-live-p imap-buffer))
    (if (and (null vm-imap-keep-trace-buffer) (not keep-buffer))
	(kill-buffer imap-buffer)
      (vm-keep-some-buffers imap-buffer 'vm-kept-imap-buffers
			    vm-imap-keep-trace-buffer
			    "saved ")
      ))
  )

(defun vm-imap-check-connection (process)
  ;;------------------------------
  ;; (vm-buffer-type:assert 'process)
  ;;------------------------------
  (cond ((or (not (processp process))
	     (not (memq (process-status process) '(open run))))
	 ;;-------------------
	 ;; (vm-buffer-type:exit)
	 ;;-------------------
	 (vm-imap-normal-error "not connected"))
	((not (buffer-live-p (process-buffer process)))
	 ;;-------------------
	 ;; (vm-buffer-type:exit)
	 ;;-------------------
	 (vm-imap-protocol-error
	  "IMAP process %s's buffer has been killed" process))))

(defun vm-imap-send-command (process command &optional tag no-tag)
  (vm-imap-log-token 'send)
  ;;------------------------------
  (vm-buffer-type:assert 'process)
  ;;------------------------------
  (vm-imap-check-connection process)
  (if (not (= (point) (point-max)))
      (vm-imap-log-tokens (list 'send1 (point) (point-max))))
  (goto-char (point-max))
  ;; try if it makes a difference to get pending output here, use timeout
  ;; (accept-process-output process 0 0.01)
  ;; (if (not (= (point) (point-max)))
  ;;     (vm-imap-log-tokens (list 'send2 (point) (point-max))))
  ;; (goto-char (point-max))

  (unless no-tag (insert-before-markers (or tag "VM") " "))
  (let ((case-fold-search t))
    (if (string-match "^LOGIN" command)
	(insert-before-markers "LOGIN <parameters omitted>\r\n")
      (insert-before-markers command "\r\n")))
  (setq vm-imap-read-point (point))
  ;; previously we had a process-send-string call for each string
  ;; to avoid extra consing but that caused a lot of packet overhead.
  (if no-tag
      (process-send-string process (format "%s\r\n" command))
    (process-send-string process (format "%s %s\r\n" (or tag "VM") command))))

(defun vm-imap-select-mailbox (process mailbox &optional 
				       just-retrieve just-examine)
  "I/O function to select an IMAP mailbox
    PROCESS - the IMAP process
    MAILBOX - the name of the mailbox to be selected
    JUST-RETRIEVE - select the mailbox for retrieval, no writing
    JUST-EXAMINE - select the mailbox in a read-only (examine) mode
Returns a list containing:
    int msg-count - number of messages in the mailbox
    int recent-count - number of recent messages in the mailbox
    string uid-validity - the UID validity value of the mailbox
    bool read-write - whether the mailbox is writable
    bool can-delete - whether the mailbox allows message deletion
    server-response permanent-flags - permanent flags used in the mailbox."

  ;;------------------------------
  (vm-buffer-type:assert 'process)
  ;;------------------------------

  (let ((imap-buffer (current-buffer))
	(command (if just-examine "EXAMINE" "SELECT"))
	tok response p
	(flags nil)
	(permanent-flags nil)
	(msg-count nil)
	(recent-count nil)
	(uid-validity nil)
	(read-write (not just-examine))
	(can-delete t)
	(need-ok t))
    (vm-imap-log-token 'select-mailbox)
    (vm-imap-send-command 
     process (format "%s %s" command (vm-imap-quote-mailbox-name mailbox)))
    (while need-ok
      (setq response (vm-imap-read-response-and-verify process command))
      (cond ((vm-imap-response-matches response '* 'OK 'vector)
	     (setq p (cdr (nth 2 response)))
	     (cond ((vm-imap-response-matches p 'UIDVALIDITY 'atom)
		    (setq tok (nth 1 p))
		    (setq uid-validity (buffer-substring (nth 1 tok)
							 (nth 2 tok))))
		   ((vm-imap-response-matches p 'PERMANENTFLAGS 'list)
		    (setq permanent-flags (nth 1 p)))))
	    ((vm-imap-response-matches response '* 'FLAGS 'list)
	     (setq flags (nth 2 response)))
	    ((vm-imap-response-matches response '* 'atom 'EXISTS)
	     (setq tok (nth 1 response))
	     (goto-char (nth 1 tok))
	     (setq msg-count (read imap-buffer)))
	    ((vm-imap-response-matches response '* 'atom 'RECENT)
	     (setq tok (nth 1 response))
	     (goto-char (nth 1 tok))
	     (setq recent-count (read imap-buffer)))
	    ((vm-imap-response-matches response 'VM 'OK '(vector READ-WRITE))
	     (setq need-ok nil read-write t))
	    ((vm-imap-response-matches response 'VM 'OK '(vector READ-ONLY))
	     (setq need-ok nil read-write nil))
	    ((vm-imap-response-matches response 'VM 'OK)
	     (setq need-ok nil))))
    (if (null flags)
	(vm-imap-protocol-error "FLAGS missing from SELECT responses"))
    (if (null msg-count)
	(vm-imap-protocol-error "EXISTS missing from SELECT responses"))
    (if (null uid-validity)
	(vm-imap-protocol-error "UIDVALIDITY missing from SELECT responses"))
    (setq can-delete (vm-imap-scan-list-for-flag flags "\\Deleted"))
    (unless just-retrieve
      (if (vm-imap-scan-list-for-flag permanent-flags "\\*")
	  (unless (vm-imap-scan-list-for-flag flags "\\Seen")
	    (vm-inform 5 
	     "Warning: No permanent changes permitted for the IMAP mailbox"))
	(vm-inform 5 
	 "Warning: No user-definable flags available for the IMAP mailbox")))
    ;;-------------------------------
    (vm-imap-session-type:set 'active)
    ;;-------------------------------
    (list msg-count recent-count
	  uid-validity read-write can-delete permanent-flags)))

(defun vm-imap-read-expunge-response (process)
  (let ((list nil)
	(imap-buffer (current-buffer))
	(need-ok t)
	tok msg-num response
	)
    (vm-imap-log-token 'read-expunge)
    (while need-ok
      (setq response (vm-imap-read-response-and-verify process "EXPUNGE"))
      (cond ((vm-imap-response-matches response '* 'atom 'EXPUNGE)
	     (setq tok (nth 1 response))
	     (goto-char (nth 1 tok))
	     (setq msg-num (read imap-buffer))
	     (setq list (cons msg-num list)))
	    ((vm-imap-response-matches response 'VM 'OK)
	     (setq need-ok nil))))
    ;;--------------------------------
    (vm-imap-session-type:set 'active)		; seq nums are now invalid
    ;;--------------------------------
    (nreverse list)))

(defun vm-imap-get-uid-list (process first last)
  "I/O function to read the uid's of a message range
    PROCESS - the IMAP process
    FIRST - message sequence number of the first message in the range
    LAST - message sequene number of the last message in the range
Returns an alist with pairs 
    int msg-num - message sequence number of a message
    string uid - uid of the message
or nil indicating failure
If there are no messages in the range then (nil) is returned.

See also `vm-imap-get-message-data-list' for a newer version of this function."

  (let ((list nil)
	(imap-buffer (current-buffer))
	tok msg-num uid response p
	(need-ok t))
    (vm-imap-log-token 'uid-list)
    ;;----------------------------------
    (vm-imap-session-type:assert-active)
    ;;----------------------------------
    (vm-imap-send-command process (format "FETCH %s:%s (UID)" first last))
    (while need-ok
      (setq response (vm-imap-read-response-and-verify process "UID FETCH"))
      (cond ((vm-imap-response-matches response '* 'atom 'FETCH 'list)
	     (setq p (cdr (nth 3 response)))
	     (if (not (vm-imap-response-matches p 'UID 'atom))
		 (vm-imap-protocol-error
		  "expected (UID number) in FETCH response"))
	     (setq tok (nth 1 response))
	     (goto-char (nth 1 tok))
	     (setq msg-num (read imap-buffer))
	     (setq tok (nth 1 p))
	     (setq uid (buffer-substring (nth 1 tok) (nth 2 tok))
		   list (cons (cons msg-num uid) list)))
	    ((vm-imap-response-matches response 'VM 'OK)
	     (setq need-ok nil))))
    ;;-------------------------------
    (vm-imap-session-type:set 'valid)
    ;;-------------------------------
    ;; returning nil means the uid fetch failed so return
    ;; something other than nil if there aren't any messages.
    (if (null list)
	(cons nil nil)
      list )))

;; This function is not recommended, but is available to use when
;; caching uid-and-flags data might be too expensive.

(defun vm-imap-get-message-data (process m uid-validity)
  "I/O function to read the flags of a message
    PROCESS  - The IMAP process
    M - a vm-message
    uid-validity -  the folder's uid-validity
Returns (msg-num: int . uid: string . size: string . flags: string list)
Throws vm-imap-protocol-error for failure.

See also `vm-imap-get-message-list' for a bulk version of this function."

  (let ((imap-buffer (current-buffer))
	response tok need-ok msg-num list)
    (if (not (equal (vm-imap-uid-validity-of m) uid-validity))
	(vm-imap-normal-error "message has invalid uid"))
    (vm-imap-log-tokens (list 'message-data (current-buffer)))
    ;;----------------------------------
    (vm-imap-session-type:assert 'valid)
    ;;----------------------------------
    (vm-imap-send-command
     process (format "SEARCH UID %s" (vm-imap-uid-of m)))
    (setq need-ok t)
    (while need-ok
      (setq response (vm-imap-read-response-and-verify process "UID"))
      (cond ((vm-imap-response-matches response 'VM 'OK)
	     (setq need-ok nil))
	    ((vm-imap-response-matches response '* 'SEARCH 'atom)
	     (if (null (setq tok (nth 2 response)))
		 (vm-imap-normal-error "message not found on server"))
	     (goto-char (nth 1 tok))
	     (setq msg-num (read imap-buffer))
	     )))
    (setq list (vm-imap-get-message-data-list process msg-num msg-num))
    (car list)))
	

(defun vm-imap-get-message-data-list (process first last)
  "I/O function to read the flags of a message range
    PROCESS - the IMAP process
    FIRST - message sequence number of the first message in the range
    LAST - message sequene number of the last message in the range
Returns an assoc list with entries
    int msg-num - message sequence number of a message
    string uid - uid of the message
    string size - message size
    (string list) flags - list of flags for the message
throws vm-imap-protocol-error for failure.

See `vm-imap-get-message-data' for getting the data for individual
messages.  `vm-imap-get-uid-list' is an older version of this function."

  (let ((list nil)
	(imap-buffer (current-buffer))
	tok msg-num uid size flag flags response p pl
	(need-ok t))
    (vm-imap-log-token (list 'message-data-list (current-buffer)))
    ;;----------------------------------
    (if vm-buffer-type-debug
	(setq vm-buffer-type-trail (cons 'message-data vm-buffer-type-trail)))
    (vm-buffer-type:assert 'process)
    (vm-imap-session-type:assert-active)
    ;;----------------------------------
    (vm-imap-send-command 
     process (format "FETCH %s:%s (UID RFC822.SIZE FLAGS)" first last))
    (while need-ok
      (setq response (vm-imap-read-response-and-verify process "FLAGS FETCH"))
      (cond 
       ((vm-imap-response-matches response '* 'atom 'FETCH 'list)
	(setq p (cdr (nth 3 response)))
	(setq tok (nth 1 response))
	(goto-char (nth 1 tok))
	(setq msg-num (read imap-buffer))
	(while p
	  (cond 
	   ((vm-imap-response-matches p 'UID 'atom)
	    (setq tok (nth 1 p))
	    (setq uid (buffer-substring (nth 1 tok) (nth 2 tok)))
	    (setq p (nthcdr 2 p)))
	   ((vm-imap-response-matches p 'RFC822\.SIZE 'atom)
	    (setq tok (nth 1 p))
	    (setq size (buffer-substring (nth 1 tok) (nth 2 tok)))
	    (setq p (nthcdr 2 p)))
	   ((vm-imap-response-matches p  'FLAGS 'list)
	    (setq pl (cdr (nth 1 p))
		  flags nil)
	    (while pl
	      (setq tok (car pl))
	      (if (not (vm-imap-response-matches (list tok) 'atom))
		  (vm-imap-protocol-error
		   "expected atom in FLAGS list in FETCH response"))
	      (setq flag (downcase
			  (buffer-substring (nth 1 tok) (nth 2 tok)))
		    flags (cons flag flags)
		    pl (cdr pl)))
	    (setq p (nthcdr 2 p)))
	   (t
	    (vm-imap-protocol-error
	     "expected UID, RFC822.SIZE and (FLAGS list) in FETCH response"))
	   ))
	(setq list 
	      (cons (cons msg-num (cons uid (cons size flags)))
		    list)))
       ((vm-imap-response-matches response 'VM 'OK)
	(setq need-ok nil))))
    list))

(defun vm-imap-ask-about-large-message (process size n)
  (let ((work-buffer nil)
	(imap-buffer (current-buffer))
	(need-ok t)
	(need-header t)
	response fetch-response
	list p
	start end)
    (unwind-protect
	(save-excursion			; save-current-buffer?
	  ;;------------------------
	  (vm-buffer-type:duplicate)
	  ;;------------------------
	  (save-window-excursion
	    ;;----------------------------------
	    (vm-imap-session-type:assert 'valid)
	    ;;----------------------------------
	    (vm-imap-send-command process
				  (format "FETCH %d (RFC822.HEADER)" n))
	    (while need-ok
	      (setq response 
		    (vm-imap-read-response-and-verify process "header FETCH"))
	      (cond ((vm-imap-response-matches response '* 'atom 'FETCH 'list)
		     (setq fetch-response response
			   need-header nil))
		    ((vm-imap-response-matches response 'VM 'OK)
		     (setq need-ok nil))))
	    (if need-header
		(vm-imap-protocol-error "FETCH OK sent before FETCH response"))
	    (setq vm-imap-read-point (point-marker))
	    (setq list (cdr (nth 3 fetch-response)))
	    (if (not (vm-imap-response-matches list 'RFC822\.HEADER 'string))
		(vm-imap-protocol-error
		 "expected (RFC822.HEADER string) in FETCH response"))
	    (setq p (nth 1 list)
		  start (nth 1 p)
		  end (nth 2 p))
	    (setq work-buffer (generate-new-buffer "*imap-glop*"))
	    ;;--------------------------
	    (vm-buffer-type:set 'scratch)
	    ;;--------------------------
	    (set-buffer work-buffer)
	    (insert-buffer-substring imap-buffer start end)
	    (vm-imap-cleanup-region (point-min) (point-max))
	    (vm-display-buffer work-buffer)
	    (setq minibuffer-scroll-window (selected-window))
	    (goto-char (point-min))
	    (if (re-search-forward "^Received:" nil t)
		(progn
		  (goto-char (match-beginning 0))
		  (vm-reorder-message-headers
		   nil :keep-list vm-visible-headers
		   :discard-regexp vm-invisible-header-regexp)))
	    (set-window-point (selected-window) (point))
	    (if (y-or-n-p 
		 (format "Retrieve message %d (size = %d)? " n size))
		'retrieve
	      (if (y-or-n-p 
		   (format "Delete message %d (size = %d) on the server? " 
			   n size))
		  'delete
		'skip))))
      ;; unwind-protections
      ;;-------------------
      (vm-buffer-type:exit)
      ;;-------------------
      (when work-buffer (kill-buffer work-buffer)))))

(defun vm-imap-retrieve-to-target (process target statblob bodypeek)
  "Read a mail message from PROCESS and store it in TARGET, which
is either a file or a buffer.  Report status using STATBLOB.  The
boolean BODYPEEK indicates whether the bodypeek function is
available for the IMAP server."
  (vm-assert (not (null vm-imap-read-point)))
  (vm-imap-log-token 'retrieve)
  (let ((***start vm-imap-read-point)	; avoid dynamic binding of 'start'
	end fetch-response list p)
    (goto-char ***start)
    (vm-set-imap-status-got statblob 0)
    (let* ((func
	    (function
	     (lambda (_beg end _len)
	       (if vm-imap-read-point
		   (progn
		     (vm-set-imap-status-got statblob (- end ***start))
		     (if (zerop (random 10))
			 (vm-imap-report-retrieval-status statblob)))))))
	   ;; this seems to slow things down.  USR, 2008-04-25
	   ;; reenabled.  USR, 2010-09-17
	   (after-change-functions (cons func after-change-functions))
	   
	   ;; (need-ok t)
	   response)

      (condition-case err
	  (setq response 
		(vm-imap-read-response-and-verify process "message FETCH"))
	(error 
	 (vm-imap-normal-error (error-message-string err)))
	(quit 
	 (vm-imap-normal-error "quit signal received during retrieval")))
      (cond ((vm-imap-response-matches response '* 'atom 'FETCH 'list)
	     (setq fetch-response response))
	    (t
	     (vm-imap-normal-error "cannot retrieve message from the server"))))
      
    ;; must make the read point a marker so that it stays fixed
    ;; relative to the text when we modify things below.
    (setq vm-imap-read-point (point-marker))
    (setq list (cdr (nth 3 fetch-response)))
    (cond
     (bodypeek
      (cond ((vm-imap-response-matches list 'BODY '(vector) 'string)
	     (setq p (nth 2 list) 
		   ***start (nth 1 p)))
	    ((vm-imap-response-matches list 'UID 'atom 'BODY '(vector) 'string)
	     (setq p (nth 4 list)
		   ***start (nth 1 p)))
	    (t
	     (vm-imap-protocol-error
	      "expected (BODY[] string) in FETCH response"))))
     (t
      (if (not (vm-imap-response-matches list 'RFC822 'string))
	  (vm-imap-protocol-error
	   "expected (RFC822 string) in FETCH response"))
      (setq p (nth 1 list)
	    ***start (nth 1 p))))
    (goto-char (nth 2 p))
    (setq end (point-marker))
    (vm-set-imap-status-need statblob nil)
    (vm-imap-cleanup-region ***start end)
    (vm-munge-message-separators vm-folder-type ***start end)
    (goto-char ***start)
    (vm-set-imap-status-got statblob nil)
    ;; avoid the consing and stat() call for all but babyl
    ;; files, since this will probably slow things down.
    ;; only babyl files have the folder header, and we
    ;; should only insert it if the crash box is empty.
    (if (and (eq vm-folder-type 'babyl)
	     (cond ((stringp target)
		    (let ((attrs (file-attributes target)))
		      (or (null attrs) (equal 0 (nth 7 attrs)))))
		   ((bufferp target)
		    (with-current-buffer target
		      (zerop (buffer-size))))))
	(let ((opoint (point)))
	  (vm-convert-folder-header nil vm-folder-type)
	  ;; if start is a marker, then it was moved
	  ;; forward by the insertion.  restore it.
	  (setq ***start opoint)
	  (goto-char ***start)
	  (vm-skip-past-folder-header)))
    (insert (vm-leading-message-separator))
    (save-restriction
      (narrow-to-region (point) end)
      (vm-convert-folder-type-headers 'baremessage vm-folder-type))
    (goto-char end)
    ;; Some IMAP servers don't understand Sun's stupid
    ;; From_-with-Content-Length style folder and assume the last
    ;; newline in the message is a separator.  And so the server
    ;; strips it, leaving us with a message that does not end
    ;; with a newline.  Add the newline if needed.
    ;;
    ;; Added From_ folders among the ones to be repaired.  USR, 2010-05-19
    (if (and (not (eq ?\n (char-after (1- (point)))))
	     (memq vm-folder-type 
		   '(From_-with-Content-Length BellFrom_ From_)))
	(insert-before-markers "\n"))
    (insert-before-markers (vm-trailing-message-separator))
    (if (stringp target)
	;; Set file type to binary for DOS/Windows.  I don't know if
	;; this is correct to do or not; it depends on whether the
	;; the CRLF or the LF newline convention is used on the inbox
	;; associated with this crashbox.  This setting assumes the LF
	;; newline convention is used.
	(progn
	  (defvar buffer-file-type) ;; FIXME: Removed in Emacs-24.4.
	  (let ((buffer-file-type t)
	        (selective-display nil))
	    (write-region ***start end target t 0)))
      (let ((b (current-buffer)))
	(with-current-buffer target
	  ;;----------------------------
	  (vm-buffer-type:enter 'unknown)
	  ;;----------------------------
	  (let ((buffer-read-only nil))
	    (insert-buffer-substring b ***start end)
	    )
	  ;;-------------------
	  (vm-buffer-type:exit)
	  ;;-------------------
	  )))
    (delete-region ***start end)
    t ))

(defun vm-imap-delete-messages (process beg end)
  ;;----------------------------------
  (vm-buffer-type:assert 'process)
  (vm-imap-session-type:assert 'valid)
  ;;----------------------------------
  (vm-imap-send-command process (format "STORE %d:%d +FLAGS.SILENT (\\Deleted)"
					beg end))
  (if (null (vm-imap-read-ok-response process))
      (vm-imap-normal-error "deletion failed")))

(defun vm-imap-get-message-size (process n)
  "Use imap PROCESS to query the size the message with sequence number
N.  Returns the size.

See also `vm-imap-get-uid-message-size'."
  (let ((imap-buffer (current-buffer))
	tok size response p
	(need-size t)
	(need-ok t))
    ;;----------------------------------
    (vm-buffer-type:assert 'process)
    (vm-imap-session-type:assert 'valid)
    (vm-imap-log-tokens (list 'message-size (current-buffer)))
    ;;----------------------------------
    (vm-imap-send-command process (format "FETCH %d:%d (RFC822.SIZE)" n n))
    (while need-ok
      (setq response (vm-imap-read-response-and-verify process "size FETCH"))
      (cond ((and need-size
		  (vm-imap-response-matches response '* 'atom 'FETCH 'list))
	     (setq need-size nil)
	     (setq p (cdr (nth 3 response)))
	     (catch 'done
	       (while p
		 (if (vm-imap-response-matches p 'RFC822\.SIZE 'atom)
		     (throw 'done nil)
		   (setq p (nthcdr 2 p))
		   (if (null p)
		       (vm-imap-protocol-error
			"expected (RFC822.SIZE number) in FETCH response")))))
	     (setq tok (nth 1 p))
	     (goto-char (nth 1 tok))
	     (setq size (read imap-buffer)))
	    ((vm-imap-response-matches response 'VM 'OK)
	     (setq need-ok nil))))
    size ))

(defun vm-imap-get-uid-message-size (process uid)
  "Uses imap PROCESS to get the size of the message with UID.  Returns
the size.

See also `vm-imap-get-message-size'."
  (let ((imap-buffer (current-buffer))
	tok size response p
	(need-size t)
	(need-ok t))
    ;;----------------------------------
    (vm-buffer-type:assert 'process)
    (vm-imap-session-type:assert-active)
    ;;----------------------------------
    (vm-imap-log-token 'uid-size)
    (vm-imap-send-command 
     process (format "UID FETCH %s:%s (RFC822.SIZE)" uid uid))
    (while need-ok
      (setq response (vm-imap-read-response-and-verify process "size FETCH"))
      (cond ((and need-size
		  (vm-imap-response-matches response '* 'atom 'FETCH 'list))
	     (setq p (cdr (nth 3 response)))
	     (while p
	       (cond 
		((vm-imap-response-matches p 'UID 'atom)
		 (setq tok (nth 1 p))
		 (unless (equal uid (buffer-substring (nth 1 tok) (nth 2 tok)))
		     (vm-imap-protocol-error 
		      "UID number mismatch in SIZE query"))
		 (setq p (nthcdr 2 p)))
		((vm-imap-response-matches p 'RFC822\.SIZE 'atom)
		 (setq tok (nth 1 p))
		 (goto-char (nth 1 tok))
		 (setq size (read imap-buffer))
		 (setq need-size nil)
		 (setq p (nthcdr 2 p)))
		(t
		 (setq p (nthcdr 2 p))))))
	    ((vm-imap-response-matches response 'VM 'OK)
	     (setq need-ok nil))
	    ;; Otherwise, skip the response
	    ))
    (if need-size
	(vm-imap-normal-error
	 "IMAP server has no information for message UID %s" uid)
      size )))

(defun vm-imap-read-capability-response (process)
  ;;----------------------------------
  (vm-buffer-type:assert 'process)
  ;;----------------------------------
  (vm-imap-log-token 'read-capability)
  (let (response r cap-list auth-list (need-ok t))
    (while need-ok
      (setq response (vm-imap-read-response-and-verify process "CAPABILITY"))
      (if (vm-imap-response-matches response 'VM 'OK)
	  (setq need-ok nil)
	(if (not (vm-imap-response-matches response '* 'CAPABILITY))
	    nil
	  ;; skip * CAPABILITY
	  (setq response (cdr (cdr response)))
	  (while response
	    (setq r (car response))
	    (if (not (eq (car r) 'atom))
		nil
	      (if (save-excursion
		    (goto-char (nth 1 r))
		    (let ((case-fold-search t))
		      (eq (re-search-forward "AUTH=." (nth 2 r) t)
			  (+ 6 (nth 1 r)))))
		  (progn
		    (setq auth-list (cons (intern
					   (upcase (buffer-substring
						    (+ 5 (nth 1 r))
						    (nth 2 r))))
					  auth-list)))
		(setq r (car response))
		(if (not (eq (car r) 'atom))
		    nil
		  (setq cap-list (cons (intern
					(upcase (buffer-substring
						 (nth 1 r) (nth 2 r))))
				       cap-list)))))
	    (setq response (cdr response))))))
    (if (or cap-list auth-list)
	(list (nreverse cap-list) (nreverse auth-list))
      nil)))

(defun vm-imap-read-greeting (process)
  "Read the initial greeting from the IMAP server.

May throw exceptions."
  ;;----------------------------------
  (vm-buffer-type:assert 'process)
  ;;----------------------------------
  (vm-imap-log-token 'read-greeting)
  (let (response)
    (setq response (vm-imap-read-response process))
    (cond ((vm-imap-response-matches response '* 'OK)
	   t )
	  ((vm-imap-response-matches response '* 'PREAUTH)
	   'preauth )
	  (t nil))))

(defun vm-imap-read-ok-response (process)
  "Reads an OK response from the IMAP server, returning a boolean
result.

May throw exceptions."
  ;; FIXME Is this the same as vm-imap-read-boolean-response?
  ;;----------------------------------
  (vm-buffer-type:assert 'process)
  ;;----------------------------------
  (vm-imap-log-token 'read-ok)
  (let (response retval (done nil))
    (while (not done)
      (setq response (vm-imap-read-response process))
      (cond ((vm-imap-response-matches response '*)
	     nil )
	    ((vm-imap-response-matches response 'VM 'OK)
	     (setq retval t)
	     (setq done t))
	    ((vm-imap-response-matches response 'VM 'NO)
	     (setq retval nil)
	     (setq done t))
	    ((vm-imap-response-matches response 'VM 'BAD)
	     (setq retval nil)
	     (setq done t)
	     (vm-imap-normal-error 
	      "server says - %s"
	      (vm-imap-read-error-message process (cadr (cadr response)))))
	    (t
	     (vm-imap-protocol-error "Did not receive OK response"))))
    retval ))

(defun vm-imap-cleanup-region (start end)
  (setq end (vm-marker end))
  (save-excursion
    (goto-char start)
    ;; CRLF -> LF
    (while (and (< (point) end) (search-forward "\r\n"  end t))
      (replace-match "\n" t t)))
  (set-marker end nil))

(defun vm-imap-read-response (process)
  "Reads a line of respose from the imap PROCESS.  Returns a list of
tokens, which may be empty when the server output is ill-formed.

May throw exceptions."
  ;;--------------------------------------------
  ;; This assertion often fails for some reason,
  ;; perhaps some asynchrony involved?
  ;; Assertion check being disabled unless debugging is on.
  (if vm-buffer-type-debug
      (vm-buffer-type:assert 'process))
  (if vm-buffer-type-debug
      (setq vm-buffer-type-trail (cons 'read vm-buffer-type-trail)))
  ;;--------------------------------------------
  (vm-imap-log-tokens (list 'response vm-imap-read-point))
  (let ((list nil) tail obj)
    (when vm-buffer-type-debug
      (unless vm-imap-read-point
	(debug nil "vm-imap-read-response: null vm-imap-read-point")))
    (goto-char vm-imap-read-point)
    (catch 'done
      (while t
	(setq obj (vm-imap-read-object process))
	(if (eq (car obj) 'end-of-line)
	    (throw 'done list))
	(if (null list)
	    (setq list (cons obj nil)
		  tail list)
	  (setcdr tail (cons obj nil))
	  (setq tail (cdr tail)))))))

(defun vm-imap-read-response-and-verify (process &optional _command-desc)
  "Reads a line of response from the imap PROCESS and checks for
standard errors like \"BAD\" and \"BYE\".  Returns a list of tokens.

Optional COMMAND-DESC is a command description that can be
printed with the error message."
  ;; FIXME Does this function throw exceptions?
  ;;--------------------------------------------
  ;; This assertion often fails for some reason,
  ;; perhaps some asynchrony involved?
  ;; Assertion check being disabled unless debugging is on.
  (if vm-buffer-type-debug
      (vm-buffer-type:assert 'process))
  (if vm-buffer-type-debug
      (setq vm-buffer-type-trail (cons 'verify vm-buffer-type-trail)))
  ;;--------------------------------------------
  (let ((response (vm-imap-read-response process)))
    (if (null response)
	nil
      (when (vm-imap-response-matches response 'VM 'NO)
	(vm-imap-normal-error 
	 "server says - %s" 
	 (vm-imap-read-error-message process (cadr (cadr response)))))
      (when (vm-imap-response-matches response 'VM 'BAD)
	(vm-imap-normal-error 
	 "server says - %s" 
	 (vm-imap-read-error-message process (cadr (cadr response)))))
      (when (vm-imap-response-matches response '* 'BYE)
	(vm-imap-normal-error "server disconnected"))
      response)))

(defun vm-imap-read-error-message (_process pos)
  "Return the error message in the PROCESS buffer starting at position POS."
  (buffer-substring 
   pos
   (save-excursion
     (goto-char pos)
     (if (search-forward "\r\n" (point-max) t)
	 (- (point) 2)
       (+ (point) 2)))))


(defun vm-imap-read-object (process &optional skip-eol)
  "Reads a single token from the PROCESS and returns it.  If the
output from PROCESS is incomplete, waits until enough output becomes
available.

May throw exceptions." 
  ;; The possible tokens are:
  ;;   (end-of-line)
  ;;   (atom position position)
  ;;   (string position position)
  ;;   (vector token...)
  ;;   (list token...)
  ;;   close-bracket
  ;;   close-paren
  ;;   close-brace
  ;;----------------------------------
  ;; Originally, this assertion failed often for some reason,
  ;; perhaps some asynchrony involved?
  ;; It has been mostly chased up by now. (Nov 2009)
  ;; Still assertion check being disabled unless debugging is on.
  (when vm-buffer-type-debug
    (vm-buffer-type:assert 'process))
  (vm-imap-log-tokens (list 'object (current-buffer)))
  ;;----------------------------------
  (let ((done nil)
	opoint
	(token nil))
    (unwind-protect
	(while (not done)		; object continuing
	  (skip-chars-forward " \t")
	  (cond ((< (- (point-max) (point)) 2)
		 (setq opoint (point))
		 (vm-imap-check-connection process)
		 ;; point might change here?
		 (vm-accept-process-output process) 
		 (goto-char opoint))
		((looking-at "\r\n")
		 (forward-char 2)
		 (setq token '(end-of-line) done (not skip-eol)))
		((looking-at "\n")
		 (vm-warn 0 2 
		  "missing CR before LF - IMAP connection may have a problem")
		 (when vm-debug (debug "vm-imap-read-object" 
				       "missing CR before LF"))
		 (forward-char 1)
		 (setq token '(end-of-line) done (not skip-eol)))
		((looking-at "\\[")
		 (forward-char 1)
		 (let* ((list (list 'vector))
			(tail list)
			obj)
		   (setq obj (vm-imap-read-object process t))
		   (while (not (eq (car obj) 'close-bracket))
		     (when (eq (car obj) 'close-paren)
		       (vm-imap-protocol-error "unexpected )"))
		     (setcdr tail (cons obj nil))
		     (setq tail (cdr tail))
		     (setq obj (vm-imap-read-object process t)))
		   (setq token list done t)))
		((looking-at "\\]")
		 (forward-char 1)
		 (setq token '(close-bracket) done t))
		((looking-at "(")
		 (forward-char 1)
		 (let* ((list (list 'list))
			(tail list)
			obj)
		   (setq obj (vm-imap-read-object process t))
		   (while (not (eq (car obj) 'close-paren))
		     (when (eq (car obj) 'close-bracket)
		       (vm-imap-protocol-error "unexpected ]"))
		     (setcdr tail (cons obj nil))
		     (setq tail (cdr tail))
		     (setq obj (vm-imap-read-object process t)))
		   (setq token list done t)))
		((looking-at ")")
		 (forward-char 1)
		 (setq token '(close-paren) done t))
		((looking-at "{")
		 ;; string ::= { n-octets } end-of-line octets...
		 (forward-char 1)
		 (let (start obj n-octets)
		   (setq obj (vm-imap-read-object process))
		     (unless (and (eq (car obj) 'atom)
				  (string-match 
				   "[0-9]*"
				   (buffer-substring (nth 1 obj) (nth 2 obj))))
		       (vm-imap-protocol-error "number expected after {"))
		     ;; gmail sometimes outputs random strings in
		     ;; braces, but we can't accept them.
		     (setq n-octets 
			   (string-to-number
			    (buffer-substring (nth 1 obj) (nth 2 obj))))
		     (setq obj (vm-imap-read-object process))
		     (unless (eq (car obj) 'close-brace)
		       (vm-imap-protocol-error "} expected"))
		     (setq obj (vm-imap-read-object process))
		     (unless (eq (car obj) 'end-of-line)
		       (vm-imap-protocol-error "CRLF expected"))
		     (setq start (point))
		     (while (< (- (point-max) start) n-octets)
		       (vm-imap-check-connection process)
		       ;; point might change here?  USR, 2011-03-16
		       (vm-accept-process-output process))
		     (goto-char (+ start n-octets))
		     (setq token (list 'string start (point))
			   done t)))
		((looking-at "}")
		 (forward-char 1)
		 (setq token '(close-brace) done t))
		((looking-at "\042") ;; double quote
		 (forward-char 1)
		 (let ((start (point))
		       (curpoint (point)))
		   (while (not done)
		     (skip-chars-forward "^\042")
		     (setq curpoint (point))
		     (if (looking-at "\042")
			 (progn
			   (setq done t)
			   (forward-char 1))
		       (vm-imap-check-connection process)
		       ;; point might change here?
		       (vm-accept-process-output process)
		       (goto-char curpoint))
		     (setq token (list 'string start curpoint)))))
		;; should be (looking-at "[\000-\040\177-\377]")
		;; but Microsoft Exchange emits 8-bit chars.
		((and (looking-at "[\000-\040\177]") 
		      (= vm-imap-tolerant-of-bad-imap 0))
		 (vm-imap-protocol-error "illegal char (%d)"
					 (char-after (point))))
		(t
		 (let ((start (point))
		       (curpoint (point))
		       ;; We should be considering 8-bit chars as
		       ;; non-word chars also but Microsoft Exchange
		       ;; uses them, despite the RFC 2060 prohibition.
		       ;; If we ever resume disallowing 8-bit chars,
		       ;; remember to write the range as \177-\376 ...
		       ;; \376 instead of \377 because Emacs 19.34 has
		       ;; a bug in the fastmap initialization code
		       ;; that causes it to infloop.
		       (not-word-chars "^\000-\040\177()[]{}")
		       (not-word-regexp "[][\000-\040\177(){}]"))
		   (while (not done)
		     (skip-chars-forward not-word-chars)
		     (setq curpoint (point))
		     (if (looking-at not-word-regexp)
			 (setq done t)
		       (vm-imap-check-connection process)
		       ;; point might change here?
		       (vm-accept-process-output process)
		       (goto-char curpoint))
		     (vm-imap-log-token (buffer-substring start curpoint))
		     (setq token (list 'atom start curpoint)))))))
      ;; unwind-protections
      (setq vm-imap-read-point (point))
      (vm-imap-log-token vm-imap-read-point)
      (vm-imap-log-token token))
    token ))

(defun vm-imap-response-matches (response &rest expr)
  "Checks if a REPSONSE from the IMAP server matches the pattern
EXPR.  The syntax of patterns is:

  EXPR ::= QUOTED-SYMBOL | atom | string | (vector EXPR*) | (list EXPR*)

Numbers are included among atoms."
  (let ((case-fold-search t) e r)
    (catch 'done
      (if (null response)
	  (throw 'done nil))
      (while (and expr response)
	(setq e (car expr)
	      r (car response))
	(cond ((stringp e)
	       (if (or (not (eq (car r) 'string))
		       (save-excursion
			 (goto-char (nth 1 r))
			 (not (eq (search-forward e (nth 2 r) t) (nth 2 r)))))
		   (throw 'done nil)))
	      ((numberp e)
	       (if (or (not (eq (car r) 'atom))
		       (save-excursion
			 (goto-char (nth 1 r))
			 (not (eq (search-forward (int-to-string e)
						  (nth 2 r) t)
				  (nth 2 r)))))
		   (throw 'done nil)))
	      ((consp e)
	       (if (not (eq (car e) (car r)))
		   (throw 'done nil))
	       (apply 'vm-imap-response-matches (cdr r) (cdr e)))
	      ((eq e 'atom)
	       (if (not (eq (car r) 'atom))
		   (throw 'done nil)))
	      ((eq e 'vector)
	       (if (not (eq (car r) 'vector))
		   (throw 'done nil)))
	      ((eq e 'list)
	       (if (not (eq (car r) 'list))
		   (throw 'done nil)))
	      ((eq e 'string)
	       (if (not (eq (car r) 'string))
		   (throw 'done nil)))
	      ;; this must to come after all the comparisons for
	      ;; specific symbols.
	      ((symbolp e)
	       (if (or (not (eq (car r) 'atom))
		       (save-excursion
			 (goto-char (nth 1 r))
			 (not (eq (search-forward (symbol-name e) (nth 2 r) t)
				  (nth 2 r)))))
		   (throw 'done nil))))
	(setq response (cdr response)
	      expr (cdr expr)))
      t )))

(defun vm-imap-bail-if-server-says-farewell (response)
  (if (vm-imap-response-matches response '* 'BYE)
      (throw 'end-of-session t)))

(defun vm-imap-scan-list-for-flag (list flag)
  (setq list (cdr list))
  (let ((case-fold-search t) e)
    (catch 'done
      (while list
	(setq e (car list))
	(if (not (eq (car e) 'atom))
	    nil
	  (goto-char (nth 1 e))
	  (if (eq (search-forward flag (nth 2 e) t) (nth 2 e))
	      (throw 'done t)))
	(setq list (cdr list)))
      nil )))

;; like Lisp get but for IMAP property lists like those returned by FETCH.
(defun vm-imap-plist-get (list name)
  (setq list (cdr list))
  (let ((case-fold-search t) e)
    (catch 'done
      (while list
	(setq e (car list))
	(if (not (eq (car e) 'atom))
	    nil
	  (goto-char (nth 1 e))
	  (if (eq (search-forward name (nth 2 e) t) (nth 2 e))
	      (throw 'done (car (cdr list)))))
	(setq list (cdr (cdr list))))
      nil )))

(defun vm-imap-poke-session (process)
  "Poke the IMAP session by sending a NOOP command, just to make sure
that the session is active.  Returns t or nil."
  (if (and process (memq (process-status process) '(open run))
	   (buffer-live-p (process-buffer process)))
      (if vm-imap-ensure-active-sessions
	  (let ((imap-buffer (process-buffer process)))
	    (with-current-buffer imap-buffer
	      ;;----------------------------
	      (vm-buffer-type:enter 'process)
	      ;;----------------------------
	      (vm-inform 7 "%s: Checking IMAP connection to %s..." "server"
			 (buffer-name vm-mail-buffer))
	      (vm-imap-send-command process "NOOP")
	      (condition-case _err
		  (let ((response nil)
			(need-ok t))
		    (while need-ok
		      (setq response
			    (vm-imap-read-response-and-verify process "NOOP"))
		      (cond ((vm-imap-response-matches response 'VM 'OK)
			     (setq need-ok nil))))
		    (vm-inform 7 "Checking IMAP connection to %s...alive" "server")
		    ;;----------------------------
		    (vm-buffer-type:exit)
		    ;;----------------------------
		    t)
		(vm-imap-protocol-error	; handler
		 ;;--------------------
		 (vm-buffer-type:exit)
		 ;;--------------------
		 nil))))		; ignore errors
	t)
    nil))

(defun vm-re-establish-folder-imap-session (&optional interactive purpose
						      just-retrieve)
  "If the IMAP session for the current folder has died,
re-establish a new one.  Optional argument PURPOSE is inserted
into the process buffer for tracing purposes. Optional argument
JUST-RETRIEVE says whether the session will only be used for
retrieval of mail. Returns the IMAP process or nil if
unsuccessful."
  (let ((process (vm-folder-imap-process))) ;; temp
    (if (and (processp process)
	     (vm-imap-poke-session process))
	process
      (when process
	(vm-imap-end-session process))
      (vm-establish-new-folder-imap-session 
       interactive purpose just-retrieve))))

(defun vm-establish-new-folder-imap-session (&optional interactive purpose
						       just-retrieve)
  "Kill and restart the IMAP session for the current folder.
Optional argument PURPOSE is inserted into the process buffer for
tracing purposes. Optional argument JUST-RETRIEVE says whether
the session will only be used for retrieval of mail. Returns the
IMAP process or nil if unsuccessful."
  ;; This is necessary because we might get unexpected EXPUNGE responses
  ;; which we don't know how to deal with.

  (let (process 
	(vm-imap-ok-to-ask (eq interactive t))
	mailbox select mailbox-count recent-count uid-validity permanent-flags
	read-write can-delete body-peek)
    (if (vm-folder-imap-process)
	(vm-imap-end-session (vm-folder-imap-process)))
    (vm-imap-log-token 'new)
    (setq process 
	  (vm-imap-make-session (vm-folder-imap-maildrop-spec)
				interactive :purpose purpose
				:folder-buffer (current-buffer)))
    (when (processp process)
      (vm-set-folder-imap-process process)
      (setq mailbox (vm-imap-parse-spec-to-list (vm-folder-imap-maildrop-spec))
	    mailbox (nth 3 mailbox))
      (unwind-protect
	  (with-current-buffer (process-buffer process)
	    ;;----------------------------
	    (vm-buffer-type:enter 'process)
	    ;;----------------------------
	    (setq select (vm-imap-select-mailbox process mailbox just-retrieve))
	    (setq mailbox-count (nth 0 select)
		  recent-count (nth 1 select)
		  uid-validity (nth 2 select)
		  read-write (nth 3 select)
		  can-delete (nth 4 select)
		  permanent-flags (nth 5 select)
		  body-peek (vm-imap-capability 'IMAP4REV1))
	    ;;---------------------------------
	    (vm-imap-session-type:set 'active)
	    ;;---------------------------------
	    )
	;; unwind-protections
	;;-------------------
	(vm-buffer-type:exit)
	;;-------------------
	(when (and (vm-folder-imap-uid-validity)
		   uid-validity
		   (not (equal (vm-folder-imap-uid-validity) uid-validity)))
	  (unless (y-or-n-p 
		   (format
		    (concat "%s: Folder's UID VALIDITY value has changed "
			    "on the server.  Refresh cache? ")
		    (buffer-name)))
	    (error "Aborted"))
	  (vm-warn 5 4
		   (concat "VM will download new copies of messages"
			   " and mark the old ones for deletion"))
	  (setq vm-imap-retrieved-messages
		(vm-imap-clear-invalid-retrieval-entries
		 (vm-folder-imap-maildrop-spec)
		 vm-imap-retrieved-messages
		 uid-validity))
	  (vm-mark-folder-modified-p (current-buffer))))

      (vm-set-folder-imap-uid-validity uid-validity) ; unique per session
      (vm-set-folder-imap-mailbox-count mailbox-count)
      (unless (vm-folder-imap-retrieved-count)
	(vm-set-folder-imap-retrieved-count mailbox-count))
      (vm-set-folder-imap-recent-count recent-count)
      (vm-set-folder-imap-read-write read-write)
      (vm-set-folder-imap-can-delete can-delete)
      (vm-set-folder-imap-body-peek body-peek)
      (vm-set-folder-imap-permanent-flags permanent-flags)
      ;;-------------------------------
      (vm-imap-dump-uid-and-flags-data)
      ;;-------------------------------
      process )))

(defun vm-re-establish-writable-imap-session (&optional interactive purpose)
  "If the IMAP session for the current folder has died, re-establish a
new one.  Returns the IMAP process or nil if unsuccessful."
  (let ((process (vm-folder-imap-process))) ;; temp
    (if  (and (processp process)
	      (vm-imap-poke-session process))
	process
      (if process
	  (vm-imap-end-session process))
      (vm-establish-writable-imap-session interactive purpose))))

(defun vm-establish-writable-imap-session (maildrop &optional 
						    interactive purpose)
  "Create a new writable IMAP session for MAILDROP and return the process.
Optional argument PURPOSE is inserted into the process buffer for
tracing purposes. Returns the IMAP process or nil if unsuccessful."
  (let (process 
	(vm-imap-ok-to-ask (eq interactive t))
	mailbox select ;; mailbox-count recent-count uid-validity permanent-flags
	read-write) ;; can-delete body-peek
    (vm-imap-log-token 'new)
    (setq process 
	  (vm-imap-make-session maildrop interactive :purpose purpose
				:folder-buffer (current-buffer)))
    (if (processp process)
	(unwind-protect
	    (save-current-buffer
	      (setq mailbox (vm-imap-parse-spec-to-list maildrop)
		    mailbox (nth 3 mailbox))
	      ;;----------------------------
	      (vm-buffer-type:enter 'process)
	      ;;----------------------------
	      (set-buffer (process-buffer process))
	      (setq select (vm-imap-select-mailbox process mailbox nil))
	      (setq ;; mailbox-count (nth 0 select)
		    ;; recent-count (nth 1 select)
		    ;; uid-validity (nth 2 select)
		    read-write (nth 3 select)
		    ;; can-delete (nth 4 select)
		    ;; permanent-flags (nth 5 select)
		    ;; body-peek (vm-imap-capability 'IMAP4REV1)
		    )
	      ;;---------------------------------
	      (vm-imap-session-type:set 'active)
	      (vm-buffer-type:exit)
	      ;;---------------------------------
	      (if read-write
		  process
		(vm-imap-end-session process)
		nil))
	  ;; unwind-protections
	  ;;--------------------
	  (vm-buffer-type:exit)
	  ;;--------------------
	  )
      nil)))


(defun vm-kill-folder-imap-session  (&optional _interactive)
  (let ((process (vm-folder-imap-process)))
    (if (processp process)
	(vm-imap-end-session process))))

(defun vm-imap-retrieve-uid-and-flags-data ()
  "Retrieve the uid's and message flags for all the messages on the
IMAP server in the current mail box.  The results are stored in
`vm-folder-access-data' in the fields imap-uid-list, imap-uid-obarray
and imap-flags-obarray.
Throws vm-imap-protocol-error for failure.

This function is preferable to `vm-imap-get-uid-list' because it
fetches flags in addition to uid's and stores them in obarrays."
  ;;------------------------------
  (if vm-buffer-type-debug
      (setq vm-buffer-type-trail 
	    (cons 'uid-and-flags-data vm-buffer-type-trail)))
  (vm-buffer-type:assert 'folder)
  ;;------------------------------
  (if (vm-folder-imap-uid-list)
      nil ; don't retrieve twice
    (let ((there (make-vector 67 0))
	  (flags (make-vector 67 0))
	  (process (vm-folder-imap-process))
	  (mailbox-count (vm-folder-imap-mailbox-count))
	  list tuples tuple) ;; uid
      (unwind-protect
	  (with-current-buffer (process-buffer process)
	    ;;----------------------------
	    (vm-buffer-type:enter 'process)
	    ;;----------------------------
	    (if (eq mailbox-count 0)
		(setq list nil)
	      (setq list (vm-imap-get-message-data-list 
			  process 1 mailbox-count)))
	    (setq tuples list)
	    (while tuples
	      (setq tuple (car tuples))
	      (set (intern (cadr tuple) there) (car tuple))
	      (set (intern (cadr tuple) flags) (nthcdr 2 tuple))
	      (setq tuples (cdr tuples)))
	    ;;-------------------------------
	    (vm-imap-session-type:set 'valid)
	    ;;-------------------------------
	    )
	;; unwind-protections
	;; ---------------------
	(vm-buffer-type:exit)
	;; ---------------------
	)
      ;; Clear the old obarrays to make sure no space leaks
      (let ((uid-obarray (vm-folder-imap-uid-obarray))
	    (flags-obarray (vm-folder-imap-flags-obarray)))
	(mapc (function 
	       (lambda (uid)
		 (unintern uid uid-obarray)
		 (unintern uid flags-obarray)))
	      (vm-folder-imap-uid-list)))
      ;; Assign the new data
      (vm-set-folder-imap-uid-list list)
      (vm-set-folder-imap-uid-obarray there)
      (vm-set-folder-imap-flags-obarray flags))))

(defun vm-imap-dump-uid-and-flags-data ()
  (when (and vm-folder-access-data
             (eq (car vm-buffer-types) 'folder))
             
    ;;------------------------------
    (vm-buffer-type:assert 'folder)
    ;;------------------------------
    (vm-set-folder-imap-uid-list nil)
    (vm-set-folder-imap-uid-obarray nil)
    (vm-set-folder-imap-flags-obarray nil)
    (if (processp (vm-folder-imap-process))
	(with-current-buffer (process-buffer (vm-folder-imap-process))
	  ;;---------------------------------
	  (vm-imap-session-type:set 'active)
	  ;;---------------------------------
	  ))
    ))

(defun vm-imap-dump-uid-seq-num-data ()
  (when (and vm-folder-access-data
             (eq (car vm-buffer-types) 'folder))
             
    ;;------------------------------
    (vm-buffer-type:assert 'folder)
    ;;------------------------------
    (vm-set-folder-imap-uid-list nil)
    (vm-set-folder-imap-uid-obarray nil)
    (if (processp (vm-folder-imap-process))
	(with-current-buffer (process-buffer (vm-folder-imap-process))
	  ;;---------------------------------
	  (vm-imap-session-type:set 'active)
	  ;;---------------------------------
	  ))
    ))

;; This function is now obsolete.  It is faster to get flags of
;; several messages at once, using vm-imap-get-message-data-list

(defun vm-imap-get-message-flags (process m &optional norecord)
  ;; gives an error if the message has an invalid uid
  (let (need-ok p r flag response saw-Seen)
    (unless (equal (vm-imap-uid-validity-of m)
		   (vm-folder-imap-uid-validity))
      (vm-imap-normal-error "message UIDVALIDITY does not match the server"))
    (unwind-protect
	(with-current-buffer (process-buffer process)
	  ;;----------------------------------
	  (vm-buffer-type:enter 'process)
	  (vm-imap-session-type:assert-active)
	  ;;----------------------------------
	  (vm-imap-send-command process
				(format "UID FETCH %s (FLAGS)"
					(vm-imap-uid-of m)))
	  ;;--------------------------------
	  (vm-imap-session-type:set 'active)
	  ;;--------------------------------
	  (setq need-ok t)
	  (while need-ok
	    (setq response (vm-imap-read-response-and-verify 
			    process "UID FETCH (FLAGS)"))
	    (cond ((vm-imap-response-matches response 'VM 'OK)
		   (setq need-ok nil))
		  ((vm-imap-response-matches response '* 'atom 'FETCH 'list)
		   (setq r (nthcdr 3 response)
			 r (car r)
			 r (vm-imap-plist-get r "FLAGS")
			 r (cdr r))
		   (while r
		     (setq p (car r))
		     (if (not (eq (car p) 'atom))
			 nil
		       (setq flag (downcase (buffer-substring (nth 1 p) (nth 2 p))))
		       (cond ((string= flag "\\answered")
			      (vm-set-replied-flag m t norecord))
			     ((string= flag "\\deleted")
			      (vm-set-deleted-flag m t norecord))
			     ((string= flag "\\flagged")
			      (vm-set-flagged-flag m t norecord))
			     ((string= flag "\\seen")
			      (vm-set-unread-flag m nil norecord)
			      (vm-set-new-flag m nil norecord)
			      (setq saw-Seen t))
			     ((string= flag "\\recent")
			      (vm-set-new-flag m t norecord))))
		     (setq r (cdr r)))
		   (if (not saw-Seen)
		       (vm-set-unread-flag m t norecord))))))
      ;; unwind-protections
      ;;-------------------
      (vm-buffer-type:exit)
      ;;-------------------
      )))

(defun vm-imap-update-message-flags (m flags &optional norecord)
  "Update the flags of the message M in the folder to imap flags FLAGS.
Optional argument NORECORD says whether this fact should not be
recorded in the undo stack."
  (let (flag saw-Seen saw-Deleted saw-Flagged seen-labels labels)
    (while flags
      (setq flag (car flags))
      (cond ((string= flag "\\answered")
	     (when (null (vm-replied-flag m))
	       (vm-set-replied-flag m t norecord)
	       (vm-set-stuff-flag-of m t)))

	    ((string= flag "\\deleted")
	     (when (null (vm-deleted-flag m))
	       (vm-set-deleted-flag m t norecord)
	       (vm-set-stuff-flag-of m t))
	     (setq saw-Deleted t))

	    ((string= flag "\\flagged")
	     (when (null (vm-flagged-flag m))
	       (vm-set-flagged-flag m t norecord)
	       (vm-set-stuff-flag-of m t))
	     (setq saw-Flagged t))

	    ((string= flag "\\seen")
	     (when (vm-unread-flag m)
	       (vm-set-unread-flag m nil norecord)
	       (vm-set-stuff-flag-of m t))
	     (when (vm-new-flag m)
	       (vm-set-new-flag m nil norecord)
	       (vm-set-stuff-flag-of m t))
	     (setq saw-Seen t))

	    ((string= flag "\\recent")
	     (when (null (vm-new-flag m))
	       (vm-set-new-flag m t norecord)
	       (vm-set-stuff-flag-of m t)))

	    ((string= flag "forwarded")
	     (when (null (vm-forwarded-flag m))
	       (vm-set-forwarded-flag m t norecord)
	       (vm-set-stuff-flag-of m t)))

	    ((string= flag "redistributed")
	     (when (null (vm-redistributed-flag m))
	       (vm-set-redistributed-flag m t norecord)
	       (vm-set-stuff-flag-of m t)))

	    ((string= flag "filed")
	     (when (null (vm-filed-flag m))
	       (vm-set-filed-flag m t norecord)
	       (vm-set-stuff-flag-of m t)))

	    ((string= flag "written")
	     (when (null (vm-written-flag m))
	       (vm-set-written-flag m t norecord)
	       (vm-set-stuff-flag-of m t)))

	    (t			  ; all other flags including \flagged
	     (setq seen-labels (cons flag seen-labels)))
	    )
      (setq flags (cdr flags)))

    (if (not saw-Seen)			; unread if the server says so
	(if (null (vm-unread-flag m))
	    (vm-set-unread-flag m t norecord)))
    (if (not saw-Deleted)		; undelete if the server says so
	(if (vm-deleted-flag m)
	    (vm-set-deleted-flag m nil norecord)))
    (if (not saw-Flagged)		; unflag if the server says so
	(if (vm-flagged-flag m)
	    (vm-set-flagged-flag m nil norecord)))
    (setq labels (sort (vm-decoded-labels-of m) 'string-lessp))
    (setq seen-labels (sort seen-labels 'string-lessp))
    (if (equal labels seen-labels)
	t
      (vm-set-decoded-labels-of m seen-labels)
      (vm-set-decoded-label-string-of m nil)
      (vm-mark-for-summary-update m)
      (vm-set-stuff-flag-of m t))
    ))

(defun vm-imap-save-message-flags (process m &optional by-uid)
  "Saves the message flags of a message on the IMAP server,
adding or deleting flags on the server as necessary.  Monotonic
flags, however, are not deleted.

Optional argument BY-UID says that the save commands to the
server should be issued by UID, not message sequence number."

  ;; Comment by USR
  ;; According to RFC 2060, it is not an error to store flags that
  ;; are not listed in PERMANENTFLAGS.  Removed unnecessary checks to
  ;; this effect.

  ;; There are 
  ;; - monotonic flags that can only be set, and 
  ;; - reversible flags that can be set or unset.
  ;; For monotonic flags that are set in VM, we set them on the
  ;; server.
  ;; For reversible flags, we copy the state from VM to the server.
  ;; (We don't know which one has precedence, but we punt that issue.)
  ;; The cache needs to be maintained consistently.

  ;;-----------------------------------------------------
  (vm-buffer-type:assert 'folder)
  (or by-uid (vm-imap-folder-session-type:assert 'valid))
  ;;-----------------------------------------------------
  (if (not (equal (vm-imap-uid-validity-of m)
		  (vm-folder-imap-uid-validity)))
      (vm-imap-normal-error "message UIDVALIDITY does not match the server"))
  (let* ((uid (vm-imap-uid-of m))
	 (uid-key1 (intern uid (vm-folder-imap-uid-obarray)))
	 (uid-key2 (intern-soft uid (vm-folder-imap-flags-obarray)))
	 (message-num (and (boundp uid-key1) (symbol-value uid-key1)))
	 (cached-flags (and (boundp uid-key2) (symbol-value uid-key2)))
					; leave uid as the dummy header
	 (labels (vm-decoded-labels-of m))
	 copied-flags need-ok flags+ flags- response)
    (when message-num
      ;; Reversible flags are treated the same as labels
      (if (not (vm-unread-flag m))
	  (setq labels (cons "\\seen" labels)))
      (if (vm-deleted-flag m)
	  (setq labels (cons "\\deleted" labels)))
      (if (vm-flagged-flag m)
	  (setq labels (cons "\\flagged" labels)))
      ;; Irreversible flags
      (if (and (vm-replied-flag m) 
	       (not (member "\\answered" cached-flags)))
	  (setq flags+ (cons "\\Answered" flags+)))
      (if (and (vm-filed-flag m) (not (member "filed" cached-flags)))
	  (setq flags+ (cons "filed" flags+)))
      (if (and (vm-written-flag m) 
	       (not (member "written" cached-flags)))
	  (setq flags+ (cons "written" flags+)))
      (if (and (vm-forwarded-flag m)
	       (not (member "forwarded" cached-flags)))
	  (setq flags+ (cons "forwarded" flags+)))
      (if (and (vm-redistributed-flag m)
	       (not (member "redistributed" cached-flags)))
	  (setq flags+ (cons "redistributed" flags+)))
      (mapc (lambda (flag) (delete flag cached-flags))
	    '("\\answered" "filed" "written" "forwarded" "redistributed"))
      ;; make copies for side effects
      (setq copied-flags (copy-sequence cached-flags))
      (setq labels (cons nil (copy-sequence labels)))
      ;; Ignore labels that are both in vm and the server
      (vm-delete-common-elements labels copied-flags 'string<)
      ;; Ignore reversible flags that we have locally reversed -- Why?
      ;; (mapc (lambda (flag) (delete flag copied-flags))
      ;;  '("\\seen" "\\deleted" "\\flagged"))
      ;; Flags to be added to the server
      (setq flags+ (append (cdr labels) flags+))
      ;; Flags to be deleted from the server
      (setq flags- (append (cdr copied-flags) flags-))

      (unwind-protect
	  (with-current-buffer (process-buffer process)
	    ;;----------------------------------
	    (vm-buffer-type:enter 'process)
	    ;;----------------------------------
	    (when flags+
	      (vm-imap-send-command 
	       process
	       (format "%sSTORE %s +FLAGS.SILENT %s" 
		       (if by-uid "UID " "")
		       (if by-uid uid message-num)
		       (mapc 'intern flags+)))
	      (setq need-ok t)
	      (while need-ok
		(setq response 
		      (vm-imap-read-response-and-verify 
		       process "STORE +FLAGS.SILENT"))
		(cond ((vm-imap-response-matches response 'VM 'OK)
		       (setq need-ok nil))))
	      (nconc cached-flags flags+))

	    (when flags-
	      (vm-imap-send-command 
	       process
	       (format "%sSTORE %s -FLAGS.SILENT %s"
		       (if by-uid "UID " "")
		       (if by-uid uid message-num)
		       (mapc 'intern flags-)))
	      (setq need-ok t)
	      (while need-ok
		(setq response 
		      (vm-imap-read-response-and-verify 
		       process "STORE -FLAGS.SILENT"))
		(cond ((vm-imap-response-matches response 'VM 'OK)
		       (setq need-ok nil))))
	      (while flags-
		(delete (car flags-) cached-flags)
		(setq flags- (cdr flags-))))

	    (vm-set-attribute-modflag-of m nil)
	    )
	;; unwind-protections
	;;-------------------
	(vm-buffer-type:exit)
	;;-------------------
	))))

(defvar vm-imap-subst-char-in-string-buffer
  (get-buffer-create " *subst-char-in-string*"))

(defun vm-imap-subst-CRLF-for-LF (string)
  (with-current-buffer vm-imap-subst-char-in-string-buffer
    (erase-buffer)
    (insert string)
    (goto-char (point-min))
    (while (search-forward "\n" nil t)
      (replace-match "\r\n" nil t))
    (buffer-substring-no-properties (point-min) (point-max))))

;;;###autoload
(defun vm-imap-save-message (process m mailbox)
  "Using the IMAP process PROCESS, save the message M to IMAP mailbox
MAILBOX." 
  (let (need-ok need-plus flags response string)
    ;; save the message's flag along with it.
    ;; don't save the deleted flag.
    (if (vm-replied-flag m)
	(setq flags (cons (intern "\\Answered") flags)))
    (if (not (vm-unread-flag m))
	(setq flags (cons (intern "\\Seen") flags)))
    (with-current-buffer (vm-buffer-of m)
      ;;----------------------------
      (vm-buffer-type:enter 'folder)
      ;;----------------------------
      (save-restriction
	(widen)
	(setq string (buffer-substring (vm-headers-of m) (vm-text-end-of m))
              string (vm-imap-subst-CRLF-for-LF string)))
      ;;-------------------
      (vm-buffer-type:exit)
      ;;-------------------
      )
    (unwind-protect
	(with-current-buffer (process-buffer process)
	  ;;----------------------------
	  (vm-buffer-type:enter 'process)
	  ;;----------------------------
	  (condition-case nil
	      (vm-imap-create-mailbox process mailbox)
	    ;; ignore errors
	    (vm-imap-protocol-error (vm-buffer-type:set 'process)))
	  ;;----------------------------------
	  (vm-imap-session-type:assert-active)
	  ;;----------------------------------
	  (vm-imap-send-command process
				(format "APPEND %s %s {%d}"
					(vm-imap-quote-mailbox-name mailbox)
					(if flags flags "()")
					(length string)))
	  ;;--------------------------------
	  (vm-imap-session-type:set 'active)
	  ;;--------------------------------
	  (setq need-plus t)
	  (while need-plus
	    (setq response (vm-imap-read-response-and-verify process "APPEND"))
	    (cond ((vm-imap-response-matches response '+)
		   (setq need-plus nil))))
	  (vm-imap-send-command process string nil t)
	  (setq need-ok t)
	  (while need-ok
	    (setq response (vm-imap-read-response-and-verify 
			    process "APPEND data"))
	    (cond ((vm-imap-response-matches response 'VM 'OK)
		   (setq need-ok nil))))
	  )
      ;; unwind-protections
      ;;-------------------
      (vm-buffer-type:exit)
      ;;-------------------
      )))

;; Incomplete -- Yet to be finished.  USR
;; creation of new mailboxes has to be straightened out

(defun vm-imap-copy-message (process m mailbox)
  "Use IMAP session PROCESS to copy message M to MAILBOX.  The PROCESS
is expected to have logged in and selected the current folder.

This is similar to `vm-imap-save-message' but uses the internal copy
operation of the server to minimize I/O."
  ;;-----------------------------
  (vm-buffer-type:set 'folder)
  ;;-----------------------------
  (let (;; (uid (vm-imap-uid-of m))
	(uid-validity (vm-imap-uid-validity-of m))
	need-ok response) ;; string
    (if (not (equal uid-validity (vm-folder-imap-uid-validity)))
	(error "Message does not have a valid UID"))
    (unwind-protect
	(save-excursion
	  ;;------------------------
	  (vm-buffer-type:duplicate)
	  ;;------------------------
	  (if (vm-attribute-modflag-of m)
	      (condition-case nil
		  (progn
		    (if (null (vm-folder-imap-flags-obarray))
			(vm-imap-retrieve-uid-and-flags-data))
		    (vm-imap-save-message-flags process m 'by-uid))
		(vm-imap-protocol-error nil))) ; is this right?
	  ;; (condition-case nil
	  ;;   (vm-imap-create-mailbox process mailbox)
	  ;; (vm-imap-protocol-error nil))

	  (set-buffer (process-buffer process))
	  ;;-----------------------------------------
	  (vm-buffer-type:set 'process)
	  (vm-imap-session-type:assert-active)
	  ;;-----------------------------------------
	  (vm-imap-send-command 
	   process
	   (format "UID COPY %s %s"
		   (vm-imap-uid-of m)
		   (vm-imap-quote-mailbox-name mailbox)))
	  ;;--------------------------------
	  (vm-imap-session-type:set 'active)
	  ;;--------------------------------
	  (setq need-ok t)
	  (while need-ok
	    (setq response 
		  (vm-imap-read-response-and-verify process "UID COPY"))
	    (cond ((vm-imap-response-matches response 'VM 'OK)
		   (setq need-ok nil)))))
      ;;-------------------
      (vm-buffer-type:exit)
      ;;-------------------
      )))

;; ------------------------------------------------------------------------
;; 
;;; interactive commands:
;;
;; vm-create-imap-folder: string -> void
;; vm-delete-imap-folder: string -> void
;; vm-rename-imap-folder: string & string -> void
;; 
;; top-level operations
;; vm-fetch-imap-message: (vm-message) -> void
;; vm-imap-synchronize-folder:
;;	(&optional :interactive interactive & 
;;                 :do-remote-expunges nil|t|'all & 
;;                 :do-local-expunges bool & 
;;                 :do-retrieves bool &
;;                 :save-attributes nil|t|'all & 
;;                 :retrieve-attributes bool) -> void
;; vm-imap-save-attributes: (&optional :all-flags bool) -> void
;; vm-imap-folder-check-mail: (&optional interactive) -> ?
;;
;; vm-imap-get-synchronization-data: (&optional bool) -> 
;;		(retrieve-list: (uid . int) list &
;;		 remote-expunge-list: (uid . uidvalidity) list &
;;		 local-expunge-list: vm-message list & 
;;		 stale-list: vm-message list)
;;
;; ------------------------------------------------------------------------



(defun vm-imap-get-synchronization-data (&optional do-retrieves)
  "Compares the UID's of messages in the local cache and the IMAP
server.  Returns a list containing:
RETRIEVE-LIST: A list of pairs consisting of UID's and message
  sequence numbers of the messages that are not present in the
  local cache and not retrieved previously, and, hence, need to be
  retrieved now.
REMOTE-EXPUNGE-LIST: A list of pairs consisting of UID's and
  UIDVALIDITY's of the messages that are not present in the local
  cache (but we have reason to believe that they have been retrieved
  previously) and, hence, need to be expunged on the server. 
LOCAL-EXPUNGE-LIST: A list of message descriptors for messages in the
  local cache which are not present on the server and, hence, need
  to expunged locally.
STALE-LIST: A list of message descriptors for messages in the
  local cache whose UIDVALIDITY values are stale.
If the argument DO-RETRIEVES is `full', then all the messages that
are not presently in cache are retrieved.  Otherwise, the
messages previously retrieved are ignored."

  ;; Comments by USR
  ;; - Originally, messages with stale UIDVALIDITY values were
  ;; ignored.  So, they would never get expunged from the cache.  The
  ;; STALE-LIST component was added to fix this.
  
  ;;-----------------------------
  (if vm-buffer-type-debug
      (setq vm-buffer-type-trail (cons 'synchronization-data
				       vm-buffer-type-trail)))
  (vm-buffer-type:assert 'folder)
  ;;-----------------------------
  (let ((here (make-vector 67 0))	; OBARRAY(uid, vm-message)
	there ;; flags
	(uid-validity (vm-folder-imap-uid-validity))
	(do-full-retrieve (eq do-retrieves 'full))
	retrieve-list remote-expunge-list local-expunge-list stale-list uid
	mp retrieved-entry)
    (vm-imap-retrieve-uid-and-flags-data)
    (setq there (vm-folder-imap-uid-obarray))
    ;; Figure out stale uidvalidity values and messages to be expunged
    ;; in the cache.
    (setq mp vm-message-list)
    (while mp
      (cond ((not (equal (vm-imap-uid-validity-of (car mp)) uid-validity))
	     (setq stale-list (cons (car mp) stale-list)))
	    ((member "stale" (vm-decoded-labels-of (car mp)))
	     nil)
	    (t
	     (setq uid (vm-imap-uid-of (car mp)))
	     (set (intern uid here) (car mp))
	     (if (not (boundp (intern uid there)))
		 (setq local-expunge-list (cons (car mp) local-expunge-list)))))
      (setq mp (cdr mp)))
    ;; Figure out messages that need to be retrieved
    (mapatoms 
     (lambda (sym)
       (let ((uid (symbol-name sym)))
	 (unless  (boundp (intern uid here))
	   ;; message not in cache.  if it has been retrieved
	   ;; previously, it needs to be expunged on the server.
	   ;; otherwise, it needs to be retrieved.
	   (setq retrieved-entry
		 (vm-find vm-imap-retrieved-messages
			  (lambda (entry)
			    (and (equal (car entry) uid)
				 (equal (cadr entry) uid-validity)))))
	   (if (or do-full-retrieve (null retrieved-entry)) ; already retrieved
	       (setq retrieve-list 
		     (cons (cons uid (symbol-value sym)) retrieve-list))
	     (setq remote-expunge-list
		   (cons (cons uid uid-validity)
			 remote-expunge-list))))))
     there)
    (setq retrieve-list 
	  (sort retrieve-list 
		(lambda (**pair1 **pair2)
		  (< (cdr **pair1) (cdr **pair2)))))	  
    (list retrieve-list remote-expunge-list local-expunge-list stale-list)))

(defun vm-imap-server-error (msg &rest args)
  (if (eq vm-imap-connection-mode 'online)
      (apply (function error) msg args)
    (vm-inform 1 "VM working in offline mode")))

;;;###autoload
(cl-defun vm-imap-synchronize-folder (&key
				    (interactive nil)
				    (do-remote-expunges nil)
				    (do-local-expunges nil)
				    (do-retrieves nil)
				    (save-attributes nil)
				    (retrieve-attributes nil))
  "Synchronize IMAP folder with the server.
   INTERACTIVE says whether the function was invoked interactively,
   e.g., as vm-get-spooled-mail.  The possible values are t,
   `password-only', and nil.
   DO-REMOTE-EXPUNGES indicates whether the server mail box should be
   expunged.  If it is `all', then all messages not present in the cache folder
   are expunged.
   DO-LOCAL-EXPUNGES indicates whether the cache buffer should be
   expunged.
   DO-RETRIEVES indicates if new messages that are not already in the
   cache should be retrieved from the server.  If this flag is `full'
   then messages previously retrieved but not in cache are retrieved
   as well.
   SAVE-ATTRIBUTES indicates if the message attributes should be updated on
   the server.  If it is `all', then the attributes of all messages are
   updated irrespective of whether they were modified or not.
   RETRIEVE-ATTRIBTUES indicates if the message attributes on the server
   should be retrieved, updating the cache.
"
  ;; -- Comments by USR
  ;; Not clear why do-local-expunges and do-remote-expunges should be
  ;; separate.  It doesn't make sense to do one but not the other!

  ;;--------------------------
  (if vm-buffer-type-debug
      (setq vm-buffer-type-trail (cons 'synchronize vm-buffer-type-trail)))
  (vm-buffer-type:set 'folder)
  (vm-imap-init-log)
  (vm-imap-log-tokens (list 'synchronize (current-buffer)
			    (vm-folder-imap-process)))
  (setq vm-buffer-type-trail nil)
  ;;--------------------------
  (if (and do-retrieves vm-block-new-mail)
      (error "Can't get new mail until you save this folder"))
  (if (or vm-global-block-new-mail
	  (eq vm-imap-connection-mode 'offline)
	  (null (vm-establish-new-folder-imap-session 
		 interactive "general operation" nil)))
      (vm-imap-server-error "Could not connect to the IMAP server")
    (if do-retrieves
	(vm-assimilate-new-messages))	; Just to be sure
    (vm-inform 6 "%s: Logging into the IMAP server..." (buffer-name))
    (let* ((folder-buffer (current-buffer))
	   (folder-name (buffer-name folder-buffer))
	   (process (vm-folder-imap-process))
	   ;; (imap-buffer (process-buffer process))
	   (uid-validity (vm-folder-imap-uid-validity))
	   ;; (imapdrop (vm-folder-imap-maildrop-spec))
	   ;; (folder (or (vm-imap-folder-for-spec imapdrop)
	   ;;             (vm-safe-imapdrop-string imapdrop)))
	   new-messages
	   (sync-data (vm-imap-get-synchronization-data do-retrieves))
	   (retrieve-list (nth 0 sync-data))
	   (remote-expunge-list (nth 1 sync-data))
	   (local-expunge-list (nth 2 sync-data))
	   (stale-list (nth 3 sync-data)))
      (when save-attributes
	(let ((mp vm-message-list)
	      (errors 0))
	  ;;  (perm-flags (vm-folder-imap-permanent-flags))
	  (vm-inform 6 "%s: Updating attributes on the IMAP server... "
		     folder-name)
	  (while mp
	    (if (or (eq save-attributes 'all)
		    (vm-attribute-modflag-of (car mp)))
		(condition-case nil
		    (vm-imap-save-message-flags process (car mp))
		  (vm-imap-protocol-error ; handler
		   (setq errors (1+ errors))
		   (vm-buffer-type:set 'folder))))
	    (setq mp (cdr mp)))
	  (if (> errors 0)
	      (vm-inform 3
	       "%s: Updating attributes on the IMAP server... %d errors" 
	       folder-name errors)
	    (vm-inform 6 "%s: Updating attributes on the IMAP server... done"
		       folder-name))))
      (when retrieve-attributes
	(let ((mp vm-message-list)
	      ;; (len (length vm-message-list))
	      (n 0)
	      uid m mflags)
	  (vm-inform 6 "%s: Retrieving message attributes and labels... "
		     folder-name)
	  (while mp
	    (setq m (car mp))
	    (setq uid (vm-imap-uid-of m))
	    (when (and (equal (vm-imap-uid-validity-of m) uid-validity)
		       (vm-folder-imap-uid-msn uid))
	      (setq mflags (vm-folder-imap-uid-message-flags uid))
	      (vm-imap-update-message-flags m mflags t))
	    (setq mp (cdr mp)
		  n (1+ n)))
	  (vm-inform 6 "%s: Retrieving message atrributes and labels... done"
		     folder-name)
	  ))
      (when (and do-retrieves retrieve-list)
	(setq new-messages (vm-imap-retrieve-messages retrieve-list)))

      (when do-local-expunges
	(vm-inform 6 "%s: Expunging messages in cache... "
		   folder-name)
	(vm-expunge-folder :quiet t :just-these-messages local-expunge-list)
	(if (and (eq interactive t) stale-list)
	    (if (y-or-n-p 
		 (format 
		  "%s: Found %s messages with invalid UIDs.  Expunge them? "
		  folder-name (length stale-list)))
		(vm-expunge-folder :quiet t :just-these-messages stale-list)
	      (vm-inform 1 "%s: They will be labelled 'stale'" folder-name)
	      (mapc 
	       (lambda (m)
		 (vm-add-or-delete-message-labels "stale" (list m) 'all))
	       stale-list)
	      ))
	(vm-inform 6 "%s: Expunging messages in cache... done" folder-name))

      (when (and do-remote-expunges
		 (if (eq do-remote-expunges 'all)
		     (setq vm-imap-messages-to-expunge remote-expunge-list)
		   vm-imap-messages-to-expunge))
	(vm-imap-expunge-remote-messages))
      ;; Not clear that one should end the session right away.  We
      ;; will keep it around for use with headers-only messages.
      ;; (vm-imap-end-session process)
      (setq vm-imap-connection-mode 'online)
      new-messages)))

(defun vm-imap-retrieve-messages (retrieve-list)
  "Retrieve into the current folder messages listed in
RETRIEVE-LIST and return the list of the retrieved messages.  The
RETRIEVE-LIST is a list of cons-pairs (uid . n) of the UID's and
message sequence numbers of messages on the IMAP server.  If
`vm-enable-external-messages' includes `imap', then messages
larger than `vm-imap-max-message-size' are retrieved in
headers-only form."
  (let* ((folder-buffer (current-buffer))
	 (process (vm-folder-imap-process))
	 (imapdrop (vm-folder-imap-maildrop-spec))
	 (folder (or (vm-imap-folder-for-spec imapdrop)
		     (vm-safe-imapdrop-string imapdrop)))
	 (use-body-peek (vm-folder-imap-body-peek))
	 (uid-validity (vm-folder-imap-uid-validity))
	 uid r-list r-entry range new-messages message-size 
	 statblob old-eob pos k mp pair
	 (headers-only (or (eq vm-enable-external-messages t)
			  (memq 'imap vm-enable-external-messages)))
	 (n 0))
    (save-excursion
      (vm-inform 6 "%s: Retrieving new messages... " 
		 (buffer-name folder-buffer))
      (save-restriction
       (widen)
       (setq old-eob (point-max))
       (goto-char (point-max))
       (when (null vm-imap-max-message-size)
	 (setq vm-imap-max-message-size most-positive-fixnum))
       ;; Annotate retrieve-list with headers-only flags
       (setq retrieve-list
	     (mapcar 
	      (lambda (pair)
		(if (> (read (vm-folder-imap-uid-message-size (car pair)))
		       vm-imap-max-message-size)
		    (list (car pair) (cdr pair) headers-only)
		  (list (car pair) (cdr pair) nil)))
	      retrieve-list))
       (setq r-list (vm-imap-bunch-retrieve-list 
		     (mapcar (function cdr) retrieve-list)))
       (unwind-protect
	   (condition-case error-data
	       (with-current-buffer (process-buffer process)
		 ;;----------------------------
		 (vm-buffer-type:enter 'process)
		 ;;----------------------------
		 (setq statblob (vm-imap-start-status-timer))
		 (vm-set-imap-status-mailbox statblob folder)
		 (vm-set-imap-status-maxmsg statblob
					    (length retrieve-list))
		 (while r-list
		   (setq pair (car r-list)
			 range (car pair)
			 headers-only (cadr pair))
		   (vm-set-imap-status-currmsg statblob n)
		   (setq message-size 
			 (vm-imap-get-message-size
			  process (car range))) ; sloppy, one size fits all
		   (vm-set-imap-status-need statblob message-size)
		   ;;----------------------------------
		   (vm-imap-session-type:assert 'valid)
		   ;;----------------------------------
		   (vm-imap-fetch-messages 
		    process (car range) (cdr range)
		    use-body-peek headers-only)
		   (setq k (1+ (- (cdr range) (car range))))
		   (setq pos (with-current-buffer folder-buffer (point)))
		   (while (> k 0)
		     (vm-imap-retrieve-to-target process folder-buffer
						 statblob use-body-peek)
		     (with-current-buffer folder-buffer
		       (if (= (point) pos)
			   (debug "IMAP internal error #2012: the point hasn't moved")))
		     (setq k (1- k)))
		   (vm-imap-read-ok-response process)
		   (setq r-list (cdr r-list)
			 n (+ n (1+ (- (cdr range) (car range)))))))
	     (vm-imap-normal-error	; handler
	      (vm-warn 0 2 "IMAP error: %s" (cadr error-data)))
	     (vm-imap-protocol-error	; handler
	      (vm-warn 0 2 "Retrieval from %s signaled: %s" folder
			 error-data))
	     ;; Continue with whatever messages have been read
	     (quit
	      (delete-region old-eob (point-max))
	      (error (format "Quit received during retrieval from %s"
			     folder))))
	 ;; unwind-protections
	 (when statblob 
	   (vm-imap-stop-status-timer statblob))	   
	 ;;-------------------
	 (vm-buffer-type:exit)
	 ;;-------------------
	 )
       ;; to make the "Mail" indicator go away
       (setq vm-spooled-mail-waiting nil)
       (vm-set-folder-imap-retrieved-count (vm-folder-imap-mailbox-count))
       (intern (buffer-name) vm-buffers-needing-display-update)
       (vm-inform 6 "%s: Updating summary... " (buffer-name folder-buffer))
       (vm-update-summary-and-mode-line)
       (setq mp (vm-assimilate-new-messages :read-attributes nil))
       (setq new-messages mp)
       (if new-messages
	   (vm-increment vm-modification-counter))
       (setq r-list retrieve-list)
       (while mp
	 (setq r-entry (car r-list)
	       uid (car r-entry)
	       headers-only (nth 2 r-entry))
	 (when headers-only 
	   (vm-set-body-to-be-retrieved-of (car mp) t)
	   (vm-set-body-to-be-discarded-of (car mp) nil))
	 (vm-set-imap-uid-of (car mp) uid)
	 (vm-set-imap-uid-validity-of (car mp) uid-validity)
	 (vm-set-byte-count-of 
	  (car mp) (vm-folder-imap-uid-message-size uid))
	 (vm-imap-update-message-flags 
	  (car mp) (vm-folder-imap-uid-message-flags uid) t)
	 (vm-mark-for-summary-update (car mp))
	 (vm-set-stuff-flag-of (car mp) t)
	 (setq mp (cdr mp)
	       r-list (cdr r-list)))
       ;; (vm-update-summary-and-mode-line) ; update message sizes, possibly
       (when vm-arrived-message-hook
	 (mapc (lambda (m)
		 (vm-run-hook-on-message 'vm-arrived-message-hook m))
	       new-messages))
       (run-hooks 'vm-arrived-messages-hook)
       new-messages
       ))))

(defun vm-imap-expunge-remote-messages ()
  "Expunge from the IMAP server messages listed in
`vm-imap-messages-to-expunge'." 
  ;; New code.  Kyle's version was piggybacking on IMAP spool
  ;; file code and wasn't ideal.
  (let* ((folder-buffer (current-buffer))
	 (process (vm-folder-imap-process))
	 (imapdrop (vm-folder-imap-maildrop-spec))
	 (folder (or (vm-imap-folder-for-spec imapdrop)
		     (vm-safe-imapdrop-string imapdrop)))
	 (uid-validity (vm-folder-imap-uid-validity))
	 (mailbox-count (vm-folder-imap-mailbox-count))
	 (expunge-count (length vm-imap-messages-to-expunge))
	 uids-to-delete m-list d-list e-list count) ;; message
    (vm-inform 6 "%s: Expunging messages on the server... "
	       (buffer-name folder-buffer))
    ;; uids-to-delete to have UID's of all UID-valid messages in
    ;; vm-imap-messages-to-expunge 
    (unwind-protect
	(condition-case error-data
	    (progn
	      (setq uids-to-delete
		    (mapcar
		     (lambda (message)
		       (if (equal (cdr message) uid-validity)
			   (car message)
			 nil))
		     vm-imap-messages-to-expunge))
	      (setq uids-to-delete (delete nil uids-to-delete))
	      (unless (equal expunge-count (length uids-to-delete))
		(vm-warn 3 2 
			 "%s deleted messages with invalid UID's were ignored"
			 (- expunge-count (length uids-to-delete))))
	      ;; m-list to have the uid's and message sequence
	      ;; numbers of messages to be expunged, in descending
	      ;; order.  the message sequence numbers don't change
	      ;; in the process, according to the IMAP4 protocol
	      (setq m-list
		    (mapcar 
		     (lambda (uid)
		       (let* ((msn (vm-folder-imap-uid-msn uid)))
			 (and msn (cons uid msn))))
		     uids-to-delete))
	      (setq m-list 
		    (sort (delete nil m-list)
			  (lambda (**pair1 **pair2) 
			    (> (cdr **pair1) (cdr **pair2)))))
	      ;; d-list to have ranges of message sequence numbers
	      ;; of messages to be expunged, in ascending order.
	      (setq d-list (vm-imap-bunch-messages
			    (nreverse (mapcar (function cdr) m-list))))
	      (setq expunge-count 0)	; number of messages expunged
	      (with-current-buffer (process-buffer process)
		;;---------------------------
		(vm-buffer-type:set 'process)
		;;---------------------------
		(mapc (lambda (range)
			(vm-imap-delete-messages
			 process (car range) (cdr range)))
		      d-list)
		;; now expunge and verify that all messages are gone
		(setq m-list (cons nil m-list)) ; dummy header added
		(setq count 0)
		(while (and (cdr m-list) (<= count vm-imap-expunge-retries))
		  ;;----------------------------------
		  (vm-imap-session-type:assert-active)
		  ;;----------------------------------
		  (vm-imap-send-command process "EXPUNGE")
		  ;;--------------------------------
		  (vm-imap-session-type:set 'active)
		  ;;--------------------------------
		  ;; e-list to have the message sequence numbers of
		  ;; messages that got expunged
		  (setq e-list (sort 
				(vm-imap-read-expunge-response process)
				'>))
		  (setq expunge-count (+ expunge-count (length e-list)))
		  (mapc 
		   (lambda (e)
		     (let ((m-cons m-list)
			   (m-pair nil)) ; uid . msn
		       (catch 'done
			 (while (cdr m-cons)
			   (setq m-pair (car (cdr m-cons)))
			   (if (> (cdr m-pair) e) 
					; decrement the message sequence
					; numbers following e in m-list
			       (rplacd m-pair (1- (cdr m-pair)))
			     (when (= (cdr m-pair) e)
			       (rplacd m-cons (cdr (cdr m-cons))))
			     ;; if (< (cdr m-pair) e) it is already expunged
			     ;; clear the message from
			     ;; vm-imap-retrieved-messages 
			     (with-current-buffer folder-buffer
			       (setq vm-imap-retrieved-messages
				     (vm-delete
				      (lambda (ret)
					(and (equal (car ret) (car m-pair))
					     (equal (cadr ret) uid-validity)))
				      vm-imap-retrieved-messages)))
			     (throw 'done t))
			   (setq m-cons (cdr m-cons))))))
		   e-list)
		  ;; m-list has message sequence numbers of messages
		  ;; that haven't yet been expunged
		  (if (cdr m-list)
		      (vm-inform 7 "%s: %s messages yet to be expunged"
				 (buffer-name folder-buffer)
				 (length (cdr m-list))))
					; try again, if the user wants us to
		  (setq count (1+ count)))
		(vm-inform 6 "%s: Expunging messages on the server... done"
			   (buffer-name folder-buffer))))

	  (vm-imap-normal-error		; handler
	   (vm-warn 0 2 "IMAP error: %s" (cadr error-data)))

	  (vm-imap-protocol-error	; handler
	   (vm-warn 0 2 "Expunge from %s signalled: %s"
		      folder error-data))
	  (quit 			; handler
	   (error "Quit received during expunge from %s"
		  folder)))
      ;; unwind-protections
      ;;-----------------------------
      (vm-buffer-type:exit)
      (vm-imap-dump-uid-seq-num-data)
      ;;-----------------------------
      )
    (vm-set-folder-imap-mailbox-count 
     (- mailbox-count expunge-count))
    (vm-set-folder-imap-retrieved-count
     (- (vm-folder-imap-retrieved-count) expunge-count))
    (vm-mark-folder-modified-p)
    ))

(defun vm-imap-bunch-retrieve-list (retrieve-list)
  "RETRIEVE-LIST consists of pairs (message-sequence-number boolean)
  where the boolean flag says whether the message is headers-only.
  Bunch the message sequence numbers to produce a list of pairs
  ((begin-num . end-num) boolean).  Each message in a bunch has the
  same headers-only flag."
  (let ((ranges nil)
	pair headers-only
	beg last last-headers-only next) ;; diff
    (when retrieve-list
      (setq pair (car retrieve-list)
	    beg (car pair)
	    headers-only (cadr pair))
      (setq last beg
	    last-headers-only headers-only)
      (setq retrieve-list (cdr retrieve-list))
      (while retrieve-list
	(setq pair (car retrieve-list)
	      next (car pair)
	      headers-only (cadr pair))
	(if (and (= (- next last) 1)
		 (eq last-headers-only headers-only)
		 (< (- next beg) vm-imap-message-bunch-size))
	    (setq last next)
	  (setq ranges (cons (list (cons beg last) last-headers-only) ranges))
	  (setq beg next)
	  (setq last next)
	  (setq last-headers-only headers-only))
	(setq retrieve-list (cdr retrieve-list)))
      (setq ranges (cons (list (cons beg last) last-headers-only) ranges)))
    (nreverse ranges)))

(defun vm-imap-bunch-messages (seq-nums)
  "Given a sorted list of message sequence numbers, creates a
  list of bunched message sequences, each of the form 
  (begin-num . end-num)."
  (let ((seqs nil)
	beg last next) ;; diff
    (when seq-nums
      (setq beg (car seq-nums))
      (setq last beg)
      (setq seq-nums (cdr seq-nums))
      (while seq-nums
	(setq next (car seq-nums))
	(if (and (= (- next last) 1)
		 (< (- next beg) vm-imap-message-bunch-size))
	    (setq last next)
	  (setq seqs (cons (cons beg last) seqs))
	  (setq beg next)
	  (setq last next))
	(setq seq-nums (cdr seq-nums)))
      (setq seqs (cons (cons beg last) seqs)))
    (nreverse seqs)))


(defun vm-fetch-imap-message (m)
  "Insert the message body of M in the current buffer, which must be
either the folder buffer or the presentation buffer.  Returns a
boolean indicating success: t if the message was fully fetched and nil
otherwise.

 (This is a special case of vm-fetch-message, not to be confused with
  vm-imap-fetch-message.)"

  (let ((body-buffer (current-buffer))
	) ;; (statblob nil)
    (unwind-protect
	(save-excursion		  ; save-current-buffer?
	  ;;----------------------------------
	  (vm-buffer-type:enter 'folder)
	  ;;----------------------------------
	  (set-buffer (vm-buffer-of (vm-real-message-of m)))
	  (let* ((statblob nil)
		 (uid (vm-imap-uid-of m))
		 (imapdrop (vm-folder-imap-maildrop-spec))
		 (folder (or (vm-imap-folder-for-spec imapdrop)
			     (vm-safe-imapdrop-string imapdrop)))
		 (process (and (eq vm-imap-connection-mode 'online)
			       (vm-re-establish-folder-imap-session 
				imapdrop "fetch")))
		 (imap-buffer (and process (process-buffer process)))
		 (use-body-peek (vm-folder-imap-body-peek))
		 (server-uid-validity (vm-folder-imap-uid-validity))
		 (old-eob (point-max))
		 message-size
		 )

	    (when (null process)
	      (if (eq vm-imap-connection-mode 'offline)
		  (error "Working in offline mode")
		(setq vm-imap-connection-mode 'autoconnect)
		(error (concat "Could not connect to IMAP server; "
			       "Type g to reconnect"))))
	    (unless (equal (vm-imap-uid-validity-of m)
			   server-uid-validity)
	      (error "Message has an invalid UID"))
	    (setq imap-buffer (process-buffer process))
	    (unwind-protect
		(with-current-buffer imap-buffer
		  ;;----------------------------------
		  (vm-buffer-type:enter 'process)
		  (vm-imap-session-type:assert-active)
		  ;;----------------------------------
		  (condition-case error-data
		      (progn
			(setq message-size 
			      (vm-imap-get-uid-message-size process uid))
			(setq statblob (vm-imap-start-status-timer))
			(vm-set-imap-status-mailbox statblob folder)
			(vm-set-imap-status-maxmsg statblob 1)
			(vm-set-imap-status-currmsg statblob 1)
			(vm-set-imap-status-need statblob message-size)
			(vm-imap-fetch-uid-message 
			 process uid use-body-peek nil)
			(vm-imap-retrieve-to-target 
			 process body-buffer statblob use-body-peek)
			(vm-imap-read-ok-response process)
			t)
		    (vm-imap-normal-error ; handler
		     (vm-warn 0 2 "IMAP message unavailable: %s" 
			      (cadr error-data))
		     nil)
		    (vm-imap-protocol-error ; handler
		     (vm-warn 0 2 "IMAP message unavailable: %s"
			      (cadr error-data))
		     nil
		     ;; Continue with whatever messages have been read
		     )
		    (quit
		     (delete-region old-eob (point-max))
		     (error (format "Quit received during retrieval from %s"
				    folder)))))
		;; unwind-protections
		(when statblob
		  (vm-imap-stop-status-timer statblob))
		;;-----------------------------
		(vm-buffer-type:exit)
		(vm-imap-dump-uid-seq-num-data)
		;;-----------------------------
		)))
      ;;-------------------
      (vm-buffer-type:exit)
      ;;-------------------
      )))
	 

(defun vm-fetch-imap-message-size (m)
  "Given an IMAP message M, return its message size by looking up the
cached tables.  If there is no cached data, return nil.  USR, 2012-10-19"
  (with-current-buffer (vm-buffer-of m)
    (condition-case _error
	(let ((uid-sym (intern-soft (vm-imap-uid-of m)
				    (vm-folder-imap-flags-obarray))))
	  (car (symbol-value uid-sym)))
      (error nil))))

(cl-defun vm-imap-save-attributes (&optional &key
					   ;; (interactive nil)
					   (all-flags nil))
  "Save the attributes of changed messages to the IMAP folder.
ALL-FLAGS, if true says that the attributes of all messages should
be saved to the IMAP folder, not only those of changed messages."
  ;;--------------------------
  (vm-buffer-type:set 'folder)
  ;;--------------------------
  (let* ((process (vm-folder-imap-process))
	 ;; (uid-validity (vm-folder-imap-uid-validity))
	 (mp vm-message-list)
	 (errors 0))
      ;;  (perm-flags (vm-folder-imap-permanent-flags))
      (vm-inform 6 "%s: Updating attributes on the IMAP server... "
		 (buffer-name))
      ;;-----------------------------------------
      (vm-imap-folder-session-type:assert 'valid)
      ;;-----------------------------------------
      (while mp
	(if (or all-flags (vm-attribute-modflag-of (car mp)))
	    (condition-case nil
		(vm-imap-save-message-flags process (car mp))
	      (vm-imap-protocol-error 	; handler
	       (setq errors (1+ errors))
	       (vm-buffer-type:set 'folder))))
	(setq mp (cdr mp)))
      (if (> errors 0)
	  (vm-inform 3 "%s: Updating attributes on the IMAP server... %d errors" 
		     (buffer-name) errors)
	(vm-inform 6 "%s: Updating attributes on the IMAP server... done"
		   (buffer-name)))))


(defun vm-imap-synchronize (&optional full)
  "Synchronize the current folder with the IMAP mailbox.
Changes made to the buffer are uploaded to the server first before
downloading the server data.
Deleted messages are not expunged.

Prefix argument FULL says that all the attribute changes and
expunges made to the cache folder should be written to the server
even if those changes were not made in the current VM session.
This is useful for saving offline work on the cache folder."
  (interactive "P")
  (vm-select-folder-buffer-and-validate 0 (vm-interactive-p))
  ;;--------------------------
  (vm-buffer-type:set 'folder)
  ;;--------------------------
  (vm-display nil nil '(vm-imap-synchronize) '(vm-imap-synchronize))
  (if (not (eq vm-folder-access-method 'imap))
      (vm-inform 0 "%s: This is not an IMAP folder" (buffer-name))
    (when (vm-establish-new-folder-imap-session t "general operation" nil)
      (vm-imap-retrieve-uid-and-flags-data)
      (vm-imap-save-attributes :all-flags full)
      ;; (vm-imap-synchronize-folder :interactive t
      ;; 			:save-attributes (if full 'all t))
      (vm-imap-synchronize-folder :interactive t 
				  :do-remote-expunges (if full 'all t) 
				  :do-local-expunges t 
				  :do-retrieves t
				  :retrieve-attributes t)
      ;; stuff the attributes of messages that need it.
      ;; (vm-inform 7 "%s: Stuffing cached data..." (buffer-name) )
      ;; (vm-stuff-folder-data :interactive t :abort-if-input-pending nil)
      ;; (vm-inform 7 "%s: Stuffing cached data... done" (buffer-name))
      ;; stuff bookmark and header variable values
      (when vm-message-list
	;; get summary cache up-to-date
	(vm-inform 6 "Updating summary... ")
	(vm-update-summary-and-mode-line)
	(vm-inform 6 "Updating summary... done")
	;; 	  (vm-stuff-bookmark)
	;; 	  (vm-stuff-pop-retrieved)
	;; 	  (vm-stuff-imap-retrieved)
	;; 	  (vm-stuff-last-modified)
	;; 	  (vm-stuff-header-variables)
	;; 	  (vm-stuff-labels)
	;; 	  (vm-stuff-summary)
	;; 	  (and vm-message-order-changed
	;; 	       (vm-stuff-message-order))
	))))
  

;;;###autoload
(defun vm-imap-folder-check-mail (&optional interactive)
  "Check if there is new mail on the server for the current IMAP
folder.  The optional argument INTERACTIVE says if the function
is being invoked interactively."
  (vm-buffer-type:wait-for-imap-session)
  ;;--------------------------
  (vm-buffer-type:set 'folder)
  ;;--------------------------
  (vm-inform 10 
	      "%s: Checking for new mail... " (buffer-name))
  (cond (vm-global-block-new-mail
	 nil)
	((null (vm-establish-new-folder-imap-session 
		interactive "checkmail" t))
	 nil)
	(t
	 (let ((result nil))
	   (cond ((> (vm-folder-imap-recent-count) 0)
		  t)
		 ((null (vm-folder-imap-retrieved-count))
		  (setq result (car (vm-imap-get-synchronization-data))))
		 (t
		  (setq result (> (vm-folder-imap-mailbox-count) 
				  (vm-folder-imap-retrieved-count)))))
	   (vm-imap-end-session (vm-folder-imap-process))
	   (vm-inform 10 "%s: Checking for new mail... done"
		       (buffer-name))
	   result))))
(defalias 'vm-imap-folder-check-for-mail 'vm-imap-folder-check-mail)
(make-obsolete 'vm-imap-folder-check-for-mail
	       'vm-imap-folder-check-mail "8.2.0")



;; ---------------------------------------------------------------------------
;;; Utilities for maildrop specs  (this should be moved up top)
;;
;; A maildrop spec is of the form
;;      protocol:hostname:port:mailbox:auth:loginid:password 
;;             0        1    2       3    4       5        6
;; vm-imap-find-spec-for-buffer: (buffer) -> maildrop-spec
;; vm-imap-make-filename-for-spec: (maildrop-spec) -> string
;; vm-imap-normalize-spec: (maildrop-spec) -> maildrop-spec
;; vm-imap-account-name-for-spec: (maildrop-spec) -> string
;; vm-imap-spec-for-account: (string) -> maildrop-spec
;; vm-imap-parse-spec-to-list: (maildrop-spec) -> string list
;; vm-imap-spec-list-to-host-alist: 
;;	(maildrop-spec list) -> (string, maildrop-spec) alist
;; ---------------------------------------------------------------------------

;; ----------- missing functions-----------
;;;###autoload
(defun vm-imap-find-name-for-spec (_spec)
  "This is a stub for a function that has not been defined."
  (error "vm-imap-find-name-for-spec has not been defined.  Please report it."
	 ))
;;-----------------------------------------

;;;###autoload
(defun vm-imap-find-spec-for-buffer (buffer)
  "Find the IMAP maildrop spec for the folder BUFFER."
  (with-current-buffer buffer
    (vm-folder-imap-maildrop-spec)))
;;   (let ((list (mapcar 'car vm-imap-account-alist))
;; 	(done nil)
;; 	(spec-items nil))
;;     (while (and (not done) list)
;;       (setq spec-items (vm-imap-parse-spec-to-list (car list)))
;;       (setcar (nthcdr 3 spec-items) folder)
;;       (if (eq buffer (vm-get-file-buffer 
;; 		      (vm-imap-make-filename-for-spec
;; 		       (vm-imap-encode-list-to-spec spec-items))))
;; 	  (setq done t)
;; 	(setq list (cdr list))))
;;     (and list (car list)))

(defvar vm-imap-account-folder-cache nil
  "Caches the list of all folders on an IMAP account.")

(defun vm-imap-folder-completion-list (string predicate method)
  "Find completions for STRING as an IMAP folder name, satisfying
  PREDICATE.  The third argument METHOD is one of:

`nil' - try-completion, returns string if there are mult possibilities,
`t' - all-completions, returns a list of all completions,
`lambda' - test-completion, test if the string is an exact match for a
           possibility , and
a pair (boundaries. SUFFIX) - completion-boundaries.

See Info node `(elisp)Programmed Completion'."
  ;; selectable-only is used via dynamic binding

  (let ((account-list (mapcar (lambda (a) (list (concat (cadr a) ":")))
			      vm-imap-account-alist))
	completion-list folder account spec process mailbox-list)

    ;; handle SPC completion (remove last " " from string)
    (when (and (> (length string) 0)
	       (string= " " (substring string -1)))
      (setq string (substring string 0 -1)))

    ;; check if account-name is present
    (setq folder (try-completion (or string "") account-list predicate))
    (setq account (car (vm-parse (if (stringp folder) folder string)
				 "\\([^:]+\\):" 1)))
    
    ;; if yes, get folders of the account into completion-list
    (when account
      (setq mailbox-list (cdr (assoc account vm-imap-account-folder-cache)))
      (setq spec (vm-imap-spec-for-account account))
      (when (and (null mailbox-list) spec)
	(unwind-protect
	    (progn
	      (setq process (vm-imap-make-session spec t 
						  :purpose "folders"))
	      (when process
		(setq mailbox-list 
		      (vm-imap-mailbox-list process selectable-only))
		(when mailbox-list
		  (add-to-list 'vm-imap-account-folder-cache 
			       (cons account mailbox-list)))))
	  ;; unwind-protection
	  (when process (vm-imap-end-session process))))
      (setq completion-list 
	    (mapcar (lambda (m) (list (format "%s:%s" account m)))
		    mailbox-list))
      (setq folder (try-completion (or string "") completion-list predicate)))
    
    ;; process the requested method
    (setq folder (if (eq folder t)
		     string
		   (or folder string)))

    (cond ((null method)		; try-completion
	   folder)
	  ((eq method t)		; all-completions
	   (mapcar 'car
		   (vm-delete (lambda (c)
				(string-prefix-p folder (car c)))
			      (or completion-list account-list) t))
	   )
	  ((eq method 'lambda)		; test-completion
	   (try-completion folder completion-list predicate)))))

;;;###autoload
(defun vm-read-imap-folder-name (prompt &optional selectable--only
					_newone default) 
  "Read an IMAP folder name in the format account:mailbox, return an
IMAP mailbox spec." 
  (let* ((selectable-only selectable--only)
	 folder-input spec list ;; completion-list process
	 default-account default-folder
	 (vm-imap-ok-to-ask t)
	 (account-list (mapcar 'cadr vm-imap-account-alist))
	 account-and-folder account folder) ;; mailbox-list
    (if (null account-list)
	(error "No known IMAP accounts.  Please set vm-imap-account-alist."))
    (if default 
	(setq list (vm-imap-parse-spec-to-list default)
	      default-account 
	      (cadr (assoc (vm-imapdrop-sans-password-and-mailbox default)
			   vm-imap-account-alist))
	      default-folder (nth 3 list))
      (setq default-account 
	    (or vm-last-visit-imap-account vm-imap-default-account)))
    (setq folder-input
	  (completing-read
	   ;; prompt
	   (format			
	    ;; "IMAP folder:%s " 
	    "%s%s" prompt
	    (if (and default-account default-folder)
		(format "(default %s:%s) " default-account default-folder)
	      ""))
	   ;; collection
	   'vm-imap-folder-completion-list 
	   ;; predicate, require-match
	   nil nil
	   ;; initial-input
	   (if default-account		
	       (format "%s:" default-account)
	     "")))
    (if (or (equal folder-input "")  
	    (equal folder-input (format "%s:" default-account)))
	(if (and default-account default-folder)
	    (setq folder-input (format "%s:%s" default-account default-folder))
	  (error 
	   "IMAP folder required in the format account-name:folder-name"))) 
    (setq account-and-folder (vm-parse folder-input "\\([^:]+\\):?" 1 2)
	  account (car account-and-folder)
	  folder (cadr account-and-folder)
	  spec (vm-imap-spec-for-account account))
    (if (null folder)
	(error 
	 "IMAP folder required in the format account-name:folder-name"))
    (if (null spec)
	(error "Unknown IMAP account %s" account))
    (setq list (vm-imap-parse-spec-to-list spec))
    (setcar (nthcdr 3 list) folder)
    (setq vm-last-visit-imap-account account)
    (vm-imap-encode-list-to-spec list)
    ))

(defun vm-imap-directory-separator (process ref)
  (let (;; (c-list nil)
	sep p r response need-ok)
    (vm-imap-check-connection process)
    (unwind-protect
	(with-current-buffer (process-buffer process)
	  ;;----------------------------------
	  (vm-buffer-type:enter 'process)
	  (vm-imap-session-type:assert-active)
	  ;;----------------------------------
	  (vm-imap-send-command 
	   process 
	   (format "LIST %s \"\"" (vm-imap-quote-mailbox-name ref)))
	  ;;--------------------------------
	  (vm-imap-dump-uid-seq-num-data)
	  ;;--------------------------------
	  (setq need-ok t)
	  (while need-ok
	    (setq response (vm-imap-read-response-and-verify process "LIST"))
	    (cond ((vm-imap-response-matches response 'VM 'OK)
		   (setq need-ok nil))
		  ((vm-imap-response-matches response '* 'LIST 'list 'string)
		   (setq r (nthcdr 3 response)
			 p (car r)
			 sep (buffer-substring (nth 1 p) (nth 2 p))))
		  ((vm-imap-response-matches response '* 'LIST 'list)
		   (vm-imap-protocol-error "unexpedcted LIST response"))))
	  sep )
      ;; unwind-protections
      ;;-------------------
      (vm-buffer-type:exit)
      ;;-------------------
      )))

(defun vm-imap-mailbox-list (process selectable--only)
  "Query the IMAP PROCESS to get a list of the mailboxes (folders)
available in the IMAP account.  SELECTABLE-ONLY flag asks only
selectable mailboxes to be listed.  Returns a list of mailbox names."
  (let ((selectable-only selectable--only)
	(c-list nil)
	p r response need-ok)
    (vm-imap-check-connection process)
    (unwind-protect
	(with-current-buffer (process-buffer process)
	  ;;----------------------------------
	  (vm-buffer-type:enter 'process)
	  (vm-imap-session-type:assert-active)
	  (vm-imap-dump-uid-seq-num-data)
	  ;;----------------------------------
	  (vm-imap-send-command process "LIST \"\" \"*\"")
	  (setq need-ok t)
	  (while need-ok
	    (setq response (vm-imap-read-response-and-verify process "LIST"))
	    (cond ((vm-imap-response-matches response 'VM 'OK)
		   (setq need-ok nil))
		  ((vm-imap-response-matches response '* 'LIST 'list)
		   (setq r (nthcdr 2 response)
			 p (car r))
		   (if (and selectable-only
			    (vm-imap-scan-list-for-flag p "\\Noselect"))
		       nil
		     (setq r (nthcdr 4 response)
			   p (car r))
		     (if (memq (car p) '(atom string))
			 (setq c-list 
			       (cons (vm-imap-decode-mailbox-name
				      (buffer-substring (nth 1 p) (nth 2 p)))
				     c-list)))))))
	  c-list )
      ;; unwind-protections
      ;;-------------------
      (vm-buffer-type:exit)
      ;;-------------------
      )))

;; This is unfinished
(defun vm-imap-mailbox-p (process mailbox selectable--only)
  "Query the IMAP PROCESS to check if MAILBOX exists as a folder.
SELECTABLE-ONLY flag asks whether the mailbox is selectable as
well. Returns a boolean value."
  (let ((selectable-only selectable--only)
	(c-list nil)
	p r response need-ok)
    (vm-imap-check-connection process)
    (unwind-protect
	(with-current-buffer (process-buffer process)
	  ;;----------------------------------
	  (vm-buffer-type:enter 'process)
	  (vm-imap-session-type:assert-active)
	  (vm-imap-dump-uid-seq-num-data)
	  ;;----------------------------------
	  (vm-imap-send-command 
	   process 
	   (format "LIST %s" (vm-imap-quote-mailbox-name mailbox)))
	  (setq need-ok t)
	  (while need-ok
	    (setq response (vm-imap-read-response-and-verify process "LIST"))
	    (cond ((vm-imap-response-matches response 'VM 'OK)
		   (setq need-ok nil))
		  ((vm-imap-response-matches response '* 'LIST 'list)
		   (setq r (nthcdr 2 response)
			 p (car r))
		   (if (and selectable-only
			    (vm-imap-scan-list-for-flag p "\\Noselect"))
		       nil
		     (setq r (nthcdr 4 response)
			   p (car r))
		     (if (memq (car p) '(atom string))
			 (setq c-list 
			       (cons (vm-imap-decode-mailbox-name
				      (buffer-substring (nth 1 p) (nth 2 p)))
				     c-list)))))))
	  c-list )
      ;; unwind-protections
      ;;-------------------
      (vm-buffer-type:exit)
      ;;-------------------
      )))

(defun vm-imap-read-boolean-response (process)
  "Read a boolean response from the IMAP server (OK, NO, BYE, BAD).
Returns a boolean value (t or nil).

May throw exceptions."
  (let ((need-ok t) retval response)
    (while need-ok
      (vm-imap-check-connection process)
      (setq response (vm-imap-read-response process))
      (cond ((vm-imap-response-matches response 'VM 'OK)
	     (setq need-ok nil retval t))
	    ((vm-imap-response-matches response 'VM 'NO)
	     (setq need-ok nil retval nil))
	    ((vm-imap-response-matches response '* 'BYE)
	     (vm-imap-normal-error "server disconnected"))
	    ((vm-imap-response-matches response 'VM 'BAD)
	     (vm-imap-normal-error 
	      "server says - %s" 
	      (vm-imap-read-error-message process (cadr (cadr response)))))))
    retval ))

(defun vm-imap-create-mailbox (process mailbox
			       &optional dont-create-parent-directories)
  "Create a MAILBOX using the IMAP PROCESS.  The optional argument
DONT-CREATE-PARENT-DIRECTORIES is defunct, but it should always be `t'."
  ;; IMAP protocol says that the parent directories will created
  ;; automatically. 
  ;; The defunct argument should be gotten rid of and the dead code
  ;; should be removed.  USR, 2012-06-10
  (if (not dont-create-parent-directories)
      (let (dir sep sep-regexp i)
	(setq sep (vm-imap-directory-separator process "")
	      sep-regexp (regexp-quote sep)
	      i 0)
	(while (string-match sep-regexp mailbox i)
	  (setq dir (substring mailbox i (match-end 0)))
	  (vm-imap-create-mailbox process dir t)
	  ;; ignore command result since creating a directory will
	  ;; routinely fail with "File exists".  We'll generate a
	  ;; real error if the final mailbox creation fails.
	  (vm-imap-read-boolean-response process)
	  (setq i (match-end 0)))))
  (vm-imap-send-command 
   process 
   (format "CREATE %s" (vm-imap-quote-mailbox-name mailbox)))
  (if (null (vm-imap-read-boolean-response process))
      (vm-imap-normal-error "creation of %s failed" mailbox)))

(defun vm-imap-delete-mailbox (process mailbox)
  (vm-imap-send-command 
   process 
   (format "DELETE %s" (vm-imap-quote-mailbox-name mailbox)))
  (if (null (vm-imap-read-boolean-response process))
      (vm-imap-normal-error "deletion of %s failed" mailbox)))

(defun vm-imap-rename-mailbox (process source dest)
  (vm-imap-send-command 
   process 
   (format "RENAME %s %s"
	   (vm-imap-quote-mailbox-name source)
	   (vm-imap-quote-mailbox-name dest)))
  (if (null (vm-imap-read-boolean-response process))
      (vm-imap-normal-error "renaming of %s to %s failed" source dest)))

;;;###autoload
(defun vm-create-imap-folder (folder)
  "Create a folder on an IMAP server.
First argument FOLDER is read from the minibuffer if called
interactively.  Non-interactive callers must provide an IMAP
maildrop specification for the folder as described in the
documentation for `vm-spool-files'."
  ;; Creates a self-contained IMAP session and destroys it at the end.
  (interactive
   (save-excursion
     ;;------------------------
     (vm-buffer-type:duplicate)
     ;;------------------------
     (vm-session-initialization)
     ;; (vm-check-for-killed-folder) 	; seems no need for this
     ;; (vm-select-folder-buffer-if-possible)
     (let ((this-command this-command)
	   (last-command last-command)
	   (folder (vm-read-imap-folder-name "Create IMAP folder: " nil t)))
       ;;-------------------
       (vm-buffer-type:exit)
       ;;-------------------
       (list folder))
     ))
  (let ((vm-imap-ok-to-ask t)
	(account (vm-imap-account-name-for-spec folder))
	process mailbox folder-display)
    (setq process (vm-imap-make-session folder t :purpose "create"))
    (if (null process)
	(error "Couldn't open IMAP session for %s"
	       (or (vm-imap-folder-for-spec folder)
		   (vm-safe-imapdrop-string folder))))
    (unwind-protect
	(with-current-buffer (process-buffer process)
	  ;;-----------------------------
	  (vm-buffer-type:enter 'process)
	  ;;-----------------------------
	  (setq mailbox (nth 3 (vm-imap-parse-spec-to-list folder)))
	  (setq folder-display (or (vm-imap-folder-for-spec folder)
				   (vm-safe-imapdrop-string folder)))
	  (vm-imap-create-mailbox process mailbox t)
	  (vm-inform 5 "Folder %s created" folder-display)
	  ;; invalidate the folder-cache
	  (setq vm-imap-account-folder-cache
		(vm-delete (lambda (a) (equal (car a) account))
			   vm-imap-account-folder-cache)))
      ;; unwind-protections
      (when (and (processp process)
		 (memq (process-status process) '(open run)))
	(vm-imap-end-session process))
      ;;-------------------
      (vm-buffer-type:exit)
      ;;-------------------
      )))
(defalias 'vm-imap-create-folder 'vm-create-imap-folder)

;;;###autoload
(defun vm-delete-imap-folder (folder)
  "Delete a folder on an IMAP server.
First argument FOLDER is read from the minibuffer if called
interactively.  Non-interactive callers must provide an IMAP
maildrop specification for the folder as described in the
documentation for `vm-spool-files'."
;; Creates a self-contained IMAP session and destroys it at the end.
  (interactive
   (save-excursion
     ;;------------------------
     (vm-buffer-type:duplicate)
     ;;------------------------
     (vm-session-initialization)
     ;; (vm-check-for-killed-folder)	; seems no need for this
     ;; (vm-select-folder-buffer-if-possible)
     (let ((this-command this-command)
	   (last-command last-command))
       (list (vm-read-imap-folder-name "Delete IMAP folder: " nil nil)))))
  (let ((vm-imap-ok-to-ask t)
	(account (vm-imap-account-name-for-spec folder))
	process mailbox folder-display)
    (setq process (vm-imap-make-session folder t :purpose "delete folder"))
    (if (null process)
	(error "Couldn't open IMAP session for %s"
	       (or (vm-imap-folder-for-spec folder)
		   (vm-safe-imapdrop-string folder))))
    (unwind-protect
	(save-current-buffer
	  ;;-----------------------------
	  (vm-buffer-type:enter 'process)
	  ;;-----------------------------
	  (set-buffer (process-buffer process))
	  (setq mailbox (nth 3 (vm-imap-parse-spec-to-list folder)))
	  (setq folder-display (or (vm-imap-folder-for-spec folder)
				   (vm-safe-imapdrop-string folder)))
	  (vm-imap-delete-mailbox process mailbox)
	  (vm-inform 5 "Folder %s deleted" folder-display)
	  ;; invalidate the folder-cache
	  (setq vm-imap-account-folder-cache
		(vm-delete (lambda (a) (equal (car a) account))
			   vm-imap-account-folder-cache)))
      ;; unwind-protections
      (when (and (processp process)
		 (memq (process-status process) '(open run)))
	(vm-imap-end-session process))
      ;;-------------------
      (vm-buffer-type:exit)
      ;;-------------------
      )))
(defalias 'vm-imap-delete-folder 'vm-delete-imap-folder)

;;;###autoload
(defun vm-rename-imap-folder (source dest)
  "Rename a folder on an IMAP server.
Argument SOURCE and DEST are read from the minibuffer if called
interactively.  Non-interactive callers must provide full IMAP
maildrop specifications for SOURCE and DEST as described in the
documentation for `vm-spool-files'."
;; Creates a self-contained IMAP session and destroys it at the end.
  (interactive
   (save-excursion
     ;;------------------------
     (vm-buffer-type:duplicate)
     ;;------------------------
     (vm-session-initialization)
     ;; (vm-check-for-killed-folder)	; seems no need for this
     ;; (vm-select-folder-buffer-if-possible)
     (let ((this-command this-command)
	   (last-command last-command)
	   source dest)
       (setq source (vm-read-imap-folder-name "Rename IMAP folder: " t nil))
       (setq dest (vm-read-imap-folder-name
		   (format "Rename %s to: " 
			   (or (vm-imap-folder-for-spec source)
			       (vm-safe-imapdrop-string source)))
		   nil t))
       (list source dest))))
  (let ((vm-imap-ok-to-ask t)
	(account (vm-imap-account-name-for-spec source))
	process mailbox-source mailbox-dest)
    (setq process (vm-imap-make-session source t :purpose "rename folder"))
    (if (null process)
	(error "Couldn't open IMAP session for %s"
	       (or (vm-imap-folder-for-spec source)
		   (vm-safe-imapdrop-string source))))
    (unwind-protect
	(save-current-buffer
	  ;;-----------------------------
	  (vm-buffer-type:enter 'process)
	  ;;-----------------------------
	  (set-buffer (process-buffer process))
	  (setq mailbox-source (nth 3 (vm-imap-parse-spec-to-list source)))
	  (setq mailbox-dest (nth 3 (vm-imap-parse-spec-to-list dest)))
	  (vm-imap-rename-mailbox process mailbox-source mailbox-dest)
	  (vm-inform 5 "Folder %s renamed to %s" 
		     (or (vm-imap-folder-for-spec source)
			 (vm-safe-imapdrop-string source))
		     (or (vm-imap-folder-for-spec dest)
			 (vm-safe-imapdrop-string dest)))
	  ;; invalidate the folder-cache
	  (setq vm-imap-account-folder-cache
		(vm-delete (lambda (a) (equal (car a) account))
			   vm-imap-account-folder-cache)))
      ;;-------------------
      (vm-buffer-type:exit)
      ;;-------------------
      (when (and (processp process)
		 (memq (process-status process) '(open run)))
	(vm-imap-end-session process))
      )))
(defalias 'vm-imap-rename-folder 'vm-rename-imap-folder)

;;;###autoload
(defun vm-list-imap-folders (account &optional filter-new)
  "List all folders on an IMAP account ACCOUNT, along with the
counts of messages in them.  The account must be one declared in
`vm-imap-account-alist'.

With a prefix argument, it lists only the folders with new messages in
them."
;; Creates a self-contained IMAP session and destroys it at the end.
  (interactive
   (save-excursion
     ;;------------------------
     (vm-buffer-type:duplicate)
     ;;------------------------
     (vm-session-initialization)
     (let ((this-command this-command)
	   (last-command last-command)
	   (completion-list (mapcar (function cadr) vm-imap-account-alist)))
       (list (completing-read 
	      ;; prompt
	      "IMAP account: " 
	      ;; collection
	      completion-list 
	      ;; predicate, require-match
	      nil t
	      ;; initial-input
	      (if vm-last-visit-imap-account		
		  (format "%s" vm-last-visit-imap-account)
		"")
	      )
	     current-prefix-arg))))
  (require 'ehelp)
  (setq vm-last-visit-imap-account account)
  (let ((vm-imap-ok-to-ask t)
	spec process mailbox-list mailbox-status-list buffer) ;; folder
    (setq spec (vm-imap-spec-for-account account))
    (setq process (and spec (vm-imap-make-session spec t :purpose "folders")))
					; new session required for STATUS
    (if (null process)
	(error "Couldn't open IMAP session for %s"
	       (or (vm-imap-folder-for-spec spec)
		   (vm-safe-imapdrop-string spec))))
    (unwind-protect
	(progn
	  (setq mailbox-list 
		(vm-imap-mailbox-list process nil))
	  (setq mailbox-status-list
		(mapcar
		 (lambda (mailbox)
		   (condition-case _err
		       (cons mailbox
			     (vm-imap-get-mailbox-status process mailbox))
		     (error (list mailbox 0 0))))
		 mailbox-list))
	  (when mailbox-list
	    (add-to-list 'vm-imap-account-folder-cache 
			 (cons account mailbox-list))))
      ;; unwind-protection
      (when process (vm-imap-end-session process)))

    (setq mailbox-status-list 
	  (sort mailbox-status-list 
		(lambda (mbstat1 mbstat2)
		  (string-lessp (car mbstat1) (car mbstat2)))))

    ;; Display the results
    (setq buffer (get-buffer-create (format "*%s folders*" account)))
    ;; (with-help-buffer (buffer-name buffer)
    ;;    (dolist (mailbox mailbox-list)
    ;; 	     (princ (format "%s\n" mailbox))))
    (with-electric-help
     (lambda ()
       (dolist (mbstat mailbox-status-list)
	 (if (or (null filter-new) (> (nth 2 mbstat) 0))
	     (princ (format "%s: %s messages, %s new \n" 
			    (car mbstat) (nth 1 mbstat) (nth 2 mbstat))))))
     buffer)
    ))

(defalias 'vm-imap-list-folders 'vm-list-imap-folders)

(defun vm-imap-get-mailbox-status (process mailbox)
  "Requests the status of IMAP MAILBOX from the server and returns the
message count and recent message count (a list of two numbers)."
  (let ((imap-buffer (process-buffer process))
	(need-ok t)
	response p tok msg-count recent-count)
    (with-current-buffer imap-buffer
      ;;-----------------------------
      (vm-buffer-type:enter 'process)
      ;;-----------------------------
      (vm-imap-send-command 
       process 
       (format "STATUS %s (MESSAGES RECENT)"
               (vm-imap-quote-mailbox-name mailbox)))
      (while need-ok
	(setq response (vm-imap-read-response-and-verify process "STATUS"))
	(cond ((vm-imap-response-matches response 'VM 'OK)
	       (setq need-ok nil))
	      ((or (vm-imap-response-matches response '* 'STATUS 'string 'list)
		   (vm-imap-response-matches response '* 'STATUS 'atom 'list))
	       (setq p (cdr (nth 3 response)))
	       (while p
		 (cond 
		  ((vm-imap-response-matches p 'MESSAGES 'atom)
		   (setq tok (nth 1 p))
		   (goto-char (nth 1 tok))
		   (setq msg-count (read imap-buffer))
		   (setq p (nthcdr 2 p)))
		  ((vm-imap-response-matches p 'RECENT 'atom)
		   (setq tok (nth 1 p))
		   (goto-char (nth 1 tok))
		   (setq recent-count (read imap-buffer))
		   (setq p (nthcdr 2 p)))
		  (t
		   (vm-imap-protocol-error
		    "expected MESSAGES and RECENT in STATUS response"))
		  )))
	      (t
	       (vm-imap-protocol-error
		"unexpected response to STATUS command"))
	      ))
      ;;-------------------
      (vm-buffer-type:exit)
      ;;-------------------
      )
    (list msg-count recent-count)))

;;; Robert Fenk's draft function for saving messages to IMAP folders.

;;;###autoload
(defun vm-imap-save-composition ()
  "Saves the current composition in the IMAP folder given by the
IMAP-FCC header. 
Add this to your `mail-send-hook' and start composing from an IMAP
folder.

May throw exceptions." 
  ;; FIXME This function should not be throwing exceptions.
  ;; Creates a self-contained IMAP session and destroys it at the end.
  (let ((mailbox (vm-mail-get-header-contents "IMAP-FCC:"))
	(mailboxes nil)
	(fcc-string (vm-mail-get-header-contents "FCC:" ","))
	fcc-list fcc maildrop spec-list 
	process flags string m ;; response
	(vm-imap-ok-to-ask t))
    (if (null mailbox)
	(setq mailboxes nil)
      ;; IMAP-FCC header present
      (when vm-mail-buffer		; has parent folder
	(with-current-buffer vm-mail-buffer
	  ;;----------------------------
	  (vm-buffer-type:enter 'folder)
	  ;;----------------------------
	  (setq m (car vm-message-pointer))
	  (when m 
	    (set-buffer (vm-buffer-of (vm-real-message-of m))))
	  (if (eq vm-folder-access-method 'imap)
	      (setq maildrop (vm-folder-imap-maildrop-spec)))
	  ;;-------------------
	  (vm-buffer-type:exit)
	  ;;-------------------
	  ))
      (when (and (null maildrop)  vm-imap-default-account)
	(setq maildrop(vm-imap-spec-for-account vm-imap-default-account))
	(when (null maildrop)
	  (error "Set `vm-imap-default-account' to use IMAP-FCC")))
      (setq process (vm-imap-make-session maildrop t :purpose "IMAP-FCC"))
      (if (null process)
	  (error "Could not connect to the IMAP server for IMAP-FCC"))
      (setq mailboxes (list (cons mailbox process)))
      (vm-mail-mode-remove-header "IMAP-FCC:"))

    (when fcc-string
      (setq fcc-list (vm-parse fcc-string "\\([^,]+\\),?"))
      (while fcc-list
	(setq fcc (car fcc-list))
	(setq spec-list (vm-parse fcc "\\([^:]+\\):?"))
	(when (member (car spec-list) '("imap" "imap-ssl" "imap-ssh"))
	  (setq process (vm-imap-make-session fcc nil :purpose "IMAP-FCC"))
	  (if (null process)
	      (error "Could not connect to the IMAP server for IMAP-FCC"))
	  (setq mailboxes (cons (cons (nth 3 spec-list) process) 
				mailboxes)))
	(setq fcc-list (cdr fcc-list))))
    
    (goto-char (point-min))
    (re-search-forward (concat "^" (regexp-quote mail-header-separator) "$"))
    (setq string (concat (buffer-substring (point-min) (match-beginning 0))
			 (buffer-substring
			  (match-end 0) (point-max))))
    (setq string (vm-imap-subst-CRLF-for-LF string))
    
    (while mailboxes
      (setq mailbox (car (car mailboxes)))
      (setq process (cdr (car mailboxes)))
      (unwind-protect
	  (save-excursion	       ; = save-current-buffer?
	    ;;-----------------------------
	    (vm-buffer-type:enter 'process)
	    ;;-----------------------------
	    ;; this can go awry if the process has died...
	    (unless process
	      (error "No connection to IMAP server for IMAP-FCC"))
	    (set-buffer (process-buffer process))
	    (condition-case nil
		(vm-imap-create-mailbox process mailbox t)
	      (vm-imap-protocol-error 	; handler
	       (vm-buffer-type:set 'process))) ; ignore errors
	    ;;----------------------------------
	    ;; (vm-imap-session-type:assert-active)
	    ;;----------------------------------

	    (vm-inform 7 "Saving outgoing message to IMAP server...")
	    (vm-imap-send-command 
	     process
	     (format "APPEND %s %s {%d}"
		     (vm-imap-quote-mailbox-name mailbox)
		     (if flags flags "()")
		     (length string)))
	    ;; could these be done with vm-imap-read-boolean-response?
	    (let ((need-plus t) response)
	      (while need-plus
		(setq response (vm-imap-read-response process))
		(cond 
		 ((vm-imap-response-matches response 'VM 'NO)
		  (vm-imap-normal-error 
		   "server says - %s"
		   (vm-imap-read-error-message process (cadr (cadr response)))))
		 ((vm-imap-response-matches response 'VM 'BAD)
		  (vm-imap-normal-error
		   "server says - %s"
		   (vm-imap-read-error-message process (cadr (cadr response)))))
		 ((vm-imap-response-matches response '* 'BYE)
		  (vm-imap-normal-error "server disconnected"))
		 ((vm-imap-response-matches response '+)
		  (setq need-plus nil)))))

	    (vm-imap-send-command process string nil t)
	    (let ((need-ok t) response)
	      (while need-ok

		(setq response (vm-imap-read-response process))
		(cond
		 ((vm-imap-response-matches response 'VM 'NO)
		  ;; (vm-imap-protocol-error "server says NO to APPEND data")
		  (vm-imap-normal-error
		   "servers says - %s:"
		   (vm-imap-read-error-message process (cadr (cadr response)))))
		 ((vm-imap-response-matches response 'VM 'BAD)
		  ;; (vm-imap-protocol-error "server says BAD to APPEND data")
		  (vm-imap-normal-error
		   "server says - %s"
		   (vm-imap-read-error-message process (cadr (cadr response)))))
		 ((vm-imap-response-matches response '* 'BYE)
		  (vm-imap-normal-error "server disconnected"))
		 ((vm-imap-response-matches response 'VM 'OK)
		  (setq need-ok nil)))))
	    (vm-inform 7 "Saving outgoing message to IMAP server... done")
	    )
	;; unwind-protections
	(when (and (processp process)
		   (memq (process-status process) '(open run)))
	  (vm-imap-end-session process))
	;;-------------------
	(vm-buffer-type:exit)
	;;-------------------
	)
      (setq mailboxes (cdr mailboxes)))
    ))

;;;###autoload
(defun vm-imap-start-bug-report ()
  "Begin to compose a bug report for IMAP support functionality."
  (interactive)
  (vm-follow-summary-cursor)
  (vm-select-folder-buffer-and-validate 0 (vm-interactive-p))
  (setq vm-kept-imap-buffers nil)
  (setq vm-imap-keep-trace-buffer 20))

;;;###autoload
(defun vm-imap-submit-bug-report ()
  "Submit a bug report for VM's IMAP support functionality.  
It is necessary to run `vm-imap-start-bug-report' before the problem
occurrence and this command after the problem occurrence, in
order to capture the trace of IMAP sessions during the occurrence."
  (interactive)
  (vm-follow-summary-cursor)
  (vm-select-folder-buffer-and-validate 0 (vm-interactive-p))
  (if (or vm-imap-keep-trace-buffer
	  (y-or-n-p "Did you run vm-imap-start-bug-report earlier? "))
      (vm-inform 5 "Thank you. Preparing the bug report... ")
    (vm-inform 1 (concat "Consider running vm-imap-start-bug-report "
			 "before the problem occurrence")))
  (let ((process (if (eq vm-folder-access-method 'imap)
		     (vm-folder-imap-process))))
    (if process
	(vm-imap-end-session process)))
  (let ((trace-buffer-hook
	 (lambda ()
	   (let ((bufs vm-kept-imap-buffers) 
		 buf)
	     (insert "\n\n")
	     (insert "IMAP Trace buffers - most recent first\n\n")
	     (while bufs
	       (setq buf (car bufs))
	       (insert "----") 
	       (insert (format "%s" buf))
	       (insert "----------\n")
	       (insert (with-current-buffer buf
			 (buffer-string)))
	       (setq bufs (cdr bufs)))
	     (insert "--------------------------------------------------\n"))
	   )))
    (vm-submit-bug-report nil (list trace-buffer-hook))
  ))


;;;###autoload
(defun vm-imap-set-default-attributes (m)
  (vm-set-headers-to-be-retrieved-of m nil)
  (vm-set-body-to-be-retrieved-of m nil)
  (vm-set-body-to-be-discarded-of m nil))

(defun vm-imap-unset-body-retrieve ()
  "Unset the body-to-be-retrieved flag of all the messages.  May
  be needed if the folder has become corrupted somehow."
  (interactive)
  (save-current-buffer
   (vm-select-folder-buffer-and-validate 0 (vm-interactive-p))
   (let ((mp vm-message-list))
     (while mp
       (vm-set-body-to-be-retrieved-of (car mp) nil)
       (vm-set-body-to-be-discarded-of (car mp) nil)
       (setq mp (cdr mp))))
   (vm-inform 5 "Marked %s messages as having retrieved bodies" 
	    (length vm-message-list))
   ))

(defun vm-imap-unset-byte-counts ()
  "Unset the byte counts of all the messages, so that the size of the
downloaded bodies will be displayed."
  (interactive)
  (save-current-buffer
   (vm-select-folder-buffer-and-validate 0 (vm-interactive-p))
   (let ((mp vm-message-list))
     (while mp
       (vm-set-byte-count-of (car mp) nil)
       (setq mp (cdr mp))))
   (vm-inform 5 "Unset the byte counts of %s messages" 
	    (length vm-message-list))
   ))


(provide 'vm-imap)
;;; vm-imap.el ends here
