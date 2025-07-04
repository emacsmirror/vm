;;; vm-pop.el --- Simple POP (RFC 1939) client for VM  -*- lexical-binding: t; -*-
;;
;; This file is part of VM
;;
;; Copyright (C) 1993, 1994, 1997, 1998 Kyle E. Jones
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
(require 'vm-misc)
(require 'vm-summary)
(require 'vm-window)
(require 'vm-motion)
(require 'vm-undo)
(require 'vm-crypto)
(require 'vm-mime)
(eval-when-compile (require 'cl-lib))

(declare-function vm-submit-bug-report 
		  "vm.el" (&optional pre-hooks post-hooks))
(declare-function open-network-stream 
		  "subr.el" (name buffer host service &rest parameters))

(if (fboundp 'define-error)
    (progn
      (define-error 'vm-cant-uidl "Can't use UIDL")
      (define-error 'vm-dele-failed "DELE command failed")
      (define-error 'vm-uidl-failed "UIDL command failed"))
  (put 'vm-cant-uidl 'error-conditions '(vm-cant-uidl error))
  (put 'vm-cant-uidl 'error-message "Can't use UIDL")
  (put 'vm-dele-failed 'error-conditions '(vm-dele-failed error))
  (put 'vm-dele-failed 'error-message "DELE command failed")
  (put 'vm-uidl-failed 'error-conditions '(vm-uidl-failed error))
  (put 'vm-uidl-failed 'error-message "UIDL command failed"))

(defun vm-pop-find-cache-file-for-spec (remote-spec)
  "Given REMOTE-SPEC, which is a maildrop specification of a folder on
a POP server, find its cache file on the file system"
  ;; Prior to VM 7.11, we computed the cache filename
  ;; based on the full POP spec including the password
  ;; if it was in the spec.  This meant that every
  ;; time the user changed his password, we'd start
  ;; visiting the wrong (and probably nonexistent)
  ;; cache file.
  ;;
  ;; To fix this we do two things.  First, migrate the
  ;; user's caches to the filenames based in the POP
  ;; sepc without the password.  Second, we visit the
  ;; old password based filename if it still exists
  ;; after trying to migrate it.
  ;;
  ;; For VM 7.16 we apply the same logic to the access
  ;; methods, pop, pop-ssh and pop-ssl and to
  ;; authentication method and service port, which can
  ;; also change and lead us to visit a nonexistent
  ;; cache file.  The assumption is that these
  ;; properties of the connection can change and we'll
  ;; still be accessing the same mailbox on the
  ;; server.

  (let ((f-pass (vm-pop-make-filename-for-spec remote-spec))
	(f-nopass (vm-pop-make-filename-for-spec remote-spec t))
	(f-nospec (vm-pop-make-filename-for-spec remote-spec t t)))
    (cond ((or (string= f-pass f-nospec)
	       (file-exists-p f-nospec))
	   nil )
	  ((file-exists-p f-pass)
	   ;; try to migrate
	   (condition-case nil
	       (rename-file f-pass f-nospec)
	     (error nil)))
	  ((file-exists-p f-nopass)
	   ;; try to migrate
	   (condition-case nil
	       (rename-file f-nopass f-nospec)
	     (error nil))))
    ;; choose the one that exists, password version,
    ;; nopass version and finally nopass+nospec
    ;; version.
    (cond ((file-exists-p f-pass)
	   f-pass)
	  ((file-exists-p f-nopass)
	   f-nopass)
	  (t
	   f-nospec))))


;; Our goal is to drag the mail from the POP maildrop to the crash box.
;; just as if we were using movemail on a spool file.
;; We remember which messages we have retrieved so that we can
;; leave the message in the mailbox, and yet not retrieve the
;; same messages again and again.

;;;###autoload
(defun vm-pop-move-mail (source destination)
  (let ((process nil)
	(m-per-session vm-pop-messages-per-session)
	(b-per-session vm-pop-bytes-per-session)
	(handler (find-file-name-handler source 'vm-pop-move-mail))
	(popdrop (or (vm-pop-find-name-for-spec source)
		     (vm-safe-popdrop-string source)))
	(statblob nil)
	(can-uidl t)
	(msgid (list nil (vm-popdrop-sans-password source) 'uidl))
	(pop-retrieved-messages vm-pop-retrieved-messages)
	auto-expunge x
	mailbox-count message-size response;; mailbox-size
	n (retrieved 0) retrieved-bytes process-buffer uidl)
    (setq auto-expunge 
	  (cond ((setq x (assoc source vm-pop-auto-expunge-alist))
		 (cdr x))
		((setq x (assoc (vm-popdrop-sans-password source)
				vm-pop-auto-expunge-alist))
		 (cdr x))
		(vm-pop-expunge-after-retrieving
		 t)
		((member source vm-pop-auto-expunge-warned)
		 nil)
		(t
		 (vm-warn 1 1
			  "Warning: POP folder is not set to auto-expunge")
		 (setq vm-pop-auto-expunge-warned
		       (cons source vm-pop-auto-expunge-warned))
		 nil)))
    (unwind-protect
	(catch 'done
	  (if handler
	      (throw 'done
		     (funcall handler 'vm-pop-move-mail source destination)))
	  (setq process (vm-pop-make-session source vm-pop-ok-to-ask))
	  (or process (throw 'done nil))
	  (setq process-buffer (process-buffer process))
	  (with-current-buffer process-buffer
	    ;; find out how many messages are in the box.
	    (vm-pop-send-command process "STAT")
	    (setq response (vm-pop-read-stat-response process)
		  mailbox-count (nth 0 response)
		  ;; mailbox-size (nth 1 response)
		  )
	    ;; forget it if the command fails
	    ;; or if there are no messages present.
	    (if (or (null mailbox-count)
		    (< mailbox-count 1))
		(throw 'done nil))
	    ;; loop through the maildrop retrieving and deleting
	    ;; messages as we go.
	    (setq n 1 retrieved-bytes 0)
	    (setq statblob (vm-pop-start-status-timer))
	    (vm-set-pop-stat-x-box statblob popdrop)
	    (vm-set-pop-stat-x-maxmsg statblob mailbox-count)
	    (while (and (<= n mailbox-count)
			(or (not (natnump m-per-session))
			    (< retrieved m-per-session))
			(or (not (natnump b-per-session))
			    (< retrieved-bytes b-per-session)))
	      (catch 'skip
		(vm-set-pop-stat-x-currmsg statblob n)
		(if can-uidl
		    (condition-case nil
			(let (list)
			  (vm-pop-send-command process (format "UIDL %d" n))
			  (setq response (vm-pop-read-response process t))
			  (if (null response)
			      (signal 'vm-cant-uidl nil))
			  (setq list (vm-parse response "\\([\041-\176]+\\) *")
				uidl (nth 2 list))
			  (if (null uidl)
			      (signal 'vm-cant-uidl nil))
			  (setcar msgid uidl)
			  (when (member msgid pop-retrieved-messages)
			    (if vm-pop-ok-to-ask
				(vm-inform
				 6
				 "Skipping message %d (of %d) from %s (retrieved already)..."
				 n mailbox-count popdrop))
			    (throw 'skip t)))
		      (vm-cant-uidl
		       ;; something failed, so UIDL must not be working.
		       (if (and (not auto-expunge)
				(or (not vm-pop-ok-to-ask)
				    (not (vm-pop-ask-about-no-uidl popdrop))))
			   (progn
			     (vm-inform 0 "Skipping mailbox %s (no UIDL support)"
				      popdrop)
			     (throw 'done (not (equal retrieved 0))))
			 ;; user doesn't care, so go ahead and
			 ;; expunge from the server
			 (setq can-uidl nil
			       msgid nil)))))
		(vm-pop-send-command process (format "LIST %d" n))
		(setq message-size (vm-pop-read-list-response process))
		(vm-set-pop-stat-x-need statblob message-size)
		(if (and (integerp vm-pop-max-message-size)
			 (> message-size vm-pop-max-message-size)
			 (progn
			   (setq response
				 (if vm-pop-ok-to-ask
				     (vm-pop-ask-about-large-message
				      process popdrop message-size n)
				   'skip))
			   (not (eq response 'retrieve))))
		    (progn
		      (if (eq response 'delete)
			  (progn
			    (vm-inform 6 "Deleting message %d..." n)
			    (vm-pop-send-command process (format "DELE %d" n))
			    (and (null (vm-pop-read-response process))
				 (throw 'done (not (equal retrieved 0)))))
			(if vm-pop-ok-to-ask
			    (vm-inform 6 "Skipping message %d..." n)
			  (vm-inform
			   5
			   "Skipping message %d in %s, too large (%d > %d)..."
			   n popdrop message-size vm-pop-max-message-size)))
		      (throw 'skip t)))
		(vm-inform 6 "Retrieving message %d (of %d) from %s..."
			 n mailbox-count popdrop)
		(vm-pop-send-command process (format "RETR %d" n))
		(and (null (vm-pop-read-response process))
		     (throw 'done (not (equal retrieved 0))))
		(and (null (vm-pop-retrieve-to-target process destination
						      statblob))
		     (throw 'done (not (equal retrieved 0))))
		(vm-inform 6 "Retrieving message %d (of %d) from %s...done"
	 	 n mailbox-count popdrop)
		(vm-increment retrieved)
		(and b-per-session
		     (setq retrieved-bytes (+ retrieved-bytes message-size)))
		(if (and (not auto-expunge) msgid)
		    (setq pop-retrieved-messages
			  (cons (copy-sequence msgid)
				pop-retrieved-messages))
		  ;; Either the user doesn't want the messages
		  ;; kept in the mailbox or there's no UIDL
		  ;; support so there's no way to remember what
		  ;; messages we've retrieved.  Delete the
		  ;; message now.
		  (vm-pop-send-command process (format "DELE %d" n))
		  ;; DELE can't fail but Emacs or this code might
		  ;; blow a gasket and spew filth down the
		  ;; connection, so...
		  (and (null (vm-pop-read-response process))
		       (throw 'done (not (equal retrieved 0))))))
	      (vm-increment n))
	     (not (equal retrieved 0)) ))
      (setq vm-pop-retrieved-messages pop-retrieved-messages)
      (if (and (eq vm-flush-interval t) (not (equal retrieved 0)))
	  (vm-stuff-pop-retrieved))
      (and statblob (vm-pop-stop-status-timer statblob))
      (if process
	  (vm-pop-end-session process)))))

(defun vm-pop-check-mail (source)
  (let ((process nil)
	(handler (find-file-name-handler source 'vm-pop-check-mail))
	(retrieved vm-pop-retrieved-messages)
	(popdrop (vm-popdrop-sans-password source))
	(count 0)
	x response)
    (unwind-protect
	(save-excursion
	  (catch 'done
	    (if handler
		(throw 'done
		       (funcall handler 'vm-pop-check-mail source)))
	    (setq process (vm-pop-make-session source nil))
	    (or process (throw 'done nil))
	    (set-buffer (process-buffer process))
	    (vm-pop-send-command process "UIDL")
	    (setq response (vm-pop-read-uidl-long-response process))
	    (if (null response)
		;; server doesn't understand UIDL
		nil
	      (if (null (car response))
		  ;; (nil . nil) is returned if there are no
		  ;; messages in the mailbox.
		  (progn
		    (vm-store-folder-totals source '(0 0 0 0))
		    (throw 'done nil))
		(while response
		  (if (not (and (setq x (assoc (cdr (car response)) retrieved))
				(equal (nth 1 x) popdrop)
				(eq (nth 2 x) 'uidl)))
		      (vm-increment count))
		  (setq response (cdr response))))
	      (vm-store-folder-totals source (list count 0 0 0))
	      (throw 'done (not (eq count 0))))
	    (vm-pop-send-command process "STAT")
	    (setq response (vm-pop-read-stat-response process))
	    (if (null response)
		nil
	      (vm-store-folder-totals source (list (car response) 0 0 0))
	      (not (equal 0 (car response))))))
      (and process (vm-pop-end-session process nil vm-pop-ok-to-ask)))))

;;;###autoload
(defun vm-expunge-pop-messages ()
  "Deletes all messages from POP mailbox that have already been retrieved
into the current folder.  VM sends POP DELE commands to all the
relevant POP servers to remove the messages."
  (interactive)
  (vm-follow-summary-cursor)
  (vm-select-folder-buffer-and-validate 0 (vm-interactive-p))
  (vm-error-if-virtual-folder)
  (if (and (vm-interactive-p) (eq vm-folder-access-method 'pop))
      (error "This command is not meant for POP folders.  Use the normal folder expunge instead."))
  (let ((process nil)
	(source nil)
	(trouble nil)
	(delete-count 0)
	(vm-global-block-new-mail t)
	(vm-pop-ok-to-ask t)
	popdrop uidl-alist data mp match)
    (unwind-protect
	(save-excursion
	  (setq vm-pop-retrieved-messages
		(delq nil vm-pop-retrieved-messages))
	  (setq vm-pop-retrieved-messages
		(sort vm-pop-retrieved-messages
		      (function (lambda (a b)
				  (cond ((string-lessp (nth 1 a) (nth 1 b)) t)
					((string-lessp (nth 1 b)
						       (nth 1 a))
					 nil)
					((string-lessp (car a) (car b)) t)
					(t nil))))))
	  (setq mp vm-pop-retrieved-messages)
	  (while mp
	    (condition-case nil
		(catch 'replay
		  (setq data (car mp))
		  (if (not (equal source (nth 1 data)))
		      (progn
			(if process
			    (progn
			     (vm-pop-end-session process)
			     (setq process nil)))
			(setq source (nth 1 data))
			(setq popdrop (or (vm-pop-find-name-for-spec source)
					  (vm-safe-popdrop-string source)))
			(condition-case nil
			    (progn
			      (vm-inform 6 
					 "Opening POP session to %s..." popdrop)
			      (setq process (vm-pop-make-session 
					     source vm-pop-ok-to-ask))
			      (if (null process)
				  (signal 'error nil))
			      (vm-inform 6 
					 "Expunging messages in %s..." popdrop))
			  (error
			   (vm-warn 0 2
				    "Couldn't open POP session to %s, skipping..."
				    popdrop)
			   (setq trouble (cons popdrop trouble))
			   (while (equal (nth 1 (car mp)) source)
			     (setq mp (cdr mp)))
			   (throw 'replay t)))
			(set-buffer (process-buffer process))
			(vm-pop-send-command process "UIDL")
			(setq uidl-alist
			      (vm-pop-read-uidl-long-response process))
			(if (null uidl-alist)
			    (signal 'vm-uidl-failed nil))))
		  (if (setq match (rassoc (car data) uidl-alist))
		      (progn
			(vm-pop-send-command process
					     (format "DELE %s" (car match)))
			(if (null (vm-pop-read-response process))
			    (signal 'vm-dele-failed nil))
			(setcar mp nil)	; side effect!!
			(vm-increment delete-count)))
		  (setq mp (cdr mp)))
	      (vm-dele-failed
	       (vm-warn 
		0 2 "DELE %s failed on %s, skipping rest of mailbox..."
		(car match) popdrop)
	       (setq trouble (cons popdrop trouble))
	       (while (equal (nth 1 (car mp)) source)
		 (setq mp (cdr mp)))
	       (throw 'replay t))
	      (vm-uidl-failed
	       (vm-warn 
		0 2 "UIDL %s failed on %s, skipping this mailbox..."
		(car match) popdrop)
	       (setq trouble (cons popdrop trouble))
	       (while (equal (nth 1 (car mp)) source)
		 (setq mp (cdr mp)))
	       (throw 'replay t))))
	  (if trouble
	      (progn
		(set-buffer (get-buffer-create "*POP Expunge Trouble*"))
		(setq buffer-read-only nil)
		(erase-buffer)
		(insert (format "%s POP message%s expunged.\n\n"
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
	    (vm-inform 5 "%s POP message%s expunged."
		     (if (zerop delete-count) "No" delete-count)
		     (if (= delete-count 1) "" "s"))))
      (and process (vm-pop-end-session process)))
    (setq vm-pop-retrieved-messages
	  (delq nil vm-pop-retrieved-messages))))

(defun vm-pop-make-session (source interactive &optional retry)
  "Create a new POP session for the POP mail box SOURCE.
The argument INTERACTIVE says the operation has been invoked
interactively.  The possible values are t, `password-only', and nil.
Optional argument RETRY says whether this call is for a
retry.

Returns the process or nil if the session could not be created." 
  (let ((shutdown nil)		   ; whether process is to be shutdown
	(folder-type vm-folder-type)
	process success
	(popdrop (or (vm-pop-find-name-for-spec source)
		     (vm-safe-popdrop-string source)))
	(coding-system-for-read (vm-binary-coding-system))
	(coding-system-for-write (vm-binary-coding-system))
	(use-ssl nil)
	(use-ssh nil)
	(session-name "POP")
	(process-connection-type nil)
	greeting timestamp ;; ssh-process
	protocol host port auth user pass ;; authinfo
	source-list pop-buffer source-nopwd)
    ;; parse the maildrop
    (setq source-list (vm-pop-parse-spec-to-list source)
	  protocol (car source-list)
	  host (nth 1 source-list)
	  port (nth 2 source-list)
	  auth (nth 3 source-list)
	  user (nth 4 source-list)
	  pass (nth 5 source-list)
	  source-nopwd (vm-popdrop-sans-password source))
    (when (= 6 (length source-list))
      (cond
       ((equal protocol "pop-ssl")
	(setq use-ssl t
	      session-name "POP over SSL")
	;; (when (null vm-stunnel-program)
	;; 	(error 
	;; 	 "vm-stunnel-program must be non-nil to use POP over SSL."))
	)
       ((equal protocol "pop-ssh")
	(setq use-ssh t
	      session-name "POP over SSH")
	(when (null vm-ssh-program)
	  (error "vm-ssh-program must be non-nil to use POP over SSH."))))
      ;; remove pop or pop-ssl from beginning of list if
      ;; present.
      (setq source-list (cdr source-list)))

    ;; carp if parts are missing
    (when (null host)
      (error "No host in POP maildrop specification, \"%s\"" source))
    (when (null port)
      (error "No port in POP maildrop specification, \"%s\"" source))
    (when (string-match "^[0-9]+$" port)
      (setq port (string-to-number port)))
    (when (null auth)
      (error
       "No authentication method in POP maildrop specification, \"%s\""
       source))
    (when (null user)
      (error "No user in POP maildrop specification, \"%s\"" source))
    (when (null pass)
      (error "No password in POP maildrop specification, \"%s\"" source))
    (when (equal pass "*")
      (setq pass (vm-pop-get-password 
		  popdrop source-nopwd user host port interactive)))
    ;; get the trace buffer
    (setq pop-buffer
	  (vm-make-work-buffer 
	   (vm-make-trace-buffer-name session-name host)))
    (unwind-protect
	(catch 'end-of-session
	  (with-current-buffer pop-buffer
	    (setq vm-folder-type (or folder-type vm-default-folder-type))
	    (buffer-disable-undo pop-buffer)
	    (make-local-variable 'vm-pop-read-point)
	    ;; clear the trace buffer of old output
	    (erase-buffer)
	    ;; Tell MULE not to mess with the text.
	    (when (fboundp 'set-buffer-file-coding-system)
	      (set-buffer-file-coding-system (vm-binary-coding-system) t))
	    (insert "starting " session-name
		    " session " (current-time-string) "\n")
	    (insert (format "connecting to %s:%s\n" host port))
	    ;; open the connection to the server
	    (condition-case err
		(with-timeout 
		    ((or vm-pop-server-timeout 1000)
		     (error (format "Timed out opening connection to %s"
				    host)))
		  (cond (use-ssl
			 (if (null vm-stunnel-program)
			     (setq process 
				   (open-network-stream session-name
							pop-buffer
							host port
							:type 'tls))
			   (vm-setup-stunnel-random-data-if-needed)
			   (setq process
				 (apply 'start-process session-name pop-buffer
					vm-stunnel-program
					(nconc (vm-stunnel-configuration-args host
									      port)
					       vm-stunnel-program-switches)))))
			(use-ssh
			 (setq process (open-network-stream
					session-name pop-buffer
					"127.0.0.1"
					(vm-setup-ssh-tunnel host port))))
			(t
			 (setq process (open-network-stream session-name
							    pop-buffer
							    host port)))))
	      (error	
	       (vm-warn 0 1 "%s" (error-message-string err))
	       (setq shutdown t)
	       (throw 'end-of-session nil)))
	    (and (null process) (throw 'end-of-session nil))
	    (setq shutdown t)
	    (setq vm-pop-read-point (point))
	    (vm-process-kill-without-query process)
	    (when (null (setq greeting (vm-pop-read-response process t)))
	      (delete-process process)
	      (throw 'end-of-session nil))
	    ;; authentication
	    (cond ((equal auth "pass")
		   (vm-pop-send-command process (format "USER %s" user))
		   (and (null (vm-pop-read-response process))
			(throw 'end-of-session nil))
		   (vm-pop-send-command process (format "PASS %s" pass))
		   (unless (vm-pop-read-response process)

		     (vm-warn 0 0 "POP login failed for %s" popdrop)
		     (vm-pop-forget-password source-nopwd host port)
		     ;; don't sleep unless we're running synchronously.
		     (when vm-pop-ok-to-ask
		       (sleep-for 2))
		     (throw 'end-of-session nil))
		   (unless (assoc source-nopwd vm-pop-passwords)
		     (setq vm-pop-passwords (cons (list source-nopwd pass)
						  vm-pop-passwords)))
		   (setq success t))
		  ((equal auth "rpop")
		   (vm-pop-send-command process (format "USER %s" user))
		   (when (null (vm-pop-read-response process))
		     (throw 'end-of-session nil))
		   (vm-pop-send-command process (format "RPOP %s" pass))
		   (when (null (vm-pop-read-response process))
		     (throw 'end-of-session nil)))
		  ((equal auth "apop")
		   (setq timestamp (vm-parse greeting "[^<]+\\(<[^>]+>\\)")
			 timestamp (car timestamp))
		   (when (null timestamp)
		     (goto-char (point-max))
		     (insert-before-markers "<<< ooops, no timestamp found in greeting! >>>\n")
		     (vm-warn 0 0 "Server of %s does not support APOP" popdrop)
		     ;; don't sleep unless we're running synchronously
		     (if vm-pop-ok-to-ask
			 (sleep-for 2))
		     (throw 'end-of-session nil))
		   (vm-pop-send-command
		    process
		    (format "APOP %s %s"
			    user
			    (vm-pop-md5 (concat timestamp pass))))
		   (unless (vm-pop-read-response process)
		     (vm-warn 0 0 "POP login failed for %s" popdrop)
		     (when vm-pop-ok-to-ask
		       (sleep-for 2))
		     (throw 'end-of-session nil))
		   (unless (assoc source-nopwd vm-pop-passwords)
		     (setq vm-pop-passwords (cons (list source-nopwd pass)
						  vm-pop-passwords)))
		   (setq success t))
		  (t (error "Don't know how to authenticate using %s" auth)))
	    (setq shutdown nil) ))
      ;; unwind-protection
      (when shutdown
	(vm-pop-end-session process t))
      (vm-tear-down-stunnel-random-data))
    
    (if success
	process
      ;; try again if possible, treat it as non-interactive the next time
      (unless retry
	(let ((auth-sources nil))
	  (vm-pop-make-session source interactive t))))))

(defun vm-pop-get-password (popdrop source user host port ask-password)
  "Return the password for POPDROP at server SOURCE.  It corresponds
to the USER login at HOST and PORT.  ASK-PASSWORD says whether
passwords can be queried interactively."
  (let ((pass (car (cdr (assoc source vm-pop-passwords))))
	authinfo)
    (when (and (null pass)
	       (boundp 'auth-sources)
	       (fboundp 'auth-source-user-or-password))
      (cond ((and (setq authinfo
			(auth-source-user-or-password
			 '("login" "password")
			 (vm-pop-find-name-for-spec source)
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
	    (read-passwd
	     (format "POP password for %s: " popdrop)))
      (when (equal pass "")
	(vm-warn 0 2 "Password cannot be empty")
	(setq pass nil)))
    (when (null pass)
      (error "Need password for %s" popdrop))
    pass)  )


(defun vm-pop-forget-password (source host port)
  "Forget the cached password for SOURCE corresponding to HOST at PORT."
  (setq vm-pop-passwords
	(vm-delete (lambda (pair)
		     (equal (car pair) source))
		   vm-pop-passwords))
  (when (fboundp 'auth-source-forget-user-or-password)
    (auth-source-forget-user-or-password 
     '("login" "password")
     (vm-pop-find-name-for-spec source) port)
    (auth-source-forget-user-or-password 
     '("login" "password")
     host port))
  )

(defun vm-pop-end-session (process &optional keep-buffer verbose)
  "Kill the POP session represented by PROCESS.  PROCESS could be
nil or be already closed.  If the optional argument KEEP-BUFFER
is non-nil, the process buffer is retained, otherwise it is
killed as well."
  (if (and process (memq (process-status process) '(open run))
	   (buffer-live-p (process-buffer process)))
      (with-current-buffer (process-buffer process)
	(vm-pop-send-command process "QUIT")
	;; Previously we did not read the QUIT response because of
	;; TCP shutdown problems (under Windows?) that made it
	;; better if we just closed the connection.  Microsoft
	;; Exchange apparently fails to expunge messages if we shut
	;; down the connection without reading the QUIT response.
	;; So we provide an option and let the user decide what
	;; works best for them.
	(if vm-pop-read-quit-response
	    (progn
	      (and verbose
		   (vm-inform 5 "Waiting for response to POP QUIT command..."))
	      (vm-pop-read-response process)
	      (and verbose
		   (vm-inform 5
		    "Waiting for response to POP QUIT command... done"))))))
  (if (and (process-buffer process)
	   (buffer-live-p (process-buffer process)))
      (if (and (null vm-pop-keep-trace-buffer) (not keep-buffer))
	  (kill-buffer (process-buffer process))
	(vm-keep-some-buffers (process-buffer process) 'vm-kept-pop-buffers
			      vm-pop-keep-trace-buffer
			      "saved ")))
  (if (fboundp 'add-async-timeout)
      (add-async-timeout 2 'delete-process process)
    (run-at-time 2 nil 'delete-process process)))

(defun vm-pop-stat-timer (o) (aref o 0))
(defun vm-pop-stat-did-report (o) (aref o 1))
(defun vm-pop-stat-x-box (o) (aref o 2))
(defun vm-pop-stat-x-currmsg (o) (aref o 3))
(defun vm-pop-stat-x-maxmsg (o) (aref o 4))
(defun vm-pop-stat-x-got (o) (aref o 5))
(defun vm-pop-stat-x-need (o) (aref o 6))
(defun vm-pop-stat-y-box (o) (aref o 7))
(defun vm-pop-stat-y-currmsg (o) (aref o 8))
(defun vm-pop-stat-y-maxmsg (o) (aref o 9))
(defun vm-pop-stat-y-got (o) (aref o 10))
(defun vm-pop-stat-y-need (o) (aref o 11))

(defun vm-set-pop-stat-timer (o val) (aset o 0 val))
(defun vm-set-pop-stat-did-report (o val) (aset o 1 val))
(defun vm-set-pop-stat-x-box (o val) (aset o 2 val))
(defun vm-set-pop-stat-x-currmsg (o val) (aset o 3 val))
(defun vm-set-pop-stat-x-maxmsg (o val) (aset o 4 val))
(defun vm-set-pop-stat-x-got (o val) (aset o 5 val))
(defun vm-set-pop-stat-x-need (o val) (aset o 6 val))
(defun vm-set-pop-stat-y-box (o val) (aset o 7 val))
(defun vm-set-pop-stat-y-currmsg (o val) (aset o 8 val))
(defun vm-set-pop-stat-y-maxmsg (o val) (aset o 9 val))
(defun vm-set-pop-stat-y-got (o val) (aset o 10 val))
(defun vm-set-pop-stat-y-need (o val) (aset o 11 val))

(defun vm-pop-start-status-timer ()
  (let ((blob (make-vector 12 nil))
	timer)
    (setq timer (run-with-timer 5 5 #'vm-pop-report-retrieval-status blob))
    (vm-set-pop-stat-timer blob timer)
    blob ))

(defun vm-pop-stop-status-timer (status-blob)
  (if (vm-pop-stat-did-report status-blob)
      (vm-inform 5 ""))
  (if (fboundp 'disable-timeout)
      (disable-timeout (vm-pop-stat-timer status-blob))
    (cancel-timer (vm-pop-stat-timer status-blob))))

(defun vm-pop-report-retrieval-status (o)
  (vm-set-pop-stat-did-report o t)
  (cond ((null (vm-pop-stat-x-got o)) t)
	;; should not be possible, but better safe...
	((not (eq (vm-pop-stat-x-box o) (vm-pop-stat-y-box o))) t)
	((not (eq (vm-pop-stat-x-currmsg o) (vm-pop-stat-y-currmsg o))) t)
	(t (vm-inform 6 "Retrieving message %d (of %d) from %s, %s..."
		    (vm-pop-stat-x-currmsg o)
		    (vm-pop-stat-x-maxmsg o)
		    (vm-pop-stat-x-box o)
		    (if (vm-pop-stat-x-need o)
			(format "%d%s of %d%s"
				(vm-pop-stat-x-got o)
				(if (> (vm-pop-stat-x-got o)
				       (vm-pop-stat-x-need o))
				    "!"
				  "")
				(vm-pop-stat-x-need o)
				(if (eq (vm-pop-stat-x-got o)
					(vm-pop-stat-y-got o))
				    " (stalled)"
				  ""))
		      "post processing"))))
  (vm-set-pop-stat-y-box o (vm-pop-stat-x-box o))
  (vm-set-pop-stat-y-currmsg o (vm-pop-stat-x-currmsg o))
  (vm-set-pop-stat-y-maxmsg o (vm-pop-stat-x-maxmsg o))
  (vm-set-pop-stat-y-got o (vm-pop-stat-x-got o))
  (vm-set-pop-stat-y-need o (vm-pop-stat-x-need o)))

(defun vm-pop-check-connection (process)
  (cond ((not (memq (process-status process) '(open run)))
	 (error "POP connection not open: %s" process))
	((not (buffer-live-p (process-buffer process)))
	 (error "POP process %s's buffer has been killed" process))))

(defun vm-pop-send-command (process command)
  (vm-pop-check-connection process)
  (goto-char (point-max))
  (if (= (aref command 0) ?P)
      (insert-before-markers "PASS <omitted>\r\n")
    (insert-before-markers command "\r\n"))
  (setq vm-pop-read-point (point))
  (process-send-string process (format "%s\r\n" command)))

(defun vm-pop-read-response (process &optional return-response-string)
  (vm-pop-check-connection process)
  (let ((case-fold-search nil)
	 match-end)
    (goto-char vm-pop-read-point)
    (while (not (search-forward "\r\n" nil t))
      (vm-pop-check-connection process)
      (accept-process-output process)
      (goto-char vm-pop-read-point))
    (setq match-end (point))
    (goto-char vm-pop-read-point)
    (if (not (looking-at "+OK"))
	(progn (setq vm-pop-read-point match-end) nil)
      (setq vm-pop-read-point match-end)
      (if return-response-string
	  (buffer-substring (point) match-end)
	t ))))

(defun vm-pop-read-past-dot-sentinel-line (process)
  (vm-pop-check-connection process)
  (let ((case-fold-search nil))
    (goto-char vm-pop-read-point)
    (while (not (re-search-forward "^\\.\r\n" nil 0))
      (beginning-of-line)
      ;; save-excursion doesn't work right
      (let ((opoint (point)))
	(vm-pop-check-connection process)
	(accept-process-output process)
	(goto-char opoint)))
    (setq vm-pop-read-point (point))))

(defun vm-pop-read-stat-response (process)
  (let ((response (vm-pop-read-response process t))
	list)
    (if (null response)
	nil
      (setq list (vm-parse response "\\([^ ]+\\) *"))
      (list (string-to-number (nth 1 list)) (string-to-number (nth 2 list))))))

(defun vm-pop-read-list-response (process)
  (let ((response (vm-pop-read-response process t)))
    (and response
	 (string-to-number (nth 2 (vm-parse response "\\([^ ]+\\) *"))))))

(defun vm-pop-read-uidl-long-response (process)
  (vm-pop-check-connection process)
  (let ((start vm-pop-read-point)
	(list nil)
	n uidl)
    (catch 'done
      (goto-char start)
      (while (not (re-search-forward "^\\.\r\n\\|^-ERR .*$" nil 0))
	(beginning-of-line)
	;; save-excursion doesn't work right
	(let ((opoint (point)))
	  (vm-pop-check-connection process)
	  (accept-process-output process)
	  (goto-char opoint)))
      (setq vm-pop-read-point (point-marker))
      (goto-char start)
      ;; no uidl support, bail.
      (if (not (looking-at "\\+OK"))
	  (throw 'done nil))
      (forward-line 1)
      (while (not (eq (char-after (point)) ?.))
	;; not loking at a number, bail.
	(if (not (looking-at "[0-9]"))
	    (throw 'done nil))
	(setq n (int-to-string (read (current-buffer))))
	(skip-chars-forward " ")
	(setq start (point))
	(skip-chars-forward "\041-\176")
	;; no tag after the message number, bail.
	(if (= start (point))
	    (throw 'done nil))
	(setq uidl (buffer-substring start (point)))
	(setq list (cons (cons n uidl) list))
	(forward-line 1))
      ;; returning nil means the uidl command failed so don't
      ;; return nil if there aren't any messages.
      (if (null list)
	  (cons nil nil)
	list ))))

(defun vm-pop-ask-about-large-message (process popdrop size n)
  (let ((work-buffer nil)
	(pop-buffer (current-buffer))
	start end)
    (unwind-protect
	(save-excursion
	  (save-window-excursion
	    (vm-pop-send-command process (format "TOP %d %d" n 0))
	    (if (vm-pop-read-response process)
		(progn
		  (setq start vm-pop-read-point)
		  (vm-pop-read-past-dot-sentinel-line process)
		  (setq end vm-pop-read-point)
		  (setq work-buffer (generate-new-buffer
				     (format "*headers of %s message %d*"
					     popdrop n)))
		  (set-buffer work-buffer)
		  (insert-buffer-substring pop-buffer start end)
		  (forward-line -1)
		  (delete-region (point) (point-max))
		  (vm-pop-cleanup-region (point-min) (point-max))
		  (vm-display-buffer work-buffer)
		  (setq minibuffer-scroll-window (selected-window))
		  (goto-char (point-min))
		  (if (re-search-forward "^Received:" nil t)
		      (progn
			(goto-char (match-beginning 0))
			(vm-reorder-message-headers
			 nil :keep-list vm-visible-headers
			 :discard-regexp vm-invisible-header-regexp)))
		  (set-window-point (selected-window) (point))))
	    (if (y-or-n-p (format "Retrieve message %d (size = %d)? " n size))
		'retrieve
	      (if (y-or-n-p (format "Delete message %d on the server? " n))
		  'delete
		'skip))))
      (and work-buffer (kill-buffer work-buffer)))))

(defun vm-pop-ask-about-no-uidl (popdrop)
  (let ((work-buffer nil)
	;; (pop-buffer (current-buffer))
	) ;; start end
    (unwind-protect
	(save-excursion
	  (save-window-excursion
	    (setq work-buffer (generate-new-buffer
			       (format "*trouble with %s*" popdrop)))
	    (set-buffer work-buffer)
	    (insert
"You have asked VM to leave messages on the server for the POP mailbox "
popdrop
".  VM cannot do so because the server does not seem to support the POP UIDL command.\n\nYou can either continue to retrieve messages from this mailbox with VM deleting the messages from the server, or you can skip this mailbox, leaving messages on the server and not retrieving any messages.")
	    (fill-individual-paragraphs (point-min) (point-max))
	    (vm-display-buffer work-buffer)
	    (setq minibuffer-scroll-window (selected-window))
	    (yes-or-no-p "Continue retrieving anyway? ")))
      (and work-buffer (kill-buffer work-buffer)))))

(defun vm-pop-retrieve-to-target (process target statblob)
  (vm-pop-check-connection process)
  (let ((start vm-pop-read-point) end)
    (goto-char start)
    (vm-set-pop-stat-x-got statblob 0)
    (while (not (re-search-forward "^\\.\r\n" nil 0))
      (beginning-of-line)
      ;; save-excursion doesn't work right
      (let* ((opoint (point))
	     (func
	      (function
	       (lambda (_beg end _len)
		 (if vm-pop-read-point
		     (progn
		       (vm-set-pop-stat-x-got statblob (- end start))
		       (if (zerop (% (random) 10))
			   (vm-pop-report-retrieval-status statblob)))))))
	     (after-change-functions (cons func after-change-functions)))
	(vm-pop-check-connection process)
	(accept-process-output process)
	(goto-char opoint)))
    (vm-set-pop-stat-x-need statblob nil)
    (setq vm-pop-read-point (point-marker))
    (goto-char (match-beginning 0))
    (setq end (point-marker))
    (vm-pop-cleanup-region start end)
    (vm-set-pop-stat-x-got statblob nil)
    ;; Some POP servers strip leading and trailing message
    ;; separators, some don't.  Figure out what kind we're
    ;; talking to and do the right thing.
    (if (eq (vm-get-folder-type nil start end) 'unknown)
	(progn
	  (vm-munge-message-separators vm-folder-type start end)
	  (goto-char start)
	  ;; avoid the consing and stat() call for all but babyl
	  ;; files, since this will probably slow things down.
	  ;; only babyl files have the folder header, and we
	  ;; should only insert it if the target folder is empty.
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
		(setq start opoint)
		(goto-char start)
		(vm-skip-past-folder-header)))
	  (insert (vm-leading-message-separator))
	  (save-restriction
	    (narrow-to-region (point) end)
	    (vm-convert-folder-type-headers 'baremessage vm-folder-type))
	  (goto-char end)
	  (insert-before-markers (vm-trailing-message-separator))))
    (if (stringp target)
	;; Set file type to binary for DOS/Windows.  I don't know if
	;; this is correct to do or not; it depends on whether the
	;; the CRLF or the LF newline convention is used on the inbox
	;; associated with this crashbox.  This setting assumes the LF
	;; newline convention is used.
	(defvar buffer-file-type) ;; FIXME: Removed in Emacs-24.4.
	(let ((buffer-file-type t)
	      (selective-display nil))
	  (write-region start end target t 0))
      (let ((b (current-buffer)))
	(with-current-buffer target
	  (let ((buffer-read-only nil))
	    (insert-buffer-substring b start end)))))
    (delete-region start end)
    t ))

(defun vm-pop-cleanup-region (start end)
  (setq end (vm-marker end))
  (save-excursion
    ;; CRLF -> LF
    (if (featurep 'xemacs)
        (progn
          ;; we need this otherwise the end marker gets corrupt and
          ;; unfortunately decode-coding-region does not return the
          ;; length to the decoded region 
          (decode-coding-region start (1- end) 'undecided-dos)
          (goto-char (- end 2))
          (delete-char 1))
    (goto-char start)
      (while (and (< (point) end) (search-forward "\r\n"  end t))
        (replace-match "\n" t t)))
    ;; chop leading dots
    (goto-char start)
    (while (and (< (point) end) (re-search-forward "^\\."  end t))
      (replace-match "" t t)
      (forward-char)))
  (set-marker end nil))

(defun vm-establish-new-folder-pop-session (&optional interactive)
  (let ((process (vm-folder-pop-process))
	;; (vm-pop-ok-to-ask (eq interactive t))
	)
    (if (processp process)
	(vm-pop-end-session process))
    (setq process 
	  (vm-pop-make-session (vm-folder-pop-maildrop-spec) interactive))
    (when (processp process)
      (vm-set-folder-pop-process process))
    process ))

(defun vm-pop-get-uidl-data ()
  (let ((there (make-vector 67 0))
	(process (vm-folder-pop-process)))
    (with-current-buffer (process-buffer process)
      (vm-pop-send-command process "UIDL")
      (let ((start vm-pop-read-point)
	    n uidl)
	(catch 'done
	  (goto-char start)
	  (while (not (re-search-forward "^\\.\r\n\\|^-ERR .*$" nil 0))
	    (beginning-of-line)
	    ;; save-excursion doesn't work right
	    (let ((opoint (point)))
	      (vm-pop-check-connection process)
	      (accept-process-output process)
	      (goto-char opoint)))
	  (setq vm-pop-read-point (point-marker))
	  (goto-char start)
	  ;; no uidl support, bail.
	  (if (not (looking-at "\\+OK"))
	      (throw 'done nil))
	  (forward-line 1)
	  (while (not (eq (char-after (point)) ?.))
	    ;; not loking at a number, bail.
	    (if (not (looking-at "[0-9]"))
		(throw 'done nil))
	    (setq n (int-to-string (read (current-buffer))))
	    (skip-chars-forward " ")
	    (setq start (point))
	    (skip-chars-forward "\041-\176")
	    ;; no tag after the message number, bail.
	    (if (= start (point))
		(throw 'done nil))
	    (setq uidl (buffer-substring start (point)))
	    (set (intern uidl there) n)
	    (forward-line 1))
	  there )))))

(defun vm-pop-get-synchronization-data ()
  "Compares the UID's of messages in the local cache and the POP
server.  Returns a list containing:
RETRIEVE-LIST: A list of pairs consisting of UID's and message
  sequence numbers of the messages that are not present in the
  local cache and not retrieved previously, and, hence, need to be
  retrieved now.
LOCAL-EXPUNGE-LIST: A list of message descriptors for messages in the
  local cache which are not present on the server and, hence, need
  to expunged locally."
  ;; The following features are in the IMAP code, but not in POP.  Why
  ;; not?  -- USR, 2012-11-24
  ;; REMOTE-EXPUNGE-LIST: A list of pairs consisting of UID's and
  ;;   UIDVALIDITY's of the messages that are not present in the local
  ;;   cache (but we have reason to believe that they have been retrieved
  ;;   previously) and, hence, need to be expunged on the server. 
  ;; If the argument DO-RETRIEVES is 'full, then all the messages that
  ;; are not presently in cache are retrieved.  Otherwise, the
  ;; messages previously retrieved are ignored.
  (let ((here (obarray-make))
	(there (vm-pop-get-uidl-data))
	;; (process (vm-folder-pop-process))
	retrieve-list local-expunge-list uid 
	mp)
    (setq mp vm-message-list)
    (while mp
      (cond ((null (vm-pop-uidl-of (car mp)))
	     nil)
	    (t
	     (setq uid (vm-pop-uidl-of (car mp)))
	     (set (intern uid here) (car mp))
	     (if (not (boundp (intern uid there)))
		 (setq local-expunge-list (cons (car mp) local-expunge-list)))))
      (setq mp (cdr mp)))
    (mapatoms 
     (lambda (sym)
       (let ((uid (symbol-name sym)))
	 (if (and (not (boundp (intern uid here)))
		  (not (assoc uid
			      vm-pop-retrieved-messages)))
	     (setq retrieve-list 
		   (cons (cons uid (symbol-value sym)) retrieve-list)))))
     there)
    (setq retrieve-list 
	  (sort retrieve-list 
		(lambda (**pair1 **pair2)
		  (string-lessp (cdr **pair1) (cdr **pair2)))))	  
    (list retrieve-list local-expunge-list)))

;;;###autoload
(cl-defun vm-pop-synchronize-folder (&key 
				   (interactive nil)
				   (do-remote-expunges nil)
				   (do-local-expunges nil)
				   (do-retrieves nil))
  "Synchronize POP folder with the server.
   INTERACTIVE says the operation has been invoked interactively.  The
   possible values are t, `password-only', and nil.
   DO-REMOTE-EXPUNGES indicates whether the server mail box should be
   expunged.
   DO-LOCAL-EXPUNGES indicates whether the cache buffer should be
   expunged.
   DO-RETRIEVES indicates if new messages that are not already in the
   cache should be retrieved from the server.  If this flag is `full'
   then messages previously retrieved but not in cache are retrieved
   as well.
"
  ;; -- Comments by USR
  ;; Not clear why do-local-expunges and do-remote-expunges should be
  ;; separate.  It doesn't make sense to do one but not the other!

  (if (and do-retrieves vm-block-new-mail)
      (error "Can't get new mail until you save this folder."))
  (if (or vm-global-block-new-mail
	  (null (vm-establish-new-folder-pop-session interactive)))
      nil
    (if do-retrieves
	(vm-assimilate-new-messages))
    (let* ((sync-data (vm-pop-get-synchronization-data))
	   (retrieve-list (nth 0 sync-data))
	   (local-expunge-list (nth 1 sync-data))
	   (process (vm-folder-pop-process))
	   (n 1)
	   (statblob nil)
	   (popdrop (vm-folder-pop-maildrop-spec))
	   (safe-popdrop (or (vm-pop-find-name-for-spec popdrop)
			     (vm-safe-popdrop-string popdrop)))
	   r-list mp got-some message-size
	   (folder-buffer (current-buffer)))
      (if (and do-retrieves retrieve-list)
	  (save-excursion
	    (save-restriction
	     (widen)
	     (goto-char (point-max))
	     (condition-case error-data
		 (with-current-buffer (process-buffer process)
		   (setq statblob (vm-pop-start-status-timer))
		   (vm-set-pop-stat-x-box statblob safe-popdrop)
		   (vm-set-pop-stat-x-maxmsg statblob
					     (length retrieve-list))
		   (setq r-list retrieve-list)
		   (while r-list
		     (vm-set-pop-stat-x-currmsg statblob n)
		     (vm-pop-send-command process (format "LIST %s"
							  (cdr (car r-list))))
		     (setq message-size (vm-pop-read-list-response process))
		     (vm-set-pop-stat-x-need statblob message-size)
		     (vm-pop-send-command process
					  (format "RETR %s"
						  (cdr (car r-list))))
		     (and (null (vm-pop-read-response process))
			  (error "server didn't say +OK to RETR %s command"
				 (cdr (car r-list))))
		     (vm-pop-retrieve-to-target process folder-buffer
						statblob)
		     (setq r-list (cdr r-list)
			   n (1+ n))))
	       (error
		(vm-warn 0 2 "Retrieval from %s signaled: %s" safe-popdrop
			 error-data))
	       (quit
		(vm-inform 0 "Quit received during retrieval from %s"
			 safe-popdrop)))
	     (and statblob (vm-pop-stop-status-timer statblob))
	     ;; to make the "Mail" indicator go away
	     (setq vm-spooled-mail-waiting nil)
	     (intern (buffer-name) vm-buffers-needing-display-update)
	     (vm-update-summary-and-mode-line)
	     (setq mp (vm-assimilate-new-messages :read-attributes nil))
	     (setq got-some mp)
             (if got-some
                 (vm-increment vm-modification-counter))
	     (setq r-list retrieve-list)
	     (while mp
	       (vm-set-pop-uidl-of (car mp) (car (car r-list)))
	       (vm-set-stuff-flag-of (car mp) t)
	       (setq mp (cdr mp)
		     r-list (cdr r-list))))))
      (if do-local-expunges
	  (vm-expunge-folder :quiet t :just-these-messages local-expunge-list))
      (if (and do-remote-expunges
	       vm-pop-messages-to-expunge)
	  (let ((process (vm-folder-pop-process)))
	    ;; POP servers usually allow only one remote accessor
	    ;; at a time vm-expunge-pop-messages will set up its
	    ;; own connection so we get out of its way by closing
	    ;; our connection.
	    (if (and (processp process)
		     (memq (process-status process) '(open run)))
		(vm-pop-end-session process))
	    (setq vm-pop-retrieved-messages
		  (mapcar (function (lambda (x) (list x popdrop 'uidl)))
			  vm-pop-messages-to-expunge))
	    (vm-expunge-pop-messages)
	    ;; Any messages that could not be expunged will be
	    ;; remembered for future
	    (setq vm-pop-messages-to-expunge
		  (mapcar (function (lambda (x) (car x)))
			  vm-pop-retrieved-messages))))
      got-some)))

;;;###autoload
(defun vm-pop-folder-check-mail (&optional interactive)
  "Check if there is new mail on the POP server for the current POP
folder.

Optional argument INTERACTIVE says whether this function is being
called from an interactive use of a command."
  (if (or vm-global-block-new-mail
	  (null (vm-establish-new-folder-pop-session interactive)))
      nil
    (let ((result (car (vm-pop-get-synchronization-data))))
      (vm-pop-end-session (vm-folder-pop-process))
      result )))
(defalias 'vm-pop-folder-check-for-mail 'vm-pop-folder-check-mail)
(make-obsolete 'vm-pop-folder-check-for-mail
	       'vm-pop-folder-check-mail "8.2.0")


;;;###autoload
(defun vm-pop-find-spec-for-name (name)
  "Returns the full maildrop specification of a short name NAME."
  (let ((list vm-pop-folder-alist)
	(done nil))
    (while (and (not done) list)
      (if (equal name (nth 1 (car list)))
	  (setq done t)
	(setq list (cdr list))))
    (and list (car (car list)))))

;;;###autoload
(defun vm-pop-find-name-for-spec (spec)
  "Returns the short name of a POP maildrop specification SPEC."
  (let ((list vm-pop-folder-alist)
	(done nil))
    (while (and (not done) list)
      (if (equal spec (car (car list)))
	  (setq done t)
	(setq list (cdr list))))
    (and list (nth 1 (car list)))))

;;;###autoload
(defun vm-pop-find-name-for-buffer (buffer)
  (let ((list vm-pop-folder-alist)
	(done nil))
    (while (and (not done) list)
      (if (eq buffer (vm-get-file-buffer (vm-pop-make-filename-for-spec
					  (car (car list)))))
	  (setq done t)
	(setq list (cdr list))))
    (and list (nth 1 (car list)))))

;;;###autoload
(defun vm-pop-make-filename-for-spec (spec &optional scrub-password scrub-spec)
  "Returns a cache file name appropriate for the POP maildrop
specification SPEC."
  (let (md5 list)
    (if (and (null scrub-password) (null scrub-spec))
	nil
      (setq list (vm-pop-parse-spec-to-list spec))
      (setcar (vm-last list) "*")	; scrub password
      (if scrub-spec
	  (progn
	    (cond ((= (length list) 6)
		   (setcar list "pop")	; standardise protocol name
		   (setcar (nthcdr 2 list) "*")	; scrub port number
		   (setcar (nthcdr 3 list) "*")) ; scrub auth method
		  (t
		   (setq list (cons "pop" list))
		   (setcar (nthcdr 2 list) "*")
		   (setcar (nthcdr 3 list) "*")))))
      (setq spec (mapconcat (function identity) list ":")))
    (setq md5 (vm-md5-string spec))
    (expand-file-name (concat "pop-cache-" md5)
		      (or vm-pop-folder-cache-directory
			  vm-folder-directory
			  (getenv "HOME")))))

(defun vm-pop-parse-spec-to-list (spec)
  (if (string-match "\\(pop\\|pop-ssh\\|pop-ssl\\)" spec)
      (vm-parse spec "\\([^:]+\\):?" 1 5)
    (vm-parse spec "\\([^:]+\\):?" 1 4)))


;;;###autoload
(defun vm-pop-start-bug-report ()
  "Begin to compose a bug report for POP support functionality."
  (interactive)
  (vm-follow-summary-cursor)
  (vm-select-folder-buffer-and-validate 0 (vm-interactive-p))
  (setq vm-kept-pop-buffers nil)
  (setq vm-pop-keep-trace-buffer 20))

;;;###autoload
(defun vm-pop-submit-bug-report ()
  "Submit a bug report for VM's POP support functionality.  
It is necessary to run `vm-pop-start-bug-report' before the problem
occurrence and this command after the problem occurrence, in
order to capture the trace of POP sessions during the occurrence."
  (interactive)
  (vm-follow-summary-cursor)
  (vm-select-folder-buffer-and-validate 0 (vm-interactive-p))
  (if (or vm-pop-keep-trace-buffer
	  (y-or-n-p "Did you run vm-pop-start-bug-report earlier? "))
      (vm-inform 5 "Thank you. Preparing the bug report... ")
    (vm-inform 1 "Consider running vm-pop-start-bug-report before the problem occurrence"))
  (let ((process (if (eq vm-folder-access-method 'pop)
		     (vm-folder-pop-process))))
    (if process
	(vm-pop-end-session process)))
  (let ((trace-buffer-hook
	 (lambda ()
	   (let ((bufs vm-kept-pop-buffers) 
		 buf)
	     (insert "\n\n")
	     (insert "POP Trace buffers - most recent first\n\n")
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
(defun vm-pop-set-default-attributes (m)
  (vm-set-headers-to-be-retrieved-of m nil)
  (vm-set-body-to-be-retrieved-of m nil)
  (vm-set-body-to-be-discarded-of m nil))


(provide 'vm-pop)
;;; vm-pop.el ends here
