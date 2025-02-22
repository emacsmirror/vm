;;; vm-menu.el --- Menu related functions and commands  -*- lexical-binding: t; -*-
;;
;; This file is part of VM
;;
;; Copyright (C) 1994 Heiko Muenkel
;; Copyright (C) 1995, 1997 Kyle E. Jones
;; Copyright (C) 2003-2006 Robert Widhopf-Fenk
;; Copyright (C) 2024-2025 The VM Developers
;;
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
;;
;;; History:
;;
;; Folders menu derived from
;;     vm-folder-menu.el
;;     v1.10; 03-May-1994
;;     Copyright (C) 1994 Heiko Muenkel
;;     email: muenkel@tnt.uni-hannover.de
;;  Used with permission and my thanks.
;;  Changed 18-May-1995, Kyle Jones
;;     Cosmetic string changes, changed some variable names
;;     and interfaced it with FSF Emacs via easymenu.el.
;;   
;; Tree menu code is essentially tree-menu.el with renamed functions
;;     tree-menu.el
;;     v1.20; 10-May-1994
;;     Copyright (C) 1994 Heiko Muenkel
;;     email: muenkel@tnt.uni-hannover.de
;;
;;  Changed 18-May-1995, Kyle Jones
;;    Removed the need for the utils.el package and references thereto.
;;    Changed file-truename calls to tree-menu-file-truename so
;;    the calls could be made compatible with FSF Emacs 19's
;;    file-truename function.
;;  Changed 30-May-1995, Kyle Jones
;;    Renamed functions: tree- -> vm-menu-hm-tree.
;;  Changed 5-July-1995, Kyle Jones
;;    Removed the need for -A in ls flags.
;;    Some systems' ls don't support -A.

;;; Code:

(require 'vm-misc)
(require 'vm-mime)

(declare-function event-window "vm-xemacs" (event))
(declare-function event-point "vm-xemacs" (event))
(declare-function popup-mode-menu "vm-xemacs" (&optional event))
(declare-function event-closest-point "vm-xemacs" (event))
(declare-function find-menu-item "vm-xemacs" 
		  (menubar item-path-list &optional parent))
(declare-function add-menu-button "vm-xemacs" 
		  (menu-path menu-leaf &optional before in-menu))
(declare-function add-menu-item "vm-xemacs" 
		  (menu-path item-name function enabled-p &optional before))
(declare-function add-menu "vm-xemacs" 
		  (menu-path menu-name menu-items &optional before))
(declare-function set-menubar-dirty-flag "vm-xemacs" ())
(declare-function set-buffer-menubar "vm-xemacs" (menubar))


(declare-function vm-pop-find-name-for-spec "vm-pop" (spec))
(declare-function vm-imap-folder-for-spec "vm-imap" (spec))
(declare-function vm-mime-plain-message-p "vm-mime" (message))
(declare-function vm-yank-message "vm-reply" (message))
(declare-function vm-mail "vm" (&optional to subject))
(declare-function vm-get-header-contents "vm-summary"
		  (message header-name-regexp &optional clump-sep))
(declare-function vm-mail-mode-get-header-contents "vm-reply"
		  (header-name-regexp))
(declare-function vm-create-virtual-folder "vm-virtual"
		  (selector &optional arg read-only name bookmark))
(declare-function vm-create-virtual-folder-of-threads "vm-virtual"
		  (selector &optional arg read-only name bookmark))
(declare-function vm-so-sortable-subject "vm-sort" (message))
(declare-function vm-su-from "vm-summary" (message))


;; This will be extended in code
(defvar vm-menu-folders-menu
  '("Manipulate Folders"
    ["Make Folders Menu" vm-menu-hm-make-folder-menu vm-folder-directory])
  "VM folder menu list.")

(defconst vm-menu-folder-menu
  `("Folder"
    ,(if (not (featurep 'xemacs))
	["Manipulate Folders" ignore (ignore)]
      vm-menu-folders-menu)
    "---"
    ["Display Summary" vm-summarize t]
    ["Toggle Threading" vm-toggle-threads-display t]
    "---"
    ["Get New Mail" vm-get-new-mail (vm-menu-can-get-new-mail-p)]
    "---"
    ["Search" vm-isearch-forward vm-message-list]
    "---"
    ["Auto-Archive" vm-auto-archive-messages vm-message-list]
    ["Expunge" vm-expunge-folder vm-message-list]
    ["Expunge POP Messages" vm-expunge-pop-messages
     (vm-menu-can-expunge-pop-messages-p)]
    ["Expunge IMAP Messages" vm-expunge-imap-messages
     (vm-menu-can-expunge-imap-messages-p)]
    "---"
    ["Visit Local Folder" vm-visit-folder t]
    ["Visit POP Folder" vm-visit-pop-folder vm-pop-folder-alist]
    ["Visit IMAP Folder" vm-visit-imap-folder vm-imap-account-alist]
    ["Revert Folder (back to disk version)" vm-revert-buffer
     (vm-menu-can-revert-p)]
    ["Recover Folder (from auto-save file)" vm-recover-file
     (vm-menu-can-recover-p)]
    ["Save" vm-save-folder (vm-menu-can-save-p)]
    ["Save As..." vm-write-file t]
    ["Quit" vm-quit-no-change t]
    ["Save & Quit" vm-quit t]
    "---"
    ;; "---"
    ;; special string that marks the tail of this menu for
    ;; vm-menu-install-visited-folders-menu.
    "-------"
    ))

(defconst vm-menu-dispose-menu
  '("Dispose"
    ["Reply to Author" vm-reply vm-message-list]
    ["Reply to All" vm-followup vm-message-list]
    ["Reply to Author (citing original)" vm-reply-include-text
     vm-message-list]
    ["Reply to All (citing original)" vm-followup-include-text
     vm-message-list]
    ["Forward" vm-forward-message vm-message-list]
    ["Forward in Plain Text" vm-forward-message-plain vm-message-list]
    ["Resend" vm-resend-message vm-message-list]
    ["Retry Bounce" vm-resend-bounced-message vm-message-list]
    "---"
    ["File" vm-save-message vm-message-list]
    ["Delete" vm-delete-message vm-message-list]
    ["Undelete" vm-undelete-message vm-message-list]
    ["Flag/Unflag" vm-toggle-flag-message]
    ["Kill Current Subject" vm-kill-subject vm-message-list]
    ["Mark Unread" vm-mark-message-unread vm-message-list]
    ["Edit" vm-edit-message vm-message-list]
    ["Print" vm-print-message vm-message-list]
    ["Pipe to Command" vm-pipe-message-to-command vm-message-list]
    ["Attach to Message Composition"
     vm-attach-message-to-composition vm-message-list]
    "---"
    ["Burst Message as Digest" (vm-burst-digest "guess") vm-message-list]
    ["Decode MIME" vm-decode-mime-message (vm-menu-can-decode-mime-p)]
    ))

(defconst vm-menu-motion-menu
  '("Motion"
    ["Page Up" vm-scroll-backward vm-message-list]
    ["Page Down" vm-scroll-forward vm-message-list]
    "----"
    ["Beginning" vm-beginning-of-message vm-message-list]
    ["End" vm-end-of-message vm-message-list]
    "----"
    ["Expose/Hide Headers" vm-expose-hidden-headers vm-message-list]
    "----"
    ["Next Message" vm-next-message t]
    ["Previous Message"	vm-previous-message t]
    "---"
    ["Next, Same Subject" vm-next-message-same-subject t]
    ["Previous, Same Subject" vm-previous-message-same-subject t]
    "---"
    ["Next Unread" vm-next-unread-message t]
    ["Previous Unread" vm-previous-unread-message t]
    "---"
    ["Next Message (no skip)" vm-next-message-no-skip t]
    ["Previous Message (no skip)" vm-previous-message-no-skip t]
    "---"
    ["Go to Last Seen Message" vm-goto-message-last-seen t]
    ["Go to Message" vm-goto-message t]
    ["Go to Parent Message" vm-goto-parent-message t]
    ))

(defconst vm-menu-virtual-menu
  '("Virtual"
    ["Visit Virtual Folder" vm-visit-virtual-folder t]
    ["Apply Virtual Folder Selectors" vm-apply-virtual-folder t]
    ["Omit Message" vm-virtual-omit-message t]
    ["Update all" vm-virtual-update-folders]
    "---"
    "Search Folders"
    ["Author" vm-create-author-virtual-folder t]
    ["Recipients" vm-create-author-or-recipient-virtual-folder t]
    ["Subject" vm-create-subject-virtual-folder t]
    ["Text (Body)" vm-create-text-virtual-folder t]
    ["Days" vm-create-date-virtual-folder t]
    ["Label" vm-create-label-virtual-folder t]
    ["Flagged" vm-create-flagged-virtual-folder t]
    ["Unseen" vm-create-unseen-virtual-folder t]
    ["Same Author as current" vm-create-virtual-folder-same-author t]
    ["Same Subject as current" vm-create-virtual-folder-same-subject t]
    ["Create General" vm-create-virtual-folder t]
    ["Create General (Threads)" vm-create-virtual-folder-of-threads t]
    "---"
    "Auto operations"
    ["Delete Message(s)" vm-virtual-auto-delete-message t]
    ["Save Message(s)" vm-virtual-save-message t]
    ["Archive Messages" vm-virtual-auto-archive-messages t]
    
    ;; special string that marks the tail of this menu for
    ;; vm-menu-install-known-virtual-folders-menu.
    "-------"
    ))

(defconst vm-menu-send-menu
  '("Send"
    ["Compose" vm-mail t]
    ["Continue Composing" vm-continue-composing-message vm-message-list]
    ["Reply to Author" vm-reply vm-message-list]
    ["Reply to All" vm-followup vm-message-list]
    ["Reply to Author (citing original)" vm-reply-include-text vm-message-list]
    ["Reply to All (citing original)" vm-followup-include-text vm-message-list]
    ["Forward Message" vm-forward-message vm-message-list]
    ["Forward Message in Plain Text" vm-forward-message-plain vm-message-list]
    ["Resend Message" vm-resend-message vm-message-list]
    ["Retry Bounced Message" vm-resend-bounced-message vm-message-list]
    ["Send Digest (RFC934)" vm-send-rfc934-digest vm-message-list]
    ["Send Digest (RFC1153)" vm-send-rfc1153-digest vm-message-list]
    ["Send MIME Digest" vm-send-mime-digest vm-message-list]
    ))

(defconst vm-menu-mark-menu
  '("Mark"
    ["Next Command Uses Marks..." vm-next-command-uses-marks
     :active vm-message-list
     :style radio
     :selected (eq last-command 'vm-next-command-uses-marks)]
    "----"
    ["Mark Message" vm-mark-message vm-message-list]
    ["Mark All Messages" vm-mark-all-messages vm-message-list]
    ["Mark Region in Summary" vm-mark-summary-region vm-message-list]
    ["Mark Thread Subtree" vm-mark-thread-subtree vm-message-list]
    ["Mark by Selector..." vm-mark-messages-by-selector vm-message-list]
    ["Mark by Virtual Folder..." 
     vm-mark-messages-by-virtual-folder vm-message-list]
    ["Mark Same Subject" vm-mark-messages-same-subject vm-message-list]
    ["Mark Same Author" vm-mark-messages-same-author vm-message-list]
    "----"
    ["Unmark Message" vm-unmark-message vm-message-list]
    ["Unmark All Messages" vm-clear-all-marks vm-message-list]
    ["Unmark Region in Summary" vm-unmark-summary-region vm-message-list]
    ["Unmark Thread Subtree" vm-unmark-thread-subtree vm-message-list]
    ["Unmark by Selector..." vm-unmark-messages-by-selector vm-message-list]
    ["Unmark by Virtual Folder..." 
     vm-unmark-messages-by-virtual-folder vm-message-list]
    ["Unmark Same Subject" vm-unmark-messages-same-subject vm-message-list]
    ["Unmark Same Author" vm-unmark-messages-same-author vm-message-list]
    ))

(defconst vm-menu-label-menu
  '("Label"
    ["Add Label" vm-add-message-labels vm-message-list]
    ["Add Existing Label" vm-add-existing-message-labels vm-message-list]
    ["Remove Label" vm-delete-message-labels vm-message-list]
    ))

(defconst vm-menu-sort-menu
  '("Sort"
    "By ascending"
    "---"
    ["Date" (vm-sort-messages "date") vm-message-list]
    ["Activity" (vm-sort-messages "activity") vm-message-list]
    ["Subject" (vm-sort-messages "subject") vm-message-list]
    ["Author" (vm-sort-messages "author") vm-message-list]
    ["Recipients" (vm-sort-messages "recipients") vm-message-list]
    ["Lines" (vm-sort-messages "line-count") vm-message-list]
    ["Bytes" (vm-sort-messages "byte-count") vm-message-list]
    "---"
    "By descending"
    "---"
    ["Date" (vm-sort-messages "reversed-date") vm-message-list]
    ["Activity" (vm-sort-messages "reversed-activity") vm-message-list]
    ["Subject" (vm-sort-messages "reversed-subject") vm-message-list]
    ["Author" (vm-sort-messages "reversed-author") vm-message-list]
    ["Recipients" (vm-sort-messages "reversed-recipients") vm-message-list]
    ["Lines" (vm-sort-messages "reversed-line-count") vm-message-list]
    ["Bytes" (vm-sort-messages "reversed-byte-count") vm-message-list]
    "---"
    ["By Multiple Fields..." vm-sort-messages vm-message-list]
    ["Revert to Physical Order" (vm-sort-messages "physical-order" t) vm-message-list]
    "---"
    ["Toggle Threading" vm-toggle-threads-display t]
    ["Expand/Collapse Thread" vm-toggle-thread t]
    ["Expand All Threads" vm-expand-all-threads t]
    ["Collapse All Threads" vm-collapse-all-threads t]
    ))

(defconst vm-menu-help-menu
  '("Help"
    ["Switch to Emacs Menubar" vm-menu-toggle-menubar t]
    "---"
    ["Customize VM" vm-customize t]
    ["Describe VM Mode" describe-mode t]
    ["VM News" vm-view-news t]
    ["VM Manual" vm-view-manual t]
    ["Submit Bug Report" vm-submit-bug-report t]
    "---"
    ["What Now?" vm-help t]
    ["Revert Folder (back to disk version)" revert-buffer (vm-menu-can-revert-p)]
    ["Recover Folder (from auto-save file)" recover-file (vm-menu-can-recover-p)]
    "---"
    ["Save Folder & Quit" vm-quit t]
    ["Quit Without Saving" vm-quit-no-change t]
    ))

(defconst vm-menu-xemacs-undo-button
  ["[Undo]" vm-undo (vm-menu-can-undo-p)]
  )

(defconst vm-menu-undo-menu
  '("Undo"
    ["Undo" vm-undo (vm-menu-can-undo-p)]
    )
  "Undo menu for FSF Emacs builds that do not allow menubar buttons.")

(defconst vm-menu-emacs-button
  ["[Emacs Menubar]" vm-menu-toggle-menubar t]
  )

(defconst vm-menu-emacs-menu
  '("Menubar"
    ["Switch to Emacs Menubar" vm-menu-toggle-menubar t]
    )
  "Menu with a \"Swich to Emacs\" action meant for FSF Emacs builds that
do not allow menubar buttons.")

(defconst vm-menu-vm-button
  ["[VM Menubar]" vm-menu-toggle-menubar t]
  )

(defconst vm-menu-mail-menu
  '("Mail Commands"
    ["Send and Exit" vm-mail-send-and-exit (vm-menu-can-send-mail-p)]
    ["Send, Keep Composing" vm-mail-send (vm-menu-can-send-mail-p)]
    ["Cancel" kill-buffer t]
    "----"
    ["Yank Original" vm-menu-yank-original vm-reply-list]
    "----"
    ("Send Using MIME..."
     ["Use MIME"
      (progn (set (make-local-variable 'vm-send-using-mime) t)
	     (vm-mail-mode-remove-tm-hooks))
      :active t
      :style radio
      :selected vm-send-using-mime]
     ["Don't use MIME"
      (set (make-local-variable 'vm-send-using-mime) nil)
      :active t
      :style radio
      :selected (not vm-send-using-mime)])
    (
     "Fragment Messages Larger Than ..."
     ["Infinity, i.e., don't fragment"
      (set (make-local-variable 'vm-mime-max-message-size) nil)
      :active vm-send-using-mime
      :style radio
      :selected (eq vm-mime-max-message-size nil)]
     ["50000 bytes"
      (set (make-local-variable 'vm-mime-max-message-size)
	   50000)
      :active vm-send-using-mime
      :style radio
      :selected (eq vm-mime-max-message-size 50000)]
     ["100000 bytes"
      (set (make-local-variable 'vm-mime-max-message-size)
	   100000)
      :active vm-send-using-mime
      :style radio
      :selected (eq vm-mime-max-message-size 100000)]
     ["200000 bytes"
      (set (make-local-variable 'vm-mime-max-message-size)
	   200000)
      :active vm-send-using-mime
      :style radio
      :selected (eq vm-mime-max-message-size 200000)]
     ["500000 bytes"
      (set (make-local-variable 'vm-mime-max-message-size)
	   500000)
      :active vm-send-using-mime
      :style radio
      :selected (eq vm-mime-max-message-size 500000)]
     ["1000000 bytes"
      (set (make-local-variable 'vm-mime-max-message-size)
	   1000000)
      :active vm-send-using-mime
      :style radio
      :selected (eq vm-mime-max-message-size 1000000)]
     ["2000000 bytes"
      (set (make-local-variable 'vm-mime-max-message-size)
	   2000000)
      :active vm-send-using-mime
      :style radio
      :selected (eq vm-mime-max-message-size 2000000)])
    (
     "Encode 8-bit Characters Using ..."
     ["Nothing, i.e., send unencoded"
      (set (make-local-variable 'vm-mime-8bit-text-transfer-encoding)
	   '8bit)
      :active vm-send-using-mime
      :style radio
      :selected (eq vm-mime-8bit-text-transfer-encoding '8bit)]
     ["Quoted-Printable"
      (set (make-local-variable 'vm-mime-8bit-text-transfer-encoding)
	   'quoted-printable)
      :active vm-send-using-mime
      :style radio
      :selected (eq vm-mime-8bit-text-transfer-encoding
		    'quoted-printable)]
     ["BASE64"
      (set (make-local-variable 'vm-mime-8bit-text-transfer-encoding)
	   'base64)
      :active vm-send-using-mime
      :style radio
      :selected (eq vm-mime-8bit-text-transfer-encoding 'base64)])
    "----"
    ["Attach File..."	vm-attach-file vm-send-using-mime]
    ["Attach MIME Message..." vm-attach-mime-file vm-send-using-mime]
    ["Encode MIME, But Don't Send" vm-mime-encode-composition
     (and vm-send-using-mime
	  (null (vm-mail-mode-get-header-contents "MIME-Version:")))]
    ["Preview MIME Before Sending" vm-preview-composition
     vm-send-using-mime]
    ))

(defconst vm-menu-mime-dispose-menu
  '("Take Action on MIME body ..."
    ["Display as Text (in default face)"
     vm-mime-reader-map-display-using-default t]
    ["Display using External Viewer"
     vm-mime-reader-map-display-using-external-viewer t]
    ["Convert to Text and Display"
     vm-mime-reader-map-convert-then-display
     (vm-menu-can-convert-to-text/plain (vm-mime-get-button-layout))]
    ;; FSF Emacs does not allow a non-string menu element name.
    ;; This is not working on XEmacs either.  USR, 2011-03-05
    ;; ,@(if (vm-menu-can-eval-item-name)
    ;; 	    (list [(format "Convert to %s and Display"
    ;; 			   (or (nth 1 (vm-mime-can-convert
    ;; 				       (car
    ;; 					(vm-mm-layout-type
    ;; 					 (vm-mime-get-button-layout)))))
    ;; 			       "different type"))
    ;; 		   (vm-mime-run-display-function-at-point
    ;; 		    'vm-mime-convert-body-then-display)
    ;; 		   (vm-mime-can-convert
    ;; 		    (car (vm-mm-layout-type
    ;; 			  (vm-mime-get-button-layout))))]))
    "---"
    ["Undo"
     vm-undo]
    "---"
    ["Save to File"
     vm-mime-reader-map-save-file t]
    ["Save to Folder"
     vm-mime-reader-map-save-message
     (let ((layout (vm-mime-get-button-layout)))
       (if (null layout)
	   nil
	 (or (vm-mime-types-match "message/rfc822"
				  (car (vm-mm-layout-type layout)))
	     (vm-mime-types-match "message/news"
				  (car (vm-mm-layout-type layout))))))]
    ["Send to Printer"
     vm-mime-reader-map-pipe-to-printer t]
    ["Pipe to Shell Command (display output)"
     vm-mime-reader-map-pipe-to-command t]
    ["Pipe to Shell Command (discard output)"
     vm-mime-reader-map-pipe-to-command-discard-output t]
    ["Attach to Message Composition Buffer"
     vm-mime-reader-map-attach-to-composition t]
    ["Delete" vm-delete-mime-object t]))

(defconst vm-menu-url-browser-menu
  (let ((w3 (cond ((fboundp 'w3-fetch-other-frame)
		   'w3-fetch-other-frame)
		  ((fboundp 'w3-fetch)
		   'w3-fetch)
		  (t 'w3-fetch-other-frame))))
    `("Send URL to ..."
      ["Window system (Copy)"
       (vm-mouse-send-url-at-position 
	(point) 'vm-mouse-send-url-to-window-system)
       t]
      ["X Clipboard"
       (vm-mouse-send-url-at-position 
	(point) 'vm-mouse-send-url-to-clipboard)
       t]
      ["browse-url"
       (vm-mouse-send-url-at-position (point) 'browse-url) 
       browse-url-browser-function]
      ["Emacs W3" (vm-mouse-send-url-at-position (point) (quote ,w3))
       (fboundp (quote ,w3))]
      ["Emacs W3M" (vm-mouse-send-url-at-position (point) 'w3m-browse-url)
       (fboundp 'w3m-browse-url)]
      "---"
      ["Firefox"
       (vm-mouse-send-url-at-position 
	(point) 'vm-mouse-send-url-to-firefox)
       vm-firefox-program]
      ["Konqueror"
       (vm-mouse-send-url-at-position 
	(point) 'vm-mouse-send-url-to-konqueror)
       vm-konqueror-client-program]
      ;; ["Mosaic"
      ;;  (vm-mouse-send-url-at-position 
      ;;  (point) 'vm-mouse-send-url-to-mosaic)
      ;;  vm-mosaic-program]
      ;; ["mMosaic"
      ;;  (vm-mouse-send-url-at-position 
      ;; 	(point) 'vm-mouse-send-url-to-mmosaic)
      ;;  vm-mmosaic-program]
      ["Mozilla"
       (vm-mouse-send-url-at-position 
	(point) 'vm-mouse-send-url-to-mozilla)
       vm-mozilla-program]
;;       ["Netscape"
;;        (vm-mouse-send-url-at-position 
;; 	(point) 'vm-mouse-send-url-to-netscape)
;;        vm-netscape-program]
      ["Opera"
       (vm-mouse-send-url-at-position 
	(point) 'vm-mouse-send-url-to-opera)
       vm-opera-program])))

(defconst vm-menu-mailto-url-browser-menu
  `("Send Mail using ..."
    ["VM" (vm-mouse-send-url-at-position (point) 'ignore) t]))

(defconst vm-menu-subject-menu
  '("Take Action on Subject..."
    ["Kill Subject" vm-kill-subject vm-message-list]
    ["Next Message, Same Subject" vm-next-message-same-subject
     vm-message-list]
    ["Previous Message, Same Subject" vm-previous-message-same-subject
     vm-message-list]
    ["Mark Messages, Same Subject" vm-mark-messages-same-subject
     vm-message-list]
    ["Unmark Messages, Same Subject" vm-unmark-messages-same-subject
     vm-message-list]
    ["Virtual Folder, Matching Subject" vm-menu-create-subject-virtual-folder
     vm-message-list]
    ))

(defconst vm-menu-author-menu
  '("Take Action on Author..."
    ["Mark Messages, Same Author" vm-mark-messages-same-author
     vm-message-list]
    ["Unmark Messages, Same Author" vm-unmark-messages-same-author
     vm-message-list]
    ["Virtual Folder, Matching Author" vm-menu-create-author-virtual-folder
     vm-message-list]
    ["Send a message" vm-menu-mail-to
     vm-message-list]
    ))

(defconst vm-menu-attachment-menu
  `("Fiddle With Attachment"
    ("Set Content Disposition..."
     ["Unspecified"
      (vm-mime-set-attachment-disposition-at-point 'unspecified)
      :active vm-send-using-mime
      :style radio
      :selected (eq (vm-mime-attachment-disposition-at-point)
		    'unspecified)]
     ["Inline"
      (vm-mime-set-attachment-disposition-at-point 'inline)
      :active vm-send-using-mime
      :style radio
      :selected (eq (vm-mime-attachment-disposition-at-point) 'inline)]
     ["Attachment"
      (vm-mime-set-attachment-disposition-at-point 'attachment)
      :active vm-send-using-mime
      :style radio
      :selected (eq (vm-mime-attachment-disposition-at-point)
		    'attachment)])
    ("Set Content Encoding..."
     ["Guess"
      (vm-mime-set-attachment-encoding-at-point "guess")
      :active vm-send-using-mime
      :style radio
      :selected (eq (vm-mime-attachment-encoding-at-point) nil)]
     ["Binary"
      (vm-mime-set-attachment-encoding-at-point "binary")
      :active vm-send-using-mime
      :style radio
      :selected (string= (vm-mime-attachment-encoding-at-point) "binary")]
     ["7bit"
      (vm-mime-set-attachment-encoding-at-point "7bit")
      :active vm-send-using-mime
      :style radio
      :selected (string= (vm-mime-attachment-encoding-at-point) "7bit")]
     ["8bit"
      (vm-mime-set-attachment-encoding-at-point "8bit")
      :active vm-send-using-mime
      :style radio
      :selected (string= (vm-mime-attachment-encoding-at-point) "8bit")]
     ["quoted-printable"
      (vm-mime-set-attachment-encoding-at-point "quoted-printable")
      :active vm-send-using-mime
      :style radio
      :selected (string= (vm-mime-attachment-encoding-at-point) "quoted-printable")]
     )
    ("Saved attachments"
     ["Include references"
      (vm-mime-set-attachment-forward-local-refs-at-point t)
      :active vm-send-using-mime
      :style radio
      :selected (vm-comp-comp-forward-local-refs-at-point)]
     ["Include objects"
      (vm-mime-set-attachment-forward-local-refs-at-point nil)
      :active vm-send-using-mime
      :style radio
      :selected (not (vm-mime-attachment-forward-local-refs-at-point))])
    ["Delete"
     (vm-mime-delete-attachment-button)
     :style button]
    ["Delete, but keep infos"
     (vm-mime-delete-attachment-button-keep-infos)
     :style button]
    ))

(defconst vm-menu-image-menu
  `("Redisplay Image"
    ["4x Larger"
     (vm-mime-run-display-function-at-point 'vm-mime-larger-image)
     (stringp vm-imagemagick-convert-program)]
    ["4x Smaller"
     (vm-mime-run-display-function-at-point 'vm-mime-smaller-image)
     (stringp vm-imagemagick-convert-program)]
    ["Rotate Left"
     (vm-mime-run-display-function-at-point 'vm-mime-rotate-image-left)
     (stringp vm-imagemagick-convert-program)]
    ["Rotate Right"
     (vm-mime-run-display-function-at-point 'vm-mime-rotate-image-right)
     (stringp vm-imagemagick-convert-program)]
    ["Mirror"
     (vm-mime-run-display-function-at-point 'vm-mime-mirror-image)
     (stringp vm-imagemagick-convert-program)]
    ["Brighter"
     (vm-mime-run-display-function-at-point 'vm-mime-brighten-image)
     (stringp vm-imagemagick-convert-program)]
    ["Dimmer"
     (vm-mime-run-display-function-at-point 'vm-mime-dim-image)
     (stringp vm-imagemagick-convert-program)]
    ["Monochrome"
     (vm-mime-run-display-function-at-point 'vm-mime-monochrome-image)
     (stringp vm-imagemagick-convert-program)]
    ["Revert to Original"
     (vm-mime-run-display-function-at-point 'vm-mime-revert-image)
     (get
      (vm-mm-layout-cache
       (vm-extent-property (vm-find-layout-extent-at-point) 'vm-mime-layout))
      'vm-image-modified)]
    ))

(defvar vm-menu-vm-menubar nil)

(defconst vm-menu-vm-menu
  `("VM"
    ,vm-menu-folder-menu
    ,vm-menu-motion-menu
    ,vm-menu-send-menu
    ,vm-menu-mark-menu
    ,vm-menu-label-menu
    ,vm-menu-sort-menu
    ,vm-menu-virtual-menu
    ;;    ,vm-menu-undo-menu
    ,vm-menu-dispose-menu
    "---"
    "---"
    ,vm-menu-help-menu))

(defvar vm-mode-menu-map nil
  "If running in FSF Emacs, this variable stores the standard
menu bar of VM internally.                  USR, 2011-02-27")

(defun vm-menu-run-command (command &rest args)
  "Run COMMAND almost interactively, with ARGS.
call-interactive can't be used unfortunately, but this-command is
set to the command name so that window configuration will be done."
  (setq this-command command)
  (apply command args))

(defun vm-menu-can-revert-p ()
  (condition-case nil
      (save-excursion
	(vm-select-folder-buffer)
	(and (buffer-modified-p) buffer-file-name))
    (error nil)))

(defun vm-menu-can-recover-p ()
  (condition-case nil
      (save-excursion
	(vm-select-folder-buffer)
	(and buffer-file-name
	     buffer-auto-save-file-name
	     (file-newer-than-file-p
	      buffer-auto-save-file-name
	      buffer-file-name)))
    (error nil)))

(defun vm-menu-can-save-p ()
  (condition-case nil
      (save-excursion
	(vm-select-folder-buffer)
	(or (eq major-mode 'vm-virtual-mode)
	    (buffer-modified-p)))
    (error nil)))

(defun vm-menu-can-get-new-mail-p ()
  (condition-case nil
      (save-excursion
	(vm-select-folder-buffer)
	(or (eq major-mode 'vm-virtual-mode)
	    (and (not vm-block-new-mail) (not vm-folder-read-only))))
    (error nil)))

(defun vm-menu-can-undo-p ()
  (condition-case nil
      (save-excursion
	(vm-select-folder-buffer)
	vm-undo-record-list)
    (error nil)))

(defun vm-menu-can-decode-mime-p ()
  (condition-case nil
      (save-excursion
	(vm-select-folder-buffer)
	(and vm-display-using-mime
	     vm-message-pointer
	     vm-presentation-buffer
;;	     (not vm-mime-decoded)
	     (not (vm-mime-plain-message-p (car vm-message-pointer)))))
    (error nil)))

(defun vm-menu-can-convert-to-text/plain (layout)
  (let ((type (car (vm-mm-layout-type layout))))
    (or (equal (nth 1 (vm-mime-can-convert type)) "text/plain")
	(and (equal type "message/external-body")
	     (vm-menu-can-convert-to-text/plain
	      (car (vm-mm-layout-parts layout)))))))

(defun vm-menu-can-expunge-pop-messages-p ()
  (condition-case nil
      (save-excursion
	(vm-select-folder-buffer)
	(not (eq vm-folder-access-method 'pop)))
    (error nil)))

(defun vm-menu-can-expunge-imap-messages-p ()
  (condition-case nil
      (save-excursion
	(vm-select-folder-buffer)
	(not (eq vm-folder-access-method 'imap)))
    (error nil)))

(defun vm-menu-yank-original ()
  (interactive)
  (save-excursion
    (let ((mlist vm-reply-list))
      (while mlist
	(vm-yank-message (car mlist))
	(goto-char (point-max))
	(setq mlist (cdr mlist))))))

(defun vm-menu-can-send-mail-p ()
  (save-match-data
    (catch 'done
      (let ((headers '("to" "cc" "bcc" "resent-to" "resent-cc" "resent-bcc"))
	    h)
	(while headers
	  (setq h (vm-mail-mode-get-header-contents (car headers)))
	  (and (stringp h) (string-match "[^ \t\n,]" h)
	       (throw 'done t))
	  (setq headers (cdr headers)))
	nil ))))

(defun vm-menu-create-subject-virtual-folder ()
  (interactive)
  (vm-select-folder-buffer-and-validate 0 (vm-interactive-p))
  (setq this-command 'vm-create-virtual-folder)
  (vm-create-virtual-folder 'sortable-subject (regexp-quote
	 			       (vm-so-sortable-subject
	 				(car vm-message-pointer)))))

(defun vm-menu-create-author-virtual-folder ()
  (interactive)
  (vm-select-folder-buffer-and-validate 0 (vm-interactive-p))
  (setq this-command 'vm-create-virtual-folder)
  (vm-create-virtual-folder 'author (regexp-quote
				     (vm-su-from (car vm-message-pointer)))))

(defun vm-menu-mail-to ()
  (interactive)
  (vm-select-folder-buffer-and-validate 0 (vm-interactive-p))
  (setq this-command 'vm-mail)
  (vm-mail (vm-get-header-contents (car vm-message-pointer) "From:")))


(defun vm-menu--global-menubar ()
  (if (featurep 'xemacs)
      (with-current-buffer (get-buffer-create "*scratch*")
        current-menubar)
    (lookup-key (current-global-map) [menu-bar])))

(defun vm-menu-initialize-vm-mode-menu-map ()
  (if (null vm-mode-menu-map)
      (let ((map (make-sparse-keymap))
	    (dummy (make-sparse-keymap)))
	;; initialize all the vm-menu-fsfemacs-*-menu variables
	;; with the menus.
	(easy-menu-define vm-menu-fsfemacs-help-menu (list dummy) nil
			     vm-menu-help-menu)
	(easy-menu-define vm-menu-fsfemacs-dispose-menu (list dummy) nil
			     (cons "Dispose" (nthcdr 4 vm-menu-dispose-menu)))
	(easy-menu-define vm-menu-fsfemacs-dispose-popup-menu (list dummy) nil
			     vm-menu-dispose-menu)
	(easy-menu-define vm-menu-fsfemacs-undo-menu (list dummy) nil
	  		     vm-menu-undo-menu)
	(easy-menu-define vm-menu-fsfemacs-emacs-menu (list dummy) nil
			     vm-menu-emacs-menu)
	(easy-menu-define vm-menu-fsfemacs-virtual-menu (list dummy) nil
			     vm-menu-virtual-menu)
	(easy-menu-define vm-menu-fsfemacs-sort-menu (list dummy) nil
			     vm-menu-sort-menu)
	(easy-menu-define vm-menu-fsfemacs-label-menu (list dummy) nil
			     vm-menu-label-menu)
	(easy-menu-define vm-menu-fsfemacs-mark-menu (list dummy) nil
			     vm-menu-mark-menu)
	(easy-menu-define vm-menu-fsfemacs-send-menu (list dummy) nil
			     vm-menu-send-menu)
	(easy-menu-define vm-menu-fsfemacs-motion-menu (list dummy) nil
			     vm-menu-motion-menu)
;;	(easy-menu-define vm-menu-fsfemacs-folders-menu (list dummy) nil
;;			     vm-menu-folders-menu)
	(easy-menu-define vm-menu-fsfemacs-folder-menu (list dummy) nil
			     vm-menu-folder-menu)
	(easy-menu-define vm-menu-fsfemacs-vm-menu (list dummy) nil
			     vm-menu-vm-menu)
	;; for mail mode
	(easy-menu-define vm-menu-fsfemacs-mail-menu (list dummy) nil
			     vm-menu-mail-menu)
	;; subject menu
	(easy-menu-define vm-menu-fsfemacs-subject-menu (list dummy) nil
			     vm-menu-subject-menu)
	;; author menu
	(easy-menu-define vm-menu-fsfemacs-author-menu (list dummy) nil
			     vm-menu-author-menu)
	;; url browser menu
	(easy-menu-define vm-menu-fsfemacs-url-browser-menu (list dummy) nil
			     vm-menu-url-browser-menu)
	;; mailto url browser menu
	(easy-menu-define vm-menu-fsfemacs-mailto-url-browser-menu
			     (list dummy) nil
			     vm-menu-url-browser-menu)
	;; mime dispose menu
	(easy-menu-define vm-menu-fsfemacs-mime-dispose-menu
			     (list dummy) nil
			     vm-menu-mime-dispose-menu)
	;; attachment menu
	(easy-menu-define vm-menu-fsfemacs-attachment-menu
			     (list dummy) nil
			     vm-menu-attachment-menu)
	;; image menu
	(easy-menu-define vm-menu-fsfemacs-image-menu
			     (list dummy) nil
			     vm-menu-image-menu)
	;; block the global menubar entries in the map so that VM
	;; can take over the menubar if necessary.
	(define-key map [rootmenu] (make-sparse-keymap))
	(define-key map [rootmenu vm] (cons "VM" (make-sparse-keymap "VM")))
	(define-key map [rootmenu vm file] 'undefined)
	(define-key map [rootmenu vm files] 'undefined)
	(define-key map [rootmenu vm search] 'undefined)
	(define-key map [rootmenu vm edit] 'undefined)
	(define-key map [rootmenu vm options] 'undefined)
	(define-key map [rootmenu vm buffer] 'undefined)
	(define-key map [rootmenu vm tools] 'undefined)
	(define-key map [rootmenu vm help] 'undefined)
	(define-key map [rootmenu vm mule] 'undefined)
	;; 19.29 changed the tag for the Help menu.
	(define-key map [rootmenu vm help-menu] 'undefined)
	;; now build VM's menu tree.
	(let ((menu-alist
	       '((dispose
		  (cons "Dispose" vm-menu-fsfemacs-dispose-menu))
		 (folder
		  (cons "Folder" vm-menu-fsfemacs-folder-menu))
		 (help
		  (cons "Help" vm-menu-fsfemacs-help-menu))
		 (label
		  (cons "Label" vm-menu-fsfemacs-label-menu))
		 (mark
		  (cons "Mark" vm-menu-fsfemacs-mark-menu))
		 (motion
		  (cons "Motion" vm-menu-fsfemacs-motion-menu))
		 (send
		  (cons "Send" vm-menu-fsfemacs-send-menu))
		 (sort
		  (cons "Sort" vm-menu-fsfemacs-sort-menu))
		 (virtual
		  (cons "Virtual" vm-menu-fsfemacs-virtual-menu))
		 (emacs
		  (if (and (vm-menubar-buttons-possible-p) 
			   vm-use-menubar-buttons)
		      (cons "[Emacs Menubar]" 'vm-menu-toggle-menubar)
		    (cons "Menubar" vm-menu-fsfemacs-emacs-menu)))
		 (undo
		  (if (and (vm-menubar-buttons-possible-p)
			   vm-use-menubar-buttons)
		      (cons "[Undo]" 'vm-undo)
		    (cons "Undo" vm-menu-fsfemacs-undo-menu)))))
	      (cons nil)
	      (vec (vector 'rootmenu 'vm nil))
	      ;; menus appear in the opposite order that we
	      ;; define-key them.
	      (menu-list
	       (if (consp vm-use-menus)
		   (reverse vm-use-menus)
		 (list 'help nil 'dispose 'undo 'virtual 'sort
		       'label 'mark 'send 'motion 'folder)))
	      (menu nil))
	  (while menu-list
	    (setq menu (car menu-list))
	    (if (null menu)
		nil;; no flushright support in FSF Emacs
	      (aset vec 2 (intern (concat "vm-menubar-" (symbol-name menu))))
	      (setq cons (assq menu menu-alist))
	      (if cons
		  (define-key map vec (eval (cadr cons)))))
	    (setq menu-list (cdr menu-list))))
	(setq vm-mode-menu-map map)
	(run-hooks 'vm-menu-setup-hook))))

(defun vm-menu-make-xemacs-menubar ()
  (let ((menu-alist
	 '((dispose . vm-menu-dispose-menu)
	   (folder . vm-menu-folder-menu)
	   (help . vm-menu-help-menu)
	   (label . vm-menu-label-menu)
	   (mark . vm-menu-mark-menu)
	   (motion . vm-menu-motion-menu)
	   (send . vm-menu-send-menu)
	   (sort . vm-menu-sort-menu)
	   (virtual . vm-menu-virtual-menu)
	   (emacs . vm-menu-emacs-button)
	   (undo . vm-menu-xemacs-undo-button)))
	cons
	(menubar nil)
	(menu-list vm-use-menus))
    (while menu-list
      (if (null (car menu-list))
	  (setq menubar (cons nil menubar))
	(setq cons (assq (car menu-list) menu-alist))
	(if cons
	    (setq menubar (cons (symbol-value (cdr cons)) menubar))))
      (setq menu-list (cdr menu-list)))
    (nreverse menubar) ))

(defun vm-menu-popup-mode-menu (event)
  (interactive "e")
  (cond ((and (featurep 'xemacs) vm-use-menus)
	 (set-buffer (window-buffer (event-window event)))
	 (and (event-point event) (goto-char (event-point event)))
	 (popup-mode-menu))
	((and (not (featurep 'xemacs)) vm-use-menus)
	 (set-buffer (window-buffer (posn-window (event-start event))))
	 (goto-char (posn-point (event-start event)))
	 (vm-menu-popup-fsfemacs-menu event))))

(defvar vm-menu-fsfemacs-attachment-menu)
(defun vm-menu-popup-context-menu (event)
  (interactive "e")
  ;; We should not need to do anything here for XEmacs.  The
  ;; default binding of mouse-3 is popup-mode-menu which does
  ;; what we want for the normal case.  For special context,s
  ;; like when the mouse is over an URL, XEmacs has local keymap
  ;; support for extents.  Any context sensitive area should be
  ;; contained in an extent with a keymap that has mouse-3 bound
  ;; to a function that will pop up a context sensitive menu.
  (cond ((and (not (featurep 'xemacs)) vm-use-menus)
	 (set-buffer (window-buffer (posn-window (event-start event))))
	 (goto-char (posn-point (event-start event)))
	 (if (get-text-property (point) 'vm-mime-object)
	     (vm-menu-popup-fsfemacs-menu
	      event vm-menu-fsfemacs-attachment-menu)
	   (let (o-list menu (found nil)) ;; o
	     (setq o-list (overlays-at (point)))
	     (while (and o-list (not found))
	       (cond ((overlay-get (car o-list) 'vm-url)
		      (setq found t)
		      (vm-menu-popup-url-browser-menu event))
		     ((setq menu (overlay-get (car o-list) 'vm-header))
		      (setq found t)
		      (vm-menu-popup-fsfemacs-menu event menu))
		     ((setq menu (overlay-get (car o-list) 'vm-image))
		      (setq found t)
		      (vm-menu-popup-fsfemacs-menu event menu))
		     ((overlay-get (car o-list) 'vm-mime-layout)
		      (setq found t)
		      (vm-menu-popup-mime-dispose-menu event)))
	       (setq o-list (cdr o-list)))
	     (and (not found) (vm-menu-popup-fsfemacs-menu event)))))))

;; to quiet the byte-compiler
(defvar vm-menu-fsfemacs-url-browser-menu)
(defvar vm-menu-fsfemacs-mailto-url-browser-menu)
(defvar vm-menu-fsfemacs-mime-dispose-menu)

(defun vm-menu-goto-event (event)
  (cond ((featurep 'xemacs)
	 ;; Must select window instead of just set-buffer because
	 ;; popup-menu returns before the user has made a
	 ;; selection.  This will cause the command loop to
	 ;; resume which might undo what set-buffer does.
	 (select-window (event-window event))
	 (and (event-closest-point event)
	      (goto-char (event-closest-point event))))
	((not (featurep 'xemacs))
	 (set-buffer (window-buffer (posn-window (event-start event))))
	 (goto-char (posn-point (event-start event))))))

(defun vm-menu-popup-url-browser-menu (event)
  (interactive "e")
  (vm-menu-goto-event event)
  (cond ((and (featurep 'xemacs) vm-use-menus)
	 (popup-menu vm-menu-url-browser-menu))
	((and (not (featurep 'xemacs)) vm-use-menus)
	 (vm-menu-popup-fsfemacs-menu
	  event vm-menu-fsfemacs-url-browser-menu))))

(defun vm-menu-popup-mailto-url-browser-menu (event)
  (interactive "e")
  (vm-menu-goto-event event)
  (cond ((and (featurep 'xemacs) vm-use-menus)
	 (popup-menu vm-menu-mailto-url-browser-menu))
	((and (not (featurep 'xemacs)) vm-use-menus)
	 (vm-menu-popup-fsfemacs-menu
	  event vm-menu-fsfemacs-mailto-url-browser-menu))))

(defun vm-menu-popup-mime-dispose-menu (event)
  (interactive "e")
  (vm-menu-goto-event event)
  (cond ((and (featurep 'xemacs) vm-use-menus)
	 (popup-menu vm-menu-mime-dispose-menu))
	((and (not (featurep 'xemacs)) vm-use-menus)
	 (vm-menu-popup-fsfemacs-menu
	  event vm-menu-fsfemacs-mime-dispose-menu))))

(defun vm-menu-popup-attachment-menu (event)
  (interactive "e")
  (vm-menu-goto-event event)
  (cond ((and (featurep 'xemacs) vm-use-menus)
	 (popup-menu vm-menu-attachment-menu))
	((and (not (featurep 'xemacs)) vm-use-menus)
	 (vm-menu-popup-fsfemacs-menu
	  event vm-menu-fsfemacs-attachment-menu))))

(defvar vm-menu-fsfemacs-image-menu)
(defun vm-menu-popup-image-menu (event)
  (interactive "e")
  (vm-menu-goto-event event)
  (cond ((and (featurep 'xemacs) vm-use-menus)
	 (popup-menu vm-menu-image-menu))
	((and (not (featurep 'xemacs)) vm-use-menus)
	 (vm-menu-popup-fsfemacs-menu
	  event vm-menu-fsfemacs-image-menu))))

;; to quiet the byte-compiler
(defvar vm-menu-fsfemacs-mail-menu)
(defvar vm-menu-fsfemacs-dispose-popup-menu)
(defvar vm-menu-fsfemacs-vm-menu)

(defun vm-menu-popup-fsfemacs-menu (event &optional menu)
  (interactive "e")
  (set-buffer (window-buffer (posn-window (event-start event))))
  (goto-char (posn-point (event-start event)))
  (let ((map (or menu mode-popup-menu))
	key command func)
    (setq key (x-popup-menu event map)
	  key (apply 'vector key)
          command (lookup-key map key)
	  func (and (symbolp command) (symbol-function command)))
    (cond ((null func) (setq this-command last-command))
	  ((symbolp func)
	   (setq this-command func)
	   (call-interactively this-command))
	  (t
	   (call-interactively command)))))

(defun vm-menu-mode-menu ()
  (if (featurep 'xemacs)
      (cond ((eq major-mode 'mail-mode)
	     vm-menu-mail-menu)
	    ((memq major-mode '(vm-mode vm-presentation-mode
				vm-summary-mode vm-virtual-mode))
	     vm-menu-dispose-menu)
	    (t vm-menu-vm-menu))
    (cond ((eq major-mode 'mail-mode)
	   vm-menu-fsfemacs-mail-menu)
	  ((memq major-mode '(vm-mode vm-summary-mode vm-virtual-mode))
	   vm-menu-fsfemacs-dispose-popup-menu)
	  (t vm-menu-fsfemacs-vm-menu))))

(defun vm-menu-set-menubar-dirty-flag ()
  (cond ((featurep 'xemacs)
	 (set-menubar-dirty-flag))
	((not (featurep 'xemacs))
	 ;; force-mode-line-update seems to have been buggy in Emacs
	 ;; 21, 22, and 23.  So we do it ourselves.  USR, 2011-02-26
	 ;; (force-mode-line-update t)
	 (set-buffer-modified-p (buffer-modified-p))
	 (when (and vm-user-interaction-buffer
		    (buffer-live-p vm-user-interaction-buffer))
	   (with-current-buffer vm-user-interaction-buffer
	     (set-buffer-modified-p (buffer-modified-p)))))))

(defun vm-menu-fsfemacs-add-vm-menu ()
  "Add a menu or a menubar button to the Emacs menubar for switching
to a VM menubar."
  (if (and (vm-menubar-buttons-possible-p) vm-use-menubar-buttons)
      (define-key vm-mode-map [menu-bar vm]
	'(menu-item "[VM Menubar]" vm-menu-toggle-menubar))
    (define-key vm-mode-map [menu-bar vm]
      (cons "Menubar" (make-sparse-keymap "VM")))
    (define-key vm-mode-map [menu-bar vm vm-toggle]
      '(menu-item "Switch to VM Menubar" vm-menu-toggle-menubar))))
      
(defun vm-menu-toggle-menubar (&optional buffer)
  "Toggle between the VM's dedicated menu bar and the standard Emacs
menu bar.                                             USR, 2011-02-27"
  (interactive)
  (if buffer
      (set-buffer buffer)
    (vm-select-folder-buffer-and-validate 0 (vm-interactive-p)))
  (cond ((featurep 'xemacs)
	 (if (null (car (find-menu-item current-menubar '("[Emacs Menubar]"))))
	     (set-buffer-menubar vm-menu-vm-menubar)
	   ;; copy the current menubar in case it has been changed.
	   (make-local-variable 'vm-menu-vm-menubar)
	   (setq vm-menu-vm-menubar (copy-sequence current-menubar))
	   (set-buffer-menubar (copy-sequence (vm-menu--global-menubar)))
	   (condition-case nil
	       (add-menu-button nil vm-menu-vm-button nil)
	     (void-function
	      (add-menu-item nil "Menubar" 'vm-menu-toggle-menubar t))))
	 (vm-menu-set-menubar-dirty-flag)
	 (vm-check-for-killed-summary)
	 (and vm-summary-buffer
	      (save-excursion
		(vm-menu-toggle-menubar vm-summary-buffer)))
	 (vm-check-for-killed-presentation)
	 (and vm-presentation-buffer-handle
	      (save-excursion
		(vm-menu-toggle-menubar vm-presentation-buffer-handle))))
	((not (featurep 'xemacs))
	 (if (not (eq (lookup-key vm-mode-map [menu-bar])
		      (lookup-key vm-mode-menu-map [rootmenu vm])))
	     (define-key vm-mode-map [menu-bar]
	       (lookup-key vm-mode-menu-map [rootmenu vm]))
	   (define-key vm-mode-map [menu-bar]
	     (make-sparse-keymap "Menu"))
	   (vm-menu-fsfemacs-add-vm-menu))
	 (vm-menu-set-menubar-dirty-flag))))

(defun vm-menu-install-menubar ()
  "Install the dedicated menu bar of VM.              USR, 2011-02-27"
  (cond ((featurep 'xemacs)
	 (setq vm-menu-vm-menubar (vm-menu-make-xemacs-menubar))
	 (set-buffer-menubar vm-menu-vm-menubar)
         (run-hooks 'vm-menu-setup-hook)
         (setq vm-menu-vm-menubar current-menubar))
	((and (not (featurep 'xemacs))
	      ;; menus only need to be installed once for FSF Emacs
	      (not (fboundp 'vm-menu-undo-menu)))
	 (vm-menu-initialize-vm-mode-menu-map)
	 (define-key vm-mode-map [menu-bar]
	   (lookup-key vm-mode-menu-map [rootmenu vm])))))

(defun vm-menu-install-menubar-item ()
  "Install VM's menu on the current - presumably the standard - menu
bar.						     USR, 2011-02-27"
  (cond ((and (featurep 'xemacs) (vm-menu--global-menubar))
	 (set-buffer-menubar (copy-sequence (vm-menu--global-menubar)))
	 (add-menu nil "VM" (cdr vm-menu-vm-menu)))
	((and (not (featurep 'xemacs))
	      ;; menus only need to be installed once for FSF Emacs
	      (not (fboundp 'vm-menu-undo-menu)))
	 (vm-menu-initialize-vm-mode-menu-map)
	 (define-key vm-mode-map [menu-bar]
	   (lookup-key vm-mode-menu-map [rootmenu])))))

(defun vm-menu-install-vm-mode-menu ()
  "This function strangely does nothing!               USR, 2011-02-27."
  ;; nothing to do here.
  ;; handled in vm-mouse.el
  (cond ((featurep 'xemacs)
	 t )
	((not (featurep 'xemacs))
	 t )))

(defun vm-menu-install-mail-mode-menu ()
  (cond ((featurep 'xemacs)
	 ;; mail-mode doesn't have mode-popup-menu bound to
	 ;; mouse-3 by default.  fix that.
	 (if vm-popup-menu-on-mouse-3
	     (define-key vm-mail-mode-map 'button3 'popup-mode-menu))
	 ;; put menu on menubar also.
	 (if (vm-menu--global-menubar)
	     (progn
	       (set-buffer-menubar
		(copy-sequence (vm-menu--global-menubar)))
	       (add-menu nil "Mail" (cdr vm-menu-mail-menu))))
	 t )
	((not (featurep 'xemacs))
	 ;; I'd like to do this, but the result is a combination
	 ;; of the Emacs and VM Mail menus glued together.
	 ;; Poorly.
	 ;;(define-key vm-mail-mode-map [menu-bar mail]
	 ;;  (cons "Mail" vm-menu-fsfemacs-mail-menu))
	 (defvar mail-mode-map)
	 (define-key mail-mode-map [menu-bar mail]
	   (cons "Mail" vm-menu-fsfemacs-mail-menu))
	 (if vm-popup-menu-on-mouse-3
	     (define-key vm-mail-mode-map [down-mouse-3]
	       'vm-menu-popup-context-menu)))))

(defun vm-menu-install-menus ()
  "Install VM menus, either in the current menu bar or in a
separate dedicated menu bar, depending on the value of
`vm-use-menus'.                           USR, 2011-02-27"
  (cond ((consp vm-use-menus)
	 (vm-menu-install-vm-mode-menu)
	 (vm-menu-install-menubar)
	 (vm-menu-install-known-virtual-folders-menu))
	((eq vm-use-menus 1)
	 (vm-menu-install-vm-mode-menu)
	 (vm-menu-install-menubar-item)
	 (vm-menu-install-known-virtual-folders-menu))
	(t nil)))

(defun vm-menu-install-known-virtual-folders-menu ()
  (let ((folders (sort (mapcar 'car vm-virtual-folder-alist)
		       (function string-lessp)))
	(menu nil)
	tail
	;; special string indicating tail of Virtual menu
	(special "-------"))
    (while folders
      (setq menu (cons (vector "    "
			       (list 'vm-menu-run-command
				     ''vm-visit-virtual-folder (car folders))
			       :suffix (car folders))
		       menu)
	    folders (cdr folders)))
    (and menu (setq menu (nreverse menu)
		    menu (nconc (list "Visit:" "---") menu)))
    (setq tail (member special vm-menu-virtual-menu))
    (if (and menu tail)
	(progn
	  (setcdr tail menu)
	  (vm-menu-set-menubar-dirty-flag)
	  (cond ((not (featurep 'xemacs))
		 (makunbound 'vm-menu-fsfemacs-virtual-menu)
		 (easy-menu-define vm-menu-fsfemacs-virtual-menu
				      (list (make-sparse-keymap))
				      nil
				      vm-menu-virtual-menu)
		 (define-key vm-mode-menu-map [rootmenu vm vm-menubar-virtual]
		   (cons "Virtual" vm-menu-fsfemacs-virtual-menu))))))))

(defun vm-menu-install-visited-folders-menu ()
  (let ((folders (vm-delete-duplicates (copy-sequence vm-folder-history)))
	(menu nil)
	tail foo
	spool-files
	(i 0)
	;; special string indicating tail of Folder menu
	(special "-------"))
    (while (and folders (< i 10))
      (setq menu (cons
		  (vector "    "
			  (cond
			   ((and (vm-pop-folder-spec-p (car folders))
				 (setq foo (vm-pop-find-name-for-spec
					    (car folders))))
			    (list 'vm-menu-run-command
				  ''vm-visit-pop-folder foo))
			   ((and (vm-imap-folder-spec-p (car folders))
				 (setq foo (vm-imap-folder-for-spec
					    (car folders))))
			    (list 'vm-menu-run-command
				  'vm'visit-imap-folder foo))
			   (t
			    (list 'vm-menu-run-command
				  ''vm-visit-folder (car folders))))
			  :suffix (car folders))
		       menu)
	    folders (cdr folders)
	    i (1+ i)))
    (and menu (setq menu (nreverse menu)
		    menu (nconc (list "Visit:" "---") menu)))
    (setq spool-files (vm-spool-files)
	  folders (cond ((and (consp spool-files)
			      (consp (car spool-files)))
			 (mapcar (function car) spool-files))
			((and (consp spool-files)
			      (stringp (car spool-files))
			      (stringp vm-primary-inbox))
			 (list vm-primary-inbox))
			(t nil)))
    (if (and menu folders)
	(nconc menu (list "---" "---")))
    (while folders
      (setq menu (nconc menu
			(list (vector "    "
				      (list 'vm-menu-run-command
					    ''vm-visit-folder (car folders))
				      :suffix (car folders))))
	    folders (cdr folders)))
    (setq tail (member special vm-menu-folder-menu))
    (if (and menu tail)
	(progn
	  (setcdr tail menu)
	  (vm-menu-set-menubar-dirty-flag)
	  (cond ((not (featurep 'xemacs))
		 (makunbound 'vm-menu-fsfemacs-folder-menu)
		 (easy-menu-define vm-menu-fsfemacs-folder-menu
				      (list (make-sparse-keymap))
				      nil
				      vm-menu-folder-menu)
		 (define-key vm-mode-menu-map [rootmenu vm vm-menubar-folder]
		   (cons "Folder" vm-menu-fsfemacs-folder-menu))))))))

(defun vm-customize ()
  "Customize VM options."
  (interactive)
  (customize-group 'vm))

(defun vm-view-news ()
  "View NEWS for the current VM version."
  (interactive)
  (let* ((vm-dir (file-name-directory (locate-library "vm")))
	 (doc-dirs (list (and vm-configure-docdir
			       (expand-file-name vm-configure-docdir))
			 (concat vm-dir "../")))
	 doc-dir)
    (while doc-dirs
      (setq doc-dir (car doc-dirs))
      (if (and doc-dir
               (file-exists-p (expand-file-name "NEWS" doc-dir)))
          (setq doc-dirs nil)
	(setq doc-dirs (cdr doc-dirs))))
    (vm-view-file-other-frame (expand-file-name "NEWS" doc-dir))))

(defun vm-view-manual ()
  "View the VM manual."
  (interactive)
  (info "VM"))


;;; Muenkel Folders menu code

(defvar vm-menu-hm-no-hidden-dirs t
  "*Hidden directories are suppressed in the folder menus, if non nil.")

(defconst vm-menu-hm-hidden-file-list '("^\\..*" ".*\\.~[0-9]+~"))

(defun vm-menu-hm-delete-folder (folder)
  "Query deletes a folder."
  (interactive "fDelete folder: ")
  (if (file-exists-p folder)
      (if (y-or-n-p (concat "Delete the folder " folder " ? "))
	  (progn
	    (if (file-directory-p folder)
		(delete-directory folder)
	      (delete-file folder))
	    (vm-inform 5 "Folder deleted.")
	    (vm-menu-hm-make-folder-menu)
	    (vm-menu-hm-install-menu)
	    )
	(vm-inform 0 "Aborted"))
    (error "Folder %s does not exist." folder)
    (vm-menu-hm-make-folder-menu)
    (vm-menu-hm-install-menu)
    ))
	

(defun vm-menu-hm-rename-folder (folder)
  "Rename a folder."
  (interactive "fRename folder: ")
  (if (file-exists-p folder)
      (rename-file folder
		   (read-file-name (concat "Rename "
					   folder
					   " to ")
				   (directory-file-name folder)
				   folder))
    (error "Folder %s does not exist." folder))
  (vm-menu-hm-make-folder-menu)
  (vm-menu-hm-install-menu)
  )


(defun vm-menu-hm-create-dir (parent-dir)
  "Create a subdir in PARENT-DIR."
  (interactive "DCreate new directory in: ")
  (setq parent-dir (or parent-dir vm-folder-directory))
  (make-directory
   (expand-file-name (read-file-name
		      (format "Create directory in %s called: "
			      parent-dir)
		      parent-dir)
		     vm-folder-directory)
   t)
  (vm-menu-hm-make-folder-menu)
  (vm-menu-hm-install-menu)
  )


(defun vm-menu-hm-make-folder-menu ()
  "Makes a menu with the mail folders of the directory `vm-folder-directory'."
  (interactive)
  (vm-inform 5 "Building folders menu...")
  (let ((folder-list (vm-menu-hm-tree-make-file-list vm-folder-directory))
	(inbox-list (if (listp (car vm-spool-files))
			(mapcar 'car vm-spool-files)
		      (list vm-primary-inbox))))
    (setq vm-menu-folders-menu
	  (cons "Manipulate Folders"
		(list (cons "Visit Inboxes  "
			    (vm-menu-hm-tree-make-menu
			     inbox-list
			     'vm-visit-folder
			     t))
		      (cons "Visit Folder   "
			    (vm-menu-hm-tree-make-menu
			     folder-list
			     'vm-visit-folder
			     t
			     vm-menu-hm-no-hidden-dirs
			     vm-menu-hm-hidden-file-list))
		      (cons "Save Message   "
			    (vm-menu-hm-tree-make-menu
			     folder-list
			     'vm-save-message
			     t
			     vm-menu-hm-no-hidden-dirs
			     vm-menu-hm-hidden-file-list))
		      "----"
		      (cons "Delete Folder  "
			    (vm-menu-hm-tree-make-menu
			     folder-list
			     'vm-menu-hm-delete-folder
			     t
			     nil
			     nil
			     t
			     ))
		      (cons "Rename Folder  "
			    (vm-menu-hm-tree-make-menu
			     folder-list
			     'vm-menu-hm-rename-folder
			     t
			     nil
			     nil
			     t
			     ))
		      (cons "Make New Directory in..."
			    (vm-menu-hm-tree-make-menu
			     (cons (list vm-folder-directory) folder-list)
			     'vm-menu-hm-create-dir
			     t
			     nil
			     '(".*")
			     t
			     ))
		      "----"
		      ["Rebuild Folders Menu" vm-menu-hm-make-folder-menu vm-folder-directory]
		      ))))
  (vm-inform 5 "Building folders menu... done")
  (vm-menu-hm-install-menu))

(defun vm-menu-hm-install-menu ()
  (cond ((featurep 'xemacs)
	 (cond ((car (find-menu-item current-menubar '("VM")))
		(add-menu '("VM") "Folders"
			  (cdr vm-menu-folders-menu) "Motion"))
	       ((car (find-menu-item current-menubar
				     '("Folder" "Manipulate Folders")))
		(add-menu '("Folder") "Manipulate Folders"
			  (cdr vm-menu-folders-menu) "Motion"))))
	((not (featurep 'xemacs))
	 (easy-menu-define vm-menu-fsfemacs-folders-menu
			      (list (make-sparse-keymap))
			      nil
			      vm-menu-folders-menu)
	 (define-key vm-mode-menu-map [rootmenu vm folder folders]
	   (cons "Manipulate Folders" vm-menu-fsfemacs-folders-menu)))))


;;; Muenkel tree-menu code

(defconst vm-menu-hm-tree-ls-flags "-aFLR"
  "*A String with the flags used in the function
vm-menu-hm-tree-ls-in-temp-buffer for the ls command.
Be careful if you want to change this variable.
The ls command must append a / on all files which are directories.
The original flags are -aFLR.")


(defun vm-menu-hm-tree-ls-in-temp-buffer (dir temp-buffer)
"List the directory DIR in the TEMP-BUFFER."
  (switch-to-buffer temp-buffer)
  (erase-buffer)
  (let ((process-connection-type nil))
    (call-process "ls" nil temp-buffer nil vm-menu-hm-tree-ls-flags dir))
  (goto-char (point-min))
  (while (search-forward "//" nil t)
    (replace-match "/"))
  (goto-char (point-min))
  (while (re-search-forward "\\.\\.?/\n" nil t)
    (replace-match ""))
  (goto-char (point-min)))


(defconst vm-menu-hm-tree-temp-buffername "*tree*"
  "Name of the temp buffers in tree.")


(defun vm-menu-hm-tree-make-file-list-1 (root list)
  (let ((filename (buffer-substring (point) (progn
					      (end-of-line)
					      (point)))))
    (while (not (string= filename ""))
      (setq
       list
       (append
	list
	(list
	 (cond ((char-equal (char-after (- (point) 1)) ?/)
		;; Directory
		(setq filename (substring filename 0 (1- (length filename))))
		(save-excursion
		  (search-forward (concat root filename ":"))
		  (forward-line)
		  (vm-menu-hm-tree-make-file-list-1 (concat root filename "/")
						(list (vm-menu-hm-tree-menu-file-truename
						       filename
						       root)))))
	       ((char-equal (char-after (- (point) 1)) ?*)
		;; Executable
		(setq filename (substring filename 0 (1- (length filename))))
		(vm-menu-hm-tree-menu-file-truename filename root))
	       (t (vm-menu-hm-tree-menu-file-truename filename root))))))
      (forward-line)
      (setq filename (buffer-substring (point) (progn
						 (end-of-line)
						 (point)))))
    list))


(defun vm-menu-hm-tree-menu-file-truename (file &optional root)
  (file-truename (expand-file-name file root)))

(defun vm-menu-hm-tree-make-file-list (dir)
  "Makes a list with the files and subdirectories of DIR.
The list looks like: ((dirname1 file1 file2)
                      file3
                      (dirname2 (dirname3 file4 file5) file6))"
  (save-window-excursion
    (setq dir (expand-file-name dir))
    (if (not (string= (substring dir -1) "/"))
	(setq dir (concat dir "/")))
;;    (while (string-match "/$" dir)
;;      (setq dir (substring dir 0 -1)))
    (vm-menu-hm-tree-ls-in-temp-buffer dir
				 (generate-new-buffer-name
				  vm-menu-hm-tree-temp-buffername))
    (let ((list nil))
      (setq list (vm-menu-hm-tree-make-file-list-1 dir nil))
      (kill-buffer (current-buffer))
      list)))


(defun vm-menu-hm-tree-hide-file-p (filename re-hidden-file-list)
  "t, if one of the regexps in RE-HIDDEN-FILE-LIST matches the FILENAME."
  (cond ((not re-hidden-file-list) nil)
	((string-match (car re-hidden-file-list)
		       (vm-menu-hm-tree-menu-file-truename filename)))
	(t (vm-menu-hm-tree-hide-file-p filename (cdr re-hidden-file-list)))))


(defun vm-menu-hm-tree-make-menu (dirlist
		       function
		       selectable
		       &optional
		       no-hidden-dirs
		       re-hidden-file-list
		       include-current-dir)
  "Returns a menu list.
Each item of the menu list has the form
 [\"subdir\" (FUNCTION \"dir\") SELECTABLE].
Hidden directories (with a leading point) are suppressed,
if NO-HIDDEN-DIRS are non nil. Also all files which are
matching a regexp in RE-HIDDEN-FILE-LIST are suppressed.
If INCLUDE-CURRENT-DIR non nil, then an additional command
for the current directory (.) is inserted."
  (let ((subdir nil)
	(menulist nil))
    (while (setq subdir (car dirlist))
      (setq dirlist (cdr dirlist))
      (cond ((and (stringp subdir)
		  (not (vm-menu-hm-tree-hide-file-p subdir re-hidden-file-list)))
	     (setq menulist
		   (append menulist
			   (list
			    (vector (file-name-nondirectory subdir)
				    (list function subdir)
				    selectable)))))
	    ((and (listp subdir)
		  (or (not no-hidden-dirs)
		      (not (char-equal
			    ?.
			    (string-to-char
			     (file-name-nondirectory (car subdir))))))
		  (setq menulist
			(append
			 menulist
			 (list
			  (cons (file-name-nondirectory (car subdir))
				(if include-current-dir
				    (cons
				     (vector "."
					     (list function
						   (car subdir))
					     selectable)
				     (vm-menu-hm-tree-make-menu (cdr subdir)
						     function
						     selectable
						     no-hidden-dirs
						     re-hidden-file-list
						     include-current-dir
						     ))
				  (vm-menu-hm-tree-make-menu (cdr subdir)
						  function
						  selectable
						  no-hidden-dirs
						  re-hidden-file-list
						  ))))))))
	    (t nil))
      )
    menulist
    )
  )

(provide 'vm-menu)
;;; vm-menu.el ends here
