;;; vm-mouse.el --- Mouse related functions and commands  -*- lexical-binding: t; -*-
;;
;; This file is part of VM
;;
;; Copyright (C) 1995-1997 Kyle E. Jones
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

(require 'vm-menu)

(declare-function vm-mail-to-mailto-url "vm-reply" (url))
(declare-function event-window "vm-xemacs" (event))
(declare-function event-point "vm-xemacs" (event))

(defun vm-mouse-set-mouse-track-highlight (start end &optional overlay)
  "Create and return an overlay for mouse selection from START to
END.  If the optional argument OVERLAY is provided then that that
overlay is moved to cover START to END.  No new overlay is created in
that case.                                            USR, 2010-08-01"
  (if (null overlay)
	(cond ((not (featurep 'xemacs))
	       (let ((o (make-overlay start end)))
		 (overlay-put o 'mouse-face 'highlight)
		 o ))
	      ((featurep 'xemacs)
	       (let ((o (vm-make-extent start end)))
		 (vm-set-extent-property o 'start-open t)
		 (vm-set-extent-property o 'priority 10)
		 (vm-set-extent-property o 'highlight t)
		 o )))
    (cond ((not (featurep 'xemacs))
	   (move-overlay overlay start end))
	  ((featurep 'xemacs)
	   (vm-set-extent-endpoints overlay start end)))))

;;;###autoload
(defun vm-mouse-button-2 (event)
  "The immediate action event in VM buffers, depending on where the
mouse is clicked.  See Info node `(VM) Using the Mouse'."
  (interactive "e")
  ;; go to where the event occurred
  (cond ((featurep 'xemacs)
	 (set-buffer (window-buffer (event-window event)))
	 (and (event-point event) (goto-char (event-point event))))
	((not (featurep 'xemacs))
	 (set-buffer (window-buffer (posn-window (event-start event))))
	 (goto-char (posn-point (event-start event)))))
  ;; now dispatch depending on where we are
  (cond ((eq major-mode 'vm-summary-mode)
	 (mouse-set-point event)
	 (beginning-of-line)
	 (if (let ((vm-follow-summary-cursor t))
	       (vm-follow-summary-cursor))
	     nil
	   (setq this-command 'vm-scroll-forward)
	   (call-interactively 'vm-scroll-forward)))
	((eq major-mode 'vm-folders-summary-mode)
	 (mouse-set-point event)
	 (beginning-of-line)
	 (vm-follow-folders-summary-cursor))
	((memq major-mode '(vm-mode vm-virtual-mode vm-presentation-mode))
	 (vm-mouse-popup-or-select event))))

;;;###autoload
(defun vm-mouse-button-3 (event)
  "Brings up the context-sensitive menu in VM buffers, depending
on where the mouse is clicked.  See Info node `(VM) Using the
Mouse'."
  (interactive "e")
  (if vm-use-menus
      (progn
	;; go to where the event occurred
	(cond ((featurep 'xemacs)
	       (set-buffer (window-buffer (event-window event)))
	       (and (event-point event) (goto-char (event-point event))))
	      ((not (featurep 'xemacs))
	       (set-buffer (window-buffer (posn-window (event-start event))))
	       (goto-char (posn-point (event-start event)))))
	;; now dispatch depending on where we are
	(cond ((eq major-mode 'vm-summary-mode)
	       (vm-menu-popup-mode-menu event))
	      ((eq major-mode 'vm-mode)
	       (vm-menu-popup-context-menu event))
	      ((eq major-mode 'vm-presentation-mode)
	       (vm-menu-popup-context-menu event))
	      ((eq major-mode 'vm-virtual-mode)
	       (vm-menu-popup-context-menu event))
	      ((eq major-mode 'mail-mode)
	       (vm-menu-popup-context-menu event))))))

(defun vm-mouse-3-help (_object)
  nil
  "Use mouse button 3 to see a menu of options.")

(defun vm-mouse-get-mouse-track-string (event)
  (save-current-buffer
    ;; go to where the event occurred
    (cond ((featurep 'xemacs)
	   (set-buffer (window-buffer (event-window event)))
	   (and (event-point event) (goto-char (event-point event))))
	  ((not (featurep 'xemacs))
	   (set-buffer (window-buffer (posn-window (event-start event))))
	   (goto-char (posn-point (event-start event)))))
    (cond ((not (featurep 'xemacs))
	   (let ((o-list (overlays-at (point)))
		 (string nil))
	     (while o-list
	       (if (overlay-get (car o-list) 'mouse-face)
		   (setq string (vm-buffer-substring-no-properties
				 (overlay-start (car o-list))
				 (overlay-end (car o-list)))
			 o-list nil)
		 (setq o-list (cdr o-list))))
	     string ))
	  ((featurep 'xemacs)
	   (let ((e (vm-extent-at (point) 'highlight)))
	     (if e
		 (buffer-substring (vm-extent-start-position e)
				   (vm-extent-end-position e))
	       nil)))
	  (t nil))))

;;;###autoload
(defun vm-mouse-popup-or-select (event)
  (interactive "e")
  (cond ((not (featurep 'xemacs))
	 (set-buffer (window-buffer (posn-window (event-start event))))
	 (goto-char (posn-point (event-start event)))
	 (let (o-list (found nil))
	   (setq o-list (overlays-at (point)))
	   (while (and o-list (not found))
	     (cond ((overlay-get (car o-list) 'vm-url)
		    (setq found t)
		    (vm-mouse-send-url-at-event event))
		   ((overlay-get (car o-list) 'vm-mime-function)
		    (setq found t)
		    (funcall (overlay-get (car o-list) 'vm-mime-function)
			     (car o-list))))
	     (setq o-list (cdr o-list)))
	   (and (not found) (vm-menu-popup-context-menu event))))
	;; The XEmacs code is not actually used now, since all
	;; selectable objects are handled by an extent keymap
	;; binding that points to a more specific function.  But
	;; this might come in handy later if I want selectable
	;; objects that don't have an extent keymap attached.
	((featurep 'xemacs)
	 (set-buffer (window-buffer (event-window event)))
	 (and (event-point event) (goto-char (event-point event)))
	 (let (e)
	   (cond ((vm-extent-at (point) 'vm-url)
		  (vm-mouse-send-url-at-event event))
		 ((setq e (vm-extent-at (point) 'vm-mime-function))
		  (funcall (vm-extent-property e 'vm-mime-function) e))
		 (t (vm-menu-popup-context-menu event)))))))

;;;###autoload
(defun vm-mouse-send-url-at-event (event)
  (interactive "e")
  (cond ((featurep 'xemacs)
	 (set-buffer (window-buffer (event-window event)))
	 (and (event-point event) (goto-char (event-point event)))
	 (vm-mouse-send-url-at-position (event-point event)))
	((not (featurep 'xemacs))
	 (set-buffer (window-buffer (posn-window (event-start event))))
	 (goto-char (posn-point (event-start event)))
	 (vm-mouse-send-url-at-position (posn-point (event-start event))))))

(defun vm-mouse-send-url-at-position (pos &optional browser)
  (save-restriction
    (widen)
    (cond ((featurep 'xemacs)
	   (let ((e (vm-extent-at pos 'vm-url))
		 url)
	     (if (null e)
		 nil
	       (setq url (buffer-substring (vm-extent-start-position e)
					   (vm-extent-end-position e)))
	       (vm-mouse-send-url url browser))))
	  ((not (featurep 'xemacs))
	   (let (o-list url o)
	     (setq o-list (overlays-at pos))
	     (while (and o-list (null (overlay-get (car o-list) 'vm-url)))
	       (setq o-list (cdr o-list)))
	     (if (null o-list)
		 nil
	       (setq o (car o-list))
	       (setq url (vm-buffer-substring-no-properties
			  (overlay-start o)
			  (overlay-end o)))
	       (vm-mouse-send-url url browser)))))))

(defun vm-mouse-send-url (url &optional browser switches)
  (if (string-match "^[A-Za-z0-9._-]+@[A-Za-z0-9._-]+$" url)
      (setq url (concat "mailto:" url)))
  (if (string-match "^mailto:" url)
      (vm-mail-to-mailto-url url)
    (let ((browser (or browser vm-url-browser))
	  (switches (or switches vm-url-browser-switches)))
      (cond ((symbolp browser)
	     (funcall browser url))
	    ((stringp browser)
	     (vm-inform 5 "Sending URL to %s..." browser)
	     (apply 'vm-run-background-command browser
		    (append switches (list url)))
	     (vm-inform 5 "Sending URL to %s... done" browser))))))

(defun vm-mouse-send-url-to-netscape (url &optional new-netscape new-window)
  ;; Change commas to %2C to avoid confusing Netscape -remote.
  (while (string-match "," url)
    (setq url (replace-match "%2C" nil t url)))
  (vm-inform 5 "Sending URL to Netscape...")
  (if new-netscape
      (apply 'vm-run-background-command vm-netscape-program
	     (append vm-netscape-program-switches (list url)))
    (or (equal 0 (apply 'vm-run-command vm-netscape-program
			(append vm-netscape-program-switches
				(list "-remote"
				      (concat "openURL(" url
					      (if new-window ",new-window" "")
					      ")")))))
	(vm-mouse-send-url-to-netscape url t new-window)))
  (vm-inform 5 "Sending URL to Netscape... done"))

(defun vm-mouse-send-url-to-opera (url &optional new-opera new-window)
  ;; Change commas to %2C to avoid confusing Netscape -remote.
  (while (string-match "," url)
    (setq url (replace-match "%2C" nil t url)))
  (vm-inform 5 "Sending URL to Opera...")
  (if new-opera
      (apply 'vm-run-background-command vm-opera-program
	     (append vm-opera-program-switches (list url)))
    (or (equal 0 (apply 'vm-run-command vm-opera-program
			(append vm-opera-program-switches
				(list "-remote"
				      (concat "openURL(" url
					      ")")))))
	(vm-mouse-send-url-to-opera url t new-window)))
  (vm-inform 5 "Sending URL to Opera... done"))


(defun vm-mouse-send-url-to-mozilla (url &optional new-mozilla new-window)
  ;; Change commas to %2C to avoid confusing Netscape -remote.
  (while (string-match "," url)
    (setq url (replace-match "%2C" nil t url)))
  (vm-inform 5 "Sending URL to Mozilla...")
  (if new-mozilla
      (apply 'vm-run-background-command vm-mozilla-program
	     (append vm-mozilla-program-switches (list url)))
    (or (equal 0 (apply 'vm-run-command vm-mozilla-program
			(append vm-mozilla-program-switches
				(list "-remote"
				      (concat "openURL(" url
					      (if new-window ",new-window" "")
					      ")")))))
	(vm-mouse-send-url-to-mozilla url t new-window)))
  (vm-inform 5 "Sending URL to Mozilla... done"))

(defun vm-mouse-send-url-to-netscape-new-window (url)
  (vm-mouse-send-url-to-netscape url nil t))

(defun vm-mouse-send-url-to-opera-new-window (url)
  (vm-mouse-send-url-to-opera url nil t))

(defun vm-mouse-send-url-to-mozilla-new-window (url)
  (vm-mouse-send-url-to-mozilla url nil t))

(defvar buffer-file-type)

(defun vm-mouse-send-url-to-mosaic (url &optional new-mosaic new-window)
  (vm-mouse-send-url-to-xxxx-mosaic 'mosaic url new-mosaic new-window))

(defun vm-mouse-send-url-to-mmosaic (url &optional new-mosaic new-window)
  (vm-mouse-send-url-to-xxxx-mosaic 'mmosaic url new-mosaic new-window))

(defun vm-mouse-send-url-to-xxxx-mosaic (m-type url &optional
					 new-mosaic new-window)
  (let ((what (cond ((eq m-type 'mmosaic) "mMosaic")
		    (t "Mosaic"))))
    (vm-inform 5 "Sending URL to %s..." what)
    (if (null new-mosaic)
	(let ((pid-file (cond ((eq m-type 'mmosaic)
			       "~/.mMosaic/.mosaicpid")
			      (t "~/.mosaicpid")))
	      (work-buffer " *mosaic work*")
	      (coding-system-for-read (vm-line-ending-coding-system))
	      (coding-system-for-write (vm-line-ending-coding-system))
	      pid)
	  (cond ((file-exists-p pid-file)
		 (set-buffer (get-buffer-create work-buffer))
		 (setq selective-display nil)
		 (erase-buffer)
		 (insert-file-contents pid-file)
		 (setq pid (int-to-string (string-to-number (buffer-string))))
		 (erase-buffer)
		 (insert (if new-window "newwin" "goto") ?\n)
		 (insert url ?\n)
		 ;; newline convention used should be the local
		 ;; one, whatever that is.
		 (setq buffer-file-type nil)
		 (if (fboundp 'set-buffer-file-coding-system)
		     (set-buffer-file-coding-system
		      (vm-line-ending-coding-system) nil))
		 (write-region (point-min) (point-max)
			       (concat "/tmp/Mosaic." pid)
			       nil 0)
		 (set-buffer-modified-p nil)
		 (kill-buffer work-buffer)))
	  (cond ((or (null pid)
		     (not (equal 0 (vm-run-command "kill" "-USR1" pid))))
		 (setq new-mosaic t)))))
    (if new-mosaic
	(apply 'vm-run-background-command
	       (cond ((eq m-type 'mmosaic) vm-mmosaic-program)
		     (t vm-mosaic-program))
	       (append (cond ((eq m-type 'mmosaic) vm-mmosaic-program-switches)
			     (t vm-mosaic-program-switches))
		       (list url))))
    (vm-inform 5 "Sending URL to %s... done" what)))

(defun vm-mouse-send-url-to-mosaic-new-window (url)
  (vm-mouse-send-url-to-mosaic url nil t))

(defun vm-mouse-send-url-to-konqueror (url &optional new-konqueror)
  (vm-inform 5 "Sending URL to Konqueror...")
  (if new-konqueror
      (apply 'vm-run-background-command vm-konqueror-program
	     (append vm-konqueror-program-switches (list url)))
    (or (equal 0 (apply 'vm-run-command vm-konqueror-client-program
			(append vm-konqueror-client-program-switches
				(list "openURL" url))))
	(vm-mouse-send-url-to-konqueror url t)))
  (vm-inform 5 "Sending URL to Konqueror... done"))

(defun vm-mouse-send-url-to-firefox (url &optional _new-window)
  (vm-inform 5 "Sending URL to Mozilla Firefox...")
  (if t					; new-window parameter ignored
      (apply 'vm-run-background-command vm-firefox-program
	     (append vm-firefox-program-switches (list url)))
    ;; OpenURL is obsolete
    ;; https://developer.mozilla.org/en-US/docs/Mozilla/Command_Line_Options#Remote_Control
    (or (equal 0 (apply 'vm-run-command vm-firefox-client-program
			(append vm-firefox-client-program-switches
				(list url))))
	(vm-mouse-send-url-to-firefox url t)))
  (vm-inform 5 "Sending URL to Mozilla Firefox... done"))

(defun vm-mouse-send-url-to-konqueror-new-window (url)
  (vm-mouse-send-url-to-konqueror url t))

(defvar vm-warn-for-interprogram-cut-function t)

(defun vm-mouse-send-url-to-window-system (url)
  (unless interprogram-cut-function
    (when vm-warn-for-interprogram-cut-function 
      (vm-warn 1 2 
	       (concat "Copying to kill ring only; "
		       "Customize interprogram-cut-function to copy to Window system"))
      (setq vm-warn-for-interprogram-cut-function nil)))
  (kill-new url))

(defun vm-mouse-send-url-to-clipboard (url &optional type)
  (unless type (setq type 'CLIPBOARD))
  (vm-inform 5 "Sending URL to %s..." type)
  (cond ((fboundp 'own-selection)	; XEmacs
	 (own-selection url type))
	((fboundp 'x-set-selection)	; Gnu Emacs
	 (x-set-selection type url))
	((fboundp 'x-own-selection)	; lselect for Emacs21?
	 (x-own-selection url type)))
  (vm-inform 5 "Sending URL to %s... done" type))

;;;###autoload
(defun vm-mouse-install-mouse ()
  (cond ((featurep 'xemacs)
	 (if (null (lookup-key vm-mode-map 'button2))
	     (define-key vm-mode-map 'button2 'vm-mouse-button-2)))
	((not (featurep 'xemacs))
	 (if (null (lookup-key vm-mode-map [mouse-2]))
	     (define-key vm-mode-map [mouse-2] 'vm-mouse-button-2))
	 (if vm-popup-menu-on-mouse-3
	     (progn
	       (define-key vm-mode-map [mouse-3] 'ignore)
	       (define-key vm-mode-map [down-mouse-3] 'vm-mouse-button-3))))))

(defun vm-run-background-command (command &rest arg-list)
  (vm-inform 5 "vm-run-background-command: %S %S" command arg-list)
  (apply (function call-process) command
         nil
         0
         nil arg-list))

(defun vm-run-command (command &rest arg-list)
  (vm-inform 5 "vm-run-command: %S %S" command arg-list)
  (apply (function call-process) command
         nil
         (get-buffer-create (concat " *" command "*"))
         nil arg-list))

(defvar binary-process-input) ;; FIXME: Unknown var.  XEmacs?

;; return t on zero exit status
;; return (exit-status . stderr-string) on nonzero exit status
(defun vm-run-command-on-region (start end output-buffer command
				       &rest arg-list)
  (let ((tempfile nil)
	;; use binary coding system in FSF Emacs/MULE
	(coding-system-for-read (vm-binary-coding-system))
	(coding-system-for-write (vm-binary-coding-system))
        (buffer-file-format nil)
	;; for DOS/Windows command to tell it that its input is
	;; binary.
	(binary-process-input t)
	;; call-process-region calls write-region.
	;; don't let it do CR -> LF translation.
	(selective-display nil)
	status errstring)
    (unwind-protect
	(progn
	  (setq tempfile (vm-make-tempfile-name))
	  (setq status
		(apply 'call-process-region
		       start end command nil
		       (list output-buffer tempfile)
		       nil arg-list))
	  (cond ((equal status 0) t)
		;; even if exit status non-zero, if there was no
		;; diagnostic output the command probably
		;; succeeded.  I have tried to just use exit status
		;; as the failure criterion and users complained.
		((equal (nth 7 (file-attributes tempfile)) 0)
		 (vm-warn 0 0 "%s exited non-zero (code %s)" command status)
		 (if vm-report-subprocess-errors
		     (cons status "")
		   t))
		(t (save-excursion
		     (vm-warn 0 0 "%s exited non-zero (code %s)" command status)
		     (set-buffer (find-file-noselect tempfile))
		     (setq errstring (buffer-string))
		     (kill-buffer nil)
		     (cons status errstring)))))
      (vm-error-free-call 'delete-file tempfile))))

;; stupid yammering compiler
(defvar vm-mouse-read-file-name-prompt)
(defvar vm-mouse-read-file-name-dir)
(defvar vm-mouse-read-file-name-default)
(defvar vm-mouse-read-file-name-must-match)
(defvar vm-mouse-read-file-name-initial)
(defvar vm-mouse-read-file-name-history)
(defvar vm-mouse-read-file-name-return-value)
(defvar vm-mouse-read-file-name-should-delete-frame)

(defun vm-mouse-read-file-name (prompt &optional dir default
				       must-match initial history)
  "Like read-file-name, except uses a mouse driven interface.
HISTORY argument is ignored."
  (save-excursion
    (or dir (setq dir default-directory))
    (set-buffer (vm-make-work-buffer " *Files*"))
    (use-local-map (make-sparse-keymap))
    (setq buffer-read-only t
	  default-directory dir)
    (make-local-variable 'vm-mouse-read-file-name-prompt)
    (make-local-variable 'vm-mouse-read-file-name-dir)
    (make-local-variable 'vm-mouse-read-file-name-default)
    (make-local-variable 'vm-mouse-read-file-name-must-match)
    (make-local-variable 'vm-mouse-read-file-name-initial)
    (make-local-variable 'vm-mouse-read-file-name-history)
    (make-local-variable 'vm-mouse-read-file-name-return-value)
    (make-local-variable 'vm-mouse-read-file-name-should-delete-frame)
    (setq vm-mouse-read-file-name-prompt prompt)
    (setq vm-mouse-read-file-name-dir dir)
    (setq vm-mouse-read-file-name-default default)
    (setq vm-mouse-read-file-name-must-match must-match)
    (setq vm-mouse-read-file-name-initial initial)
    (setq vm-mouse-read-file-name-history history)
    (setq vm-mouse-read-file-name-prompt prompt)
    (setq vm-mouse-read-file-name-return-value nil)
    (setq vm-mouse-read-file-name-should-delete-frame nil)
    (if (and vm-mutable-frame-configuration vm-frame-per-completion
	     (vm-multiple-frames-possible-p))
	(save-excursion
	  (setq vm-mouse-read-file-name-should-delete-frame t)
	  (vm-goto-new-frame 'completion)))
    (switch-to-buffer (current-buffer))
    (vm-mouse-read-file-name-event-handler)
    (save-excursion
      (local-set-key "\C-g" 'vm-mouse-read-file-name-quit-handler)
      (recursive-edit))
    ;; buffer could have been killed
    (and (boundp 'vm-mouse-read-file-name-return-value)
	 (prog1
	     vm-mouse-read-file-name-return-value
	   (kill-buffer (current-buffer))))))

(defun vm-mouse-read-file-name-event-handler (&optional string)
  (let ((key-doc "Click here for keyboard interface.")
	start list)
    (if string
	(cond ((equal string key-doc)
	       (condition-case nil
		   (save-excursion
		     (setq vm-mouse-read-file-name-return-value
			   (save-excursion
			     (vm-keyboard-read-file-name
			      vm-mouse-read-file-name-prompt
			      vm-mouse-read-file-name-dir
			      vm-mouse-read-file-name-default
			      vm-mouse-read-file-name-must-match
			      vm-mouse-read-file-name-initial
			      vm-mouse-read-file-name-history)))
		     (vm-mouse-read-file-name-quit-handler t))
		 (quit (vm-mouse-read-file-name-quit-handler))))
	      ((file-directory-p string)
	       (setq default-directory (expand-file-name string)))
	      (t (setq vm-mouse-read-file-name-return-value
		       (expand-file-name string))
		 (vm-mouse-read-file-name-quit-handler t))))
    (setq buffer-read-only nil)
    (erase-buffer)
    (setq start (point))
    (insert vm-mouse-read-file-name-prompt)
    (vm-set-region-face start (point) 'bold)
    (cond ((and (not string) vm-mouse-read-file-name-default)
	   (setq start (point))
	   (insert vm-mouse-read-file-name-default)
	   (vm-mouse-set-mouse-track-highlight start (point))
	   )
	  ((not string) nil)
	  (t (insert default-directory)))
    (insert ?\n ?\n)
    (setq start (point))
    (insert key-doc)
    (vm-mouse-set-mouse-track-highlight start (point))
    (vm-set-region-face start (point) 'italic)
    (insert ?\n ?\n)
    (setq list (vm-delete-backup-file-names
		(vm-delete-auto-save-file-names
		 (vm-delete-index-file-names
		  (directory-files default-directory)))))

    ;; delete dot files
    (setq list (vm-delete (lambda (file)
                            (string-match "^\\.\\([^.].*\\)?$" file))
                          list))
    ;; append a "/" to directories
    (setq list (mapcar (lambda (file)
                         (if (file-directory-p file)
                             (concat file "/")
                           file))
                       list))
    
    (vm-show-list list 'vm-mouse-read-file-name-event-handler)
    (setq buffer-read-only t)))

;;;###autoload
(defun vm-mouse-read-file-name-quit-handler (&optional normal-exit)
  (interactive)
  (if vm-mouse-read-file-name-should-delete-frame
      (vm-maybe-delete-windows-or-frames-on (current-buffer)))
  (if normal-exit
      (throw 'exit nil)
    (throw 'exit t)))

(defvar vm-mouse-read-string-prompt)
(defvar vm-mouse-read-string-completion-list)
(defvar vm-mouse-read-string-multi-word)
(defvar vm-mouse-read-string-return-value)
(defvar vm-mouse-read-string-should-delete-frame)

(defun vm-mouse-read-string (prompt completion-list &optional multi-word)
  (with-current-buffer (vm-make-work-buffer " *Choices*")
    (use-local-map (make-sparse-keymap))
    (setq buffer-read-only t)
    (make-local-variable 'vm-mouse-read-string-prompt)
    (make-local-variable 'vm-mouse-read-string-completion-list)
    (make-local-variable 'vm-mouse-read-string-multi-word)
    (make-local-variable 'vm-mouse-read-string-return-value)
    (make-local-variable 'vm-mouse-read-string-should-delete-frame)
    (setq vm-mouse-read-string-prompt prompt)
    (setq vm-mouse-read-string-completion-list completion-list)
    (setq vm-mouse-read-string-multi-word multi-word)
    (setq vm-mouse-read-string-return-value nil)
    (setq vm-mouse-read-string-should-delete-frame nil)
    (if (and vm-mutable-frame-configuration vm-frame-per-completion
	     (vm-multiple-frames-possible-p))
	(save-excursion
	  (setq vm-mouse-read-string-should-delete-frame t)
	  (vm-goto-new-frame 'completion)))
    (switch-to-buffer (current-buffer))
    (vm-mouse-read-string-event-handler)
    (save-excursion
      (local-set-key "\C-g" 'vm-mouse-read-string-quit-handler)
      (recursive-edit))
    ;; buffer could have been killed
    (and (boundp 'vm-mouse-read-string-return-value)
	 (prog1
	     (if (listp vm-mouse-read-string-return-value)
		 (mapconcat 'identity vm-mouse-read-string-return-value " ")
	       vm-mouse-read-string-return-value)
	   (kill-buffer (current-buffer))))))

(defun vm-mouse-read-string-event-handler (&optional string)
  (let ((key-doc  "Click here for keyboard interface.")
	(bs-doc   "      .... to go back one word.")
	(done-doc "      .... when you're done.")
	start) ;; list
    (if string
	(cond ((equal string key-doc)
	       (condition-case nil
		   (save-excursion
		     (setq vm-mouse-read-string-return-value
			   (vm-keyboard-read-string
			    vm-mouse-read-string-prompt
			    vm-mouse-read-string-completion-list
			    vm-mouse-read-string-multi-word))
		     (vm-mouse-read-string-quit-handler t))
		 (quit (vm-mouse-read-string-quit-handler))))
	      ((equal string bs-doc)
	       (setq vm-mouse-read-string-return-value
		     (nreverse
		      (cdr
		       (nreverse vm-mouse-read-string-return-value)))))
	      ((equal string done-doc)
	       (vm-mouse-read-string-quit-handler t))
	      (t (setq vm-mouse-read-string-return-value
		       (nconc vm-mouse-read-string-return-value
			      (list string)))
		 (if (null vm-mouse-read-string-multi-word)
		     (vm-mouse-read-string-quit-handler t)))))
    (setq buffer-read-only nil)
    (erase-buffer)
    (setq start (point))
    (insert vm-mouse-read-string-prompt)
    (vm-set-region-face start (point) 'bold)
    (insert (mapconcat 'identity vm-mouse-read-string-return-value " "))
    (insert ?\n ?\n)
    (setq start (point))
    (insert key-doc)
    (vm-mouse-set-mouse-track-highlight start (point))
    (vm-set-region-face start (point) 'italic)
    (insert ?\n)
    (if vm-mouse-read-string-multi-word
	(progn
	  (setq start (point))
	  (insert bs-doc)
	  (vm-mouse-set-mouse-track-highlight start (point))
	  (vm-set-region-face start (point) 'italic)
	  (insert ?\n)
	  (setq start (point))
	  (insert done-doc)
	  (vm-mouse-set-mouse-track-highlight start (point))
	  (vm-set-region-face start (point) 'italic)
	  (insert ?\n)))
    (insert ?\n)
    (vm-show-list vm-mouse-read-string-completion-list
		  'vm-mouse-read-string-event-handler)
    (setq buffer-read-only t)))

;;;###autoload
(defun vm-mouse-read-string-quit-handler (&optional normal-exit)
  (interactive)
  (if vm-mouse-read-string-should-delete-frame
      (vm-maybe-delete-windows-or-frames-on (current-buffer)))
  (if normal-exit
      (throw 'exit nil)
    (throw 'exit t)))

(provide 'vm-mouse)
;;; vm-mouse.el ends here
