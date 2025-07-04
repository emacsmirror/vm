;;; vm-avirtual.el --- additional functions for virtual folder selectors  -*- lexical-binding: t; -*-
;;
;; This file is an add-on for VM
;; 
;; Copyright (C) 2000-2006 Robert Widhopf-Fenk
;; Copyright (C) 2024-2025 The VM Developers
;;
;; Author:      Robert Widhopf-Fenk
;; Status:      Tested with XEmacs 21.4.19 & VM 7.19
;; Keywords:    VM, virtual folders 
;; X-URL:       http://www.robf.de/Hacking/elisp

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

;;; Commentary:
;;
;; Virtual folders are one of the greatest features offered by VM, however
;; sometimes I do not want to visit a virtual folder in order to do something
;; on messages.  E.g. I have a virtual folder selector for spam messages and I
;; want VM to mark those messages matching the selector for deletion when
;; retrieving new messages.  This can be done with a trick described in
;; the VM-FAQ, however this created two new buffers polluting my buffer space.
;; So this package provides a function `vm-auto-delete-messages' for this
;; purpose without drawbacks. 
;; 
;; Then after I realized I was maintaining three different variables for
;; actually the same things.  They were `vm-auto-folder-alist' for automatic
;; selection of folders when saving messages, `vm-virtual-folder-alist' for my
;; loved virtual folders and `vmpc-conditions' in order to solve the handling
;; of my different email-addresses.
;;
;; This was kind of annoying, since virtual folder selectors offer the
;; best way of specifying conditions, but they only work on messages
;; within folders and not on messages which are currently being
;; composed. So I decided to extend virtual folder selectors also to
;; message composing, although not all of the selectors are meaningful
;; for `mail-mode'.
;;
;; I wrote functions which can replace (*) the existing ones and others that
;; add new (+) functionality.  Finally I came up with the following ones:
;;       * vm-virtual-auto-archive-messages 
;;       * vm-virtual-save-message 
;;       * vmpc-check-virtual-selector
;;       + vm-virtual-auto-delete-messages
;;       + vm-virtual-auto-delete-message
;;       + vm-virtual-omit-message
;;       + vm-virtual-update-folders
;;       + vm-virtual-apply-function
;; and the following variables
;;      vm-virtual-check-case-fold-search
;;      vm-virtual-auto-delete-message-selector
;;      vm-virtual-auto-folder-alist
;;      vm-virtual-message
;; and a couple of new selectors
;;      mail-mode       if in mail-mode evals its `argument' else `nil'
;;      vm-mode         if in vm-mode evals its `arg' else `nil'
;;      eval            evaluates its `arg' (write own complex selectors)
;;
;; So by using theses new features I can maintain just one selector for
;; e.g. my private email-address and get the right folder for saving messages,
;; visiting the corresponding virtual folders, auto archiving, setting the FCC
;; header and setting up `vmpc-conditions'.  Do you know a mailer than can
;; beat this?
;;
;; My default selector for spam messages:
;; 
;; ("spam" ("received")
;;  (vm-mode
;;   (and (new) (undeleted)
;;        (or
;;         ;; kill all those where all authors/recipients
;;         ;; are unknown to my BBDB, i.e. messages from
;;         ;; strangers who are not recognized by me.
;;         ;; (c't 12/2001) 
;;         (not (in-bbdb))
;;         ;; authors that I do not know
;;         (and (not (in-bbdb authors))
;;              (or
;;               ;;  with bad content
;;               (spam-word)
;;               ;; they hide ID codes by long subjects
;;               (subject "       ")
;;               ;; HTML only messages
;;               (header "^Content-Type: text/html")
;;               ;; for 8bit encoding "chinese" spam
;;               (header "[¡-ÿ][¡-ÿ][¡-ÿ][¡-ÿ]")
;;               ;; for qp-encoding "chinese" spam
;;               (header "=[A-F][0-9A-F]=[A-F][0-9A-F]=[A-F][0-9A-F]=[A-F][0-9A-F]=[A-F][0-9A-F]")
;;               ))))))
;;
;;; Feel free to send me any comments or bug reports.
;;
;;; Code:

(require 'vm-macro)
(require 'vm-vars)
(require 'vm-thread)

;; FIXME: Cyclic dependency, we can't require `vm-virtual'.
(declare-function vm-vs-spam-word "vm-virtual" (m &optional part))

(declare-function vm-get-folder-buffer "vm" (folder))
;; The following function is erroneously called for fsfemacs as well
(declare-function key-or-menu-binding "vm-xemacs" (key &optional menu-flag))
(declare-function bbdb-get-addresses "ext:bbdb-com"
		  (only-first-address 
		   uninteresting-senders 
		   get-header-content-function
		   &rest get-header-content-function-args))
(declare-function bbdb-search-simple "ext:bbdb" (name net))

; group already defined in vm-vars
;(defgroup vm nil
;  "VM"
;  :group 'mail)

(defgroup vm-avirtual nil
  "VM additional virtual folder selectors and functions."
  :group 'vm-ext)

;;----------------------------------------------------------------------------
(eval-and-compile
  (require 'vm-misc)
  (require 'regexp-opt)
  (require 'time-date)

  (vm-load-features '(bbdb bbdb-autoloads bbdb-com) byte-compile-current-file))

(defvar bbdb-get-addresses-headers)	; dummy declaration
(defvar bbdb-user-mail-names)
(defvar bbdb-get-only-first-address-p)

;;----------------------------------------------------------------------------
(defvar vm-mail-virtual-selector-function-alist
  '(;; standard selectors 
    (and . vm-mail-vs-and)
    (or . vm-mail-vs-or)
    (not . vm-mail-vs-not)
    (any . vm-mail-vs-any)
    (header . vm-mail-vs-header)
    (text . vm-mail-vs-text)
    (header-or-text . vm-mail-vs-header-or-text)
    (recipient . vm-mail-vs-recipient)
    (author . vm-mail-vs-author)
    (principal . vm-mail-vs-principal)
    (author-or-recipient . vm-mail-vs-author-or-recipient)
    (subject . vm-mail-vs-subject)
    (sortable-subject . vm-mail-vs-sortable-subject)
    (more-chars-than . vm-mail-vs-more-chars-than)
    (less-chars-than . vm-mail-vs-less-chars-than)
    (more-lines-than . vm-mail-vs-more-lines-than)
    (less-lines-than . vm-mail-vs-less-lines-than)
    (replied . vm-mail-vs-replied)
    (answered . vm-mail-vs-answered)
    (forwarded . vm-mail-vs-forwarded)
    (redistributed . vm-mail-vs-redistributed)
    (unreplied . vm-mail-vs-unreplied)
    (unanswered . vm-mail-vs-unanswered)
    (unforwarded . vm-mail-vs-unforwarded)
    (unredistributed . vm-mail-vs-unredistributed)

    ;; unknown selectors which return always nil
    (new . vm-mail-vs-unknown)
    (unread . vm-mail-vs-unknown)
    (read . vm-mail-vs-unknown)
    (unseen . vm-mail-vs-unknown)
    (recent . vm-mail-vs-unknown)
    (deleted . vm-mail-vs-unknown)
    (filed . vm-mail-vs-unknown)
    (written . vm-mail-vs-unknown)
    (edited . vm-mail-vs-unknown)
    (marked . vm-mail-vs-unknown)
    (undeleted . vm-mail-vs-unknown)
    (unfiled . vm-mail-vs-unknown)
    (unwritten . vm-mail-vs-unknown)
    (unedited . vm-mail-vs-unknown)
    (unmarked . vm-mail-vs-unknown)
    (expanded . vm-mail-vs-unknown)
    (collapsed . vm-mail-vs-unknown)
    (virtual-folder-member . vm-mail-vs-unknown)
    (label . vm-mail-vs-unknown)
    (sent-before . vm-mail-vs-unknown)
    (sent-after . vm-mail-vs-unknown)

    
    ;; new selectors 
    (mail-mode . vm-mail-vs-mail-mode)
    (vm-mode . vm-vs-vm-mode)
    (eval . vm-mail-vs-eval)
    (older-than . vm-mail-vs-older-than)
    (newer-than . vm-mail-vs-newer-than)
    (in-bbdb . vm-mail-vs-in-bbdb)
    ))

;;-----------------------------------------------------------------------------
(defun vm-avirtual-add-selectors (selectors)
  (let ((alist 'vm-virtual-selector-function-alist)
        (sup-alist 'vm-supported-interactive-virtual-selectors)
        sel)
    
    (while selectors
      (setq sel (car selectors))
      (add-to-list alist (cons sel (intern (format "vm-vs-%s" sel))))
      (add-to-list sup-alist (list (format "%s" sel)))
      (setq selectors (cdr selectors)))))

(vm-avirtual-add-selectors
 '(mail-mode 
   vm-mode 
   eval 
   selected 
   in-bbdb 
   folder-name 
   ))

;;-----------------------------------------------------------------------------
;; we redefine the basic selectors for some extra features ...

(defcustom vm-virtual-check-case-fold-search t
  "Whether to use case-fold-search or not when applying virtual selectors.
I was really missing this!"
  :type 'boolean
  :group 'vm-avirtual)

(defcustom vm-virtual-check-diagnostics nil
  "When set to nil we will display messages on matching selectors."
  :type 'boolean
  :group 'vm-avirtual)

(defvar vm-virtual-check-level 0)

(defun vm-vs-or (m &rest selectors)
  "Virtual selector combinator for checking the disjunction of the
given SELECTORS."
  (let ((case-fold-search vm-virtual-check-case-fold-search)
        (vm-virtual-check-level (+ 2 vm-virtual-check-level))
        (result nil) selector arglist function)
    (while selectors
      (setq selector (car (car selectors))
	    function (cdr (assq selector vm-virtual-selector-function-alist)))
      (if (null function)
	  (vm-warn 0 2 "Invalid virtual selector: %s" selector)
	(setq arglist (cdr (car selectors))
	      result (apply function m arglist))
	(if vm-virtual-check-diagnostics
	    (princ (format "%sor: %s (%S%s)\n" 
			   (make-string vm-virtual-check-level ? )
			   (if result t nil) selector
			   (if arglist (format " %S" arglist) "")))))
      (setq selectors (if result nil (cdr selectors))))
    result))

(defun vm-vs-and (m &rest selectors)
  "Virtual selector combinator for checking the conjunction of the
given SELECTORS."
  (let ((vm-virtual-check-level (+ 2 vm-virtual-check-level))
        (result t) selector arglist function)
    (while selectors
      (setq selector (car (car selectors))
	    function (cdr (assq selector vm-virtual-selector-function-alist)))
      (if (null function)
	  (vm-warn 0 2 "Invalid virtual selector: %s" selector)
	(setq arglist (cdr (car selectors))
	      result (apply function m arglist))
	(if vm-virtual-check-diagnostics
	    (princ (format "%sand: %s (%S%s)\n" 
			   (make-string vm-virtual-check-level ? )
			   (if result t nil) selector
			   (if arglist (format " %S" arglist) "")))))
      (setq selectors (if (null result) nil (cdr selectors))))
    result))

(defun vm-vs-not (m selector)
  "Virtual selector combinator for checking the negation of the
given SELECTOR."
  (let ((vm-virtual-check-level (+ 2 vm-virtual-check-level))
        (selector (car selector))
	(selectorlist (cdr selector))
        result function)
    (setq function (cdr (assq selector vm-virtual-selector-function-alist)))
    (if (null function)
	(vm-warn 0 2 "Invalid virtual selector: %s" selector)
      (setq result (apply function m selectorlist))
      (if vm-virtual-check-diagnostics
	  (princ (format "%snot: %s for (%S%s)\n"
			 (make-string vm-virtual-check-level ? )
			 (if result t nil) selector
			 (if selectorlist (format " %S" selectorlist) "")))))
    (not result)))

;;-----------------------------------------------------------------------------
;;;###autoload
(defun vm-avirtual-check-for-missing-selectors (&optional arg)
  "Check if there are selectors missing for either vm-mode or mail-mode."
  (interactive "P")
  (let ((a (if arg vm-mail-virtual-selector-function-alist
             vm-virtual-selector-function-alist))
        (b (mapcar (lambda (s) (car s))
                   (if arg vm-virtual-selector-function-alist
                     vm-mail-virtual-selector-function-alist)))
        l)
    (while a
      (if (not (memq (caar a) b))
          (setq l (concat (format "%s" (caar a)) ", " l)))
      (setq a (cdr a)))
    (if l
        (message "Selectors %s are missing" l)
      (message "No selectors are missing"))))

;;---------------------------------------------------------------------------
;; new virtual folder selectors
(defvar vm-virtual-message nil
  "Set to the VM message vector when doing a `vm-vs-eval'.")

(defun vm-vs-folder-name (m regexp)
  "Virtual selector to check if the current folder's name matches REGEXP."
  (setq m (vm-real-message-of m))
  (string-match regexp (buffer-name (marker-buffer (vm-start-of m)))))

(defun vm-vs-vm-mode (&rest selectors)
  (if (not (equal major-mode 'mail-mode))
      (apply 'vm-vs-or selectors)
    nil))

(defun vm-vs-selected (m)
  (save-excursion
    (vm-select-folder-buffer)
    (eq m (car vm-message-pointer))))

(defun vm-vs-in-bbdb (m &optional address-class only-first)
  "check if one of the email addresses in the message headers is known
in BBDB."
  (let (bbdb-user-mail-names)
    (let* ((bbdb-get-only-first-address-p only-first)
           (bbdb-user-mail-names nil)
           (bbdb-get-addresses-headers
            (if address-class
                (or (list (assoc address-class bbdb-get-addresses-headers))
                    (error "no such address class"))
              bbdb-get-addresses-headers))
           (addresses (bbdb-get-addresses nil nil
                                          'bbdb/vm-get-header-content
                                          (vm-real-message-of m)))
           (done nil)
           addr)
      (while (and (not done) addresses)
        (setq addr (caddar addresses)
              addresses (cdr addresses))
        (let ((name (car addr))
              (net  (cadr addr)))
          (setq done (or (bbdb-search-simple nil net)
                         (bbdb-search-simple name nil)))))
      done)))

(defun vm-mail-vs-in-bbdb (&optional address-class only-first)
  "check if one of the email addresses in the message headers is known
in BBDB."
  (let (bbdb-user-mail-names)
    (let* ((bbdb-get-only-first-address-p only-first)
           (bbdb-user-mail-names nil)
           (bbdb-get-addresses-headers
            (if address-class
                (or (list (assoc address-class bbdb-get-addresses-headers))
                    (error "no such address class"))
              bbdb-get-addresses-headers))
           (addresses (bbdb-get-addresses nil nil
                                          'vm-mail-mode-get-header-contents))
           (done nil)
           addr)
      (while (and (not done) addresses)
        (setq addr (caddar addresses)
              addresses (cdr addresses))
        (let ((name (car addr))
              (net  (cadr addr)))
          (setq done (or (bbdb-search-simple nil net)
                         (bbdb-search-simple name nil)))))
      done)))

;;;###autoload
(defun vm-add-spam-word (word)
  "Add a new WORD to the list of spam words."
  (interactive (list (if (region-active-p)
                         (buffer-substring (point) (mark))
                       (read-string "Spam word: "))))
  (save-excursion 
    (when (not (member word vm-spam-words))
      (if (get-file-buffer vm-spam-words-file)
          (set-buffer (get-file-buffer vm-spam-words-file))
        (set-buffer (find-file-noselect vm-spam-words-file)))
      (goto-char (point-max))
      ;; if the last character is no newline, then append one!
      (if (and (not (= (point) (point-min)))
               (save-excursion
                 (backward-char 1)
                 (not (looking-at "\n"))))
          (insert "\n"))
      (insert word)
      ;; FIXME Why not basic-save-buffer?
      (save-buffer)
      (setq vm-spam-words (cons word vm-spam-words))
      (setq vm-spam-words-regexp (regexp-opt vm-spam-words)))))

;;;###autoload
(defun vm-spam-words-rebuild ()
  "Discharge the internal cached data about spam words."
  (interactive)
  (setq vm-spam-words nil
        vm-spam-words-regexp nil)
  (if (get-file-buffer vm-spam-words-file)
      (kill-buffer (get-file-buffer vm-spam-words-file)))
  (vm-vs-spam-word nil)
  (vm-inform 5 "%d spam words are installed" (length vm-spam-words)))

;;---------------------------------------------------------------------------
;; new mail virtual folder selectors 

(defun vm-mail-vs-eval (&rest selectors)
  (eval (cadr selectors)))

(defun vm-mail-vs-mail-mode (&rest selectors)
  (if (equal major-mode 'mail-mode)
      (apply 'vm-mail-vs-or selectors)
    nil))

(defalias 'vm-vs-mail-mode 'vm-mail-vs-mail-mode)

(defun vm-mail-vs-or (&rest selectors)
  (let ((result nil) selector arglist
        (case-fold-search vm-virtual-check-case-fold-search))
    (while selectors
      (setq selector (car (car selectors))
            arglist (cdr (car selectors))
            result (apply (cdr (assq selector
                                     vm-mail-virtual-selector-function-alist))
                          arglist)
            selectors (if result nil (cdr selectors)))
      (if vm-virtual-check-diagnostics
          (princ (format "%sor: %s (%S%s)\n" 
                         (make-string vm-virtual-check-level ? )
                         (if result t nil) selector
                         (if arglist (format " %S" arglist) "")))))
    result))

(defun vm-mail-vs-and (&rest selectors)
  (let ((result t) selector arglist)
    (while selectors
      (setq selector (car (car selectors))
            arglist (cdr (car selectors))
            result (apply (cdr (assq selector
                                     vm-mail-virtual-selector-function-alist))
                          arglist)
            selectors (if (null result) nil (cdr selectors)))
      (if vm-virtual-check-diagnostics
          (princ (format "%sand: %s (%S%s)\n" 
                         (make-string vm-virtual-check-level ? )
                         (if result t nil) selector
                         (if arglist (format " %S" arglist) "")))))
    result))

(defun vm-mail-vs-not (arg)
  (let ((selector (car arg))
        (arglist (cdr arg))
        result)
    (setq result 
	  (apply 
	   (cdr (assq selector vm-mail-virtual-selector-function-alist))
	   arglist))
    (if vm-virtual-check-diagnostics
        (princ (format "%snot: %s for (%S%s)\n"
                       (make-string vm-virtual-check-level ? )
                       (if result t nil) selector
                       (if arglist (format " %S" arglist) ""))))
    (not result)))

;; return just nil for those selectors not known for mail-mode
(defun vm-mail-vs-unknown (&optional _arg)
  nil)

(defun vm-mail-vs-any ()
  t)

(defun vm-mail-vs-author (arg)
  (let ((val (vm-mail-mode-get-header-contents "Sender\\|From:")))
    (and val (string-match arg val))))

(defun vm-mail-vs-principal (arg)
  (let ((val (vm-mail-mode-get-header-contents "Reply-To:")))
    (and val (string-match arg val))))

(defun vm-mail-vs-recipient (arg)
  (let (val)
    (or
     (and (setq val (vm-mail-mode-get-header-contents "\\(Resent-\\)?To:"))
          (string-match arg val))
     (and (setq val (vm-mail-mode-get-header-contents "\\(Resent-\\)?CC:"))
          (string-match arg val))
     (and (setq val (vm-mail-mode-get-header-contents "\\(Resent-\\)?BCC:"))
          (string-match arg val)))))

(defun vm-mail-vs-author-or-recipient (arg)
  (or (vm-mail-vs-author arg)
      (vm-mail-vs-recipient arg)))

(defun vm-mail-vs-subject (arg)
  (let ((val (vm-mail-mode-get-header-contents "Subject:")))
    (and val (string-match arg val))))

(defun vm-mail-vs-sortable-subject (arg)
  (let ((case-fold-search t)
        (subject (vm-mail-mode-get-header-contents "Subject:")))
    (when subject
      (setq subject (vm-so-trim-subject subject))
      (string-match arg subject))))

(defun vm-mail-vs-header (arg)
  (save-excursion
    (let ((start (point-min)) end)
      (goto-char start)
      (search-forward (concat "\n" mail-header-separator "\n"))
      (setq end (match-beginning 0))
      (goto-char start)
      (re-search-forward arg end t))))

(defun vm-mail-vs-text (arg)
  (save-excursion
    (goto-char (point-min))
    (search-forward (concat "\n" mail-header-separator "\n"))
    (re-search-forward arg (point-max) t)))

(defun vm-mail-vs-header-or-text (arg)
  (save-excursion
    (goto-char (point-min))
    (re-search-forward arg (point-max) t)))

(defun vm-mail-vs-more-chars-than (arg)
  (> (- (point-max) (point-min) (length mail-header-separator) 2) arg))

(defun vm-mail-vs-less-chars-than (arg)
  (< (- (point-max) (point-min) (length mail-header-separator) 2) arg))

(defun vm-mail-vs-more-lines-than (arg)
  (> (- (count-lines (point-min) (point-max)) 1) arg))

(defun vm-mail-vs-less-lines-than (arg)
  (< (- (count-lines (point-min) (point-max)) 1) arg))

(defun vm-mail-vs-replied ()
  vm-reply-list)
(fset 'vm-mail-vs-answered 'vm-mail-vs-replied)

(defun vm-mail-vs-forwarded ()
  vm-forward-list)

(defun vm-mail-vs-redistributed ()
  (vm-mail-mode-get-header-contents "Resent-[^:]+:"))

(defun vm-mail-vs-unreplied ()
  (not (vm-mail-vs-forwarded )))
(fset 'vm-mail-vs-unanswered 'vm-mail-vs-unreplied)

(defun vm-mail-vs-unforwarded ()
  (not (vm-mail-vs-forwarded )))

(defun vm-mail-vs-unredistributed ()
  (not (vm-mail-vs-redistributed )))

(defun vm-mail-vs-older-than (arg)
  (let* ((date (vm-mail-mode-get-header-contents "Date:"))
         (days (and date (days-between (current-time-string) date))))
    (and days (> days arg))))

(defun vm-mail-vs-newer-than (arg)
  (let* ((date (vm-mail-mode-get-header-contents "Date:"))
         (days (and date (days-between (current-time-string) date))))
    (and days (<= days arg))))

;;----------------------------------------------------------------------------

(defun vm-virtual-folder-member-p (name folder-list)
  "Checks if the VM folder with NAME, currently loaded, is among
the folders listed in FOLDER-LIST."
  (let (buffer)
    (catch 'found
      (while folder-list
	(setq buffer (vm-get-folder-buffer (car folder-list)))
	(when (and buffer (buffer-name buffer)
		   (string-match name (buffer-name buffer)))
	  (throw 'found t))
	(setq folder-list (cdr folder-list)))
      nil)))
        
;;;###autoload
(defun vm-virtual-get-selector (vfolder &optional valid-folder-list)
  "Return the selector of virtual folder VFOLDER for VALID-FOLDER-LIST."
  (interactive 
   (list (vm-read-string "Virtual folder: " vm-virtual-folder-alist)
         (if (equal major-mode 'mail-mode) 
	     nil
           (save-excursion 
	     (vm-select-folder-buffer)
	     (list (buffer-name))))))

  (let ((clauses (cadr (assoc vfolder vm-virtual-folder-alist)))
        (selector nil)
	(folders valid-folder-list))
    (when clauses
      (if (null folders)
          (setq selector (append (cdr clauses) selector))
        (while folders
          (when (vm-virtual-folder-member-p (car folders) (car clauses))
              (setq selector (append (cdr clauses) selector)))
          (setq folders (cdr folders)))))

    selector))

;;-----------------------------------------------------------------------------

;;;###autoload
(defun vm-virtual-check-selector (selector &optional msg virtual)
  "Return t if SELECTOR matches the message MSG.
If VIRTUAL is true we check the current message and not the real one."
  (if msg
      (if virtual
          (apply 'vm-vs-or msg selector)
        (with-current-buffer (vm-buffer-of (vm-real-message-of msg))
          (apply 'vm-vs-or msg selector)))
    (if (eq major-mode 'mail-mode)
        (apply 'vm-mail-vs-or selector))))

;;;###autoload
(defun vm-virtual-check-selector-interactive (selector &optional diagnostics)
  "Return t if SELECTOR matches the current message.
Called with an prefix argument we display more diagnostics about the selector
evaluation.  Information is displayed in the order of evaluation and indented
according to the level of recursion. The displayed information is has the
format: 
	FATHER-SELECTOR: RESULT CHILD-SELECTOR"
  (interactive 
   (list  (vm-read-string "Virtual folder: " vm-virtual-folder-alist)
          current-prefix-arg))
  (save-excursion
    (vm-select-folder-buffer-and-validate 1 (vm-interactive-p))
    (vm-follow-summary-cursor)
    (let ((msg (car vm-message-pointer))
          (virtual (eq major-mode 'vm-virtual-mode))
          (vm-virtual-check-diagnostics (or vm-virtual-check-diagnostics
                                            diagnostics)))
      (with-output-to-temp-buffer "*VM virtual-folder-check*"
        (with-current-buffer "*VM virtual-folder-check*"
          (toggle-truncate-lines t))
        (princ (format "Checking %S on <%s> from %s\n\n" selector
                       (vm-su-subject msg) (vm-su-from msg)))
        (princ (format "\nThe virtual folder selector `%s' is %s\n"
                       selector
                       (if (vm-virtual-check-selector
                            (vm-virtual-get-selector selector)
                            msg virtual)
                           "true"
                         "false")))))))

;;----------------------------------------------------------------------------
(defvar vmpc-current-state nil)
;;;###autoload
(defun vmpc-virtual-check-selector (selector &optional folder-list)
  "Checks SELECTOR based on the state of vmpc on the original or current."
  (setq selector (vm-virtual-get-selector selector folder-list))
  (if (null selector)
      (error "no virtual folder %s!" selector))
  (cond ((or (eq vmpc-current-state 'reply)
             (eq vmpc-current-state 'forward)
             (eq vmpc-current-state 'resend))
         (vm-virtual-check-selector selector (car vm-message-pointer)))
        ((eq vmpc-current-state 'automorph)
         (vm-virtual-check-selector selector))))

;;----------------------------------------------------------------------------
;;;###autoload
(defun vm-virtual-apply-function (count &optional selector function)
  "Apply a FUNCTION to the next COUNT messages matching SELECTOR." 
  (interactive "p")
  (when (vm-interactive-p)
      (vm-follow-summary-cursor)
      (setq selector (vm-virtual-get-selector
                      (vm-read-string "Virtual folder: "
                                      vm-virtual-folder-alist)))
      (if (featurep 'xemacs)
	  (setq function 
		(key-or-menu-binding (read-key-sequence "VM command: ")))
	(setq function
		(key-binding (read-key-sequence "VM command: ")))))

  (vm-select-folder-buffer-and-validate 1 (vm-interactive-p))

  (let ((mlist (vm-select-operable-messages 
		(or count 1) (vm-interactive-p)"Apply to"))
        (count 0))

    (while mlist
      (if (vm-virtual-check-selector selector (car mlist))
          (progn (funcall function (car mlist))
                 (vm-increment count)))
      (setq mlist (cdr mlist)))

    count))

;;----------------------------------------------------------------------------
;;;###autoload
(defun vm-virtual-update-folders (&optional count message-list)
  "Add the current message to all virtual folders that are
applicable.  

With a prefix argument COUNT, the current message and the next
COUNT - 1 messages are added.  A negative argument means
the current message and the previous |COUNT| - 1 messages are
added.

When invoked on marked messages (via `vm-next-command-uses-marks'),
only marked messages are added, other messages are ignored.  If
applied to collapsed threads in summary and thread operations are
enabled via `vm-enable-thread-operations' then all messages in the
thread are added."
  (interactive "p")
  (vm-select-folder-buffer-and-validate 0 (vm-interactive-p))

  (let ((new-messages (or message-list
                          (vm-select-operable-messages
			   count (vm-interactive-p) "Update")))
        b-list)
    (setq new-messages (copy-sequence new-messages))
    (if (and new-messages vm-virtual-buffers)
        (save-excursion
          (setq b-list vm-virtual-buffers)
          (while b-list
            ;; buffer might be dead
            (if (buffer-name (car b-list))
                (let (tail-cons)
                  (set-buffer (car b-list))
                  (setq tail-cons (vm-last vm-message-list))
                  (vm-build-virtual-message-list new-messages)
                  (if (or (null tail-cons) (cdr tail-cons))
                      (progn
                        (setq vm-ml-sort-keys nil)
                        (if vm-thread-obarray
                            (vm-build-threads (cdr tail-cons)))
                        (vm-set-summary-redo-start-point
                         (or (cdr tail-cons) vm-message-list))
                        (vm-set-numbering-redo-start-point
                         (or (cdr tail-cons) vm-message-list))
                        (if (null vm-message-pointer)
                            (progn (setq vm-message-pointer vm-message-list
                                         vm-need-summary-pointer-update t)
                                   (if vm-message-pointer
                                       (vm-present-current-message))))
                        (setq vm-messages-needing-summary-update new-messages
                              vm-need-summary-pointer-update t)
                        (vm-update-summary-and-mode-line)
                        (if vm-summary-show-threads
                            (vm-sort-messages (or vm-ml-sort-keys "activity")))))))
            (setq b-list (cdr b-list)))))
    new-messages))

;;----------------------------------------------------------------------------
;;;###autoload
(defun vm-virtual-omit-message (&optional count message-list)
  "Omits a message from a virtual folder.
IMHO allowing it for real folders makes no sense.  One rather should create a
virtual folder of all messages."
  (interactive "p")
  (vm-select-folder-buffer-and-validate 0 (vm-interactive-p))

  (if (not (eq major-mode 'vm-virtual-mode))
      (error "This is no virtual folder."))

  (let ((old-messages (or message-list
                          (vm-select-operable-messages
			   count (vm-interactive-p) "Omit")))
        prev curr
        (mp vm-message-list))

    (while mp
      (if (not (member (car mp) old-messages))
          nil
        (setq prev (vm-reverse-link-of (car mp))
              curr (or (cdr prev) vm-message-list))
        (vm-set-numbering-redo-start-point (or prev t))
        (vm-set-summary-redo-start-point (or prev t))
        (if (eq vm-message-pointer curr)
            (setq vm-system-state nil
                  vm-message-pointer (or prev (cdr curr))))
        (if (eq vm-last-message-pointer curr)
            (setq vm-last-message-pointer nil))
        (if (null prev)
            (progn
              (setq vm-message-list (cdr vm-message-list))
              (and (cdr curr)
                   (vm-set-reverse-link-of (car (cdr curr)) nil)))
          (setcdr prev (cdr curr))
          (and (cdr curr)
               (vm-set-reverse-link-of (car (cdr curr)) prev))))
      (setq mp (cdr mp)))

    (vm-update-summary-and-mode-line)
    (if vm-summary-show-threads
        (vm-sort-messages (or vm-ml-sort-keys "activity")))
    old-messages))

;;----------------------------------------------------------------------------

(defcustom vm-virtual-auto-delete-message-selector "spam"
  "*Name of virtual folder selector used for automatically deleting a message.
Actually they are only marked for deletion."
  :group 'vm-avirtual
  :type 'string)

(defcustom vm-virtual-auto-delete-message-folder nil
  "*When set to a folder name we save affected messages there."
  :group 'vm-avirtual
  :type '(choice (file :tag "VM folder" "spam")
                 (const :tag "Disabled" nil)))

(defcustom vm-virtual-auto-delete-message-expunge nil
  "*When true we expunge the affected right after marking and saving them."
  :group 'vm-avirtual
  :type 'boolean)

;;;###autoload
(defun vm-virtual-auto-delete-message (&optional count selector)
  "*Mark messages matching a virtual folder selector for deletion.
The virtual folder selector can be configured by the variable
`vm-virtual-auto-delete-message-selector'.

This function does not visit the virtual folder, but checks only the current
message, therefore it is much faster and not so disturbing like the method
described in the VM-FAQ.

In order to automatically mark spam for deletion use the function
`vm-virtual-auto-delete-messages'.  See its documentation on how to hook it
into VM!"
  (interactive "p")
  
  (setq selector (or selector
                       (vm-virtual-get-selector
                        vm-virtual-auto-delete-message-selector)))

  (let (spammlist)
    (setq count (vm-virtual-apply-function
                 count
                 selector
                 (lambda (msg)
		   (setq spammlist (cons msg spammlist))
		   (vm-set-labels
		    msg (list vm-virtual-auto-delete-message-selector))
		   (vm-set-deleted-flag msg t)
		   (vm-mark-for-summary-update msg t))))

    (when spammlist
      (setq spammlist (reverse spammlist))
      ;; save them 
      (if vm-virtual-auto-delete-message-folder
          (let ((vm-arrived-messages-hook nil)
                (vm-arrived-message-hook nil)
                (mlist spammlist))
            (while mlist
              (let ((vm-message-pointer mlist))
                (vm-save-message vm-virtual-auto-delete-message-folder))
              (setq mlist (cdr mlist)))))
      ;; expunge them 
      (if vm-virtual-auto-delete-message-expunge
          (vm-expunge-folder :quiet t :just-these-messages spammlist)))
    
    (vm-display nil nil '(vm-delete-message vm-delete-message-backward)
                (list this-command))
    
    (vm-update-summary-and-mode-line)
    
    (message "%s message%s %s"
             (if (> count 0) count "No")
             (if (= 1 count) "" "s")
             (concat
              (if vm-virtual-auto-delete-message-folder
                  (format "saved to %s and "
                          vm-virtual-auto-delete-message-folder)
                "")
              (if vm-virtual-auto-delete-message-expunge
                  "expunged right away"
                "marked for deletion")))))
  
;;;###autoload
(defun vm-virtual-auto-delete-messages ()
  "*Mark all messages from the current up to the last for (spam-)deletion.
Add this to `vm-arrived-messages-hook'.

See the function `vm-virtual-auto-delete-message' for details.

 (add-hook \\='vm-arrived-messages-hook #\\='vm-virtual-auto-delete-messages)
"
  (interactive)

  (if (vm-interactive-p)
      (vm-follow-summary-cursor))
  (vm-select-folder-buffer-and-validate 1 (vm-interactive-p))
  (vm-virtual-auto-delete-message (length vm-message-pointer)))

;;----------------------------------------------------------------------------
;;;###autoload
(defcustom vm-virtual-auto-folder-alist nil
  "*Non-nil value should be an alist that VM will use to choose a default
folder name when messages are saved.  The alist should be of the form
        ((VIRTUAL-FOLDER-NAME . FOLDER-NAME)
          ...)
where VIRTUAL-FOLDER-NAME is a string, and FOLDER-NAME
is a string or an s-expression that evaluates to a string.

This allows you to extend `vm-virtual-auto-select-folder' to generate
a folder name.  Your function may use `folder' to get the currently chosen
folder name and `mp' (a vm-message-pointer) to access the message. 

Example:
 (setq vm-virtual-auto-folder-alist
       \\='((\"spam\" (concat folder \"-\"
                           (format-time-string \"%y%m\" (current-time))))))

This will return \"spam-0008\" as a folder name for messages matching the
virtual folder selector of the virtual folder \"spam\" during August in year
2000."
  :type 'sexp
  :group 'vm-avirtual)

(defcustom vm-virtual-make-up-auto-folder-names t
  "*Non-nil value causes the vm-avirtual.el package to make up
auto-folder names from virtual folder names, so that all messages
belonging to a virtual folder are saved to real folders with the
same name.  Any auto-folder names suggested in
`vm-virtual-auto-folder-alist' will take priority over such made
up names."
  :type 'boolean
  :group 'vm-avirtual)


;;;###autoload
(defun vm-virtual-auto-select-folder (&optional m virtual-folder-alist
                                                valid-folder-list
                                                not-to-history)
  "Return the first matching virtual folder.
This is a more powerful replacement of `vm-auto-select-folder'.
It is used by `vm-virtual-save-message' for finding the folder to
save the current message.  It may also be used for finding the
right FCC for outgoing messages.                    RobF, 2004-05-02

The matching virtual folder is found for the message M (defaults to
the current message).

VIRTUAL-FOLDER-ALIST is the association list of virtual folder definitions
 (defaults to `vm-virtual-folder-alist').

VALID-FOLDER-LIST is the list of folder names that may be regarded as
the folder names of the message.  (The default is the name of
the current folder.  If the message is virtual, it is the folder name of
the underlying real message.)

NOT-TO-HISTORY says that the history of last saved folders should not
be altered.  (By default, it is updated with the folder name returned
by this function.)

This is not yet the whole story!                    USR, 2013-01-18"

  (unless m (setq m (car vm-message-pointer)))
  (unless virtual-folder-alist
    (setq virtual-folder-alist vm-virtual-folder-alist))
  (unless valid-folder-list
    (setq valid-folder-list 
	  (cond ((eq major-mode 'mail-mode)
		 nil)
		((eq major-mode 'vm-mode)
		 (save-excursion
		   (vm-select-folder-buffer)
		   (list (buffer-name))))
		((eq major-mode 'vm-virtual-mode)
		 (list (buffer-name
			(vm-buffer-of
			 (vm-real-message-of m))))))))
  
  (let ((vfolders virtual-folder-alist)
        vfolder selector matching-vfolders auto-folders)

    (when t;(and m (aref m 0) (aref (aref m 0) 0)
            ;   (marker-buffer (aref (aref m 0) 0)))
      ;; set matching-vfolders in reverse order of priority
      (while vfolders
	(setq vfolder (caar vfolders))
        (setq selector (vm-virtual-get-selector 
			vfolder valid-folder-list))
        (when (and selector (vm-virtual-check-selector selector m))
          (setq matching-vfolders (cons vfolder matching-vfolders))
          (if not-to-history
              (setq vfolders nil)))
        (setq vfolders (cdr vfolders)))
      
      ;; (setq matching-vfolders (reverse matching-vfolders))
      
      ;; find auto-folders for matching-vfolders in order of priority
      (vm-mapc
       (lambda (vfolder)
	 (let ((auto-folder 
		(cadr (assoc vfolder vm-virtual-auto-folder-alist))))
	   (cond (auto-folder
		  (setq auto-folders 
			(cons (eval auto-folder) auto-folders)))
		 (vm-virtual-make-up-auto-folder-names
		  (setq auto-folders
			(cons vfolder auto-folders)))
		 )))
       matching-vfolders)

      ;; adjust the vm-folder-history
      (when (and (not not-to-history) auto-folders)
        (let ((folders (cdr auto-folders)) folder)
          (while folders
            (setq folder (vm-abbreviate-file-name
			  (expand-file-name (car folders) vm-folder-directory))
                  vm-folder-history (delete folder vm-folder-history)
                  vm-folder-history (nconc (list folder) vm-folder-history)
                  folders (cdr folders)))))

      ;; return the first match
      (car auto-folders))))
  
;;-----------------------------------------------------------------------------
;;;###autoload
(defvar vm-sort-compare-auto-folder-cache nil)
(add-to-list 'vm-supported-sort-keys "auto-folder")

(defun vm-sort-compare-auto-folder (m1 m2)
  (let* (s1 s2)
    (if (setq s1 (assoc m1 vm-sort-compare-auto-folder-cache))
        (setq s1 (cdr s1))
      (setq s1 (vm-virtual-auto-select-folder m1))
      (add-to-list 'vm-sort-compare-auto-folder-cache (cons m1 s1)))
    (if (setq s2 (assoc m2 vm-sort-compare-auto-folder-cache))
        (setq s2 (cdr s2))
      (setq s2 (vm-virtual-auto-select-folder m2))
      (add-to-list 'vm-sort-compare-auto-folder-cache (cons m2 s2)))
    (cond ((or (and (null s1) s2)
               (and s1 s2 (string-lessp s1 s2)))
           t)
          ((or (and (null s1) (null s2))
               (and s1 s2 (string-equal s1 s2)))
           '=)
          (t nil))))

;;;###autoload
(defun vm-sort-insert-auto-folder-names ()
  (interactive)
  (if (vm-interactive-p)
      (vm-sort-messages "auto-folder"))
  (save-excursion
    (vm-select-folder-buffer-and-validate 0 (vm-interactive-p))
    ;; remove old descriptions
    (with-current-buffer vm-summary-buffer
      (goto-char (point-min))
      (let ((buffer-read-only nil)
            (s (point-min))
            (p (point-min)))
        (while (setq p (next-single-property-change p 'vm-auto-folder))
          (if (get-text-property (1+ p) 'vm-auto-folder)
              (setq s p)
            (delete-region s p))
          (setq p (1+ p)))))
    ;; add new descriptions
    (let ((ml vm-message-list)
          (oldf "")
          m f)
      (while ml
        (setq m (car ml)
              f (cdr (assoc m vm-sort-compare-auto-folder-cache)))
        (when (not (equal oldf f))
          (setq m (vm-su-start-of m))
          (with-current-buffer (marker-buffer m)
            (let ((buffer-read-only nil))
              (goto-char m)
              (insert (format "%s\n" (or f "no default folder")))
              (put-text-property m (point) 'vm-auto-folder t)
              (put-text-property m (point) 'face 'blue)
              ;; fix messages summary mark 
              (set-marker m (point))))
          (setq oldf f))
        (setq ml (cdr ml))))))
        
;;----------------------------------------------------------------------------
;;;###autoload
(defun vm-virtual-save-message (&optional folder count)
  "Save the current message to a mail folder.
Like `vm-save-message' but the default folder is guessed by
`vm-virtual-auto-select-folder'."
  (interactive
   (list
    ;; protect value of last-command
    (let ((last-command last-command)
          (this-command this-command))
      (vm-follow-summary-cursor)
      (let ((default (save-current-buffer
                       (vm-select-folder-buffer)
                       (or (vm-virtual-auto-select-folder)
                           vm-last-save-folder)))
            (dir (or vm-folder-directory default-directory)))
        (cond ((and default
                    (let ((default-directory dir))
                      (file-directory-p default)))
               (vm-read-file-name "Save in folder: "
                                  dir nil nil default 'vm-folder-history))
              (default
                (vm-read-file-name
                 (format "Save in folder: (default %s) " default)
                 dir default nil nil 'vm-folder-history))
              (t
               (vm-read-file-name "Save in folder: " dir nil)))))
    (prefix-numeric-value current-prefix-arg)))
  (vm-select-folder-buffer-and-validate 1 (vm-interactive-p))
  (vm-save-message folder count))

;;----------------------------------------------------------------------------
;;;###autoload
(defun vm-virtual-auto-archive-messages (&optional prompt)
  "With a prefix ARG ask user before saving." 
  (interactive "P")
  (vm-select-folder-buffer-and-validate 1 (vm-interactive-p))
  (vm-error-if-folder-read-only)

  (let ((auto-folder)
        (archived 0))
    (unwind-protect
	(let ((vm-message-pointer	; local copy
	       (if (eq last-command 'vm-next-command-uses-marks)
		   (vm-select-operable-messages
		    0 (vm-interactive-p) "Archive")))
	      (vm-last-save-folder vm-last-save-folder) ; shadowed
	      (vm-move-after-deleting nil)		; shadowed
	      (done nil)
	      msg stop-point)
	  (setq vm-message-pointer (or vm-message-pointer vm-message-list))
	  ;; Double check if the user really wants to archive
	  (unless 
	      (or (not vm-confirm-for-auto-archive)
		  (null vm-message-pointer)
		  (not (vm-interactive-p))
		  (y-or-n-p 
		   (format "Auto archive %s messages? "
			   (if (eq last-command 'vm-next-command-uses-marks)
			       "marked" "all"))))
	    (error "Aborted"))
	  (vm-inform 5 "Archiving...")
	  ;; mark the place where we should stop.
	  (setq stop-point (vm-last vm-message-pointer))
	  (while (not done)
	    (setq msg (car vm-message-pointer))
	    (when (and (not (vm-filed-flag msg))
		       (not (vm-deleted-flag msg))
		       (setq auto-folder
			     (vm-virtual-auto-select-folder msg))
		       (not (eq (vm-get-file-buffer auto-folder)
				(current-buffer)))
		       (or (not prompt)
			   (y-or-n-p
			    (format "Save message %s in folder %s? "
				    (vm-number-of (car vm-message-pointer))
				    auto-folder))))
	      (condition-case nil
		  (let ((vm-delete-after-saving vm-delete-after-archiving)
			(last-command 'vm-virtual-auto-archive-messages))
		    (vm-save-message auto-folder 1 nil 'quiet)
		    (vm-increment archived)
		    (vm-inform 6 "%d archived, still working..." archived))
		(error nil)))
            (setq done (eq vm-message-pointer stop-point)
                  vm-message-pointer (cdr vm-message-pointer))))
      ;; unwind-protection
      ;; fix mode line
      (intern (buffer-name) vm-buffers-needing-display-update)
      (vm-update-summary-and-mode-line))
    (if (zerop archived)
        (vm-inform 5 "No messages were archived")
      (vm-inform 5 "%d message%s archived"
		 archived (if (= 1 archived) "" "s")))))

;;----------------------------------------------------------------------------
;;;###autoload
(defun vm-virtual-make-folder-persistent ()
  "Save all messages of current virtual folder in the real folder
with the same name."
  (interactive)
  (save-excursion
    (vm-select-folder-buffer-and-validate 0 (vm-interactive-p))
    (if (eq major-mode 'vm-virtual-mode)
        (let ((file (substring (buffer-name) 1 -1)))
          (vm-goto-message 0)
          (vm-save-message file (length vm-message-list))
          (vm-inform 5 "Saved virtual folder in file \"%s\"" file))
      (error "This is not a virtual folder"))))

;;----------------------------------------------------------------------------

(provide 'vm-avirtual)
;;; vm-avirtual.el ends here
