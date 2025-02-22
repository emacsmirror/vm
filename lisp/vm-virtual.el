;;; vm-virtual.el --- Virtual folders for VM  -*- lexical-binding: t; -*-
;;
;; This file is part of VM
;;
;; Copyright (C) 1990-1997 Kyle E. Jones
;; Copyright (C) 2000-2006 Robert Widhopf-Fenk
;; Copyright (C) 2011 Uday S. Reddy
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

(require 'vm-message)
(require 'vm-macro)
(require 'vm-misc)
(require 'vm-minibuf)

;; FIXME: Cyclic dependence between vm-virtual.el and vm-avirtual.el
;; prevents us from requiring `vm-avirtual' here.
(defvar vm-virtual-message)

(declare-function vm-visit-folder "vm" 
		  (folder &optional read-only &key interactive just-visit))
(declare-function vm-visit-virtual-folder "vm"
		  (folder &optional read-only bookmark summary-format
			  default-directory)) 
(declare-function vm-visit-virtual-folder-other-window "vm"
		  (folder &optional read-only bookmark summary-format
			  default-directory))
(declare-function vm-visit-virtual-folder-other-frame "vm"
		  (folder &optional read-only bookmark summary-format
			  default-directory))
(declare-function vm-mode "vm" 
		  (&optional read-only))
(declare-function vm-get-folder-buffer "vm"
		  (folder))


(defvar inhibit-local-variables) ;; FIXME: Unknown var.  XEmacs?

;;;###autoload
(defun vm-build-virtual-message-list (new-messages &optional dont-finalize)
  "Builds a list of messages matching the virtual folder definition
stored in the variable `vm-virtual-folder-definition'.

If the NEW-MESSAGES argument is nil, the message list is
derived from the folders listed in the virtual folder
definition and selected by the various selectors.  The
resulting message list is assigned to `vm-message-list' unless
DONT-FINALIZE is non-nil.

If NEW-MESSAGES is non-nil then it is a list of messages to
be tried against the selector parts of the virtual folder
definition.  Matching messages are added to `vm-message-list',
instead of replacing it.

The messages in the NEW-MESSAGES list, if any, must all be in the
same real folder.

The list of matching virtual messages is returned.

If DONT-FINALIZE is nil, in addition to `vm-message-list' being
set, the virtual messages are added to the virtual message
lists of their real messages, the current buffer is added to
`vm-virtual-buffers' list of each real folder buffer represented
in the virtual list, and `vm-real-buffers' is set to a list of
all the real folder buffers involved."
  (let ((clauses (cdr vm-virtual-folder-definition))
	(message-set (make-vector 311 0))
	(vbuffer (current-buffer))
	(mirrored vm-virtual-mirror)
	(case-fold-search t)
	(tail-cons (if dont-finalize nil (last vm-message-list)))
	(new-message-list nil)
	virtual location-vector
	message folders folder buffer
	selectors i ;; sel-list selector arglist
	real-buffers-used components)
    (if dont-finalize
	nil
      ;; Since there is at most one virtual message in the folder
      ;; buffer of a virtual folder, the location data vector (and
      ;; the markers in it) of all virtual messages in a virtual
      ;; folder is shared.  We initialize the vector here if it
      ;; hasn't been created already.
      (if vm-message-list
	  (setq location-vector
		(vm-location-data-of (car vm-message-pointer)))
	(setq i 0
	      location-vector
	      (make-vector vm-location-data-vector-length nil))
	(while (< i vm-location-data-vector-length)
	  (aset location-vector i (vm-marker nil))
	  (vm-increment i)))
      ;; To keep track of the messages in a virtual folder to
      ;; prevent duplicates we create and maintain a set that
      ;; contain all the real messages.
      (dolist (m vm-message-list)
	(intern (vm-message-id-number-of (vm-real-message-of m))
		message-set)))
    ;; now select the messages
    (save-excursion
      (dolist (clause clauses)
	(setq folders (car clause)
	      selectors (cdr clause))
	(while folders			; folders can change below
	  (setq folder (car folders))
	  (cond ((and (stringp folder) (vm-pop-folder-spec-p folder))
		 nil)
		((and (stringp folder) (vm-imap-folder-spec-p folder))
		 nil)
		((stringp folder)	; Local folder, use full path
		 (setq folder (expand-file-name folder vm-folder-directory)))
		((listp folder)		; Sexpr, eval it
		 (setq folder (eval folder))))
	  (catch 'done
	    (when (null folder)
	      ;; folder was a s-expr which returned nil
	      ;; skip it
	      (throw 'done nil))
	    (when (and (stringp folder) (file-directory-p folder))
	      ;; an entire directory!
	      (setq folders (nconc folders
				   (vm-delete-backup-file-names
				    (vm-delete-auto-save-file-names
				     (vm-delete-directory-file-names
				      (directory-files folder t nil))))))
	      (throw 'done t))
	    (cond ((bufferp folder)
		   (setq buffer folder)
		   (setq components (cons (cons buffer nil) components)))
		  ((and (stringp folder)
			(setq buffer (vm-get-folder-buffer folder)))
		   (setq components (cons (cons buffer nil) components)))
		  ((stringp folder)
		   ;; letter bomb protection
		   ;; set inhibit-local-variables to t for v18 Emacses
		   ;; set enable-local-variables to nil
		   ;; for newer Emacses
		   (let ((inhibit-local-variables t)
			 (coding-system-for-read 
			  (vm-binary-coding-system))
			 (enable-local-eval nil)
			 (enable-local-variables nil)
			 (vm-frame-per-folder nil)
			 (vm-verbosity (1- vm-verbosity)))
		     (vm-visit-folder folder nil :just-visit t)
		     (vm-select-folder-buffer)
		     (setq buffer (current-buffer))
		     (setq components (cons (cons buffer t) components))))
		  (t (catch 'done nil)))
	   (when (or (null new-messages)
		     ;; If we're assimilating messages into an
		     ;; existing virtual folder, only allow selectors
		     ;; that would be normally applied to this folder.
		     (eq (vm-buffer-of (car new-messages)) buffer))
	     ;; Check if the folder is already visited, or visit it
	     (cond ((bufferp buffer)
		    (set-buffer buffer))
		   (t			; is this case needed?
		    (catch 'done nil)))
	     (if (eq major-mode 'vm-virtual-mode)
		 (setq virtual t
		       real-buffers-used 
		       (append vm-real-buffers real-buffers-used))
	       (setq virtual nil)
	       (unless (memq (current-buffer) real-buffers-used)
		 (setq real-buffers-used (cons (current-buffer)
					       real-buffers-used)))
	       (unless (eq major-mode 'vm-mode)
		 (vm-mode)))

	    ;; change (sexpr) into ("/file" "/file2" ...)
	    ;; this assumes that there will never be (sexpr sexpr2)
	    ;; in a virtual folder spec.
	    ;; But why are we doing this?  This is ugly and
	    ;; error-prone, and breaks things for server folders!
	    ;; USR, 2010-09-20
	    ;; (when (bufferp folder)
	    ;; 	(if virtual
	    ;; 	    (setcar (car clauses)
	    ;; 		    (delq nil
	    ;; 			  (mapcar 'buffer-file-name vm-real-buffers)))
	    ;; 	  (if buffer-file-name
	    ;; 	      (setcar (car clauses) (list buffer-file-name)))))

	    ;; if new-messages non-nil use it instead of the
	    ;; whole message list
	    (dolist (m (or new-messages vm-message-list))
	      (when (and (or dont-finalize
			     (not (intern-soft
				   (vm-message-id-number-of
				    (vm-real-message-of m))
				   message-set)))
			 (if virtual
			     (with-current-buffer
				(vm-buffer-of (vm-real-message-of m))
			       (apply 'vm-vs-or m selectors))
			   (apply 'vm-vs-or m selectors)))
		(when (and vm-virtual-debug
			   (member (vm-su-message-id m)
				   vm-traced-message-ids))
		  (debug "vm-build-virtual-message-list" m)
		  (apply 'vm-vs-or m selectors))
		(unless dont-finalize
		  (intern
		   (vm-message-id-number-of (vm-real-message-of m))
		   message-set))
		(setq message (copy-sequence (vm-real-message-of m)))
		(unless mirrored
		  (vm-set-mirror-data-of
		   message (make-vector vm-mirror-data-vector-length nil))
		  (vm-set-virtual-messages-sym-of
		   message (make-symbol "<v>"))
		  (vm-set-virtual-messages-of message nil)
		  (vm-set-attributes-of
		   message (make-vector vm-attributes-vector-length nil)))
		(vm-set-location-data-of message location-vector)
		(vm-set-softdata-of
		 message (make-vector vm-softdata-vector-length nil))
		(if (eq m (symbol-value (vm-mirrored-message-sym-of m)))
		    (vm-set-mirrored-message-sym-of
		     message (vm-mirrored-message-sym-of m))
		  (let ((sym (make-symbol "<<>>")))
		    (set sym m)
		    (vm-set-mirrored-message-sym-of message sym)))
		(vm-set-real-message-sym-of
		 message (vm-real-message-sym-of m))
		(vm-set-message-type-of message vm-folder-type)
		(vm-set-message-access-method-of
		 message vm-folder-access-method)
		(vm-set-message-id-number-of 
		 message vm-message-id-number)
		(vm-increment vm-message-id-number)
		(vm-set-buffer-of message vbuffer)
		(vm-set-reverse-link-sym-of message (make-symbol "<--"))
		(vm-set-reverse-link-of message tail-cons)
		(if (null tail-cons)
		    (setq new-message-list (list message)
			  tail-cons new-message-list)
		  (setcdr tail-cons (list message))
		  (if (null new-message-list)
		      (setq new-message-list (cdr tail-cons)))
		  (setq tail-cons (cdr tail-cons)))))))
	  (setq folders (cdr folders)))))
    (if dont-finalize
	new-message-list
      ;; this doesn't need to work currently, but it might someday
      ;; (if virtual
      ;;    (setq real-buffers-used (vm-delete-duplicates real-buffers-used)))
      (vm-increment vm-modification-counter)
      ;; Until this point the user doesn't really have a virtual
      ;; folder, as the virtual messages haven't been linked to the
      ;; real messages, virtual buffers to the real buffers, and no
      ;; message list has been installed.
      ;;
      ;; Now we tie it all together, with this section of code being
      ;; uninterruptible.
      (let ((inhibit-quit t)
	    (label-obarray vm-label-obarray))
	(unless vm-real-buffers
	  (setq vm-real-buffers real-buffers-used))
	(unless vm-component-buffers
	  (setq vm-component-buffers components))
	(save-excursion
	  (dolist (real-buffer real-buffers-used)
	    (set-buffer real-buffer)
	    ;; inherit the global label lists of all the associated
	    ;; real folders.
	    (mapatoms (function (lambda (x) (intern (symbol-name x)
						    label-obarray)))
		      vm-label-obarray)
	    (unless (memq vbuffer vm-virtual-buffers)
	      (setq vm-virtual-buffers (cons vbuffer
					     vm-virtual-buffers)))))
	(dolist (m new-message-list)
	  (vm-set-virtual-messages-of
	   (vm-real-message-of m)
	   (cons m (vm-virtual-messages-of (vm-real-message-of m)))))
	(if vm-message-list
	    (when new-message-list
	      (vm-set-summary-redo-start-point new-message-list)
	      (vm-set-numbering-redo-start-point new-message-list))
	  (vm-set-summary-redo-start-point t)
	  (vm-set-numbering-redo-start-point t)
	  (setq vm-message-list new-message-list))
	new-message-list ))))

;;;###autoload
(defun vm-create-virtual-folder (selector &optional arg read-only name
					  bookmark)
  "Create a new virtual folder from messages in the current folder.
The messages will be chosen by applying the selector you specify,
which is normally read from the minibuffer.  See `vm-vs-interactive'
for the list of selectors.

Prefix arg means the new virtual folder should be visited read only."
  (interactive
   (let ((last-command last-command)
	 (this-command this-command)
	 (prefix current-prefix-arg))
     (save-current-buffer
     (vm-select-folder-buffer)
     (nconc (vm-read-virtual-selector "Create virtual folder of messages: ")
	    (list prefix)))))

  (vm-select-folder-buffer-and-validate 1 (vm-interactive-p))
  (if vm-folder-read-only (setq read-only t))
  (let ((use-marks (eq last-command 'vm-next-command-uses-marks))
	(parent-summary-format vm-summary-format)
	vm-virtual-folder-alist ; shadow the global variable
	clause
	)
    (unless name
      (setq name (vm-virtual-folder-name (buffer-name) selector arg)))
    (setq clause (if arg (list selector arg) (list selector)))
    (if use-marks
	(setq clause (list 'and '(marked) clause)))
    (setq vm-virtual-folder-alist
	  `(( ,name (((get-buffer ,(buffer-name))) ,clause))))
    (vm-visit-virtual-folder name read-only bookmark 
			     parent-summary-format default-directory))
  ;; have to do this again here because the known virtual
  ;; folder menu is now hosed because we installed it while
  ;; vm-virtual-folder-alist was bound to the temp value above
  (when vm-use-menus
    (vm-menu-install-known-virtual-folders-menu)))

(defalias 'vm-create-search-folder 'vm-create-virtual-folder)

;;;###autoload
(defun vm-create-virtual-folder-other-frame
  		(selector &optional arg read-only name bookmark)
  "Create a new virtual folder from messages in the current folder,
using another frame.
The messages will be chosen by applying the selector you specify,
which is normally read from the minibuffer.  See `vm-vs-interactive'
for the list of selectors.

Prefix arg means the new virtual folder should be visited read only."
  (interactive
   (let ((last-command last-command)
	 (this-command this-command)
	 (prefix current-prefix-arg))
     (save-current-buffer
     (vm-select-folder-buffer)
     (nconc (vm-read-virtual-selector "Create virtual folder of messages: ")
	    (list prefix)))))

  (vm-select-folder-buffer-and-validate 1 (vm-interactive-p))
  (if vm-folder-read-only (setq read-only t))
  (let ((use-marks (eq last-command 'vm-next-command-uses-marks))
	(parent-summary-format vm-summary-format)
	vm-virtual-folder-alist ; shadow the global variable
	clause
	)
    (unless name
      (setq name (vm-virtual-folder-name (buffer-name) selector arg)))
    (setq clause (if arg (list selector arg) (list selector)))
    (if use-marks
	(setq clause (list 'and '(marked) clause)))
    (setq vm-virtual-folder-alist
	  `(( ,name (((get-buffer ,(buffer-name))) ,clause))))
    (vm-visit-virtual-folder-other-frame
     name read-only bookmark parent-summary-format default-directory))
  ;; have to do this again here because the known virtual
  ;; folder menu is now hosed because we installed it while
  ;; vm-virtual-folder-alist was bound to the temp value above
  (when vm-use-menus
    (vm-menu-install-known-virtual-folders-menu)))

(defalias 'vm-create-search-folder-other-frame
  'vm-create-virtual-folder-other-frame)

;;;###autoload
(defun vm-create-virtual-folder-other-window 
  		(selector &optional arg read-only name bookmark)
  "Create a new virtual folder from messages in the current folder
using another window.
The messages will be chosen by applying the selector you specify,
which is normally read from the minibuffer.  See `vm-vs-interactive'
for the list of selectors.

Prefix arg means the new virtual folder should be visited read only."
  (interactive
   (let ((last-command last-command)
	 (this-command this-command)
	 (prefix current-prefix-arg))
     (save-current-buffer
     (vm-select-folder-buffer)
     (nconc (vm-read-virtual-selector "Create virtual folder of messages: ")
	    (list prefix)))))

  (vm-select-folder-buffer-and-validate 1 (vm-interactive-p))
  (if vm-folder-read-only (setq read-only t))
  (let ((use-marks (eq last-command 'vm-next-command-uses-marks))
	(parent-summary-format vm-summary-format)
	vm-virtual-folder-alist ; shadow the global variable
	clause
	)
    (unless name
      (setq name (vm-virtual-folder-name (buffer-name) selector arg)))
    (setq clause (if arg (list selector arg) (list selector)))
    (if use-marks
	(setq clause (list 'and '(marked) clause)))
    (setq vm-virtual-folder-alist
	  `(( ,name (((get-buffer ,(buffer-name))) ,clause))))
    (vm-visit-virtual-folder-other-window
     name read-only bookmark parent-summary-format default-directory))
  ;; have to do this again here because the known virtual
  ;; folder menu is now hosed because we installed it while
  ;; vm-virtual-folder-alist was bound to the temp value above
  (when vm-use-menus
    (vm-menu-install-known-virtual-folders-menu)))

(defalias 'vm-create-search-folder-other-window 
  'vm-create-virtual-folder-other-window)

;;;###autoload
(defun vm-create-virtual-folder-of-threads (selector &optional arg
						     read-only name
						     bookmark)
  "Create a new virtual folder of threads in the current folder.
The threads will be chosen by applying the selector you specify,
which is normally read from the minibuffer.  If any message in a
thread matches the selector then the thread is chosen.

Prefix arg means the new virtual folder should be visited read only."
  (interactive
   (let ((last-command last-command)
	 (this-command this-command)
	 (prefix current-prefix-arg))
     (save-current-buffer
     (vm-select-folder-buffer)
     (nconc (vm-read-virtual-selector "Create virtual folder of threads: ")
	    (list prefix)))))

  (vm-select-folder-buffer-and-validate 1 (vm-interactive-p))
  (vm-build-threads-if-unbuilt)
  (let ((use-marks (eq last-command 'vm-next-command-uses-marks))
	(parent-summary-format vm-summary-format)
	vm-virtual-folder-alist ; shadow the global variable
	clause
	)
    (unless name
      (setq name (vm-virtual-folder-name (buffer-name) selector arg)))
    (setq clause 
	  (if arg 
	      (list 'thread (list selector arg))
	    (list 'thread (list selector))))
    (if use-marks
	(setq clause (list 'and '(marked) clause)))
    (setq vm-virtual-folder-alist
	  `(( ,name (((get-buffer ,(buffer-name))) ,clause))))
    (vm-visit-virtual-folder name read-only bookmark
			     parent-summary-format default-directory))
  ;; have to do this again here because the known virtual
  ;; folder menu is now hosed because we installed it while
  ;; vm-virtual-folder-alist was bound to the temp value above
  (when vm-use-menus
    (vm-menu-install-known-virtual-folders-menu)))  


;;;###autoload
(defun vm-apply-virtual-folder (name &optional read-only)
  "Apply the selectors of a named virtual folder to the current folder
and create a virtual folder containing the selected messages.

Prefix arg means the new virtual folder should be visited read only."
  (interactive
   (let ((last-command last-command)
	 (this-command this-command))
     (list
      (completing-read 
       ;; prompt
       "Apply this virtual folder's selectors: "
       ;; collection
       vm-virtual-folder-alist 
       ;; predicate, require-match
       nil t)
      current-prefix-arg)))
  (vm-select-folder-buffer-and-validate 1 (vm-interactive-p))
  (let ((vfolder (assoc name vm-virtual-folder-alist))
	(use-marks (eq last-command 'vm-next-command-uses-marks))
	(parent-summary-format vm-summary-format)
	clauses vm-virtual-folder-alist)
    (or vfolder (error "No such virtual folder, %s" name))
    (setq vfolder (vm-copy vfolder))
    (setq clauses (cdr vfolder))
    (while clauses
      (setcar (car clauses) (list (list 'get-buffer (buffer-name))))
      (if use-marks
	  (setcdr (car clauses)
		  (list (list 'and '(marked)
			      (nconc (list 'or) (cdr (car clauses)))))))
      (setq clauses (cdr clauses)))
    (setcar vfolder (vm-virtual-application-folder-name
		     (buffer-name) (car vfolder)))
    (setq vm-virtual-folder-alist (list vfolder))
    ;; FIXME should the bookmark here be nil?
    (vm-visit-virtual-folder (car vfolder) read-only 
			     nil parent-summary-format default-directory))
  ;; have to do this again here because the "known virtual
  ;; folder" menu is now hosed because we installed it while
  ;; vm-virtual-folder-alist was bound to the temp value above
  (if vm-use-menus
      (vm-menu-install-known-virtual-folders-menu)))

;;;###autoload
(defun vm-create-virtual-folder-same-subject ()
  "Create a virtual folder (search folder) for all messages with
the same subject as the current message."
  (interactive)
  (vm-follow-summary-cursor)
  (vm-select-folder-buffer-and-validate 1 (vm-interactive-p))
  (let* ((subject (vm-so-sortable-subject (car vm-message-pointer)))
	 (displayed-subject subject)
	 (bookmark (if (vm-virtual-message-p (car vm-message-pointer))
		       (vm-real-message-of (car vm-message-pointer))
		     (car vm-message-pointer))))
    (if (equal subject "")
	(setq subject "^$"
	      displayed-subject "\"\"")
      (setq subject (regexp-quote subject)))
    (vm-create-virtual-folder
     'sortable-subject subject nil
     (vm-virtual-folder-name (buffer-name) 'subject displayed-subject)
     bookmark)))

;;;###autoload
(defun vm-create-virtual-folder-same-author ()
  "Create a virtual folder (search folder) for all messages from the
same author as the current message."
  (interactive)
  (vm-follow-summary-cursor)
  (vm-select-folder-buffer-and-validate 1 (vm-interactive-p))
  (let* ((author (vm-su-from (car vm-message-pointer)))
	 (displayed-author author)
	 (bookmark (if (vm-virtual-message-p (car vm-message-pointer))
		       (vm-real-message-of (car vm-message-pointer))
		     (car vm-message-pointer))))
    (if (equal author "")
	(setq author "^$"
	      displayed-author "<none>")
      (setq author (regexp-quote author)))
    (vm-create-virtual-folder
     'author author nil
     (vm-virtual-folder-name (buffer-name) 'author displayed-author)
     bookmark)))

;;;###autoload
(defun vm-create-virtual-folder-same-recipient ()
  "Create a virtual folder (search folder) for all messages that have
as a recipient the `To' addressee as the current message. If there are
multiple addressees, only the first one is chosen."
  (interactive)
  (vm-follow-summary-cursor)
  (vm-select-folder-buffer-and-validate 1 (vm-interactive-p))
   ;;  to be modified
  (let* ((recipient (car (vm-parse (vm-su-to (car vm-message-pointer))
				   "\\([^,]*\\)\\(, \\)?" 1 1)))
	 (displayed-recipient recipient)
	 (bookmark (if (vm-virtual-message-p (car vm-message-pointer))
		       (vm-real-message-of (car vm-message-pointer))
		     (car vm-message-pointer))))
    (if (equal recipient "")
	(setq recipient "^$"
	      displayed-recipient "<none>")
      (setq recipient (regexp-quote recipient)))
    ;; end of to be modified
    (vm-create-virtual-folder
     'author-or-recipient recipient nil
     (vm-virtual-folder-name (buffer-name) 'author-or-recipient
			     displayed-recipient) 
     bookmark)))

;;;###autoload
(defun vm-create-author-virtual-folder (&optional string read-only name)
  "Create a virtual folder (search folder) of messages with the given
string in the author's name/address, from the current folder.

Prefix arg means the new virtual folder should be visited read only."
  (interactive
   (let ((last-command last-command)
	 (this-command this-command)
	 (prefix current-prefix-arg))
     (vm-select-folder-buffer)
     (list (read-string "Virtual folder of author: ")
	   prefix)))
  (vm-create-virtual-folder 'author string read-only name))

;;;###autoload
(defun vm-create-author-or-recipient-virtual-folder 
  			(&optional string read-only name)
  "Create a virtual folder (search folder) of messages with the given
string in the name/address of the author or recipients, from the
current folder.  

Prefix arg means the new virtual folder should be visited read only."
  (interactive
   (let ((last-command last-command)
	 (this-command this-command)
	 (prefix current-prefix-arg))
     (vm-select-folder-buffer)
     (list (read-string "Virtual folder of author/recipient: ")
	   prefix)))
  (vm-create-virtual-folder 'author-or-recipient string read-only name))

;;;###autoload
(defun vm-create-subject-virtual-folder (&optional string read-only subject)
  "Create a virtual folder (search folder) with given subject from
messages in the current folder. 

Prefix arg means the new virtual folder should be visited read only."
  (interactive
   (let ((last-command last-command)
	 (this-command this-command)
	 (prefix current-prefix-arg))
     (vm-select-folder-buffer)
     (list (read-string "Virtual folder of subject: ")
	   prefix)))
  (vm-create-virtual-folder 'subject string read-only subject))

;;;###autoload
(defun vm-create-text-virtual-folder (&optional string read-only subject)
  "Create a virtual folder (search folder) of all messsages with the
given string in its text.

Prefix arg means the new virtual folder should be visited read only."
  (interactive
   (let ((last-command last-command)
	 (this-command this-command)
	 (prefix current-prefix-arg))
     (vm-select-folder-buffer)
     (list (read-string "Virtual folder for text string: ")
	   prefix)))
  (vm-create-virtual-folder 'text string read-only subject))

;;;###autoload
(defun vm-create-date-virtual-folder (&optional arg read-only subject)
  "Create a virtual folder (search folder) of all messsages with date
in given range.

Prefix arg means the new virtual folder should be visited read only."
  (interactive
   (let ((last-command last-command)
	 (this-command this-command)
	 (prefix current-prefix-arg))
     (vm-select-folder-buffer)
     (list (read-number "Virtual folder of date in days: ")
	   prefix)))
  (vm-create-virtual-folder 'newer-than arg read-only subject))

;;;###autoload
(defun vm-create-label-virtual-folder (&optional arg read-only name)
  "Create a virtual folder with given label from messages in the
current folder.

Prefix arg means the new virtual folder should be visited read only."
  (interactive
   (let ((last-command last-command)
	 (this-command this-command)
	 (prefix current-prefix-arg))
     (vm-select-folder-buffer)
     (list (vm-read-string "Virtual folder of label: "
			   (vm-obarray-to-string-list vm-label-obarray))
	   prefix)))
  (vm-create-virtual-folder 'label arg read-only name))

;;;###autoload
(defun vm-create-flagged-virtual-folder (&optional read-only name)
  "Create a virtual folder (search folder) with all the flagged
messages in the current folder.

Prefix arg means the new virtual folder should be visited read only."
  (interactive
   (let ((last-command last-command)
	 (this-command this-command)
	 (prefix current-prefix-arg))
     (vm-select-folder-buffer)
     (list prefix)))
  (vm-create-virtual-folder 'flagged read-only name))

;;;###autoload
(defun vm-create-new-virtual-folder (&optional read-only name)
  "Create a virtual folder (search folder) of all newly received
messages in the current folder.

Prefix arg means the new virtual folder should be visited read only."
  (interactive
   (let ((last-command last-command)
	 (this-command this-command)
	 (prefix current-prefix-arg))
     (vm-select-folder-buffer)
     (list prefix)))
  (vm-create-virtual-folder 'new read-only name))

;;;###autoload
(defun vm-create-unseen-virtual-folder (&optional read-only name)
  "Create a virtual folder (search folder) of all unseen from messages in the
current folder.

Prefix arg means the new virtual folder should be visited read only."
  (interactive
   (let ((last-command last-command)
	 (this-command this-command)
	 (prefix current-prefix-arg))
     (vm-select-folder-buffer)
     (list prefix)))
  (vm-create-virtual-folder 'unseen read-only name))


(defun vm-toggle-virtual-mirror ()
  (interactive)
  (vm-select-folder-buffer-and-validate 0 (vm-interactive-p))
  (if (not (eq major-mode 'vm-virtual-mode))
      (error "This is not a virtual folder."))
  (let ((mp vm-message-list)
	(inhibit-quit t)
	modified undo-list)
    (setq undo-list vm-saved-undo-record-list
	  vm-saved-undo-record-list vm-undo-record-list
	  vm-undo-record-list undo-list
	  vm-undo-record-pointer undo-list)
    (setq modified vm-saved-buffer-modified-p
	  vm-saved-buffer-modified-p (buffer-modified-p))
    (set-buffer-modified-p modified)
    (if vm-virtual-mirror
	(while mp
	  (vm-set-attributes-of
	   (car mp) (or (vm-saved-virtual-attributes-of (car mp))
			(make-vector vm-attributes-vector-length nil)))
	  (vm-set-mirror-data-of
	   (car mp) (or (vm-saved-virtual-mirror-data-of (car mp))
			(make-vector vm-mirror-data-vector-length nil)))
	  (vm-mark-for-summary-update (car mp) t)
	  (setq mp (cdr mp)))
      (while mp
	;; mark for summary update _before_ we set this message to
	;; be mirrored.  this will prevent the real message and
	;; the other messages that will share attributes with
	;; this message from having their summaries
	;; updated... they don't need it.
	(vm-mark-for-summary-update (car mp) t)
	(vm-set-saved-virtual-attributes-of
	 (car mp) (vm-attributes-of (car mp)))
	(vm-set-saved-virtual-mirror-data-of
	 (car mp) (vm-mirror-data-of (car mp)))
	(vm-set-attributes-of
	 (car mp) (vm-attributes-of (vm-real-message-of (car mp))))
	(vm-set-mirror-data-of
	 (car mp) (vm-mirror-data-of (vm-real-message-of (car mp))))
	(setq mp (cdr mp))))
    (setq vm-virtual-mirror (not vm-virtual-mirror))
    (vm-increment vm-modification-counter))
  (vm-update-summary-and-mode-line)
  (vm-inform 5 "Virtual folder now %s the underlying real folder%s."
	   (if vm-virtual-mirror "mirrors" "does not mirror")
	   (if (cdr vm-real-buffers) "s" "")))

;;;###autoload
(defun vm-virtual-help ()
(interactive)
  (vm-display nil nil '(vm-virtual-help) '(vm-virtual-help))
  (vm-inform 0 "VV = visit, VX = apply selectors, VC = create, VM = toggle virtual mirror"))

(defun vm-vs-or (m &rest selectors)
  "Virtual selector combinator for checking the disjunction of the
given SELECTORS."
  (let ((result nil) selector arglist function)
    (while selectors
      (setq selector (car (car selectors))
	    function (cdr (assq selector vm-virtual-selector-function-alist)))
      (if (null function)
	  (vm-warn 0 2 "Invalid virtual selector: %s" selector)
	(setq arglist (cdr (car selectors))
	      result (apply function m arglist)))
      (setq selectors (if result nil (cdr selectors))))
    result ))

(defun vm-vs-and (m &rest selectors)
  "Virtual selector combinator for checking the conjunction of the
given SELECTORS."
  (let ((result t) selector arglist function)
    (while selectors
      (setq selector (car (car selectors))
	    function (cdr (assq selector vm-virtual-selector-function-alist)))
      (if (null function)
	  (vm-warn 0 2 "Invalid virtual selector: %s" selector)
	(setq arglist (cdr (car selectors))
	      result (apply function m arglist)))
      (setq selectors (if (null result) nil (cdr selectors))))
    result ))

(defun vm-vs-not (m selector)
  "Virtual selector combinator for checking the negation of the
given SELECTOR."
  (let ((selector (car selector))
	(selectorlist (cdr selector))
	function
	(result nil))
    (setq function (cdr (assq selector vm-virtual-selector-function-alist)))
    (if (null function)
	(vm-warn 0 2 "Invalid virtual selector: %s" selector)
      (setq result (not (apply function m selectorlist))))
    result))

(defun vm-vs-sexp (m expression)
  "Virtual selector combinator to check a complex EXPRESSION made
of other selectors."
  (vm-vs-and m expression))

(defun vm-vs-eval (&rest selectors)
  "Virtual selector to check if a message satisfies a condition given
by a Lisp EXPRESSION.  The EXPRESSION should use the variable
`vm-virtual-message' to refer to the message being checked."
  (let ((vm-virtual-message (car selectors)))
    (eval (cadr selectors))))

(defun vm-vs-any (_m) 
  "Virtual selector that always selects any message."
  t)

(defun vm-vs-thread (m selector)
  "Virtual selector combinator to check a given SELECTOR holds for any
message in a thread."
  (let ((selector (car selector))
	(selectorlist (cdr selector))
	(root (vm-thread-root m))
	tree function)
    (setq tree (vm-thread-subtree-safe root))
    (setq function (cdr (assq selector vm-virtual-selector-function-alist)))
    (vm-find tree
	     (lambda (m)
	       (apply function m selectorlist)))))

(defun vm-vs-thread-all (m selector)
  "Virtual selector combinator to check a given SELECTOR holds for all
messages in a thread."
  (let ((selector (car selector))
	(selectorlist (cdr selector))
	(root (vm-thread-root m))
	tree function)
    (setq tree (vm-thread-subtree-safe root))
    (setq function (cdr (assq selector vm-virtual-selector-function-alist)))
    (vm-for-all tree
	     (lambda (m)
	       (apply function m selectorlist)))))

(defun vm-vs-author (m regexp)
  "Virtual selector to check if the author matches REGEXP."
  (or (string-match regexp (vm-su-full-name m))
      (string-match regexp (vm-su-from m))))

(defun vm-vs-recipient (m regexp)
  "Virtual selector to check if any recipient of the message matches REGEXP."
  (or (string-match regexp (vm-su-to-cc m))
      (string-match regexp (vm-su-to-cc-names m))))

(defun vm-vs-addressee (m regexp)
  "Virtual selector to check if any addressee of the message matches REGEXP."
  (or (string-match regexp (vm-su-to m))
      (string-match regexp (vm-su-to-names m))))

(defun vm-vs-principal (m regexp)
  "Virtual selector to check if the principal of the message (the
\"Reply-To\" header) matches REGEXP."
  (or (string-match regexp (vm-su-reply-to m))
      (string-match regexp (vm-su-reply-to-name m))))

(defun vm-vs-author-or-recipient (m regexp)
  "Virtual selector to check if the author or any of the recipients of
the message matches REGEXP."
  (or (vm-vs-author m regexp)
      (vm-vs-recipient m regexp)))

(defun vm-vs-subject (m regexp)
  "Virtual selector to check if the subject of the message matches REGEXP."
  (string-match regexp (vm-su-subject m)))

(defun vm-vs-sortable-subject (m regexp)
  "Virtual selector to check if the subject of the message, as used
for sorting summary lines, matches REGEXP.  This differs from the
actual subject string in that it ignores prefixes, suffixes or
insignificant characters.  (See `vm-subject-ignored-prefix',
`vm-subject-ignored-suffix', `vm-subject-tag-prefix',
`vm-subject-tag-prefix-exceptions' and `vm-subject-significant-chars')" 
  (string-match regexp (vm-so-sortable-subject m)))

(defun vm-vs-sent-before (m date)
  "Virtual selector to check if the date of the message was earlier
than a given DATE.  The DATE is specified in the format
          \"31 Dec 1999 23:59:59 GMT\"
but you can leave out any part of it to get a sensible default."
  (condition-case _error
      (string< (vm-so-sortable-datestring m)
	       (vm-timezone-make-date-sortable date))
    (error t)))

(defun vm-vs-sent-after (m date)
  "Virtual selector to check if the date of the message was earlier
than a given DATE.  The DATE is specified in the format
          \"31 Dec 1999 23:59:59 GMT\"
but you can leave out any part of it to get a sensible default."
  (condition-case _error
      (string< (vm-timezone-make-date-sortable date)
	       (vm-so-sortable-datestring m))
    	(error t)))

(defun vm-vs-older-than (m days)
  "Virtual selector to check if the date of the message was at least
given DAYS ago.  (Today is considered 0 days ago, and yesterday is
1 day ago.)"
  (let ((date (vm-su-datestring m)))
    (condition-case _error
        (> (days-between (current-time-string) date) days)
      (error t))))

(defun vm-vs-newer-than (m days)
  "Virtual selector to check if the date of the message was at most
given DAYS ago.  (Today is considered 0 days ago, and yesterday is
1 day ago.)"
  (let ((date (vm-su-datestring m)))
    (condition-case _error
        (<= (days-between (current-time-string) date) days)
      (error t))))

(defun vm-vs-outgoing (m)
  "Virtual selector to check if the message is an outgoing message,
i.e., sent by the user of this VM."
  (and vm-summary-uninteresting-senders
       (or (string-match vm-summary-uninteresting-senders (vm-su-full-name m))
           (string-match vm-summary-uninteresting-senders (vm-su-from m)))))

(defun vm-vs-uninteresting-senders (m)
  "Virtual selector to check of the sender is an \"uninteresting\"
sender.  (See `vm-summary-uninteresting-senders'.)"
  (string-match vm-summary-uninteresting-senders
                (vm-get-header-contents m "From:")))

(defun vm-vs-attachment (m)
  "Virtual selector to check if the message has an attachment.

Note that the message should have been loaded from external source (if
any) for it to match this selector."
  (or (vm-attachments-flag m)
      (vm-vs-text m vm-vs-attachment-regexp)))

(defun vm-vs-spam-word (m &optional part)
  "Virtual selector to check if the message has a spam word in the
given message PART (which can be \"header\", \"text\" or
\"header-or-text\".  Spam words are those loaded from the
`vm-spam-words-file'.

Note that the message should have been loaded from external source (if
any) for this selector to detect the occurrences in the text."
  (if (and (not vm-spam-words)
           vm-spam-words-file
           (file-readable-p vm-spam-words-file)
           (not (get-file-buffer vm-spam-words-file)))
      (with-current-buffer (find-file-noselect vm-spam-words-file)
        (goto-char (point-min))
        (while (re-search-forward "^\\s-*\\([^#;].*\\)\\s-*$" (point-max) t)
          (setq vm-spam-words (cons (match-string 1) vm-spam-words)))
        (setq vm-spam-words-regexp (regexp-opt vm-spam-words))))
  (if (and m vm-spam-words-regexp)
      (let ((case-fold-search t))
        (cond ((eq part 'header)
               (vm-vs-header m vm-spam-words-regexp))
              ((eq part 'header-or-text)
               (vm-vs-header-or-text m vm-spam-words-regexp))
              (t
               (vm-vs-text m vm-spam-words-regexp))))))

(defun vm-vs-spam-score (m min &optional max)
  "Virtual selector to check if the spam score is >= MIN and
optionally <= MAX.  The headers that will be checked are those
listed in `vm-vs-spam-score-headers'."
  (let ((spam-headers vm-vs-spam-score-headers)
        it-is-spam)
    (while spam-headers
      (let* ((spam-selector (car spam-headers))
             (score (vm-get-header-contents m (car spam-selector))))
        (when (and score (string-match (nth 1 spam-selector) score))
          (setq score (funcall (nth 2 spam-selector) (match-string 0 score)))
          (if (and (<= min score) (or (null max) (<= score max)))
              (setq it-is-spam t spam-headers nil))))
      (setq spam-headers (cdr spam-headers)))
    it-is-spam))

(defun vm-vs-header (m regexp)
  "Virtual selector to check if any header contains an instance of REGEXP."
  (with-current-buffer (vm-buffer-of (vm-real-message-of m))
    (save-excursion
      (save-restriction
	(widen)
	(goto-char (vm-headers-of (vm-real-message-of m)))
	(re-search-forward regexp (vm-text-of (vm-real-message-of m)) t)))))

(defun vm-vs-header-field (m field regexp)
  "Virtual selector to check if the given header FIELD contains
an instance of REGEXP."
  (let ((header (vm-get-header-contents m field)))
    (string-match regexp header)))

(defun vm-vs-uid (m arg)
  "Virtual selector to check if the message UID is ARG."
  (equal (vm-imap-uid-of m) arg))

(defun vm-vs-uidl (m arg)
  "Virtual selector to check if the message UIDL is ARG."
  (equal (vm-pop-uidl-of m) arg))

(defun vm-vs-message-id (m regexp)
  "Virtual selector to check if the message id contains an instance of
REGEXP."
  (string-match regexp (vm-su-message-id m)))

(defun vm-vs-label (m arg)
  "Virtual selector to check of ARG is a label of the message."
  (member arg (vm-decoded-labels-of m)))

(defun vm-vs-text (m regexp)
  "Virtual selector to check if the body of the message has an
instance of REGEXP.

Note that the message should have been loaded from external source (if
any) for it to match this selector."
  (with-current-buffer (vm-buffer-of (vm-real-message-of m))
    (save-excursion
      (save-restriction
	(widen)
	(goto-char (vm-text-of (vm-real-message-of m)))
	(re-search-forward regexp (vm-text-end-of (vm-real-message-of m)) t)))))

(defun vm-vs-header-or-text (m regexp)
  "Virtual selector to check if either the header or the body of
the message has an instance of REGEXP.

Note that the message should have been loaded from external source (if
any) for the selector to detect occurrences in the text."
  (with-current-buffer (vm-buffer-of (vm-real-message-of m))
    (save-excursion
      (save-restriction
	(widen)
	(goto-char (vm-headers-of (vm-real-message-of m)))
	(re-search-forward regexp (vm-text-end-of (vm-real-message-of m)) t)))))

(defun vm-vs-more-chars-than (m arg)
  "Virtual selector to check if the message size in characters is more
than ARG."
  (> (string-to-number (vm-su-byte-count m)) arg))

(defun vm-vs-less-chars-than (m arg)
  "Virtual selector to check if the message size in characters is less
than ARG."
  (< (string-to-number (vm-su-byte-count m)) arg))

(defun vm-vs-more-lines-than (m arg)
  "Virtual selector to check if the message size in lines is more
than ARG."
  (> (string-to-number (vm-su-line-count m)) arg))

(defun vm-vs-less-lines-than (m arg)
  "Virtual selector to check if the message size in lines is less
than ARG."
  (< (string-to-number (vm-su-line-count m)) arg))

(defun vm-vs-virtual-folder-member (m)
  "Virtual selector to check if the message is a member of any virtual
folders currently being viewed."
  (vm-virtual-messages-of m))

(defun vm-vs-new (m) (vm-new-flag m))
(fset 'vm-vs-recent 'vm-vs-new)
(defun vm-vs-unread (m) (vm-unread-flag m))
(fset 'vm-vs-unseen 'vm-vs-unread)
(defun vm-vs-read (m) (not (or (vm-new-flag m) (vm-unread-flag m))))
(defun vm-vs-flagged (m) (vm-flagged-flag m))
(defun vm-vs-unflagged (m) (not (vm-flagged-flag m)))
(defun vm-vs-deleted (m) (vm-deleted-flag m))
(defun vm-vs-replied (m) (vm-replied-flag m))
(fset 'vm-vs-answered 'vm-vs-replied)
(defun vm-vs-forwarded (m) (vm-forwarded-flag m))
(defun vm-vs-redistributed (m) (vm-redistributed-flag m))
(defun vm-vs-filed (m) (vm-filed-flag m))
(defun vm-vs-written (m) (vm-written-flag m))
(defun vm-vs-marked (m) (vm-mark-of m))
(defun vm-vs-edited (m) (vm-edited-flag m))

(defun vm-vs-undeleted (m) (not (vm-deleted-flag m)))
(defun vm-vs-unreplied (m) (not (vm-replied-flag m)))
(fset 'vm-vs-unanswered 'vm-vs-unreplied)
(defun vm-vs-unforwarded (m) (not (vm-forwarded-flag m)))
(defun vm-vs-unredistributed (m) (not (vm-redistributed-flag m)))
(defun vm-vs-unfiled (m) (not (vm-filed-flag m)))
(defun vm-vs-unwritten (m) (not (vm-written-flag m)))
(defun vm-vs-unmarked (m) (not (vm-mark-of m)))
(defun vm-vs-unedited (m) (not (vm-edited-flag m)))
(defun vm-vs-expanded (m) (vm-expanded-root-p m))
(defun vm-vs-collapsed (m) (vm-collapsed-root-p m))


(put 'sexp 'vm-virtual-selector-clause "matching S-expression selector")
(put 'eval 'vm-virtual-selector-clause "giving true for expression")
(put 'header 'vm-virtual-selector-clause "with header matching")
(put 'label 'vm-virtual-selector-clause "with label of")
(put 'uid 'vm-virtual-selector-clause "with IMAP UID of")
(put 'uidl 'vm-virtual-selector-clause "with POP UIDL of")
(put 'message-id 'vm-virtual-selector-clause "with Message ID of")
(put 'text 'vm-virtual-selector-clause "with text matching")
(put 'header-or-text 'vm-virtual-selector-clause
     "with header or text matching")
(put 'recipient 'vm-virtual-selector-clause "with recipient matching")
(put 'addressee 'vm-virtual-selector-clause "with addressee matching")
(put 'principal 'vm-virtual-selector-clause "with principal matching")
(put 'author-or-recipient 'vm-virtual-selector-clause
     "with author or recipient matching")
(put 'author 'vm-virtual-selector-clause "with author matching")
(put 'subject 'vm-virtual-selector-clause "with subject matching")
(put 'sent-before 'vm-virtual-selector-clause "sent before")
(put 'sent-after 'vm-virtual-selector-clause "sent after")
(put 'older-than 'vm-virtual-selector-clause "days older than")
(put 'newer-than 'vm-virtual-selector-clause "days newer than")
(put 'more-chars-than 'vm-virtual-selector-clause
     "with more characters than")
(put 'less-chars-than 'vm-virtual-selector-clause
     "with less characters than")
(put 'more-lines-than 'vm-virtual-selector-clause "with more lines than")
(put 'less-lines-than 'vm-virtual-selector-clause "with less lines than")

(put 'sexp 'vm-virtual-selector-arg-type 'string)
(put 'eval 'vm-virtual-selector-arg-type 'string)
(put 'header 'vm-virtual-selector-arg-type 'string)
(put 'label 'vm-virtual-selector-arg-type 'label)
(put 'uid 'vm-virtual-selector-arg-type 'string)
(put 'uidl 'vm-virtual-selector-arg-type 'string)
(put 'message-id 'vm-virtual-selector-arg-type 'string)
(put 'text 'vm-virtual-selector-arg-type 'string)
(put 'header-or-text 'vm-virtual-selector-arg-type 'string)
(put 'recipient 'vm-virtual-selector-arg-type 'string)
(put 'addressee 'vm-virtual-selector-arg-type 'string)
(put 'principal 'vm-virtual-selector-arg-type 'string)
(put 'author-or-recipient 'vm-virtual-selector-arg-type 'string)
(put 'author 'vm-virtual-selector-arg-type 'string)
(put 'subject 'vm-virtual-selector-arg-type 'string)
(put 'sent-before 'vm-virtual-selector-arg-type 'string)
(put 'sent-after 'vm-virtual-selector-arg-type 'string)
(put 'older-than 'vm-virtual-selector-arg-type 'number)
(put 'newer-than 'vm-virtual-selector-arg-type 'number)
(put 'more-chars-than 'vm-virtual-selector-arg-type 'number)
(put 'less-chars-than 'vm-virtual-selector-arg-type 'number)
(put 'more-lines-than 'vm-virtual-selector-arg-type 'number)
(put 'less-lines-than 'vm-virtual-selector-arg-type 'number)
(put 'spam-score 'vm-virtual-selector-arg-type 'number)

;;;###autoload
(defun vm-read-virtual-selector (prompt)
  (let (selector (arg nil))
    (setq selector
	  (vm-read-string prompt vm-supported-interactive-virtual-selectors)
	  selector (intern selector))
    (let ((arg-type (get selector 'vm-virtual-selector-arg-type)))
      (if (null arg-type)
	  nil
	(setq prompt (concat (substring prompt 0 -2) " "
			     (get selector 'vm-virtual-selector-clause)
			     ": "))
	(raise-frame (selected-frame))
	(cond ((eq arg-type 'number)
	       (setq arg (vm-read-number prompt)))
	      ((eq arg-type 'label)
	       (let ((vm-completion-auto-correct nil)
		     (completion-ignore-case t))
		 (setq arg (downcase
			    (vm-read-string
			     prompt
			     (vm-obarray-to-string-list
			      vm-label-obarray)
			     nil)))))
	      (t (setq arg (read-string prompt))))))
    (let ((real-arg
	   (if (or (eq selector 'sexp) (eq selector 'eval))
	       (let ((read-arg (read arg)))
		 (if (listp read-arg) read-arg (list read-arg)))
	     arg)))
      (or (fboundp (intern (concat "vm-vs-" (symbol-name selector))))
	  (error "Invalid selector"))
      (list selector real-arg))))


;;;###autoload
(defun vm-virtual-quit (&optional no-expunge no-change)
  "Clear away links between real and virtual folders when a
`vm-quit' is performed in the current folder (which could be either
real or virtual)."
  (save-excursion
    (cond ((eq major-mode 'vm-virtual-mode)
	   ;; don't trust blindly, user might have killed some of
	   ;; these buffers.
	   (setq vm-component-buffers 
		 (vm-delete (lambda (pair)
			      (buffer-name (car pair)))
			    vm-component-buffers t))
	   (setq vm-real-buffers 
		 (vm-delete 'buffer-name vm-real-buffers t))
	   (let ((b (current-buffer))
		 (mirrored-msg nil)
		 (real-msg nil)
		 ;; lock out interrupts here
		 (inhibit-quit t))
	     ;; Move the message-pointer of the original buffer to the
	     ;; current message in the virtual folder
	     (setq mirrored-msg (and vm-message-pointer
				     (vm-mirrored-message-of 
				      (car vm-message-pointer))))
	     (when (and mirrored-msg (not no-change) 
			(vm-buffer-of mirrored-msg))
	       (with-current-buffer (vm-buffer-of mirrored-msg)
		 (vm-record-and-change-message-pointer
		  vm-message-pointer (vm-message-position mirrored-msg)
		  :present t)))
	     (dolist (real-buf vm-real-buffers)
	       (with-current-buffer real-buf
		 (setq vm-virtual-buffers (delq b vm-virtual-buffers))))
	     (dolist (m vm-message-list)
	       (setq real-msg (vm-real-message-of m))
	       (vm-set-virtual-messages-of
		real-msg (delq m (vm-virtual-messages-of real-msg))))
	     (condition-case error-data
		 (dolist (pair vm-component-buffers)
		   (when (cdr pair)
		     (with-current-buffer (car pair)
		       ;; Use dynamic bindings from vm-quit
		       (let ((vm-verbosity (1- vm-verbosity)))
			 (vm-quit no-expunge no-change)))))
	       (error 
		(vm-warn 0 2 "Unable to quit component folders: %s"
			 (prin1-to-string error-data))))))

	  ((eq major-mode 'vm-mode)
	   ;; don't trust blindly, user might have killed some of
	   ;; these buffers.
	   (setq vm-virtual-buffers
		 (vm-delete 'buffer-name vm-virtual-buffers t))
	   (let (vmp
		 (b (current-buffer))
		 ;; lock out interrupts here
		 (inhibit-quit t))
	     (dolist (m vm-message-list)
	       ;; we'll clear these messages from the virtual
	       ;; folder by looking for messages that have a "Q"
	       ;; id number associated with them.
	       (when (vm-virtual-messages-of m)
		 (dolist (v-m (vm-virtual-messages-of m))
		   (vm-set-message-id-number-of v-m "Q"))
		 (vm-unthread-message-and-mirrors m :message-changing nil)
		 (vm-set-virtual-messages-of m nil)))
	     (dolist (virtual-buf vm-virtual-buffers)
	       (set-buffer virtual-buf)
	       (setq vm-real-buffers (delq b vm-real-buffers))
	       ;; set the message pointer to a new value if it is
	       ;; now invalid.
	       (when (and vm-message-pointer
			  (equal "Q" (vm-message-id-number-of
				      (car vm-message-pointer))))
		 (vm-garbage-collect-message)
		 (setq vmp vm-message-pointer)
		 (while (and vm-message-pointer
			     (equal "Q" (vm-message-id-number-of
					 (car vm-message-pointer))))
		   (setq vm-message-pointer
			 (cdr vm-message-pointer)))
		 ;; if there were no good messages ahead, try going
		 ;; backward.
		 (unless vm-message-pointer
		   (setq vm-message-pointer vmp)
		   (while (and vm-message-pointer
			       (equal "Q" (vm-message-id-number-of
					   (car vm-message-pointer))))
		     (setq vm-message-pointer
			   (vm-reverse-link-of (car vm-message-pointer))))))
	       ;; expunge the virtual messages associated with
	       ;; real messages that are going away.
	       (setq vm-message-list
		     (vm-delete (function
				 (lambda (m)
				   (equal "Q" (vm-message-id-number-of m))))
				vm-message-list nil))
	       (if (null vm-message-pointer)
		   (setq vm-message-pointer vm-message-list))
	       ;; same for vm-last-message-pointer
	       (if (null vm-last-message-pointer)
		   (setq vm-last-message-pointer nil))
	       (vm-clear-virtual-quit-invalidated-undos)
	       (vm-reverse-link-messages)
	       (vm-set-numbering-redo-start-point t)
	       (vm-set-summary-redo-start-point t)
	       (if vm-message-pointer
		   (vm-present-current-message)
		 (vm-update-summary-and-mode-line))))))))

;;;###autoload
(defun vm-virtual-save-folder (prefix)
  (save-excursion
    ;; don't trust blindly, user might have killed some of
    ;; these buffers.
    (setq vm-real-buffers (vm-delete 'buffer-name vm-real-buffers t))
    (dolist (real-buf vm-real-buffers)
	(set-buffer real-buf)
	(vm-save-folder prefix)))
  (vm-unmark-folder-modified-p (current-buffer)) 
  (vm-clear-modification-flag-undos)
  (vm-update-summary-and-mode-line))

;;;###autoload
(defun vm-virtual-get-new-mail ()
  (save-excursion
    ;; don't trust blindly, user might have killed some of
    ;; these buffers.
    (setq vm-real-buffers (vm-delete 'buffer-name vm-real-buffers t))
    (dolist (real-buf vm-real-buffers)
      (set-buffer real-buf)
      (condition-case _error-data
	  (vm-get-new-mail)
	;; handlers
	(folder-read-only
	 (vm-warn 0 1 "Folder is read only: %s"
		  (or buffer-file-name (buffer-name))))
	(unrecognized-folder-type
	 (vm-warn 0 1 "Folder type is unrecognized: %s"
		  (or buffer-file-name (buffer-name)))))))
  (vm-emit-totals-blurb))

;;;###autoload
(defun vm-make-virtual-copy (m)
  "Copy of the real message of the virtual message M in the current
folder buffer (which should be the virtual folder in which M occurs)."
  (widen)
  (let ((virtual-buffer (current-buffer))
	(real-m (vm-real-message-of m))
	(buffer-read-only nil)
	(modified (buffer-modified-p)))
    (unwind-protect
	(with-current-buffer (vm-buffer-of real-m)
	  (save-restriction
	    (widen)
	    ;; must reference this now so that headers will be in
	    ;; their final position before the message is copied.
	    ;; otherwise the vheader offset computed below will be wrong.
	    (vm-vheaders-of real-m)
	    (copy-to-buffer virtual-buffer (vm-start-of real-m)
			    (vm-end-of real-m))))
      (set-buffer-modified-p modified))
    (set-marker (vm-start-of m) (point-min))
    (set-marker (vm-headers-of m) (+ (vm-start-of m)
				     (- (vm-headers-of real-m)
					(vm-start-of real-m))))
    (set-marker (vm-vheaders-of m) (+ (vm-start-of m)
				      (- (vm-vheaders-of real-m)
					 (vm-start-of real-m))))
    (set-marker (vm-text-of m) (+ (vm-start-of m) (- (vm-text-of real-m)
						     (vm-start-of real-m))))
    (set-marker (vm-text-end-of m) (+ (vm-start-of m)
				      (- (vm-text-end-of real-m)
					 (vm-start-of real-m))))
    (set-marker (vm-end-of m) (+ (vm-start-of m) (- (vm-end-of real-m)
						    (vm-start-of real-m))))))
;; ;; now load vm-avirtual to avoid a loading loop
;; (require 'vm-avirtual)

(provide 'vm-virtual)
;;; vm-virtual.el ends here
