;;; vm-vars.el --- VM user and internal variable initialization  -*- lexical-binding: t; -*-
;;
;; This file is part of VM
;;
;; Copyright (C) 1989-2003 Kyle E. Jones
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

(declare-function vm-parse "vm-misc" (string regexp &optional matchn matches))
(declare-function vm-delete-directory-names "vm-misc" (list))
(declare-function vm-display "vm-window" 
		  (buffer display commands configs &optional do-not-raise))

(declare-function xemacs-locate-data-directory "vm-xemacs" (name))
(fset 'xemacs-locate-data-directory 'locate-data-directory)
;; Don't use vm-device-type here because it may not be loaded yet.
(declare-function device-type "vm-xemacs" ())
;; (fset 'xemacs-device-type 'device-type)

;; Custom group definitions
(defgroup vm nil
  "The VM mail reader."
  :link '(custom-manual "(vm)Top")
  :link '(url-link :tag "VM Homepage" "http://www.nongnu.org/viewmail/")
  :group 'mail)

(defgroup vm-faces nil
  "Faces for VM."
  :group 'vm)

(defgroup vm-misc nil
  "Miscellaneous VM configuration options."
  :group 'vm)

(defgroup vm-folders nil
  "Mail folder settings for VM."
  :group 'vm)

(defgroup vm-virtual nil
  "Settings for virtual folders."
  :group 'vm-folders)

(defgroup vm-external nil
  "Settings for external messages."
  :group 'vm-folders)

(defgroup vm-pop nil
  "POP3 mail folders for VM."
  :group 'vm-folders)

(defgroup vm-imap nil
  "IMAP mail folders for VM."
  :group 'vm-folders)

(defgroup vm-mime nil
  "MIME options for VM."
  :group 'vm)

(defgroup vm-helpers nil
  "External helper programs used by VM."
  :group 'vm)

(defgroup vm-summary nil
  "Options for VM's summary window."
  :group 'vm)

(defgroup vm-hooks nil
  "Hooks for the VM mail reader."
  :group 'vm)

(defgroup vm-digest nil
  "Options affecting VM's handling of digests."
  :group 'vm)

(defgroup vm-frames nil
  "Options affecting frames and windows in VM."
  :group 'vm)

(defgroup vm-url nil
  "Options affecting handling of URLs in VM."
  :group 'vm)

(defgroup vm-compose nil
  "Options affecting mail composition within VM."
  :group 'vm)

(defgroup vm-reply nil
  "Options for replying to messages within VM."
  :group 'vm-compose)

(defgroup vm-forward nil
  "Options for forwarding messages within VM."
  :group 'vm-compose)

(defgroup vm-presentation nil
  "Options affecting the presentation of messages in VM."
  :group 'vm)

(defgroup vm-dispose nil
  "Options affecting the saving, deleting and expunging of messages in VM."
  :group 'vm)

(defgroup vm-print nil
  "Options affecting printing of messages in VM."
  :group 'vm)

(defgroup vm-toolbar nil
  "Options affecting the VM toolbar"
  :group 'vm)

(defgroup vm-add-ons nil
  "Options for non-core VM extensions"
  :group 'vm)

;; Custom variable definitions

(defcustom vm-assimilate-new-messages-sorted nil
  "*When enabled new messages will be inserted in current sort order.
Otherwise they are appended to the folder, which is VM default."
  :group 'vm-presentation
  :type 'boolean)

(defcustom vm-init-file "~/.vm"
  "*Startup file for VM that is loaded the first time you run VM
in an Emacs session."
  :group 'vm-misc
  :type 'file)

(defcustom vm-preferences-file "~/.vm.preferences"
  "*Secondary startup file for VM, loaded after `vm-init-file'.  It is
meant for specifying the preferred settings for VM variables."
  :group 'vm-misc
  :type 'file)

(defcustom vm-temp-file-directory
  (or (getenv "TMPDIR")
      (and (file-directory-p "/tmp") "/tmp")
      (and (file-directory-p "C:\\TEMP") "C:\\TEMP")
      (and (file-directory-p "C:\\") "C:\\")
      "/tmp")
  "*Name of a directory where VM can put temporary files."
  :group 'vm-misc
  :type 'directory)

(defcustom vm-folder-directory nil
  "*Directory where folders of mail are kept."
  :group 'vm-folders
  :type '(choice (const nil) directory))

(defcustom vm-thunderbird-folder-directory nil
  "*Directory where Thunderbird's local folders are kept.  This
setting is used in `vm-visit-thunderbird-folder'.  

Note that only Thunderbird's local folders can be visited in VM,
not its IMAP folders. "
  :group 'vm-folders
  :type '(choice (const nil) directory))

(defvar vm-foreign-folder-directory nil
  "If the current folder is a \"foreign\" folder, i.e., maintained by
anothe mail client such as Thunderbird, then this variable holds its
directory.")

(defcustom vm-primary-inbox "~/INBOX"
  "*Mail is moved from the system mailbox to this file for reading."
  :group 'vm-folders
  :type 'file)

(defcustom vm-crash-box nil
  "*File in which to store mail temporarily while it is transferred from
the system mailbox to the primary inbox.  If a crash occurs
during this mail transfer, any missing mail will be found in this
file.  VM will do crash recovery from this file automatically at
startup, as necessary.

If the variable is to nil, a crash box name is created by appending
`vm-primary-inbox' and `vm-crash-box-suffix'."
  :group 'vm-folders
  :type '(choice file 
		 (const :tag "Use vm-crash-box-suffix" nil)))

(defcustom vm-crash-box-suffix ".crash"
  "*String suffix used to create possible crash box file names for folders.
When VM uses `vm-spool-file-suffixes' to create a spool file name,
it will append the value of `vm-crash-box-suffix' to the folder's
file name to create a crash box name."
  :group 'vm-folders
  :type '(choice string
		 (const :tag "No crash boxes" nil)))

(defcustom vm-keep-crash-boxes nil
  "*Non-nil value should be a string specifying a directory where
your crash boxes should be moved after VM has copied new mail
out of them.  This is a safety measure.  In at least one case a
pointer corruption bug inside Emacs has caused VM to believe that
it had copied information out of the crash box when it in fact
had not.  VM then deleted the crash box, losing the batch of
incoming mail.  This is an exceedingly rare problem, but if you
want to avoid losing mail if it happens, set `vm-keep-crash-boxes'
to point to a directory in the same filesystem as all your
crash boxes.  Each saved crash box will have a unique name based
on the current date and time the box was saved.  You will need to
clean out this directory from time to time; VM does not do so.

A nil value means VM should just delete crash boxes after it
has copied out the mail."
  :group 'vm-folders
  :type '(choice directory 
                 (const :tag "No, do not keep crash boxes" nil)))

(defcustom vm-external-fetch-message-for-presentation t
  "*Non-nil value indicates that external message bodies should be
automatically fetched for message presentation.  If it is nil, then
messages will be presented with only the headers and `vm-load-message'
must be used to load the externally stored message bodies."
  :group 'vm-external
  :type '(choice (const :tag "No automatic fetching" nil)
		(const :tag "Automatic fetching" t)))

(defvaralias 'vm-fetched-message-limit 
  'vm-external-fetched-message-limit)
(defcustom vm-external-fetched-message-limit 10
  "Should be an integer representing the maximum number of messages
that VM should keep in the Folder buffer when the messages are
fetched on demand, or nil to signify no limit."
  :group 'vm-external
  :type '(choice (const :tag "No Limit" nil) 
		 (integer :tag "Number of Mesages")))

(defcustom vm-index-file-suffix nil
  "*Suffix used to construct VM index file names, e.g., \".inx\".
When VM visits a folder, it checks for the existence of a file
whose name is the folder's file name with the value of this
variable appended to it.  If found, the file's contents will be
used to tell VM about the contents of the folder.  This is faster
than parsing the folder itself.

When you save a folder, the index file will be rewritten with
updated information about the folder.

A nil value means VM should not read or write index files."
  :group 'vm-folders
  :type '(choice (string :tag "File Suffix")
                 (const :tag "Do not use index file" nil)))

(defcustom vm-enable-external-messages nil
  "*Non-nil value should be a list of contexts in which VM may
use message bodies stored externally.  External messages are
those stored in external sources such as the file system or
remote mail servers.  In some cases, VM is able to work with
minimal header information of the messages, without loading the
entire message bodies into the folder buffers.

This allows faster start-up times and smaller memory images of
Emacs sessions, at the cost of short delays when messages are
viewed.

As of version 8.2.0, this facility is only available for IMAP
folders (context name `imap').  Messages larger than
`vm-imap-max-message-size' are treated as external messages."
  :group 'vm-external
  :type '(repeat (choice (const imap))))

(defvar vm-load-headers-only nil
  "This variable is replaced by `vm-enable-external-messages'.")
(make-obsolete-variable 'vm-load-headers-only 
			'vm-enable-external-messages "8.2.0")

(defcustom vm-spool-files nil
  "If non-nil this variable's value should be a list of strings
or a list of lists.

If the value is a list of strings, the strings should name files
that VM will check for incoming mail instead of the default place
VM thinks your system mailbox is.  Mail will be moved from these
mailboxes to your primary inbox as specified by `vm-primary-inbox',
using `vm-crash-box' as a waystation.

If the value is a list of lists, each sublist should be of the form

    (INBOX SPOOLNAME CRASHBOX)

INBOX, SPOOLNAME and CRASHBOX are all strings.

INBOX is the folder where you want your new mail to be moved when
you type `g' (running `vm-get-new-mail') in VM.  It is where you
will read the mail.

SPOOLNAME is where the mail system leaves your incoming mail,
e.g. /var/spool/mail/kyle.  It can also be a mailbox
specification of the form, \"po:USER\", where USER is a user
name.  VM will pass this specification to the movemail program.
It is up to movemail to interpret it and figure out where to find
your mailbox.  Some systems use special authentication methods that
are only accessible via the movemail program.

SPOOLNAME can also be a POP maildrop.

    A POP maildrop specification has the following format:

       \"pop:HOST:PORT:AUTH:USER:PASSWORD\"
    or
       \"pop-ssl:HOST:PORT:AUTH:USER:PASSWORD\"
    or
       \"pop-ssh:HOST:PORT:AUTH:USER:PASSWORD\"

    The second form is used to speak POP over an SSL connection.
    For this to work you should either have a version of Emacs
    with SSL capability or you have the stunnel program installed
    and set the variable `vm-stunnel-program'.  The SSL version
    of the POP server will not use the same port as the non-SSL
    version.

    The third form is used to speak POP over an SSH connection.
    You must have the ssh program installed and the variable
    `vm-ssh-program' must name it in order for POP over SSH to
    work.  SSH must be able to authenticate without a password,
    which means you must be using either .shosts authentication
    or RSA authentication.

    HOST is the host name of the POP server

    PORT is the TCP port number to connect to.  This should
    normally be 110, unless you're using POP over SSL in which
    case the stanard port is 995.

    USER is the user name sent to the server.

    PASSWORD is the secret shared by you and the server for
    authentication purposes.  How is it used depends on the value of
    the AUTH parameter.  If the PASSWORD is \"*\", VM will prompt
    you for the password the first time you try to retrieve mail from
    maildrop.  If the password is valid, VM will not ask you for the
    password again during this Emacs session.

    AUTH is the authentication method used to convince the server you
    should have access to the maildrop.  Acceptable values are
    \"pass\", \"rpop\" and \"apop\".  For \"pass\", the PASSWORD is sent to
    the server with the POP PASS command.  For \"rpop\", the PASSWORD
    should be the string to be sent to the server via the RPOP
    command.  In this case the string is not really a secret;
    authentication is done by other means.  For \"apop\", an MD5 digest
    of the PASSWORD appended to the server timestamp will be sent to
    the server with the APOP command.  In order to use \"apop\" you
    will have to set the value of `vm-pop-md5-program' appropriately to
    point at the program that will generate the MD5 digest that VM
    needs.

SPOOLNAME can also be an IMAP maildrop.

    An IMAP maildrop specification has the following format:

       \"imap:HOST:PORT:MAILBOX:AUTH:USER:PASSWORD\"
    or
       \"imap-ssl:HOST:PORT:MAILBOX:AUTH:USER:PASSWORD\"
    or
       \"imap-ssh:HOST:PORT:MAILBOX:AUTH:USER:PASSWORD\"

    The second form is used to speak IMAP over an SSL connection.
    For this to work, you should either be using a version of
    Emacs with SSL capability or you must have the stunnel
    program installed and the variable `vm-stunnel-program'
    naming it.

    The third form is used to speak IMAP over an SSH connection.
    You must have the ssh program installed and the variable
    `vm-ssh-program' must name it in order for IMAP over SSH to
    work.  SSH must be able to authenticate without a password,
    which means you must be using .shosts authentication or
    public key user authentication.

    HOST is the host name of the IMAP server.

    PORT is the TCP port number to connect to.  This should
    normally be 143.  For IMAP over SSL, the standard port is
    993.  There is no special port for IMAP over SSH.

    MAILBOX is the name of the mailbox on the IMAP server.  Should
    be \"inbox\", to access your default IMAP maildrop on the
    server.

    AUTH is the authentication method used to convince the server
    you should have access to the maildrop.  Acceptable values
    are \"preauth\", \"login\" and \"cram-md5\".  \"preauth\"
    causes VM to skip the authentication stage of the protocol
    with the assumption that the session was authenticated in some
    external way.  \"login\", tells VM to use the IMAP LOGIN
    command for authentication, which sends your username and
    password in cleartext to the server.  \"cram-md5\" is a
    challenge response system that convinces the server of your
    identity without transmitting your password in the clear.
    Not all servers support \"cram-md5\"; if you're not sure, ask
    your mail administrator or just try it.

    USER is the user name used with authentication methods that
    require such an identifier.  \"login\" and \"cram-md5\"
    use it currently.

    PASSWORD is the secret shared by you and the server for
    authentication purposes.  If the PASSWORD is \"*\", VM
    will prompt you for the password the first time you try to
    retrieve mail from maildrop.  If the password is valid, VM
    will not ask you for the password again during this Emacs
    session.

CRASHBOX is the temporary file that VM uses to store mail in
transit between the SPOOLNAME and the INBOX.  If the system
crashes or Emacs dies while mail is being moved, and the new
mail is not in the SPOOLNAME or the INBOX, then it will be in
the CRASHBOX.

There can be multiple entries with the same INBOX value, but a
particular SPOOLNAME should appear only once.  CRASHBOXes should
not be shared among different INBOXes, but you can use the same
CRASHBOX/INBOX pair with a different SPOOLNAME.

`vm-spool-files' will default to the value of the shell
environmental variables MAILPATH or MAIL if either of these
variables are defined and no particular value for `vm-spool-files'
has been specified."
  :group 'vm-folders
  :type '(choice (repeat :tag "List of spool files" 
                         (file :tag "Spoolfile"))
                 (repeat :tag "List of (inbox spoolfile crashbox) elements"
                         (list (file :tag "Inbox")
                               (file :tag "Spoolfile")
                               (file :tag "Crashbox")))))

;; use this function to access vm-spool-files on the fly.  this
;; allows us to use environmental variables without setting
;; vm-spool-files at load time and thereby making it hard to dump an
;; Emacs containing a preloaded VM.
(defun vm-spool-files ()
  (or vm-spool-files
      (and (setq vm-spool-files (getenv "MAILPATH"))
	   (setq vm-spool-files
		 (vm-delete-directory-names
		  (vm-parse vm-spool-files
			    "\\([^:%?]+\\)\\([%?][^:]*\\)?\\(:\\|$\\)"))))
      (and (setq vm-spool-files (getenv "MAIL"))
	   (setq vm-spool-files (vm-delete-directory-names
				 (list vm-spool-files))))))

(defcustom vm-spool-file-suffixes nil
  "*List of suffixes to be used to create possible spool file names
for folders.  Example:

  (setq vm-spool-file-suffixes \\='(\".spool\" \"-\"))

If you visit a folder ~/mail/beekeeping, when VM attempts to
retrieve new mail for that folder it will look for mail in
~/mail/beekeeping.spool and ~/mail/beekeeping- in addition to
scanning `vm-spool-files' for matches.

The value of `vm-spool-files-suffixes' will not be used unless
`vm-crash-box-suffix' is also defined, since a crash box is
required for all mail retrieval from spool files."
  :group 'vm-folders
  :type '(repeat string))

(defcustom vm-make-spool-file-name nil
  "*Non-nil value should be a function that returns a spool file name
for a folder.  The function will be called with one argument, the
folder's file name.  If the folder does not have a file name,
the function will not be called."
  :group 'vm-folders
  :type '(choice (const :tag "Default" nil)
                 function))

(defcustom vm-make-crash-box-name nil
  "*Non-nil value should be a function that returns a crash box file name
for a folder.  The function will be called with one argument, the
folder's file name.  If the folder does not have a file name,
the function will not be called."
  :group 'vm-folders
  :type '(choice (const :tag "Default" nil)
                 function))

(defconst vm-pop-md5-program "md5"
  "*Program that reads a message on its standard input and writes an
MD5 digest on its output.")

(defcustom vm-pop-max-message-size nil
  "*If VM is about to retrieve via POP a message larger than this
size (in bytes) it will ask the you whether it should retrieve
the message.

If VM is retrieving mail automatically because `vm-auto-get-new-mail'
is set to a numeric value then you will not be prompted about large
messages.  This is to avoid prompting you while you're typing in
another buffer.  In this case the large message will be skipped with a
warning message.  You will be able to retrieved any skipped messages
later by running `vm-get-new-mail' interactively.

A nil value for `vm-pop-max-message-size' means no size limit."
  :group 'vm-pop
  :type '(choice (const :tag "No Limit" nil) 
		 (integer :tag "Bytes")))

(defcustom vm-pop-messages-per-session nil
  "*Non-nil value should be an integer specifying how many messages to
retrieve per POP session.  When you type `g' to get new mail, VM
will only retrieve that many messages from any particular POP maildrop.
To retrieve more messages, type `g' again.

A nil value means there's no limit."
  :group 'vm-folders
  :type '(choice (const :tag "No Limit" nil) 
		 integer))

(defcustom vm-pop-bytes-per-session nil
  "*Non-nil value should be an integer specifying how many bytes to
retrieve per POP session.  When you type `g' to get new mail, VM
will only retrieve messages until the byte limit is reached on
any particular POP maildrop.  To retrieve more messages, type `g'
again.

A nil value means there's no limit."
  :group 'vm-folders
  :type '(choice (const :tag "No Limit" nil) 
		 (integer :tag "Bytes")))

(defcustom vm-pop-expunge-after-retrieving nil
  "*Non-nil value means that, when a POP mailbox is used as a
spool file, messages should be deleted after retrieving them.  A
nil value means messages will be left in the POP mailbox until
you run `vm-expunge-pop-messages'.  VM can only support a nil
value for this variable if the remote POP server supports the
UIDL command.  If the server does not support UIDL and you've
asked VM leave messages on the server, VM will complain about the
lack of UIDL support and not retrieve messages from the server.

This variable only affects POP mailboxes not listed in
`vm-pop-auto-expunge-alist' (which is the recommended method for
customizing this behavior)."
  :group 'vm-folders
  :type 'boolean)

(defcustom vm-pop-auto-expunge-alist nil
  "*List of POP mailboxes and values specifying whether messages
should be automatically deleted from the mailbox after retrieval.
The format of the list is

  ((MAILBOX . VAL) (MAILBOX . VAL) ...)

MAILBOX should be a POP mailbox specification as described in
the documentation for the variable `vm-spool-files'.  If you have
the POP password specified in the `vm-spool-files' entry, you do
not have to specify it here as well.  Use `*' instead; VM will
still understand that this mailbox is the same as the one in
`vm-spool-files' that gives the password.

VAL should be nil if retrieved messages should be left in the
corresponding POP mailbox, t if retrieved messages should be
deleted from the mailbox immediately after retrieval.

VM can only support a non-nil setting of this variable if the
remote POP server supports the UIDL command.  If the server does
not support UIDL and you've asked to VM leave messages on the server,
VM will complain about the lack of UIDL support and not retrieve
messages from the server."
  :group 'vm-folders
  :type '(repeat (cons string boolean)))

(defvar vm-pop-auto-expunge-warned nil
  "List of POP mailboxes for which warning has been given about the
lack of settings for auto-expunge.")

(defcustom vm-pop-read-quit-response t
  "*Non-nil value tells VM to read the response to the POP QUIT command.
Sometimes, for reasons unknown, the QUIT response never arrives
from some POP servers and VM will hang waiting for it.  So it is
useful to be able to tell VM not to wait.  Some other
servers will not expunge messages unless the QUIT response is
read, so for these servers you should set the variable's value to
t."
  :group 'vm-pop
  :type 'boolean)

(defconst vm-recognize-pop-maildrops 
  "^\\(pop\\|pop-ssl\\|pop-ssh\\):[^:]+:[^:]+:[^:]+:[^:]+:.+"
  "Regular expression matching the maildrop specification of POP
  folders.  It can be set to nil to prohibit POP maildrops.")

(defcustom vm-pop-folder-alist nil
  "*Alist of POP maildrop specifications and names that refer to them.
The alist format is:

 ((POPDROP NAME) ...)

POPDROP is a POP maildrop specification in the same format used
by `vm-spool-files' (which see).

NAME is a string that should give a less cumbersome name that you
will use to refer to this maildrop when using `vm-visit-pop-folder'."
  :group 'vm-pop
  :type '(repeat (list string string)))

(defcustom vm-pop-folder-cache-directory nil
  "*Directory where VM stores cached copies of POP folders.
When VM visits a POP folder (really just a POP server where you
have a mailbox) it stores the retrieved message on your computer
so that they need not be retrieved each time you visit the folder.
The cached copies are stored in the directory specified by this
variable."
  :group 'vm-pop
  :type '(choice (const nil) directory))

(defcustom vm-pop-server-timeout nil
  "*Number of seconds to wait for output from the POP server before
timing out.  It can be set to nil to never time out."
  :group 'vm-pop
  :type '(choice (const :tag "Never" nil) 
		 (integer :tag "Seconds")))

(defcustom vm-imap-max-message-size nil
  "*The largest message size of IMAP messages that VM should retrieve
automatically.  

If VM encounters an IMAP message larger than this size, the action
is as follows:

- In IMAP folders, the message is treated as an external message if
`vm-enable-external-messages' includes `imap'.  Otherwise it is
retrieved.

- In local folders, the message is skipped if it is part of
automatic mail retrieval.  During interactive mail retrieval, obtained by
running `vm-get-new-mail', VM queries you whether it should be retrieved.

A nil value for `vm-imap-max-message-size' means no size limit."
  :group 'vm-imap
  :type '(choice (const :tag "Unlimited" nil)
                 (integer :tag "Bytes")))

(defcustom vm-imap-messages-per-session nil
  "*Non-nil value should be an integer specifying how many messages to
retrieve per IMAP session.  When you type `g' to get new mail, VM
will only retrieve that many messages from any particular IMAP maildrop.
To retrieve more messages, type `g' again.

A nil value means there's no limit."
  :group 'vm-folders
  :type '(choice (const :tag "Unlimited" nil) integer))

(defcustom vm-imap-bytes-per-session nil
  "*Non-nil value should be an integer specifying how many bytes to
retrieve per IMAP session.  When you type `g' to get new mail, VM
will only retrieve messages until the byte limit is reached on
any particular IMAP maildrop.  To retrieve more messages, type `g'
again.

A nil value means there's no limit."
  :group 'vm-folders
  :type '(choice (const :tag "No Limit" nil) 
		 (integer :tag "Bytes")))

(defcustom vm-imap-expunge-after-retrieving nil
  "*Non-nil value means that, when an IMAP mailbox is used as a
spool file, messages should be deleted after retrieving them.  A
nil value means messages will be left in the IMAP mailbox until
you run `vm-expunge-imap-messages'.

This variable only affects IMAP mailboxes not listed in
`vm-imap-auto-expunge-alist' (which is the recommended method for
customizing this behavior)."
  :group 'vm-folders
  :type 'boolean)

(defcustom vm-imap-auto-expunge-alist nil
  "*List of IMAP mailboxes and values specifying whether messages
should be automatically deleted from the mailbox after retrieval.
The format of the list is

  ((MAILBOX . VAL) (MAILBOX . VAL) ...)

MAILBOX should be an IMAP mailbox specification as described in
the documentation for the variable `vm-spool-files'.  If you have
the IMAP password specified in the `vm-spool-files' entry, you do
not have to specify it here as well.  Use `*' instead; VM will
still understand that this mailbox is the same as the one in
`vm-spool-files' that contains the password.

VAL should be nil if retrieved messages should be left in the
corresponding IMAP mailbox, t if retrieved messages should be
deleted from the mailbox immediately after retrieval."
  :group 'vm-folders
  :type '(repeat (cons (string :tag "IMAP Folder Specificaiton")
		       boolean)))

(defvar vm-imap-auto-expunge-warned nil
  "List of IMAP mailboxes for which warning has been given about the
lack of settings for auto-expunge.")

(defconst vm-recognize-imap-maildrops 
  "^\\(imap\\|imap-ssl\\|imap-ssh\\):[^:]+:[^:]+:[^:]+:[^:]+:[^:]+:.+"
  "Regular expression matching maildrop specificaiton of IMAP
folders.  It can be set to nil to prohibit the recognition of
IMAP maildrops.")

(defvar vm-imap-server-list nil
  "List of IMAP maildrop specifications that tell VM the IMAP servers
you have access to and how to log into them.  The IMAP maildrop
specification in the same format used by `vm-spool-files' (which
see).  The mailbox part of the specifiation is ignored and should
be asterisk or some other placeholder.

***This customization variable is deprecated.  Use `vm-imap-account-alist'
instead. 

Example:
 (setq vm-imap-server-list
      \\='(\"imap-ssl:mail.foocorp.com:993:inbox:login:becky:*\"
        \"imap:crickle.lex.ky.us:143:inbox:login:becky:*\"))")

(make-obsolete-variable 'vm-imap-server-list
			'vm-imap-account-alist "8.1.0")

(defcustom vm-imap-account-alist nil
  "*Alist of IMAP account specifications and names that refer to them.
The alist format is:

 ((IMAPDROP NAME) ...)

IMAPDROP is a IMAP maildrop specification in the same format used
by `vm-spool-files' (which see).

NAME is a string that should give a less cumbersome name that you
will use to refer to this maildrop when using `vm-visit-imap-folder'.

Example:
 (setq vm-imap-account-alist
      \\='((\"imap-ssl:mail.foocorp.com:993:inbox:login:becky:*\" \"becky\")
        (\"imap:crickle.lex.ky.us:143:inbox:login:becky:*\" \"crickle\")))"
  :group 'vm-imap
  :type '(repeat (list (string :tag "IMAP Folder Specification") 
		       (string :tag "Nickname"))))

(defcustom vm-imap-default-account nil
  "*Set this variable to a string denoting the name of an IMAP account
 (short name) declared in `vm-imap-account-alist'.  The account
 specified here will be regarded as the default account for
 various purposes, e.g., for saving copies of outgoing mail."
  :group 'vm-imap
  :type '(choice (const :tag "None" nil) 
		 (string :tag "IMAP Account")))

(defcustom vm-imap-refer-to-inbox-by-account-name nil
  "*If set to non-nil, the INBOX folders on IMAP accounts are
referred to by their account names instead of as \"INBOX\".  The
account names are those declared in `vm-imap-account-alist'.
This is useful if one wants to handle multiple IMAP accounts
during the same VM session, all of which might have an \"INBOX\"
folder."
  :group 'vm-imap
  :type 'boolean)

(defcustom vm-imap-tolerant-of-bad-imap nil
  "*Level of tolerance that vm should use for IMAP servers that
don't follow the IMAP specification.  Default of NIL or 0 means no
tolerance.  Level 1 allows possibly harmless violations of
prohibitions.  (But these violations could also be symptomatic of
deeper problems.)  Use this level carefully.  Higher levels of
violations are not currently permitted."
  :group 'vm-imap
  :type '(choice (const :tag "No Tolerance" nil) 
		 (const :tag "Tolerant" 1)))

(defcustom vm-imap-folder-cache-directory nil
  "*Directory where VM stores cached copies of IMAP folders.
When VM visits a IMAP folder (really just a IMAP server where you
have a mailbox) it stores the retrieved message on your computer
so that they need not be retrieved each time you visit the folder.
The cached copies are stored in the directory specified by this
variable."
  :group 'vm-imap
  :type '(choice (const :tag "None" nil) directory))

(defcustom vm-imap-save-to-server nil
  "*This variable controls the behavior of the `vm-save-message'
command.  If it is non-NIL, then messages from IMAP folders
are saved to other IMAP folders on the server, instead of
local folders.  Messages from local folders are still saved to local
folders.

The specialized commands `vm-save-message-to-local-folder' and
`vm-save-message-to-imap-folder' can be used to obtain particular
behavior independent of this variable."
  :group 'vm-imap
  :type 'boolean)

(defcustom vm-imap-expunge-retries 1
  "*Number of retries to be performed for expunging IMAP mailboxes.
Increase this if your IMAP server is sluggish."
  :group 'vm-imap
  :type 'integer)

(defcustom vm-imap-server-timeout nil
  "*Number of seconds to wait for output from the IMAP server before
timing out.  It can be set to nil to never time out."
  :group 'vm-imap
  :type '(choice (const :tag "Never" nil) 
		 (integer :tag "Seconds")))

(defcustom vm-imap-connection-mode 'online
  "*The mode of connection to the IMAP server.  Possible values
are: `online', `offline', and `autoconnect'.  In the `online' mode,
synchronization works normally and message bodies of external
messages are fetched when needed.  In `offline' mode, no
connection is established to the IMAP server and message bodies
are not fetched.  In the `autoconnect' mode, a connection is
established whenever a synchronization operation is performed and the
connection mode is then turned into `online'."
  :group 'vm-imap
  :type '(choice (const :tag "online" online)
		 (const :tag "offline" offline)
		 (const :tag "autoconnect" autoconnect)))

(defcustom vm-imap-ensure-active-sessions t
  "*If non-NIL, ensures that an IMAP session is active before issuing
commands to the server.  If it is not active, a new session is
started.  This ensures a failure-proof operation, but involves
additional overhead in checking that the session is active."
  :group 'vm-imap
  :type 'boolean)

(defcustom vm-imap-message-bunch-size 10
  "*Number of messages to be bunched together in IMAP server
operations.  This permits faster interation with the IMAP servers.  To
disable bunching, set it to 1."
  :group 'vm-imap
  :type 'integer)

(defcustom vm-imap-sync-on-get t
  "*If this variable is non-NIL, then the vm-get-new-mail command
should synchronize with the IMAP mailbox on the server.  This involves
expunging messages that have been expunged from the server, saving and
retrieving message attributes as well retrieving new messages.  If the
variable is NIL, this functionality can be obtained via the
vm-imap-synchronize command."
  :group 'vm-imap
  :type 'boolean)

(defcustom vm-auto-get-new-mail t
  "*Non-nil value causes VM to automatically move mail from spool files
to a mail folder when the folder is first visited.  Nil means
you must always use `vm-get-new-mail' to pull in newly arrived messages.

If the value is a number, then it specifies how often (in
seconds) VM should check for new mail and try to retrieve it.
This is done asynchronously using a timer task and may occur
while you are editing other files.  It should not disturb your
editing, except perhaps for a pause while the check is being
done."
  :group 'vm-folders
  :type '(choice (const :tag "No" nil)
		 (const :tag "Yes" t)
		 (integer :tag "Seconds")))

(defcustom vm-mail-check-interval 300
  "*Numeric value specifies the number of seconds between checks
for new mail, carried out using a timer task.  The maildrops for all
visited folders are checked. 

A nil value means don't check for new mail.

Note that if new mail is found, it is not retrieved.  The
buffer local variable `vm-spooled-mail-waiting' is set non-nil in
the buffers of those folders that have mail waiting.  VM
displays \"Mail\" in the mode line of folders that have mail
waiting."
  :group 'vm-folders
  :type '(choice (const nil) integer))

(defcustom vm-mail-check-always nil
  "*Set this variable to `t' if you want VM's mail-check to run
continuously and take into account multiple mail clients reading from
the same mail spool."
  :group 'vm-folders
  :type 'boolean)

(defvar vm-spooled-mail-waiting nil
  "Value is non-nil if there is mail waiting for the current folder.
This variable's value is local in all buffers.
VM maintains this variable, you should not set it.")
(make-variable-buffer-local 'vm-spooled-mail-waiting)

(defcustom vm-default-folder-type
  (cond ((not (boundp 'system-configuration))
         'From_)
        ((or (string-match "-solaris" system-configuration)
             (string-match "usg-unix-v" system-configuration)
             (string-match "-ibm-aix" system-configuration))
         'From_-with-Content-Length)
        ((string-match "-sco" system-configuration)
         'mmdf)
        (t 'From_))
  "Default folder type for empty folders.
If VM has to add messages that have no specific folder type to an
empty folder, the folder will become this default type.
Allowed types are:

   From_
   From_-with-Content-Length
   BellFrom_
   mmdf
   babyl

Value must be a symbol, not a string. i.e. write

  (setq vm-default-folder-type \\='From_)

in your .emacs or .vm file.

If you set this variable's value to From_-with-Content-Length you
must set `vm-trust-From_-with-Content-Length' non-nil."
  :group 'vm-folders
  :type '(choice (const From_)
                 (const From_-with-Content-Length)
                 (const BellFrom_)
                 (const mmdf)
                 (const babyl)))

(defcustom vm-default-From_-folder-type 'From_
  "*Value must be a symbol that tells VM which From-style folder type
is used by your local mail delivery system.  Valid values are

    From_
    BellFrom_

Messages in From_ folders are separated by the two newlines
followed by the string \"From\" and a space.  Messages in
BellFrom_ folders are only required to have a single newline
before the \"From\" string.

Since BellFrom_ and From_ folders cannot be reliably distinguished
from each other, you must tell VM which one your system uses by
setting the variable `vm-default-From_-folder-type' to either From_
or BellFrom_."
  :group 'vm-folders
  :type '(choice (const From_)
                 (const BellFrom_)))

(defcustom vm-default-new-folder-line-ending-type nil
  "*Value must be a symbol that specifies the line ending convention
to use for new folders.  Text files under UNIXish and Windows
systems use different characters to indicate the end of a line.
UNIXish systems use a single linefeed character, Windows uses a
carriage return followed by a line feed.  The value of this
variable tells VM which to use.

`nil' means use the line ending convention of the local system;
CRLF if you're on a Windows system, LF for UNIXish systems.
`crlf' means use CRLF.
`lf' mean use LF.
`cr' means use CR (old Macs use this)."
  :group 'vm-folders
  :type '(choice (const :tag "System Default" nil)
		 (const :tag "Windows" crlf)
		 (const :tag "Old Mac" cr)
		 (const :tag "Unix" lf)))

(defcustom vm-check-folder-types t
  "*Non-nil value causes VM to check folder and message types for
compatibility before it performs certain operations.

Before saving a message to a folder, VM will check that the destination folder
is of the same type as the message to be saved.

Before incorporating message into a visited folder, VM will check that the
messages are of the same type as that folder.

A nil value means don't do the checks.

If non-nil, VM will either convert the messages to the appropriate
type before saving or incorporating them, or it will signal an
error.  The value of `vm-convert-folder-types' determines which
action VM will take."
  :group 'vm-folders
  :type 'boolean)

(defcustom vm-convert-folder-types t
  "*Non-nil value means that when VM checks folder types and finds
a mismatch (see `vm-check-folder-types'), it will convert the
source messages to the type of the destination folder, if it can.

If `vm-check-folder-types' is nil, then this variable isn't
consulted."
  :group 'vm-folders
  :type 'boolean)

(defcustom vm-trust-From_-with-Content-Length
  (eq vm-default-folder-type 'From_-with-Content-Length)
  "*Non-nil value means that if the first message in a folder contains
a Content-Length header and begins with \"From \" VM can safely
assume that all messages in the folder have Content-Length headers
that specify the length of the text section of each message.  VM
will then use these headers to determine message boundaries
instead of the usual way of searching for two newlines followed by a
line that begins with \"From \".

If you set `vm-default-folder-type' to From_-with-Content-Length you
must set this variable non-nil."
  :group 'vm-folders
  :type 'boolean)

(defvar vm-sync-thunderbird-status t
  "If set to t, VM synchronizes its headers with the headers of
Thunderbird so that full interoperation with Thunderbird becomes
possible.  If it is set to `read-only' then VM reads the Thunderbird
status flags, but refrains from updating them.  If it is set to nil
then VM makes no attempt to read or write the Thunderbird status
flags.") 

(make-variable-buffer-local 'vm-sync-thunderbird-status)

;; (defvar vm-folder-sync-thunderbird-status t
;;   "If t VM synchronizes its headers with the headers of
;; Thunderbird so that full interoperation with Thunderbird becomes
;; possible.  This is not a customization variable.  See
;; `vm-sync-thunderbird-status' for customization.") 

;; (defvar vm-read-thunderbird-status t
;;   "* If t VM reads the headers of Thunderbird when visiting
;; folders, but not write Thunderbird headers.  This variable has
;; effect only if `vm-folder-sync-thunderbird-status' is nil.")

(defvar vm-folder-read-thunderbird-status t
  "If t VM reads the headers of Thunderbird when visiting
folders.  This is not a customization variable.  See
`vm-sync-thunderbird-status' for customization.")

(make-variable-buffer-local 'vm-folder-read-thunderbird-status)

(defcustom vm-sort-messages-by-delivery-date nil
  "*If set to t, VM will use the \"Delivery-Date\" header instead of
the \"Date\" header for sorting messages."
  :group 'vm-summary
  :type 'boolean)

(defcustom vm-visible-headers
  '("Resent-"
    "From:" "Sender:"
    "To:" "Newsgroups:" "Apparently-To:" "Cc:"
    "Subject:"
    "Date:")
  "*List of headers that should be visible when VM first displays a message.
These should be listed in the order you wish them presented.
Regular expressions are allowed.  There's no need to anchor
patterns with \"^\", as searches always start at the beginning of
a line.  Put a colon at the end of patterns to get exact matches.
For example, \"Date\" matches \"Date\" and \"Date-Sent\".  Header names
are always matched case insensitively.

If the value of `vm-invisible-header-regexp' is nil, only the
headers matched by `vm-visible-headers' will be displayed.
Otherwise all headers are displayed except those matched by
`vm-invisible-header-regexp'.  In this case `vm-visible-headers'
specifies the order in which headers are displayed.  Headers not
matching `vm-visible-headers' are displayed last."
  :group 'vm-presentation
  :type '(repeat regexp))

(defcustom vm-invisible-header-regexp nil
  "*Non-nil value should be a regular expression that tells what headers
VM should NOT normally display when presenting a message.  All other
headers will be displayed.  The variable `vm-visible-headers' specifies
the presentation order of headers; headers not matched by
`vm-visible-headers' are displayed last.

Nil value causes VM to display ONLY those headers specified in
`vm-visible-headers'."
  :group 'vm-presentation
  :type '(choice (const nil) regexp))

(defcustom vm-highlighted-header-regexp nil
  "*Value specifies which headers to highlight.
This is a regular expression that matches the names of headers that should
be highlighted when a message is first presented.  For example setting
this variable to \"From:\\\\|Subject:\" causes the From and Subject
headers to be highlighted.

If you're using XEmacs, you might want to use the builtin
`highlight-headers' package instead.  If so, then you should set
the variable `vm-use-lucid-highlighting' non-nil.  You'll need to
set the various variables used by the highlight-headers package
to customize highlighting.  `vm-highlighted-header-regexp' is
ignored in this case."
  :group 'vm-presentation
  :type '(choice (const nil) regexp))

(defcustom vm-use-lucid-highlighting (condition-case nil
                                         (progn
                                           (require 'highlight-headers)
                                           t )
                                       (error nil))
  "*Non-nil means to use the `highlight-headers' package in XEmacs.
Nil means just use VM's builtin header highlighting code.

FSF Emacs always uses VM's builtin highlighting code."
  :group 'vm-misc
  :type 'boolean)

(defface vm-highlighted-header '((t (:inherit bold)))
 "Default face used to highlight headers."
 :group 'vm-faces)
;; (copy-face 'bold 'vm-highlighted-header)

(defcustom vm-highlighted-header-face 'vm-highlighted-header
  "*Face to be used to highlight headers.
The headers to highlight are specified by the `vm-highlighted-header-regexp'
variable.

This variable is ignored under XEmacs if `vm-use-lucid-highlighting' is
non-nil.  XEmacs' highlight-headers package is used instead.  See the
documentation for the function `highlight-headers' to find out how to
customize header highlighting using this package."
  :group 'vm-faces
  :type 'symbol)

(defcustom vm-preview-lines 0
  "*Non-nil value N causes VM to display the visible headers + N lines of text
of a message when it is first presented.  The message is not actually
flagged as read until it is exposed in its entirety.

A value of t causes VM to display as much of the message as will
fit in the window associated with the folder buffer.

A nil value causes VM not to preview messages; no text lines are hidden and
messages are immediately flagged as read."
  :group 'vm-presentation 
  :type '(choice boolean integer))

(defcustom vm-preview-read-messages nil
  "*Non-nil value means to preview messages even if they've already been read.
A nil value causes VM to preview messages only if new or unread."
  :group 'vm-presentation
  :type 'boolean)

(defconst vm-always-use-presentation-buffer t
  "Non-nil means to always use a presentation buffer for displaying
  messages.  It will also be used if no decoding or other
  modification of the message are necessary.")

(make-obsolete-variable 'vm-always-use-presentation-buffer
  "The current behaviour is equivalent to setting this variable
  to t.  Please remove all settings for this variable and report
  any problems that you might encounter."
  "8.2.0")

(defconst vm-always-use-presentation t
  "Non-nil means to always use a presentation buffer for displaying
  messages.  It will also be used if no decoding or other
  modification of the message are necessary.  

This constant is a place holder for the obsolete variable
`vm-always-use-presentation-buffer'.  It should be removed eventually.")

(defcustom vm-word-wrap-paragraphs nil
  "*If non-nil, causes VM to word wrap paragraphs with long lines.
This is done using the `longlines' library, which must be installed
for the variable to have effect."
  :group 'vm-presentation
  :type 'boolean)

(defcustom vm-word-wrap-paragraphs-in-reply nil
  "*If non-nil, causes VM to word wrap paragraphs with long lines
during message composition.  This is done using the `longlines'
library, which must be installed for the variable to have
effect."
  :group 'vm-reply
  :type 'boolean)

(defcustom vm-fill-paragraphs-containing-long-lines nil
  "*This variable can be set to nil, a numeric value N, the
symbol `window-width'.  If it is numeric, it causes VM to fill
paragraphs that contain lines spanning that many columns or more.
Setting it to `window-width' has the effect of using the width of
the Emacs window.

Only plain text messages and text/plain MIME parts will be
filled.  The message itself is not modified; its text is copied
into a presentation buffer before the filling is done.

This variable determines which paragraphs are filled,
but `vm-paragraph-fill-column' determines the fill column.

Note that filling is carried out only if word wrapping is not in
effect.  The variable `vm-word-wrap-paragraphs' controls word
wrapping."
  :group 'vm-presentation 
  :type '(choice (const :tag "Off" nil)
		 (const :tag "Window width" window-width)
		 (integer :tag "Fill width")))

(defcustom vm-fill-paragraphs-containing-long-lines-in-reply nil
  "This variable can be set to nil, a numeric value N, the
symbol `window-width'.  If it is numeric, it causes VM to fill
included text in replies provided it has lines spanning that many
columns or more.  Setting it to `window-width' has the effect of
using the width of the Emacs window.

This variable determines which paragraphs are filled,
but `vm-fill-long-lines-in-reply-column' determines the fill column.

Note that filling is carried out only if word wrapping is not in
effect.  The variable `vm-word-wrap-paragraphs-in-reply' controls word
wrapping."
  :group 'vm-reply
  :type '(choice (const :tag "No" nil)
		 (const :tag "Window width" window-width)
		 (integer :tag "Fill column")))

(defcustom vm-paragraph-fill-column (default-value 'fill-column)
  "*Column beyond which automatic line-wrapping should happen when
re-filling lines longer than the value of
`vm-fill-paragraphs-containing-long-lines'."
  :group 'vm-presentation
  :type 'integer)

(defcustom vm-fill-long-lines-in-reply-column (default-value 'fill-column)
  "*Fill lines spanning that many columns or more in replies."
  :group 'vm-reply
  :type '(choice (const :tag "Off" nil)
                 (const :tag "Window width" window-width)
                 (integer :tag "Fill column")))

(defcustom vm-use-presentation-minor-modes nil
  "*Asks VM to use minor modes for the message presentation text
when appropriate, e.g., when the text is prepared using the
emacs-w3m package.

Customize `vm-presentation-minor-modes' to set the appropriate minor modes."
  :group 'vm-presentation
  :type '(choice (const :tag "No minor modes" nil)
		 (const :tag "Use minor modes" t)))

(defcustom vm-presentation-minor-modes '((emacs-w3m w3m-minor-mode))
  "*An assocation list mapping message presentation methods,
such as emacs-w3m, to the corresponding minor modes to be used in
the presentation buffer."
  :group 'vm-presentation
  :type '(repeat (list (symbol :tag "Presentation method")
		       (symbol :tag "Minor mode"))))
;; smime related stuff
(defvar vm-smime-sign-message nil
  "Tells VM to sign the message upon sending, should not be set
directly rather use the function `vm-smime-sign-message' or
`vm-smime-sign-encrypt-message'")

(defvar vm-smime-encrypt-message nil
  "Tells VM to encrypt the message upon sending, should not be
set directly rather use the function `vm-smime-encrypt-message'
or `vm-smime-sign-encrypt-message'")

(defcustom vm-smime-get-recipient-certificate-method 'ask
  "The method by which VM should find the certificates to use in
encrypting this S/MIME encoded composition. Valid valus are as follows:

   `ask' - Ask the user to specify the files manually each time. The
          user will be prompted for a file name and whether they want
          to specify another thereafter and so on.

   `links' - This method assumes that there exist links under
            `smime-certificate-directory' given by the recipient address
            to the appropriate PEM encoded certificate, i.e.
             ~/CERTS/bob@somewhere.com -> ~/CERTS/bob_johnstons_certificate.pem
            If any recipient in the message does not have such a link
            the sender will be asked if they would like to supply an
            alternative file"
  :type '(choice (const :tag "Ask" ask)
				 (const :tag "Links" links))
  :group 'vm-mime)

(defcustom vm-display-using-mime t
  "*Non-nil value means VM should display messages using MIME.
MIME (Multipurpose Internet Mail Extensions) is a set of
extensions to the standard Internet message format that allows
reliable tranmission and reception of arbitrary data including
images, audio and video as well as ordinary text.

A non-nil value for this variable means that VM will recognize
MIME encoded messages and display them as specified by the
various MIME standards specifications.

A nil value means VM will not display MIME messages any
differently than any other message."
  :group 'vm-mime
  :type 'boolean)

;; this is t because at this time (11 April 1997) Solaris is
;; generating too many mangled MIME version headers.  For the same
;; reason vm-mime-avoid-folding-content-type is also set to t.
(defcustom vm-mime-ignore-mime-version t
  "*Non-nil value means ignore the version number in the MIME-Version
header.  VM only knows how to decode and display MIME version 1.0
messages.  Some systems scramble the MIME-Version header, causing
VM to believe that it cannot display a message that it actually
can display.  You can set `vm-mime-ignore-mime-version' non-nil if
you use such systems."
  :group 'vm-mime
  :type 'boolean)

(defcustom vm-mime-require-mime-version-header nil
  "*Non-nil means a message must contain MIME-Version to be considered MIME.
The MIME standard requires that MIME messages contain a MIME-Version,
but some mailers ignore the standard and do not send the header.  Set
this variable to nil if you want VM to be lax and parse such messages
as MIME anyway."
  :group 'vm-mime
  :type 'boolean)

(defcustom vm-mime-ignore-composite-type-opaque-transfer-encoding t
  "*Non-nil means VM should ignore transfer encoding declarations
of base64 and quoted-printable for object of type message/* or
multipart/*.  The MIME spec requires that these composite types
use either 7bit, 8bit, or binary transfer encodings but some
mailers declare quoted-printable and base64 even when they are
not used.  Set this variable non-nil if you want VM to be lax and
ignore this problem and try to display the object anyway."
  :group 'vm-mime
  :type 'boolean)

(defcustom vm-mime-ignore-missing-multipart-boundary t
  "*Non-nil means VM should treat a missing MIME boundary marker
as if the marker were at the end of the current enclosing MIME
object or, if there is no enclosing object, at the end of the
message.  A nil value means VM will complain about missing
boundaries and refuse to parse such MIME messages."
  :group 'vm-mime
  :type 'boolean)

(defcustom vm-send-using-mime t
  "*Non-nil value means VM should support sending messages using MIME.
MIME (Multipurpose Internet Mail Extensions) is a set of
extensions to the standard Internet message format that allows
reliable tranmission and reception of arbitrary data including
images, audio and video as well as traditional text.

A non-nil value for this variable means that VM will

  - allow you to attach files and messages to your outbound message.
  - analyze the composition buffer when you send off a message and
    encode it as needed.

A nil value means VM will not offer any support for composing
MIME messages."
  :group 'vm-mime
  :type 'boolean)

(defvaralias 'vm-honor-mime-content-disposition
  'vm-mime-honor-content-disposition)
(defcustom vm-mime-honor-content-disposition nil
  "Non-nil value means use information from the Content-Disposition
header to display MIME messages.  Possible values are `t', to mean that the
Content-Disposition header should always be honored or `internal-only',
to mean that an \"inline\" disposition should be honored only for
internally-displayable types. 

The Content-Disposition header specifies whether a MIME object
should be displayed inline or treated as an attachment.  For VM,
\"inline\" display means displaying the object in the Emacs
buffer, if possible.  Attachments will be displayed as a button
that you can use mouse-2 to activate or mouse-3 to pull up a menu
of options."
  :group 'vm-mime
  :type '(choice (const :tag "Ignore it" nil)
		 (const :tag "Honor it always" t)
		 (const :tag "Honor inline for internal types" internal-only)))

(defcustom vm-auto-decode-mime-messages t
  "*Non-nil value causes MIME decoding to occur automatically
when a message containing MIME objects is exposed.  A nil value
means that you will have to run the `vm-decode-mime-message'
command (normally bound to `D') manually to decode and display
MIME objects."
  :group 'vm-mime
  :type 'boolean)

(defcustom vm-mime-decode-for-preview t
  "*Non-nil value causes partial MIME decoding to happen when a message
is previewed, instead of when it is displayed in full.  The point of
this is if `vm-preview-lines' is set to a non-nil, non-zero
value you can see readable text instead of a potentially inscrutable
MIME jumble.  `vm-auto-decode-mime-messages' must also be set non-nil
for this variable to have effect."
  :group 'vm-mime
  :type 'boolean)

(defvar vm-mime-decode-for-show t
  "*Control variable that says whether MIME messages should be decoded
for showing the message, in addition to decoding for preview.")

(defvaralias 'vm-auto-displayed-mime-content-types
  'vm-mime-auto-displayed-content-types)
(defcustom vm-mime-auto-displayed-content-types 
  '("text" "image" "message/rfc822")
  "List of MIME content types that should be displayed immediately
after decoding.  Other types will be displayed as a button that
you must activate to display the object.

A value of t means that all types should be displayed immediately.
A nil value means never display MIME objects immediately; only use buttons.

If the value is a list, it should be a list of strings, which
should all be types or type/subtype pairs.  Example:

 (setq vm-mime-auto-displayed-content-types \\='(\"text\" \"image/jpeg\"))

If a top-level type is listed without a subtype, all subtypes of
that type are assumed to be included.

Note that all multipart types are processed specially, and this
variable does not apply to them.  In particular,

   multipart/digest messages are always displayed as a button to
   avoid automatically visiting a new folder while you are moving
   around in the current folder.

   message/partial messages are always displayed as a button,
   because there always needs to be a way to trigger the assembly
   of the parts into a full message.

Any type that cannot be displayed internally or externally will
be displayed as a button that allows you to save the body of the MIME
object to a file."
  :group 'vm-mime
  :type '(choice (const t) 
                 (const nil)
                 (repeat string)))

(defvaralias 'vm-auto-displayed-mime-content-type-exceptions
  'vm-mime-auto-displayed-content-type-exceptions)
(defcustom vm-mime-auto-displayed-content-type-exceptions nil
  "List of MIME content types that should not be displayed immediately
after decoding.  These types will be displayed as a button that you
must activate to display the object.  This is an exception list for
the types listed in `vm-mime-auto-displayed-content-types'; all types
listed there will be auto-displayed except those in the exception
list.

The value should be either nil or a list of strings.  The strings
should all be types or type/subtype pairs.  Example:

 (setq vm-mime-auto-displayed-content-type-exceptions \\='(\"text/html\"))

If a top-level type is listed without a subtype, all subtypes of
that type are assumed to be included."
  :group 'vm-mime
  :type '(choice (const nil)
                 (repeat string)))

(defcustom vm-mime-internal-content-types t
  "*List of MIME content types that should be displayed internally
if Emacs is capable of doing so.  A value of t means that VM
displays all types internally if possible.  A list of exceptions
can be specified via `vm-mime-internal-content-type-exceptions'.
A nil value means never display MIME objects internally, which
means VM must run an external viewer to display MIME objects.

If the value is a list, it should be a list of strings.  Example:

 (setq vm-mime-internal-content-types \\='(\"text\" \"message\" \"image/jpeg\"))

If a top-level type is listed without a subtype, all subtypes of
that type are assumed to be included.

Note that all multipart types are always handled internally.
There is no need to list them here."
  :group 'vm-mime
  :type '(choice (const :tag "Display all interanlly when possible" t) 
                 (const :tag "Never use Emacs' internal display capabilities" nil) 
                 (repeat (string :tag "MIME Type"))))

(defcustom vm-mime-internal-content-type-exceptions nil
  "*List of MIME content types that should not be displayed internally.
This is an exception list for the types specified in
`vm-mime-internal-content-types'; all types listed there will be
displayed internally except for those in the exception list.

The value should be a list of strings.  Example:

 (setq vm-mime-internal-content-type-exceptions \\='(\"image/jpeg\"))

If a top-level type is listed without a subtype, all subtypes of
that type are assumed to be included."
  :group 'vm-mime
  :type '(choice (const nil)
                 (repeat string)))

(defcustom vm-mime-external-content-types-alist nil
  "*Alist of MIME content types and the external programs used to display them.
If VM cannot display a type internally or has been instructed not
to (see the documentation for the `vm-mime-internal-content-types'
variable) it will try to launch an external program to display that
type.

The alist format is a list of lists, each sublist having the form

 (TYPE FUNCTION ARG ... )

or

 (TYPE PROGRAM ARG ARG ... )

or

 (TYPE COMMAND-LINE)

TYPE is a string specifying a MIME type or type/subtype pair.
For example \"text\" or \"image/jpeg\".  If a top-level type is
listed without a subtype, all subtypes of that type are assumed
to be included.

In the first form, FUNCTION is a lisp function that is responsible for
displaying the attachment in an external application.  Any ARGS will
be passed to the function as arguments.  The octets that compose the
object will be written into a temporary file and the name of the file
is passed as an additional argument.

In the second form, PROGRAM is a string naming a program to run to
display an object.  Any ARGS will be passed to the program as
arguments.  The octets that compose the object will be written
into a temporary file and the name of the file can be inserted
into an ARG string by writing %f.  In earlier versions of VM the
filename was always added as the last argument; as of VM 6.49 this
is only done if %f does not appear in any of the ARG strings.
The filename inserted by %f will be quoted by `shell-quote-argument'
and thus no single quotes should be used, i.e. do not use the following 
\"...\\='%f'...\".

If the COMMAND-LINE form is used, the program and its arguments
are specified as a single string and that string is passed to the
shell for execution.  Since the command line will be passed to
the shell, you can use shell variables and redirection if needed.
As with the PROGRAM/ARGS form, the name of the temporary file
that contains the MIME object will be appended to the command
line if %f does not appear in the command line string.

In either the PROGRAM/ARG or COMMAND-LINE forms, all the
program and argument strings will have any %-specifiers in
them expanded as described in the documentation for the
variable `vm-mime-button-format-alist'.  The only difference
is that %f refers to the temporary file VM creates to store
the object to be displayed, not the filename that the sender
may have associated with the attachment.

Example:

 (setq vm-mime-external-content-types-alist
       \\='((\"text/html\" 	browse-url-of-file)
	 (\"image/gif\" 	\"xv\")
	 (\"image/jpeg\" 	\"xv\")
	 (\"video/mpeg\" 	\"mpeg_play\")
	 (\"video\" 		w32-shell-execute \"open\")))

The first matching list element will be used.

No multipart message will ever be sent to an external viewer."
  :group 'vm-mime
  :type '(choice (const nil)
                 (alist :key-type (string :tag "MIME Type")
			:value-type 
			(choice 
			 (group :tag "Function"
				(function :tag "Function")
				(repeat :inline t (string :tag "Args")))
			 (group :tag "Program" (file :tag "Program")
				(repeat :inline t (string :tag "Args")))
			 (string :tag "Shell Command")))))

(defcustom vm-mime-external-content-type-exceptions nil
  "*List of MIME content types that should not be displayed externally
without a manual request from the user.  This is an exception list
for the types specified in `vm-mime-external-content-types-alist';
types listed there will not be displayed using the specified viewer
unless you explicitly request it by menu or `$ e' from the keyboard.

The value should be a list of strings.  Example:

 (setq vm-mime-external-content-type-exceptions \\='(\"text/html\"))

If a top-level type is listed without a subtype, all subtypes of
that type are assumed to be included."
  :group 'vm-mime
  :type '(choice (const nil)
                 (repeat string)))

(defcustom vm-mime-delete-viewer-processes t
  "*Non-nil value causes VM to kill external MIME viewer processes
when you switch to a different message or quit the current message's
folder."
  :group 'vm-mime
  :type 'boolean)

(defcustom vm-mime-type-converter-alist nil
  "*Alist of MIME types and programs that can convert between them.
If VM cannot display a content type, it will scan this list to
see if the type can be converted into a type that it can display.

The alist format is

 ( (START-TYPE END-TYPE COMMAND-LINE ) ... )

START-TYPE is a string specifying a MIME type or type/subtype pair.
Example \"text\" or \"image/jpeg\".  If a top-level type is
listed without a subtype, all subtypes of that type are assumed
to be included.

END-TYPE must be an exact type/subtype pair.  This is the type
to which START-TYPE will be converted.

COMMAND-LINE is a string giving a command line to be passed to
the shell.  The octets that compose the object will be written to
the standard input of the shell command.

Example:

 (setq vm-mime-type-converter-alist
       \\='((\"image/jpeg\"	\"image/gif\"	\"jpeg2gif\")
	 (\"text/html\"		\"text/plain\"	\"striptags\")))

The first matching list element will be used."
  :group 'vm-mime
  :type '(choice (const nil)
                 (repeat (list (string :tag "From type")
                               (string :tag "To type")
                               (string :tag "Converter program")))))
(defvaralias 'vm-mime-alternative-select-method
  'vm-mime-alternative-show-method)
(make-obsolete-variable 'vm-mime-alternative-select-method
			'vm-mime-alternative-show-method
			"8.2.0")			


(defcustom vm-mime-charset-converter-alist nil
  "*Alist of MIME charsets and programs that can convert between them.
If VM cannot display a particular character set, it will scan this list to
see if the charset can be converted into a charset that it can display.

The alist format is

 ( ( START-CHARSET END-CHARSET COMMAND-LINE ) ... )

START-CHARSET is a string specifying a MIME charset.
Example \"iso-8859-1\" or \"utf-8\".

END-CHARSET is a string specifying the charset to which START-CHARSET
will be converted.

COMMAND-LINE is a string giving a command line to be passed to
the shell.  The characters in START-CHARSET will be written to the
standard input of the shell command and VM expects characters
encoded in END-CHARSET to appear at the standard output of the
COMMAND-LINE.  COMMAND-LINE is passed to the shell, so you can
use pipelines, shell variables and redirections.

Example:

 (setq vm-mime-charset-converter-alist
       \\='((\"utf-8\" \"iso-2022-jp\" \"iconv -f utf-8 -t iso-2022-jp\")))

The first matching list element will be used."
  :group 'vm-mime
  :type '(choice (const nil)
                 (repeat (list string string string))))

(defcustom vm-mime-alternative-show-method 'best-internal
  "Value tells how to choose which alternative to display when
it displays a message with \"multipart/alternative\" content.
Possible values are `best', `best-internal', `all', or a
favorite-methods list as described below.

  A MIME message of type multipart/alternative has multiple
message parts containing the same information, but each part may
be formatted differently.  VM will typically display only one of
the parts.  This variable tells VM how to choose which part to
display.

  (There is a separate variable `vm-mime-alternative-yank-method'
for deciding the multipart/alternative to be used in replies.)

  A value of `best' means choose the part that is the most
faithful to the sender's original content that can be displayed.

  A value of `best-internal' means choose the best part that can
be displayed internally, (i.e. with the built-in capabilities of
Emacs) and is allowed to be displayed internally (see
`vm-mime-internal-content-types').  If none of the parts can be
displayed internally, behavior reverts to that of `best'.

  A value of `all' means that all the alternatives are displayed.

  The value can also be a list of the form

  (favorite TYPE ...)

with the first element of the list being the symbol `favorite'.  The
remaining elements of the list are strings specifying MIME types.
VM will look for each TYPE in turn in the list of alternatives and
choose the first matching alternative found that can be displayed.

If the symbol `favorite' is `favorite-internal' instead, the first TYPE
that matches an alternative that can be displayed internally will be
chosen."

  :group 'vm-mime
  :type '(choice (choice (const best-internal)
                         (const best)
                         (const all))
                 (cons (const favorite) (repeat string))
                 (cons (const favorite-internal) (repeat string))))

(defcustom vm-mime-alternative-yank-method nil
  "*Value tells how to choose which alternative to yank, i.e.,
include, in replies, when it yanks a mesage with
\"multipart/alternative\" content.  (It is similar to
`vm-mime-alternative-show-method' used for displaying messages.)
Possible values are `best', `best-internal', `all', or a
favorite-methods list as described below.

  A value of `best' means choose the part that is the most faithful to
the sender's original content that can be displayed.

  A value of `best-internal' means choose the best part that can
be displayed internally, (i.e. with the built-in capabilities of
Emacs) and is allowed to be displayed internally (see
`vm-mime-internal-content-types').  If none of the parts can be
displayed internally, behavior reverts to that of `best'.

  A value of `all' means that all the alternatives are yanked.

  The value can also be a list of the form

  (favorite TYPE ...)

with the first element of the list being the symbol `favorite'.  The
remaining elements of the list are strings specifying MIME types.
VM will look for each TYPE in turn in the list of alternatives and
choose the first matching alternative found that can be displayed.

If the symbol `favorite' is `favorite-internal' instead, the first TYPE
that matches an alternative that can be displayed internally will be
chosen."

  :group 'vm-mime
  :type '(choice (const :tag "Use vm-mime-alternative-show-method" nil)
		 (const best-internal)
                 (const best)
                 (const all)
                 (cons (const favorite) (repeat string))
                 (cons (const favorite-internal) (repeat string))))

(defcustom vm-mime-multipart/related-show-method 'related
  "*Value tells how to handle \"multipart/related\" attachments in
email messages.  The possible values are `mixed' and `related'.

The value of `mixed' asks VM to treat \"multipart/related\"
attachments the same way as \"multipart/mixed\" attachments, i.e., all
of them will be displayed either as buttons or as content.

The value of `related' asks VM to use them as related parts which means
that they will be embedded in rendered \"text/html\" parts.

Some mail messages arrive with wrong placement of the
\"multipart/related\" content, inhibiting the html viewers from
accessing them.  In that case, setting this variable to `mixed' will
allow you to view them separately."
  :group 'vm-mime
  :type '(choice (choice (const mixed)
                         (const related))))

(defvar vm-mime-cid-retrieved nil
  "Internal variable to keep track of whether the display of
\"multipart/related\" content worked as expected, by shipping the
cid: attachments to the content viewer.")

(defcustom vm-mime-verify-signatures nil
  "*Non-nil value means that VM should attempt to verify signatures
attached in \"multipart/signed\" parts."
  :group 'vm-mime
  :type '(choice (const :tag "Do not verify" nil)
		 (const :tag "Verify" t)))

(defcustom vm-mime-text/html-handler 'auto-select
  "*The library used for displaying HTML messages.  The possible
values are:
  emacs-w3m  The emacs interface to the w3m viewer,
  emacs-w3   The emacs interface to the w3 viewer,
  w3m        The w3m viewer used externally to convert to plain text,
  lynx       The lynx viewer used externally to convert to plain text,
  auto-select Automatic selection among these alternatives, and
  nil        No internal display of HTML messages.
"
  :group 'vm-mime
  :type '(choice (const :tag "Do not display HTML messages." nil)
                 (const :tag "Autoselect best method" auto-select)
                 (const emacs-w3m)
                 (const emacs-w3)
                 (const w3m)
                 (const lynx)))

(defcustom vm-mime-text/html-blocker "<img[^>]*\\s-src=."
  "*Regexp after which a \"blocked:\" will be inserted.
This is done in order to prevent loading of embedded images used to check if
and when you read an email."
  :group 'vm-mime
  :type 'regexp)

(defcustom vm-mime-text/html-blocker-exceptions nil
  "*Regexp matching URL which should not be blocked."
  :group 'vm-mime
  :type '(choice (const :tag "None" nil)
		 regexp))

(defcustom vm-mime-default-face-charsets
  (if (not (featurep 'xemacs))
      (if (eq window-system nil)
          '("us-ascii" "ansi_x3.4-1968" "iso-8859-1")
        '("us-ascii" "ansi_x3.4-1968"))
    '("us-ascii" "ansi_x3.4-1968" "iso-8859-1"))
  "*List of character sets that can be displayed using the `default' face.
The default face is what you normally see when you edit text in Emacs.
The font assigned to the default face can typically display one or two
character sets.  For U.S. and Western European users, `us-ascii' and
one of the ISO-8859 character sets usually can be displayed.  Whatever
character sets that your default face can display should be listed as
the value of `vm-mime-default-face-charsets'.  Example:

 (setq vm-mime-default-face-charsets
       \\='(\"us-ascii\" \"ansi_x3.4-1968\" \"iso-8859-1\"))

Case is not significant in character set names.

For Emacs versions with MULE or Unicode support, this variable is
semi-obsolete and should only be used for making bogus, unregistered
character sets that are slight variants of ISO-8859-1 visible.
Don't add charsets like \"utf-8\" that require additional decoding.

A value of t means all character sets can be displayed by the
default face.  This should only be used in combination with
`vm-mime-default-face-charset-exceptions' to tell VM that most of
the mail you receive is displayable using your default face and
its associated font, even though the messages might arrive with
unknown or unregistered character sets specified in the MIME
Content-Type header."
  :group 'vm-mime
  :type '(choice (const t) (repeat string)))

(defcustom vm-mime-default-face-charset-exceptions nil
  "*List of character sets that cannot be displayed using the default face.
This variable acts as an exception list for `vm-mime-default-face-charsets'.
Character sets listed here will not be considered displayable using the
default face even if they are also listed in `vm-mime-default-face-charsets'."
  :group 'vm-mime
  :type '(repeat string))

(defcustom vm-mime-use-image-strips t
  "*Non-nil means chop an image into horizontal strip for display.
Emacs treats a displayed image as a single large character and cannot
scroll vertically within an image.  To work around this limitation VM
can display an image as a series of contiguous horizontal strips that
Emacs' scrolling routines can better handle.  To do this VM needs to
have the ImageMagick programs `convert' and `identify' installed;
`vm-imagemagick-convert-program' and `vm-imagemagick-identify-program'
must point to them.

A nil value means VM should display images without cutting them
into strips."
  :group 'vm-mime
  :type 'boolean)

(defcustom vm-mime-display-image-strips-incrementally t
  "*Non-nil means display image strips as they are created
rather than waiting until all the strips are created and displaying
them all at once.  See `vm-mime-use-image-strips'."
  :group 'vm-mime
  :type 'boolean)

(defun vm-locate-executable-file (name)
  (or (cond ((fboundp 'locate-file)
	     (locate-file name exec-path nil 1))
	    (t
	     (let (file done (dirs exec-path))
	       (while (and dirs (not done))
		 (setq file (expand-file-name name (car dirs)))
		 (if (file-executable-p file)
		     (setq done t)
		   (setq dirs (cdr dirs))))
	       (and dirs file))))
      (let ((vmdir (file-name-directory (locate-library "vm")))
	    file)
	(setq vmdir (expand-file-name "../src/" vmdir)
	      file (expand-file-name name vmdir))
	(if (file-exists-p file)
	    file
;	  (vm-warn 0 2 "VM could not find executable %S!" name)
	  nil))))

(defcustom vm-imagemagick-convert-program (vm-locate-executable-file "convert")
  "*Name of ImageMagick `convert' program.
VM uses this program to convert between image formats and to slice up
images for display.  Set this to nil and VM will not use the
`convert' program."
  :group 'vm-helpers
  :type '(choice (const :tag "None" nil)
		 file))

(defcustom vm-imagemagick-identify-program
  (vm-locate-executable-file "identify")
  "*Name of ImageMagick `identify' program.
VM uses this program to gather information about images.  Set this to nil
and VM will not use the `convert' program."
  :group 'vm-helpers
  :type '(choice (const :tag "None" nil)
		 file))

(defvar vm-mime-image-type-converter-alist
  (if (stringp vm-imagemagick-convert-program)
      (let ((x vm-imagemagick-convert-program))
	(list
	 (list "image" "image/png" (format "%s - png:-" x))
	 (list "image" "image/jpeg" (format "%s - jpeg:-" x))
	 (list "image" "image/gif" (format "%s - gif:-" x))
	 (list "image" "image/tiff" (format "%s - tiff:-" x))
	 (list "image" "image/xpm" (format "%s - xpm:-" x))
	 (list "image" "image/pbm" (format "%s - pbm:-" x))
	 (list "image" "image/xbm" (format "%s - xbm:-" x))
	))))

(defcustom vm-mime-delete-after-saving nil
  "*Non-nil value causes VM to delete MIME body contents from a folder
after the MIME object has been saved to disk.  The MIME object is replaced
with a message/external-body object that points to the disk copy of the
object."
  :group 'vm-mime
  :type 'boolean)

(defcustom vm-mime-confirm-delete t
  "*Non-nil value causes VM to request confirmation from the user before
deleting a MIME object with `vm-delete-mime-object'."
  :group 'vm-mime
  :type 'boolean)

(defvaralias 'vm-mime-savable-types
  'vm-mime-saveable-types)
(defcustom vm-mime-saveable-types
  (append
   '("application" "x-unknown" "application/x-gzip")
   ;; These are eliminated because they depend on evaluation order.
   ;; USR, 2011-04-28
   ;; (mapcar (lambda (a) (car a))
   ;;         vm-mime-external-content-types-alist)
   )
  "List of MIME types which should be saved."
    :group 'vm-mime
    :type '(repeat (string :tag "MIME type" nil)))

(defvaralias 'vm-mime-savable-type-exceptions
  'vm-mime-saveable-type-exceptions)
(defcustom vm-mime-saveable-type-exceptions
  '("text")
  "List of MIME types which should not be saved."
  :group 'vm-mime
  :type '(repeat (string :tag "MIME type" nil)))

(defvaralias 'vm-mime-deletable-types
  'vm-mime-deleteable-types)
(defcustom vm-mime-deleteable-types
  (append
   '("application" "x-unknown" "application/x-gzip")
   ;; These are eliminated because they depend on evaluation order.
   ;; USR, 2011-04-28
   ;; (mapcar (lambda (a) (car a))
   ;;         vm-mime-external-content-types-alist)
   )
  "List of MIME types which should be deleted."
    :group 'vm-mime
    :type '(repeat (string :tag "MIME type" nil)))

(defvaralias 'vm-mime-deletable-type-exceptions
  'vm-mime-deleteable-type-exceptions)
(defcustom vm-mime-deleteable-type-exceptions '("text")
  "List of MIME types which should not be deleted."
  :group 'vm-mime
  :type '(repeat (string :tag "MIME type" nil)))

(defvar vm-mime-auto-save-all-attachments-avoid-recursion nil
  "For internal use.")

(defface vm-mime-button 
  '((((type x w32 mswindows mac) (class color) (background light))
     (:background "lightgrey" :box (:line-width 2 :style released-button)))
    (((type x w32 mswindows mac) (class color) (background dark))
     (:background "grey50" :box (:line-width 2 :style released-button)))
    (((class color) (background light)) (:foreground "blue" :underline t))
    (((class color) (background dark)) (:foreground "cyan" :underline t))
    (t (:underline t)))
  "Default face used for MIME buttons."
  :group 'vm-faces)

(defface vm-mime-button-mouse
  '((((type x w32 mswindows mac) (class color))
     (:inherit highlight :box (:line-width 2 :style released-button)))
    (((class color)) (:inherit highlight))
    (t (:inherit highlight)))
  "*Face to fontify focused MIME buttons."
  :group 'vm-faces)

(defface vm-mime-button-pressed-face
  '((((type x w32 mswindows mac) (class color))
     (:inherit vm-mime-button :box (:line-width 2 :style pressed-button)))
    (((class color)) (:inherit vm-mime-button))
    (t (:inherit vm-mime-button)))
  "*Face to fontify pressed MIME buttons. (This is not yet used in VM.)"
  :group 'vm-faces)

(defcustom vm-mime-button-face 'vm-mime-button
  "*Face used for text in buttons that trigger the display of MIME objects."
  :group 'vm-faces
  :type 'symbol)

(defcustom vm-mime-button-mouse-face 'vm-mime-button-mouse
  "*Face used for text in MIME buttons when mouse is hovering."
  :group 'vm-faces
  :type 'symbol)

(defface vm-attachment-button 
  '((((type x w32 mswindows mac) (class color) (background light))
     (:background "LavenderBlush3" :box (:line-width 2 :style released-button)))
    (((type x w32 mswindows mac) (class color) (background dark))
     (:background "LavenderBlush4" :box (:line-width 2 :style released-button)))
    (((class color) (background light)) (:foreground "blue" :underline t))
    (((class color) (background dark)) (:foreground "cyan" :underline t))
    (t (:underline t)))
  "Default face used for MIME buttons."
  :group 'vm-faces)

(defface vm-attachment-button-mouse
  '((((type x w32 mswindows mac) (class color))
     (:inherit highlight :box (:line-width 2 :style released-button)))
    (((class color)) (:inherit highlight))
    (t (:inherit highlight)))
  "*Face to fontify focused MIME buttons."
  :group 'vm-faces)

(defface vm-attachment-button-pressed-face
  '((((type x w32 mswindows mac) (class color))
     (:inherit vm-attachment-button :box (:line-width 2 :style pressed-button)))
    (((class color)) (:inherit vm-attachment-button))
    (t (:inherit vm-attachment-button)))
  "*Face to fontify pressed MIME buttons. (This is not yet used in VM.)"
  :group 'vm-faces)

(defcustom vm-attachment-button-face 'vm-attachment-button
  "*Face used for text in buttons that trigger the display of MIME objects."
  :group 'vm-faces
  :type 'symbol)

(defcustom vm-attachment-button-mouse-face 'vm-attachment-button-mouse
  "*Face used for text in MIME buttons when mouse is hovering."
  :group 'vm-faces
  :type 'symbol)

(defcustom vm-mime-button-format-alist
  '(("text" . "%-60.60(%t (%c): %f, %d%) %10.10([%a]%)")
    ("multipart/alternative" . "%-50.50(%d%) %20.20([%a]%)")
    ("multipart/digest" . "%-50.50(%d, %n message%s%) %20.20([%a]%)")
    ("multipart" . "%-50.50(%d, %n part%s%) %20.20([%a]%)")
    ("message/partial" . "%-50.50(%d, part %N (of %T)%) %20.20([%a]%)")
    ("message/external-body" . "%-55.55(%d%) [%a (%x)]")
    ("message" . "%-50.50(%d%) %20.20([%a]%)")
    ("audio" . "%-55.55(%t: %f, %d%) %10.10([%a]%)")
    ("video" . "%-55.55(%t: %f, %d%) %10.10([%a]%)")
    ("image" . "%-55.55(%t: %f, %d%) %10.10([%a]%)")
    ("application" . "%-55.55(%t: %f, %d%) %10.10([%a]%)"))
  ;; old definition
  ;; '(("text" . "%-35.35(%d, %c%) [%k to %a]")
  ;;   ("multipart/alternative" . "%-35.35(%d%) [%k to %a]")
  ;;   ("multipart/digest" . "%-35.35(%d, %n message%s%) [%k to %a]")
  ;;   ("multipart" . "%-35.35(%d, %n part%s%) [%k to %a]")
  ;;   ("message/partial" . "%-35.35(%d, part %N (of %T)%) [%k to %a]")
  ;;   ("message/external-body" . "%-35.35(%d%) [%k to %a (%x)]")
  ;;   ("message" . "%-35.35(%d%) [%k to %a]")
  ;;   ("audio" . "%-35.35(%d%) [%k to %a]")
  ;;   ("video" . "%-35.35(%d%) [%k to %a]")
  ;;   ("image" . "%-35.35(%d%) [%k to %a]")
  ;;   ("application/octet-stream" . "%-35.35(%d, %f%) [%k to %a]"))
  "*List of types and formats for MIME buttons.
When VM does not display a MIME object immediately, it displays a
button or tag line in its place that describes the object and what you
have to do to display it.  The value of `vm-mime-button-format-alist'
determines the format of the text in those buttons.

The format of the list is

  ((TYPE . FORMAT) (TYPE . FORMAT) ...)

The list is searched sequentially and the FORMAT corresponding to
the first TYPE that matches the type of the button's object is
used.

TYPE should be a string specifying a top level type or a type/subtype
pair.  If a top-level type is listed without a subtype, all subtypes
of that type are assumed to be included.

FORMAT should be a string specifying the text of the button.  The
string should not include a newline.  The string may contain the
printf-like `%' conversion specifiers which substitute information
about the MIME object into the button.

Recognized specifiers are:
   a - the default action of the button.  E.g. \"display image\" for images,
       \"display text\" for text objects and so on.
   c - the character set of the object.  Usually only specified
       for text objects.  Displays as \"us-ascii\" if the MIME object
       does not specifiy a character set.
   d - the content description of the object taken from the
       Content-Description header, if present.  If the header
       isn't present, a generic description is provided.
   e - the content transfer encoding, either \"base64\" or
       \"quoted-printable\".
   f - the suggested file name to save the object into, as
       specified either in the Content-Disposition header, or the
       \"name\" parameter for objects of type \"application\".
   k - how to activate the button.  Usually \"Press RETURN\" or
       \"Click mouse-2\".
   n - for multipart types this is the number of bundled parts,
       messages, whatever.
   N - for message/partial objects, the part number.
   s - an empty string if %n would display \"1\", otherwise
       \"s\".
   t - the content type of the object, e.g. \"text/enriched\".
   T - for message/partial objects, the total number of expected
       parts.  \"?\" is displayed if the object doesn't specify
       the total number of parts expected.
   x - the content type of the external body of a message/external-body
       object.
   ( - starts a group, terminated by %).  Useful for specifying
       the field width and precision for the concatentation of
       group of format specifiers.  Example: \"%.25(%d, %t, %f%)\"
       specifies a maximum display width of 25 characters for the
       concatenation of the content description, content type and
       suggested file name.
   ) - ends a group.

Use %% to get a single %.

A numeric field width may be given between the `%' and the specifier;
this causes right justification of the substituted string.  A negative field
width causes left justification.

The field width may be followed by a `.' and a number specifying
the maximum allowed length of the substituted string.  If the
string is longer than this value the right end of the string is
truncated.  If the value is negative, the string is truncated on
the left instead of the right."
  :group 'vm-mime
  :type '(repeat (cons (string :tag "MIME Type")
		       (string :tag "Format"))))

(defcustom vm-mime-parts-display-separator
  "\n----------------------------------------------------------------------\n"
  "*Separator string to insert between mime parts when displayed
one after another."
  :group 'vm-mime
  :type 'string)

(defcustom vm-mime-7bit-composition-charset "us-ascii"
  "*Character set that VM should assume if it finds no character codes > 128
in a composition buffer.  Composition buffers are assumed to use
this character set unless the buffer contains a byte with the high bit set.
This variable specifies what character set VM should assume if
no such a character is found.

This variable is unused in XEmacs/MULE.  Since multiple character
sets can be displayed in a single buffer under MULE, VM will map
the file coding system of the composition buffer to a single MIME
character set that can display all the buffer's characters."
  :group 'vm-mime
  :type 'string)

(defcustom vm-mime-8bit-composition-charset nil
  "*Character set that VM should assume if it finds non-US-ASCII characters
in a composition buffer.  Composition buffers are assumed to use
US-ASCII unless the buffer contains a byte with the high bit set.
This variable specifies what character set VM should assume if
such a character is found.

This variable is unused in XEmacs/MULE and FSF Emacs starting
with version 20.  Since multiple character sets can be displayed
in a single buffer under MULE, VM will map the file coding system
of the buffer to a single MIME character set that can display all
the buffer's characters."
  :group 'vm-mime
  :type '(choice (string :tag "iso-8859-1" "iso-8859-1")
                 (string :tag "iso-2022-jp" "iso-2022-jp")
                 (string :tag "User defined")
                 (const  :tag "Auto select" nil)))

(defcustom vm-mime-8bit-text-transfer-encoding 'quoted-printable
  "*Symbol specifying what kind of transfer encoding to use on 8bit
text.  Characters with the high bit set cannot safely pass
through all mail gateways and mail transport software.  MIME has
two transfer encodings that convert 8-bit data to 7-bit for safe
transport. Quoted-printable leaves the text mostly readable even
if the recipient does not have a MIME-capable mail reader.  BASE64
is unreadable without a MIME-capable mail reader, unless your name
is U3BvY2s=.

A value of `quoted-printable', means to use quoted-printable encoding.
A value of `base64' means to use BASE64 encoding.
A value of `8bit' means to send the message as is.

Note that this variable usually only applies to textual MIME
content types.  Images, audio, video, etc. typically will have
some attribute that makes VM consider them to be \"binary\",
which moves them outside the scope of this variable.  For
example, messages with line lengths of 1000 characters or more
are considered binary, as are messages that contain carriage
returns (ascii code 13) or NULs (ascii code 0)."
  :group 'vm-mime
  :type '(choice (const quoted-printable) 
                 (const base64) 
                 (const 8bit)))

(defcustom vm-mime-composition-armor-from-lines nil
  "*Non-nil value means \"From \" lines should be armored before sending.
A line beginning with \"From \" is considered a message separator
by many mail delivery agents.  These agents will often insert a >
before the word \"From\" to prevent mail readers from being
confused.  This is proper behavior, but it breaks digitally signed
messages, which require bit-perfect transport in order for the
message contents to be considered genuine.

If `vm-mime-composition-armor-from-lines' is non-nil, a line
beginning with \"From \" will cause VM to encode the message
using either quoted-printable or BASE64 encoding so that the From
line can be protected."
  :group 'vm-mime
  :type 'boolean)

(defcustom vm-mime-attachment-auto-type-alist
  '(
    ("\\.jpe?g$"  .  "image/jpeg")
    ("\\.gif$"    .  "image/gif")
    ("\\.png$"    .  "image/png")
    ("\\.tiff?$"  .  "image/tiff")
    ("\\.svg$"    .  "image/svg+xml")
    ("\\.pcx$"    .  "image/x-pcx")
    ("\\.txt$"    .  "text/plain")
    ("\\.html?$"  .  "text/html")
    ("\\.css$"    .  "text/css")
    ("\\.csv$"    .  "text/csv")
    ("\\.xml$"    .  "text/xml")
    ("\\.vcf$"    .  "text/x-vcard")
    ("\\.vcard$"  .  "text/x-vcard")
    ("\\.au$"     .  "audio/basic")
    ("\\.mp4$"    .  "audio/mp4")
    ("\\.m4[abpr]$". "audio/mp4")
    ("\\.wma$"    .  "audio/x-ms-wma")
    ("\\.wax$"    .  "audio/x-ms-wax")
    ("\\.ram?$"   .  "audio/vnd.ra-realaudio")
    ("\\.ogg$"    .  "audio/vorbis")
    ("\\.oga$"    .  "audio/vorbis")
    ("\\.wav$"    .  "audio/vnd.wave")
    ("\\.mpe?g$"  .  "video/mpeg")
    ("\\.m4v$"    .  "video/mp4")
    ("\\.mov$"    .  "video/quicktime")
    ("\\.ogc$"    .  "video/ogg")
    ("\\.wmv$"    .  "video/x-ms-wmv")
    ("\\.webm$"   .  "video/webm")
    ("\\.zip$"    .  "application/zip")
    ("\\.gz$"     .  "application/x-gzip")
    ("\\.tar$"    .  "application/x-tar")
    ("\\.rar$"    .  "application/x-rar-compressed")
    ("\\.e?ps$"   .  "application/postscript")
    ("\\.pdf$"    .  "application/pdf")
    ("\\.dvi$"    .  "application/x-dvi")
    ("\\.tex$"    .  "application/x-latex")
    ("\\.ttf$"    .  "application/x-font-ttf")
    ("\\.swf$"    .  "application/x-shockwave-flash")
    ("\\.tex$"    .  "application/x-latex")
    ("\\.js$"     .  "application/javascript")
    ("\\.dtd$"    .  "application/xml-dtd")
    ("\\.pdf$"    .  "application/pdf")
    ("\\.rtf$"    .  "application/rtf")
    ("\\.doc$"    .  "application/msword")
    ("\\.xls$"    .  "application/vnd.ms-excel")
    ("\\.ppt$"    .  "application/vnd.ms-powerpoint")
    ("\\.mdb$"    .  "application/vnd.ms-access")
    ("\\.odt$"    .  "application/vnd.oasis.opendocument.text")
    ("\\.odp$"    .  "application/vnd.oasis.opendocument.presentation")
    ("\\.ods$"    .  "application/vnd.oasis.opendocument.spreadsheet")
    ("\\.odg$"    .  "application/vnd.oasis.opendocument.graphics")
    ("\\.odf$"    .  "application/vnd.oasis.opendocument.formulae")
    ("\\.odb$"    .  "application/vnd.oasis.opendocument.databases")
    ("\\.docx$"   .  "application/vnd.openxmlformats-officedocument.wordprocessingml.document")
    ("\\.docm$"   .  "application/vnd.openxmlformats-officedocument.wordprocessingml.document")
    ("\\.pptx$"   .  "application/vnd.openxmlformats-officedocument.presentationml.presentation")
    ("\\.pptm$ "  .  "application/vnd.openxmlformats-officedocument.presentationml.presentation")
    ("\\.xlsx$"   .  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
    ("\\.xlsm$"   .  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
    ("\\.hqx$"    .  "application/mac-binhex40")
    )
  "*Alist used to guess a MIME content type based on a file name.
The list format is

  ((REGEXP . TYPE) ...)

REGEXP is a string that specifies a regular expression.
TYPE is a string specifying a MIME content type.

When a file is attached to a MIME composition buffer using
`vm-attach-file', this list will be scanned until a REGEXP
matches the file's name.  The corresponding TYPE will be
offered as a default when you are prompted for the file's
type.

The value of this variable is also used to guess the MIME type of
application/octet-stream objects for display purposes if the
value of `vm-infer-mime-types' is non-nil."
  :group 'vm-mime
  :type '(repeat (cons regexp 
		       (string :tag "MIME Type"))))

(defcustom vm-mime-attachment-auto-suffix-alist
  '(
    ("image/jpeg"		.	".jpg")
    ("image/gif"		.	".gif")
    ("image/png"		.	".png")
    ("image/tiff"		.	".tif")
    ("text/html"		.	".html")
    ("audio/basic"		.	".au")
    ("video/mpeg"		.	".mpg")
    ("video/quicktime"		.	".mov")
    ("application/zip"		.	".zip")
    ("application/postscript"	.	".ps")
    ("application/pdf"		.	".pdf")
    ("application/msword"	.	".doc")
    ("application/vnd.ms-excel"	.	".xls")
    ("application/vnd.ms-powerpoint" .	".ppt")
    ("application/mac-binhex40"	.	".hqx")
   )
  "*Alist used to select a filename suffix for MIME object temporary files.
The list format is

  ((TYPE . SUFFIX) ...)

TYPE is a string specifying a MIME top-level type or a type/subtype pair.
If a top-level type is listed without a subtype, all subtypes of
that type are matched.

SUFFIX is a string specifying the suffix that should be used for
the accompanying type.

When a MIME object is displayed using an external viewer VM must
first write the object to a temporary file.  The external viewer
opens and displays that file.  Some viewers will not open a file
unless the filename ends with some extention that it recognizes
such as '.html' or '.jpg'.  You can use this variable to map MIME
types to extensions that your external viewers will recognize.  VM
will search the list for a matching type.  The suffix associated
with the first type that matches will be used."
  :group 'vm-mime
  :type '(repeat (cons (string :tag "MIME Type") 
		       (string :tag "File Suffix"))))

(defcustom vm-mime-encode-headers-regexp
  "Subject\\|\\(\\(Resent-\\)?\\(From\\|To\\|CC\\|BCC\\)\\)\\|Organization"
  "*A regexp matching the headers which should be encoded."
  :group 'vm-mime
  :type '(regexp))

(defcustom vm-mime-encode-headers-words-regexp
  (let ((8bit-word "\\([^ ,\t\n\r]*[^\x0-\x7f]+[^ ,\t\n\r]*\\)+"))
    (concat "[ ,\t\n\r]\\(" 8bit-word "\\(\\s-+" 8bit-word "\\)*\\)"))
  "*A regexp matching a set of consecutive words which must be encoded."
  :group 'vm-mime
  :type '(regexp))

(defcustom vm-mime-encode-headers-type 'Q
  "*The encoding type to use for encoding headers."
  :group 'vm-mime
  :type '(choice (const  :tag "Quoted-printable" Q)
                 (const  :tag "Binary" B)
                 (regexp :tag "BASE64 on match of " 
                         "[^- !#-'*+/-9=?A-Z^-~]")))

(defcustom vm-mime-encode-words-regexp "[^\x0-\x7f]+"
  "*A regexp matching a sequence of 8 bit chars."
  :group 'vm-mime
  :type '(regexp))

(defcustom vm-mime-max-message-size nil
  "*Largest MIME message that VM should send without fragmentation.
The value should be an integer which specifies the size in bytes.
A message larger than this value will be split into multiple parts
for transmission using the MIME message/partial type."
  :group 'vm-mime
  :type '(choice (const nil) integer))

(defcustom vm-mime-attachment-save-directory (expand-file-name "~/")
  "*Non-nil value is a default directory for saving MIME attachments.
When VM prompts you for a target file name when saving a MIME body,
any relative pathnames will be relative to this directory."
  :group 'vm-mime
  :type '(choice (const nil) 
                 directory))

(defcustom vm-mime-attachment-source-directory (expand-file-name "~/")
  "*Non-nil value is a default source directory for MIME attachments.
When `vm-attach-file' prompts you for the name of a file to
attach, any relative pathnames will be relative to this directory."
  :group 'vm-mime
  :type '(choice (const nil) 
                 directory))

(defcustom vm-mime-all-attachments-directory nil
    "*Directory to where the attachments should go or come from."
 :group 'vm-mime
 :type '(choice (directory :tag "Directory:")
                (const :tag "Use `vm-mime-attachment-save-directory'" nil)))

(defvar vm-mime-save-all-attachments-history nil
  "Directory history to where the attachments should go.")

(defvar vm-mime-yank-attachments nil
  "*This variable, originally from vm-pine, is deprecated.  It is
replaced by `vm-include-mime-attachments'.")

(defvaralias 'vm-mime-yank-attachments 'vm-include-mime-attachments)
(make-obsolete-variable 'vm-mime-yank-attachments
			'vm-include-mime-attachments
			"8.2.0")			

(defcustom vm-include-mime-attachments nil
  "*Non-nil value enables attachments to be included in quoted text in
a reply message.  Otherwise only the button label will be included."
  :group 'vm-reply
  :type 'boolean)

(defcustom vm-infer-mime-types nil
  "*Non-nil value means that VM should try to infer a MIME object's
type from its filename when deciding whether the object should be
displayed and how it should be displayed.  This will be done only
for objects of type application/octet-stream.  The object's filename
is checked against the regexps in `vm-mime-attachment-auto-type-alist'
and the type corresponding to the first match found is used."
  :group 'vm-mime
  :type 'boolean)

(defvaralias 'vm-mime-attachment-infer-type-for-text-attachments
  'vm-infer-mime-types-for-text)
(defcustom vm-infer-mime-types-for-text nil
  "Non-nil value means VM should try to infer a MIME object's
  type from its filename also for text attachments, not only for
  application/octet-stream."
   :group 'vm-mime
   :type 'boolean)
(make-obsolete-variable 'vm-mime-attachment-infer-type-for-text-attachments
			'vm-infer-mime-types-for-text "8.2.0")

(defcustom vm-mime-avoid-folding-content-type t
  "*Non-nil means don't send folded Content- headers in MIME messages.
`Folded' headers are headers broken into multiple lines as specified
in RFC822 for readability and to avoid excessive line lengths.  At
least one major UNIX vendor ships a version of sendmail that believes
a folded Content-Type header is a syntax error, and returns any such
message to sender.  A typical error message from such a sendmail
version is,

553 header syntax error, line \" charset=us-ascii\"

If you see one of these, setting `vm-mime-avoid-folding-content-type'
non-nil may let your mail get through."
  :group 'vm-mime
  :type 'boolean)

(define-obsolete-variable-alias 'vm-mime-uuencode-decoder-program
  'uudecode-decoder-program "2024")

(define-obsolete-variable-alias 'vm-mime-uuencode-decoder-switches
  'uudecode-decoder-switches "2024")

(defcustom vm-auto-next-message t
  "*Non-nil value causes VM to use `vm-next-message' to advance to the next
message in the folder if the user attempts to scroll past the end of the
current messages.  A nil value disables this behavior."
  :group 'vm-summary
  :type 'boolean)

(defcustom vm-honor-page-delimiters nil
  "*Non-nil value causes VM to honor page delimiters (as specified by the
Emacs page-delimiter variable) when scrolling through a message.
This means that when VM encounters a page delimiter when displaying a
message all the screen lines below that delimiter will be blank until
you scroll past that delimiter.  When you scroll past the delimiter
the text lines between the delimiter and the next delimiter will be
displayed.  Scrolling backward past a page delimiter reverses this
process.

A nil value means ignore page-delimiters."
  :group 'vm-presentation 
  :type 'boolean)

(defcustom vm-page-continuation-glyph "...press SPACE to see more..."
  "*Glyph VM uses to indicate there is more text on the next page.
When VM honors page delimiters (see `vm-honor-page-delimiters')
and when VM is previewing a message (see `vm-preview-lines') VM
indicates that there is more text by placing the glyph specified
by this variable at the end of the displayed text.

Under XEmacs, the value of `vm-page-continuation-glyph' can be a
string or a glyph object.

Under FSF Emacs, `vm-page-continuation-glyph' must be a string."
  :group 'vm-presentation
  :type 'boolean)

(defconst vm-default-window-configuration
  ;; startup = folder on bottom, summary on top
  ;; quitting = full screen folder
  ;; reading-message = folder on bottom, summary on top
  ;; composing-message = full screen composition
  ;; editing-message = full screen edit
  ;; vm-summarize = folder on bottom, summary on top
  ;; vm-pipe-message-to-command = summary on top, shell output on bottom
  '(
    (startup
     ((((top . 70) (left . 70)))
      (((- (0 0 80 10) (0 10 80 40))
	((nil summary) (nil message))
	((nil nil nil t) (nil nil nil nil))))))
    (quitting
     ((((top . 70) (left . 70)))
      (((0 0 80 40)
	((nil message))
	((nil nil nil t))))))
    (reading-message
     ((((top . 70) (left . 70)))
      (((- (0 0 80 10) (0 10 80 40))
	((nil summary) (nil message))
	((nil nil nil t) (nil nil nil nil))))))
    (composing-message
     ((((top . 70) (left . 70)))
      (((0 0 80 40)
	((nil composition))
	((nil nil nil t))))))
    (editing-message
     ((((top . 70) (left . 70)))
      (((0 0 80 40)
	((nil edit))
	((nil nil nil t))))))
    (vm-summarize
     ((((top . 70) (left . 70)))
      (((- (0 0 80 10) (0 10 80 40))
	((nil summary) (nil message))
	((nil nil nil t) (nil nil nil nil))))))
    (vm-folders-summarize
     ((((top . 70) (left . 70)))
      (((- (0 0 80 10) (0 10 80 40))
	((nil folders-summary) (nil message))
	((nil nil nil t) (nil nil nil nil))))))
   )
  "Default window configuration for VM if the user does not specify one.
If you want to completely turn off VM's window configuration
feature, set this variable and `vm-window-configuration-file' to
nil in your .vm file.

If you want to have a different window configuration setup than
this, you should not set this variable directly.  Rather you
should set the variable `vm-window-configuration-file' to point at
a file, and use the command `vm-save-window-configuration'
(normally bound to `WS') to modify part of this configuration to
your liking.

WARNING: Don't point `vm-window-configuration-file' at your .vm or
.emacs file.  Your window configuration file should start out as
an empty or nonexistent file.  VM will repeatedly overwrite this
file as you update your window configuration settings, so
anything else you put into this file will go away.")

(defcustom vm-window-configuration-file "~/.vm.windows"
  "*Non-nil value should be a string that tells VM where to load
and save your window configuration settings.  Your window
configuration settings are loaded automatically the first time
you run VM in an Emacs session, and tells VM how to set up
windows depending on what you are doing inside VM.

The commands `vm-save-window-configuration' (normally bound to `WS') and
`vm-delete-window-configuration' (bound to `WD') let you update this
information; see their documentation for more information.

You cannot change your window configuration setup without giving
`vm-window-configuration-file' a non-nil value.  A nil value causes
VM to use the default window setup specified by the value of
`vm-default-window-configuration'.

WARNING: Don't point `vm-window-configuration-file' at your .vm or
.emacs file.  Your window configuration file should start out as
an empty or nonexistent file.  VM will repeatedly overwrite this
file as you update your window configuration settings, so
anything else you put into this file will go away."
  :group 'vm-frames
  :type 'file)

(defcustom vm-preserve-read-only-folders-on-disk t
  "*Non-nil value means that VM will not attempt to save read-only
folders to disk and discards changes during `vm-quit'."
  :group 'vm-misc
  :type 'boolean)

(defcustom vm-expunge-before-quit nil
  "*Non-nil value causes VM to expunge deleted messages before
quitting.  You can use `vm-quit-no-expunge' and `vm-quit-no-change'
to override this behavior."
  :group 'vm-misc
  :type 'boolean)

(defcustom vm-expunge-before-save nil
  "*Non-nil value causes VM to expunge deleted messages before
saving a folder."
  :group 'vm-dispose
  :type 'boolean)

(defcustom vm-confirm-quit 'if-something-will-be-lost
  "*Value of t causes VM to always ask for confirmation before quitting
a VM visit of a folder.  A nil value means VM will ask only when messages
will be lost unwittingly by quitting, i.e. not removed by intentional
delete and expunge.  A value that is not nil and not t causes VM to ask
only when there are unsaved changes to message attributes, or when messages
will be unwittingly lost."
  :group 'vm-misc
  :type '(choice (const :tag "Always ask" t) 
                 (const :tag "Only ask if messages will be lost" nil) 
                 (const :tag "Only ask if there are unsaved changes" 
                        if-something-will-be-lost)))

(defcustom vm-confirm-new-folders nil
  "*Non-nil value causes interactive calls to `vm-save-message'
to ask for confirmation before creating a new folder."
  :group 'vm-folders
  :type 'boolean)

(defcustom vm-delete-empty-folders t
  "*Non-nil value means remove empty (zero length) folders after saving.
A value of t means always remove the folders.
A value of nil means never remove empty folders.
A value that's not t or nil means ask before removing empty folders."
  :group 'vm-folders
  :type '(choice (const :tag "Never" nil) 
		 (const :tag "Always" t)
		 (const :tag "Ask" ask)))

(defcustom vm-folder-file-precious-flag t
  "*Value that `file-precious-flag' should have in visited folders.
A non-nil value causes folders to be saved by writing to a
temporary file and then replacing the folder with that file.  A
nil value causes folders to be saved by writing directly to the
folder without the use of a temporary file."
  :group 'vm-folders
  :type 'boolean)

(defcustom vm-flush-interval 90
  "*Non-nil value specifies how often VM flushes its cached
internal data using a timer task.  A numeric value gives the
number of seconds between flushes.  A value of t means flush
every time there is a change.  Nil means don't do flushing until
a message or folder is saved.

Normally when a message attribute is changed. VM keeps the record
of the change in its internal memory and doesn't insert the
changed data into the folder buffer until a particular message or
the whole folder is saved to disk.  This makes normal Emacs
auto-saving useless for VM folder buffers because the information
you'd want to auto-save, i.e. the attribute changes are not in
the buffer when it is auto-saved.

Setting `vm-flush-interval' to a numeric value will cause the VM's
internal memory caches to be periodically flushed to the folder
buffer.  This is done non-obtrusively, so that if you type
something while flushing is occurring, the flush will abort
cleanly and Emacs will respond to your keystrokes as usual."
  :group 'vm-folders
  :type '(choice (const :tag  "Flush after folder/message saved" nil)
		 (const :tag "Flush after every change" t)
		 (integer :tag "Seconds")))

(defcustom vm-visit-when-saving 'not-always
  "*Value determines whether VM will visit folders when saving messages.
`Visiting' means that VM will read the folder into Emacs and append the
message to the buffer instead of appending to the folder file directly.
This behavior is ideal when folders are encrypted or compressed since
appending plaintext directly to such folders is a ghastly mistake.

A value of t means VM will always visit folders when saving.

A nil value means VM will never visit folders before saving to them, and
VM will generate an error if you attempt to save messages to a folder
that is being visited.  The latter restriction is necessary to insure
that the buffer and disk copies of the folder being visited remain
consistent.

A value other than nil or t means that VM will save to the folder
buffer if it is visited or to the file otherwise."
  :group 'vm-dispose
  :type '(choice (const :tag "Always" t)
		 (const :tag "Never" nil)
		 (const :tag "Not always" not-always)))

(defcustom vm-auto-folder-alist nil
  "*Non-nil value should be an alist that VM will use to choose a default
folder name when messages are saved.  The alist should be of the form
\((HEADER-NAME-REGEXP
   (REGEXP . FOLDER) ... )
  ...)
where HEADER-NAME-REGEXP and REGEXP are strings, and FOLDER
is a string or an s-expression that evaluates to a string.

If any part of the contents of the first message header whose
name is matched by HEADER-NAME-REGEXP is matched by the regular
expression REGEXP, VM will evaluate the corresponding FOLDER
and use the result as the default folder for saving the message.
If the resulting folder name is a relative pathname, then it will
be rooted in the directory named by `vm-folder-directory', or the
default-directory of the currently visited folder if
`vm-folder-directory' is nil.  If the resulting folder name is an IMAP
maildrop specification, then the corresponding IMAP folder is used for
saving. 

When FOLDER is evaluated, the current buffer will contain
only the contents of the header matched by HEADER-NAME-REGEXP.
It is safe to modify this buffer.  You can use the match data
from any \\( ... \\) grouping constructs in REGEXP along with the
function buffer-substring to build a folder name based on the
header information.  If the result of evaluating FOLDER is a
list, then the list will be treated as another auto-folder-alist
and will be descended recursively.

Whether REGEXP is matched case sensitively depends on the value
of the variable `vm-auto-folder-case-fold-search'.  Header names
are always matched case insensitively."
  :group 'vm-dispose
  :type '(choice (const :tag "None" nil)
		 (repeat (cons 
			  (regexp :tag "Header Regexp")
			  (repeat
			   (cons (regexp :tag "Content Regexp")
				 (choice (string :tag "Folder Name")
					 (sexp :tag "Folder Expresion"))))))))

(defcustom vm-save-using-auto-folders t
  "*Non-nil value means that VM will suggest folders for saving
messages automatically using the setting of `vm-auto-folder-alist'."
  :group 'vm-dispose
  :type 'boolean)

(defcustom vm-auto-folder-case-fold-search t
  "*Non-nil value means VM will ignore case when matching header
contents while doing automatic folder selection via the variable
`vm-auto-folder-alist'."
  :group 'vm-dispose
  :type 'boolean)

(defcustom vm-virtual-folder-alist nil
  "*Non-nil value should be a list of virtual folder definitions.

A virtual folder is a mapping of messages from one or more real folders
into what appears to be a single folder.  A virtual folder definition
specifies which real folders should be searched for prospective messages
and what the inclusion criteria are.

Each virtual folder definition should have the following form:

  (VIRTUAL-FOLDER-NAME
    ( (FOLDER ...)
      (SELECTOR [ARG ...]) ... )
    ... )

VIRTUAL-FOLDER-NAME is the name of the virtual folder being defined.
This is the name by which you and VM will refer to this folder.

FOLDER should be the specification of a real folder: a file path for
a local folder or a maildrop specification for a POP/IMAP folder.
There may be more than one FOLDER listed, the SELECTORs within that
sublist will apply to them all.  If FOLDER is a directory, VM will
assume this to mean that all the folders in that directory should be
searched.

The SELECTOR is a Lisp symbol that tells VM how to decide whether
a message from one of the specified FOLDERs should be included in
the virtual folder.  Some SELECTORs require an argument ARG;
unless otherwise noted ARG may be omitted.

See the VM manual section \"Virtual Selectors\" for the complete list
of recognized SELECTORs.
"
  :group 'vm-virtual
  :type '(choice
	  (const :tag "none" nil)
	  (repeat 
	   (group 
	    (string :tag "Virtual Folder Name")
	    (group (repeat :tag "Folder List" string)
		   (sexp :tag "Selectors"))))))

(defcustom vm-virtual-default-directory nil
  "*Default-directory to be used for virtual folders other than search
folders.  Since virtual folders do not visit files, the
`default-directory' for the buffers of the virtual folder will be
whatever is the `default-directory' when the virtual folder is
visited.  To override that, you can set this variable.  The directory
where your VM folders are normally stored would be a good choice.

This only affects the virtual folders created using
`vm-visit-virtual-folder'.  Search folders always inherit the
`default-directory' of their parent folders."
  :group 'vm-virtual
  :type '(choice
	  (const :tag "none" nil)
	  (string :tag "Directory path name")
	  ))

(defcustom vm-virtual-mirror t
  "*Non-nil value causes the attributes of messages in virtual folders
to mirror the changes in the attributes of the underlying real messages.
Similarly, changes in the attributes of virtual messages will change the
attributes of the underlying real messages.  A nil value causes virtual
messages to have their own distinct set of attributes, apart from the
underlying real message.

This variable automatically becomes buffer-local when set in any
fashion.  You should set this variable only in your .vm or .emacs
file.  Use setq-default.  Once VM has been started, you should not
set this variable directly, rather you should use the command
`vm-toggle-virtual-mirror', normally bound to `V M'."
  :group 'vm-virtual
  :type 'boolean)

(make-variable-buffer-local 'vm-virtual-mirror)

(defvar vm-folder-read-only nil
  "*Non-nil value causes a folder to be considered unmodifiable by VM.
Commands that modify message attributes or messages themselves are disallowed.
Commands that add or remove messages from the folder are disallowed.
Commands that scan or allow the reading of messages are allowed but the
`new' and `unread' message flags are not changed by them.

This variable automatically becomes buffer-local when set in any
fashion.  You should set this variable only in your .vm or .emacs
file.  Use setq-default.  Once VM has been started, you should not
set this variable directly, rather you should use the command
`vm-toggle-read-only', normally bound to C-x C-q.")

(make-variable-buffer-local 'vm-folder-read-only)

(defcustom vm-included-text-prefix " > "
  "*String used to prefix included text in replies."
  :group 'vm-reply
  :type 'string)

(defcustom vm-keep-sent-messages 1
  "*Non-nil value N causes VM to keep the last N messages sent from within VM.
`Keep' means that VM will not kill the composition buffer after
you send a message with C-c C-c (`vm-mail-send-and-exit').  A
value of 0 or nil causes VM never to keep such buffers.  A value
of t causes VM never to kill such buffers.

Note that these buffers will vanish once you exit Emacs.  To keep a permanent
record of your outgoing mail, use the `mail-archive-file-name' variable."
  :group 'vm-compose
  :type '(choice (const :tag "Keep" Keep)
                 (const :tag "Don't Keep" nil)
                 (integer :tag "Keep N")))

(defcustom vm-confirm-mail-send nil
  "*Non-nil means ask before sending a mail message.
This affects `vm-mail-send' and `vm-mail-send-and-exit' in Mail mode."
  :group 'vm-compose
  :type 'boolean)

(defcustom vm-mail-auto-save-directory nil
  "*Directory where messages being composed are auto-saved.  If it is
nil, `vm-folder-directory' is used for this purpose."
  :group 'vm-compose
  :type '(choice (const nil) directory))

(defcustom vm-mail-header-from nil
  "*Non-nil value should be a string that will be appear as the body
of the From header in outbound mail messages.  A nil value means don't
insert a From header.  This variable also controls the inclusion and
format of the Resent-From header, when resending a message with
`vm-resend-message'."
  :group 'vm-compose
  :type '(choice (const nil) string))

(defcustom vm-mail-use-sender-address nil
  "*If this set to `t', \\[vm-mail] will use the sender of the current
message as the recipient for the new message composition."
  :group 'vm-compose
  :type 'boolean)

(defcustom vm-mail-mode-hidden-headers '("References" "In-Reply-To" "X-Mailer")
  "*A list of headers to hide in `vm-mail-mode'."
  :group 'vm-compose
  :type '(choice (const :tag "Disabled" nil)
                 (set :tag "Header list"
                      (string "References")
                      (string "In-Reply-To")
                      (string "X-Mailer"))))

(defcustom vm-mail-header-insert-date t
  "*Non-nil value causes VM to insert a Date header into a message
when it is sent.  If the message has a Date header, it will be
removed before the new one is inserted.  If the message being
sent is a resent message (i.e. has a Resent- recipient header)
then the Resent-Date header will be removed/inserted instead.

This is useful if you set `mail-archive-file-name',
because your archived message will contain a Date header.

A nil value means don't insert a Date header."
  :group 'vm-compose
  :type 'boolean)

(defcustom vm-mail-header-insert-message-id t
  "*Non-nil value causes VM to insert a Message-ID header into a message
when it is sent.  If the message has a Message-ID header, it will
be removed before the new one is inserted.  If the message being
sent is a resent message (i.e. has a Resent- recipient header) a
Resent-Message-ID header will be removed/inserted instead.

This is useful if you set `mail-archive-file-name', because your
archived messages will contain a Message-ID header, which may be
useful later for threading messages.

A nil value means don't insert a Message-ID header."
  :group 'vm-compose
  :type 'boolean)

(defcustom vm-mail-mode-hidden-headers '("References" "X-Mailer")
  "*A list of headers to hide in `vm-mail-mode'."
  :group 'vm-compose
  :type '(repeat :tag "Header" string))

(defcustom vm-mail-header-order '("From:" "Organization:" "Subject:"
				  "Date:" "Priority:" "X-Priority:" 
				  "Importance:" "Message-ID:"
				  "MIME-Version:" "Content-Type:"
				  "To:" "Newsgroups:" "CC:" "BCC:" "Reply-To:")
  "*Order of headers when calling `vm-reorder-message-headers' interactively
in a composition buffer."
  :group 'vm-compose
  :type '(repeat :tag "Header" string))

(defcustom vm-mail-reorder-message-headers nil
  "*Reorder message headers before sending."
  :group 'vm-compose
  :type 'boolean)

(defcustom vm-do-fcc-before-mime-encode nil
  "*Non-nil means to FCC before encoding.  This allows saving of
messages unencoded, specifically not to waste storage for
attachments which are stored on disk anyway."
  :group 'vm-compose
  :type 'boolean)

(defcustom vm-reply-subject-prefix nil
  "*Non-nil value should be a string that VM should add to the beginning
of the Subject header in replies, if the string is not already present.
Nil means don't prefix the Subject header."
  :group 'vm-reply
  :type '(choice (const nil) string))

(defcustom vm-reply-ignored-addresses nil
  "*Non-nil value should be a list of regular expressions that match
addresses that VM should automatically remove from the recipient
headers of replies.  These addresses are removed from the headers
before you are placed in the message composition buffer.  So if
you see an address in the header you don't want you should remove
it yourself.

Case is ignored when matching the addresses."
  :group 'vm-reply
  :type '(choice (const nil)
                 (repeat regexp)))

(defcustom vm-reply-ignored-reply-tos nil
  "*Non-nil value should be a list of regular expressions that match
addresses that, if VM finds in a message's Reply-To header, VM
should ignore the Reply-To header and not use it for replies.  VM
will use the From header instead.

Case is ignored when matching the addresses.

This variable exists solely to provide an escape chute from
mailing lists that add a Reply-To: mailing list header, thereby
leaving no way to reply to just the author of a message."
  :group 'vm-reply
  :type '(choice (const nil)
		 (repeat regexp)))

(defcustom vm-in-reply-to-format "%i"
  "*String which specifies the format of the contents of the In-Reply-To
header that is generated for replies.  See the documentation for the
variable `vm-summary-format' for information on what this string may
contain.  The format should *not* end with a newline.
Nil means don't put an In-Reply-To header in replies.

If the format includes elements with non-ASCII characters, then
\"In-Reply-To\" should be added to `vm-mime-encode-headers-regexp'."
  :group 'vm-reply
  :type '(choice (const nil) string))

(defcustom vm-included-text-attribution-format "%F writes:\n"
  "*String which specifies the format of the attribution that precedes the
included text from a message in a reply.  See the documentation for the
variable `vm-summary-format' for information on what this string may contain.
Nil means don't attribute included text in replies."
  :group 'vm-reply
  :type '(choice (const nil) string))

(defcustom vm-include-text-basic nil
  "*If true a reply will include the basic text of a message.
This is an old method for citing messages and should not be used
normally." 
  :group 'vm-reply
  :type 'boolean)

(defvar vm-include-text-from-presentation nil
  "*If true `vm-reply-include-text' will include the presentation
of a message as shown in the Presentation buffer, instead of the
normal text generated by the default VM method.

This is an experimental feature that should not be used
normally, but it might give better results when using filling or
MIME encoded messages, e.g. HTML message.

You can only include the presentation of the current message in
your reply using this method.  Marked messages, threads and
prefix argument counts have no effect on the included text.")

(defcustom vm-included-mime-types-list nil
  "*If non-nil, the list of mime type/subtype pairs that should be
included in quoted text in a reply message in addition to the default
types.

This variable currently has an effect only if `vm-include-text-basic'
is true.  It has no effect for the default text quotation mechanism
based on MIME decoding.

The defaut value is nil." 
  :group 'vm-reply
  :type '(choice (const nil)
                 (repeat string)))

(defcustom vm-included-text-headers nil
  "*List of headers that should be retained in a message included in
a reply.  These should be listed in the order you wish them to
appear in the included text.  Regular expressions are allowed.
There's no need to anchor patterns with \"^\", as searches always
start at the beginning of a line.  Put a colon at the end of
patterns to get exact matches.  (E.g. \"Date\" matches \"Date\"
and \"Date-Sent\".)  Header names are always matched case
insensitively.

If the value of `vm-included-text-discard-header-regexp' is nil,
the headers matched by `vm-included-text-headers' are the only
headers that will be retained.

If `vm-included-text-discard-header-regexp' is non-nil, then the
headers matched by that variable will be omitted; all the others
will be included.  `vm-included-text-headers' determines the
header order in that case, with headers not matching any in the
`vm-included-text-headers' list appearing last in the header
section of the included text."
  :group 'vm-reply
  :type '(choice (const nil)
                 (repeat regexp)))

(defcustom vm-included-text-discard-header-regexp nil
  "*Non-nil value should be a regular expression that tells what
headers should not be retained in a message included in a reply.
This variable along with `vm-included-text-headers' determines
which headers are retained.

If the value of `vm-included-text-discard-header-regexp' is nil,
the headers matched by `vm-included-text-headers' are the only headers
that will be retained.

If `vm-included-text-discard-header-regexp' is non-nil, then only
headers matched by this variable will not be retained; all
others will be included.  `vm-included-text-headers' determines the
header order in that case, with headers not matching any in
the `vm-included-text-headers' list appearing last in the header
section of the included text."
  :group 'vm-reply
  :type '(choice (const nil)
                 regexp))

(defcustom vm-forwarding-subject-format "forwarded message from %F"
  "*String which specifies the format of the contents of the Subject
header that is generated for a forwarded message.  See the documentation
for the variable `vm-summary-format' for information on what this string
may contain.  The format should *not* end with nor contain a newline.
Nil means leave the Subject header empty when forwarding."
  :group 'vm-forward
  :type '(choice (const nil)
		 (string)))

(defcustom vm-forwarded-message-preamble-format
  "\n---------- Original Message ----------\n"
  "*String which specifies the preamble for a forwarded message."
  :group 'vm-forward
  :type 'string)

(defcustom vm-forwarded-headers nil
  "*List of headers that should be forwarded by `vm-forward-message'.
The headers should be listed in the order you wish them to appear
in the forwarded message.  Regular expressions are allowed.
There's no need to anchor patterns with \"^\", as searches always
start at the beginning of a line.  Put a colon at the end of
patterns to get exact matches.  (E.g. \"Date\" matches \"Date\"
and \"Date-Sent\".)  Header names are always matched
case-insensitively.

If the value of `vm-unforwarded-header-regexp' is nil, the headers
matched by `vm-forwarded-headers' are the only headers that will be
forwarded.

If `vm-unforwarded-header-regexp' is non-nil, then the headers
matched by that variable will be omitted and all the others will
be forwarded.  `vm-forwarded-headers' determines the forwarding
order in that case, with headers not matching any in the
`vm-forwarded-headers' list appearing last in the header section
of the forwarded message."
  :group 'vm-forward
  :type '(repeat regexp))

(defcustom vm-unforwarded-header-regexp "none-to-be-dropped"
  "*Non-nil value should be a regular expression that tells what
headers should not be forwarded by `vm-forward-message' and
`vm-send-digest'.  This variable along with `vm-forwarded-headers'
determines which headers are forwarded. 

If the value of `vm-unforwarded-header-regexp' is nil, the headers
matched by `vm-forwarded-headers' are the only headers that will be
forwarded.

If `vm-unforwarded-header-regexp' is non-nil, then only the
headers matched by this variable will be omitted; all the others will
be forwarded.  `vm-forwarded-headers' determines the forwarding 
order in that case, with headers not matching any in the 
`vm-forwarded-headers' list appearing last in the header section 
of the forwarded message."
  :group 'vm-forward
  :type '(choice
	  (const :tag "Only forward headers listed in vm-forward-headers" nil)
	  (const :tag "Forward all headers" "none-to-be-dropped")
          regexp))

(defcustom vm-forwarded-headers-plain
  '("From:" "To:" "Newsgroups:" "Cc:" "Subject:" "Date:" "In-Reply-To:")
  "*List of headers that should be forwarded by `vm-forward-message-plain'.
The headers should be listed in the order you wish them to appear in the
forwarded message.  Regular expressions are allowed.  There's no need to
anchor patterns with \"^\", as searches always start at the beginning of a
line.  Put a colon at the end of patterns to get exact matches. (E.g.,
\"Date\" matches \"Date\" and \"Date-Sent\".)  Header names are always 
matched case-insensitively.

If the value of `vm-unforwarded-header-regexp-plain' is nil, the headers
matched by `vm-forwarded-headers' are the only headers that will be
forwarded.

If `vm-unforwarded-header-regexp-plain' is non-nil, then the headers
matched by that variable will be omitted and all the others will be
forwarded.  In this case, `vm-forwarded-headers-plain' determines the
forwarding order in that case, with headers not matching any in the
`vm-forwarded-headers-plain' list appearing last in the header section
of the forwarded message."
  :group 'vm-forward
  :type '(repeat regexp))

(defcustom vm-unforwarded-header-regexp-plain nil
  "*Non-nil value should be a regular expression that tells what
headers should not be forwarded by `vm-forward-message-plain'.  This
variable along with `vm-forwarded-headers-plain' determines which headers
are forwarded.

If the value of `vm-unforwarded-header-regexp-plain' is nil, the
headers matched by `vm-forwarded-headers-plain' are the only
headers that will be forwarded.

If `vm-unforwarded-header-regexp-plain' is non-nil, then only the
headers matched by this variable will be omitted; all the others
will be forwarded.  `vm-forwarded-headers-plain' determines the
forwarding order in that case, with headers not matching any in
the `vm-forwarded-headers-plain' list appearing last in the
header section of the forwarded message."
  :group 'vm-forward
  :type '(choice
	  (const :tag "Only forward headers listed in vm-forward-headers-plain" nil)
	  (const :tag "Forward all headers" "none-to-be-dropped")
          regexp))

(defconst vm-forwarded-mime-headers '("MIME" "Content")
  "List of MIME headers that are always included in messages forwarded with
encapsulation.") 

(defcustom vm-forwarding-digest-type "mime"
  "*Non-nil value should be a string that specifies the type of
message encapsulation format to use when forwarding messages.
Legal values of this variable are:

\"mime\"
\"rfc934\"
\"rfc1153\"
nil

A nil value means to use plain text forwarding."
  :group 'vm-forward
  :type '(choice
          (const "mime")
          (const "rfc934")
          (const "rfc1153")
	  (const :tag "Forward in plain text" nil)))

(defcustom vm-mime-forward-local-external-bodies nil
  "*Non-nil value means that the `message/external-body' MIME
parts are retained in messages during forwarding, as long as
their external bodies are on the local file system.  A nil value
means that the externally referenced objects are fetched into the
message before forwarding.  The fetching is only done for objects
accessed with the `local-file' access method.  Objects referenced
with other methods are not fetched.

In particular, the MIME attachments that are saved to
disk (using, for example, `vm-mime-save-all-attchments') are
represented in messages with `message/external-body' references.
Setting the variable to a non-nil value causes these references
to be sent in forwarded messages.  Setting it to nil causes the
references to be expanded out with the actual attachments."
  :group 'vm-mime
  :type 'boolean)
(make-obsolete-variable 'vm-mime-forward-local-external-bodies
			'vm-mime-forward-saved-attachments "8.2.0")

(defcustom vm-mime-forward-saved-attachments 
  (not vm-mime-forward-local-external-bodies)
  "*Non-nil value means that any attachments saved to local files
using, for example `vm-mime-save-all-attachments', will be
retrieved and re-attached to forwarded messages.  

Nil value means that the messages will be forwarded with external
references to the saved attachments.  The recipients will need to
fetch the attachments themselves if they have access to your file
system.

This replaces the variable `vm-mime-forward-local-external-bodies' in
previous versions of VM.  If you had set that variable to `nil' then
you should set this variable to `t'."
  :group 'vm-mime
  :type 'boolean)

(defcustom vm-burst-digest-messages-inherit-labels t
  "*Non-nil values means messages from a digest inherit the digest's labels.
Labels are added to messages with `vm-add-message-labels', normally
bound to `l a'."
  :group 'vm-digest
  :type 'boolean)

(defcustom vm-digest-preamble-format "\"%s\" (%F)"
  "*String which specifies the format of the preamble lines generated by
`vm-send-digest' when it is invoked with a prefix argument.  One
line will be generated for each message put into the digest.  See the
documentation for the variable `vm-summary-format' for information
on what this string may contain.  The format should *not* end
with nor contain a newline."
  :group 'vm-digest
  :type 'string)

(defcustom vm-digest-center-preamble t
  "*Non-nil value means VM will center the preamble lines that precede
the start of a digest.  How the lines will be centered depends on the
ambient value of fill-column.   A nil value suppresses centering."
  :group 'vm-digest
  :type 'boolean)

(defcustom vm-digest-identifier-header-format "X-Digest: %s\n"
  "*Header to insert into messages burst from a digest.
Value should be a format string of the same type as `vm-summary-format'
that describes a header to be inserted into each message burst from a
digest.  The format string must end with a newline."
  :group 'vm-digest
  :type 'string)

(defcustom vm-digest-burst-type "guess"
  "*Value specifies the default digest type offered by `vm-burst-digest'
when it asks you what type of digest you want to unpack.  Allowed
values of this variable are:

   \"rfc934\"
   \"rfc1153\"
   \"mime\"
   \"guess\"

rfc1153 digests have a preamble, followed by a line of exactly 70
dashes, with digested messages separated by lines of exactly 30 dashes.

rfc934 digests separate messages on any line that begins with a few
dashes, but doesn't require lines with only dashes or lines with a
specific number of dashes.  In the text of the message, any line
beginning with dashes is textually modified to be preceded by a dash
and a space to prevent confusion with message separators.

MIME digests use whatever boundary that is specified by the
boundary parameter in the Content-Type header of the digest.

If the value is \"guess\", and you take the default
response when `vm-burst-digest' queries you, VM will try to guess
the digest type."
  :group 'vm-digest
  :type '(choice (const "rfc934") 
                 (const "rfc1153") 
                 (const "mime")
                 (const "guess")))

(defcustom vm-digest-send-type "mime"
  "*String that specifies the type of digest `vm-send-digest' will use.
Legal values of this variable are:

\"rfc934\"
\"rfc1153\"
\"mime\"
nil

A nil value means to use plain text digests."
  :group 'vm-digest
  :type '(choice (const "mime")
		 (const "rfc934") 
                 (const "rfc1153") 
		 (const :tag "Plain text digests" nil)))

(defcustom vm-rfc934-digest-headers
  '("Resent-"
    "From:" "Sender:"
    "To:" "Newsgroups:" "Cc:"
    "Subject:"
    "Date:"
    "Message-ID:"
    "Keywords:")
  "*List of headers that should be appear in RFC 934 digests
created by VM.  These should be listed in the order you wish them
to appear in the digest.  Regular expressions are allowed.
There's no need to anchor patterns with \"^\", as searches always
start at the beginning of a line.  Put a colon at the end of
patterns to get exact matches.  (E.g. \"Date\" matches \"Date\"
and \"Date-Sent\".)  Header names are always matched case
insensitively.

If the value of `vm-rfc934-digest-discard-header-regexp' is nil, the headers
matched by `vm-rfc934-digest-headers' are the only headers that will be
kept.

If `vm-rfc934-digest-discard-header-regexp' is non-nil, then only
headers matched by that variable will be discarded; all others
will be kept.  `vm-rfc934-digest-headers' determines the order of
appearance in that case, with headers not matching any in the
`vm-rfc934-digest-headers' list appearing last in the headers
of the digestified messages."
  :group 'vm-digest
  :type '(repeat regexp))

(defcustom vm-rfc934-digest-discard-header-regexp nil
  "*Non-nil value should be a regular expression that tells
what headers should not appear in RFC 934 digests created by VM.  This
variable along with `vm-rfc934-digest-headers' determines which headers
are kept and which are discarded.

If the value of `vm-rfc934-digest-discard-header-regexp' is nil, the headers
matched by `vm-rfc934-digest-headers' are the only headers that will be
kept.

If `vm-rfc934-digest-discard-header-regexp' is non-nil, then only
headers matched by this variable will be discarded; all others
will be kept.  `vm-rfc934-digest-headers' determines the order of
appearance in that case, with headers not matching any in the
`vm-rfc934-digest-headers' list appearing last in the headers
of the digestified messages."
  :group 'vm-digest
  :type '(choice (const nil)
                 regexp))

(defcustom vm-rfc1153-digest-headers
  '("Resent-"
    "Date:"
    "From:" "Sender:"
    "To:" "Newsgroups:" "Cc:"
    "Subject:"
    "Message-ID:"
    "Keywords:")
  "*List of headers that should be appear in RFC 1153 digests
created by VM.  These should be listed in the order you wish them
to appear in the digest.  Regular expressions are allowed.
There is no need to anchor patterns with \"^\", as searches always
start at the beginning of a line.  Put a colon at the end of
patterns to get exact matches.  (E.g. \"Date\" matches \"Date\"
and \"Date-Sent\".)  Header names are always matched case
insensitively.

If the value of `vm-rfc1153-digest-discard-header-regexp' is nil, the headers
matched by `vm-rfc1153-digest-headers' are the only headers that will be
kept.

If `vm-rfc1153-digest-discard-header-regexp' is non-nil, then only
headers matched by that variable will be discarded; all others
will be kept.  `vm-rfc1153-digest-headers' determines the order of
appearance in that case, with headers not matching any in the
`vm-rfc1153-digest-headers' list appearing last in the headers of
the digestified messages."
  :group 'vm-digest
  :type '(repeat regexp))

(defcustom vm-rfc1153-digest-discard-header-regexp "\\(X400-\\)?Received:"
  "*Non-nil value should be a regular expression that tells
what headers should not appear in RFC 1153 digests created by VM.  This
variable along with `vm-rfc1153-digest-headers' determines which headers
are kept and which headers are discarded.

If the value of `vm-rfc1153-digest-discard-header-regexp' is nil, the headers
matched by `vm-rfc1153-digest-headers' are the only headers that will be
kept.

If `vm-rfc1153-digest-discard-header-regexp' is non-nil, then only
headers matched by this variable will be discarded; all others
will be kept.  `vm-rfc1153-digest-headers' determines the order of
appearance in that case, with headers not matching any in the
`vm-rfc1153-digest-headers' list appearing last in the headers of
the digestified messages."
  :group 'vm-digest
  :type '(choice (const nil)
                 regexp))

(defcustom vm-mime-digest-headers
  '("Resent-"
    "From:" "Sender:"
    "To:" "Newsgroups:" "Cc:"
    "Subject:"
    "Date:"
    "Message-ID:"
    "Keywords:"
    "MIME-Version:"
    "Content-")
  "*List of headers that should be appear in MIME digests
created by VM.  These should be listed in the order you wish them
to appear in the messages in the digest.  Regular expressions are
allowed.  There's no need to anchor patterns with \"^\", as
searches always start at the beginning of a line.  Put a colon at
the end of patterns to get exact matches.  (E.g. \"Date\" matches
\"Date\" and \"Date-Sent\".)  Header names are always matched
case insensitively.

If the value of `vm-mime-digest-discard-header-regexp' is nil, the headers
matched by `vm-mime-digest-headers' are the only headers that will be
kept.

If `vm-mime-digest-discard-header-regexp' is non-nil, then only
headers matched by that variable will be discarded; all others
will be kept.  `vm-mime-digest-headers' determines the order of
appearance in that case, with headers not matching any in the
`vm-mime-digest-headers' list appearing last in the headers
of the digestified messages."
  :group 'vm-digest
  :type '(repeat regexp))

(defcustom vm-mime-digest-discard-header-regexp nil
  "*Non-nil value should be a regular expression that tells
which headers should not appear in MIME digests created
by VM.  This variable along with `vm-mime-digest-headers'
determines which headers are kept and which are discarded.

If the value of `vm-mime-digest-discard-header-regexp' is nil, the headers
matched by `vm-mime-digest-headers' are the only headers that will be
kept.

If `vm-mime-digest-discard-header-regexp' is non-nil, then only
headers matched by this variable will be discarded; all others
will be kept.  `vm-mime-digest-headers' determines the order of
appearance in that case, with headers not matching any in the
`vm-mime-digest-headers' list appearing last in the headers
of the digestified messages."
  :group 'vm-digest
  :type '(choice (const nil)
                 regexp))

(defcustom vm-resend-bounced-headers
  '("MIME-Version:" "Content-"
    "From:" "Sender:" "Reply-To:"
    "To:" "Newsgroups:" "Cc:"
    "Subject:"
    "Newsgroups:"
    "In-Reply-To:" "References:"
    "Keywords:"
    "X-")
  "*List of headers that should be appear in messages resent with
`vm-resend-bounced-message'.  These should be listed in the order you wish them
to appear in the message.  Regular expressions are allowed.
There is no need to anchor patterns with \"^\", as searches always
start at the beginning of a line.  Put a colon at the end of
patterns to get exact matches.  (E.g. \"Date\" matches \"Date\"
and \"Date-Sent\".)  Header names are always matched case
insensitively.

If the value of `vm-resend-bounced-discard-header-regexp' is nil, the headers
matched by `vm-resend-bounced-headers' are the only headers that will be
kept.

If `vm-resend-bounced-discard-header-regexp' is non-nil, then only
headers matched by that variable will be discarded; all others
will be kept.  `vm-resend-bounced-headers' determines the order of
appearance in that case, with headers not matching any in the
`vm-resend-bounced-headers' list appearing last in the headers of
the message."
  :group 'vm-forward
  :type '(repeat regexp))

(defcustom vm-resend-bounced-discard-header-regexp nil
  "*Non-nil value should be a regular expression that tells
what headers should not appear in a resent bounced message.  This
variable along with `vm-resend-bounced-headers' determines which headers
are kept and which headers are discarded.

If the value of `vm-resend-bounced-discard-header-regexp' is nil,
the headers matched by `vm-resend-bounced-headers' are the only
headers that will be kept.

If `vm-resend-bounced-discard-header-regexp' is non-nil, then only
headers matched by this variable will be discarded; all others
will be kept.  `vm-resend-bounced-headers' determines the order of
appearance in that case, with headers not matching any in the
`vm-resend-bounced-headers' list appearing last in the headers of
the message."
  :group 'vm-forward
  :type '(choice (const nil)
                 regexp))

(defcustom vm-resend-headers nil
  "List of headers that should appear in messages resent with
`vm-resend-message'.  These should be listed in the order you wish them
to appear in the message.  Regular expressions are allowed.
There is no need to anchor patterns with \"^\", as searches always
start at the beginning of a line.  Put a colon at the end of
patterns to get exact matches.  (E.g. \"Date\" matches \"Date\"
and \"Date-Sent\".)  Header names are always matched case
insensitively.

If the value of `vm-resend-discard-header-regexp' is nil, the headers
matched by `vm-resend-headers' are the only headers that will be
kept.

If `vm-resend-discard-header-regexp' is non-nil, then only
headers matched by that variable will be discarded; all others
will be kept.  `vm-resend-headers' determines the order of
appearance in that case, with headers not matching any in the
`vm-resend-headers' list appearing last in the headers of
the message."
  :group 'vm-forward
  :type '(repeat regexp))

(defcustom vm-resend-discard-header-regexp "\\(\\(X400-\\)?Received:\\|Resent-\\)"
  "*Non-nil value should be a regular expression that tells
what headers should not appear in a resent message.  This
variable along with `vm-resend-headers' determines which
headers are kept and which headers are discarded.

If the value of `vm-resend-discard-header-regexp' is nil,
the headers matched by `vm-resend-headers' are the only
headers that will be kept.

If `vm-resend-discard-header-regexp' is non-nil, then only
headers matched by this variable will be discarded; all others
will be kept.  `vm-resend-headers' determines the order of
appearance in that case, with headers not matching any in the
`vm-resend-headers' list appearing last in the headers of
the message."
  :group 'vm-forward
  :type '(choice (const nil)
		 regexp))

(defcustom vm-summary-format "%n %*%a %-17.17F %-3.3m %2d %4l/%-5c %I\"%s\"\n"
  "*String which specifies the message summary line format.
The string may contain the printf-like `%' conversion specifiers which
substitute information about the message into the final summary line.

Recognized specifiers are:
   a - attribute indicators (always four characters wide)
       The first char is  `D', `N', `U', ` ' or `!' for deleted, new, unread,
       read and flagged messages respectively.
       The second char is `F', `W' or ` ' for filed (saved) or written
       messages.
       The third char is `R', `Z' or ` ' for messages replied to,
       and forwarded messages.
       The fourth char is `E' if the message has been edited, ` ' otherwise.
   A - longer version of attributes indicators (seven characters wide)
       The first char is  `D', `N', `U', ` ' or `!' for deleted, new, unread
       read and flagged messages respectively.
       The second is `r' or ` ', for message replied to.
       The third is `z' or ` ', for messages forwarded.
       The fourth is `b' or ` ', for messages redistributed.
       The fifth is `f' or ` ', for messages filed.
       The sixth is `w' or ` ', for messages written.
       The seventh is `e' or ` ', for messages that have been edited.
   b - shorter version of attribute indicators (1 character wide)
       The first char is  `D', `N', `U', ` ' or `!' for deleted, new, unread
       read and flagged messages respectively.
   c - number of characters in message (ignoring headers)
   d - numeric day of month message sent
   f - author's address
   F - author's full name (same as f if full name not found)
   h - hour:min:sec message sent
   H - hour:min message sent
   i - message ID
   I - thread indentation
   l - number of lines in message (ignoring headers)
   L - labels (as a comma list)
   m - month message sent
   M - numeric month message sent (January = 1)
   n - message number
   p - indicator for postponed messages 
   P - indicator for attachments, see `vm-summary-attachment-indicator'
   r - addresses of the recipients of the message, in a comma-separated list
   R - full names of the recipients of the message, in a comma-separated list
       If a full name cannot be found, the corresponding address is used
       instead.
   s - message subject
   S - human readable size of the message
   t - addresses of the addressees of the message, in a comma-separated list
   T - full names of the addressees of the message, in a comma-separated list
       If a full name cannot be found, the corresponding address is used
       instead.
   U - user defined specifier.  The next character in the format
       string should be a letter.  VM will call the function
       vm-summary-function-<letter> (e.g. vm-summary-function-A for
       \"%UA\") in the folder buffer with the message being summarized
       bracketed by (point-min) and (point-max).  The function
       will be passed a message struct as an argument.
       The function should return a string, which VM will insert into
       the summary as it would for information from any other summary
       specifier.
   w - day of the week message sent
   y - year message sent
   z - timezone of date when the message was sent
   * - `*' if the message is marked, ` ' otherwise
   ( - starts a group, terminated by %).  Useful for specifying
       the field width and precision for the concatentation of
       group of format specifiers.  Example: \"%.35(%I%s%)\"
       specifies a maximum display width of 35 characters for the
       concatenation of the thread indentation and the subject.
   ) - ends a group.

Use %% to get a single %.

A numeric field width may be given between the `%' and the specifier;
this causes right justification of the substituted string.  A negative field
width causes left justification.

The field width may be followed by a `.' and a number specifying
the maximum allowed length of the substituted string.  If the
string is longer than this value the right end of the string is
truncated.  If the value is negative, the string is truncated on
the left instead of the right.

The summary format need not be one line per message but it must end with
a newline, otherwise the message pointer will not be displayed correctly
in the summary window."
  :group 'vm-summary
  :type 'string)

(defcustom vm-restore-saved-summary-formats nil
  "*If t, the summary format is stored in each folder and restored
after visiting it again."
  :group 'vm-summary
  :type 'boolean)

(defcustom vm-summary-postponed-indicator "P"
  "*Indicator shown for postponed messages."
  :group 'vm-summary
  :type 'string)

(defcustom vm-summary-attachment-indicator "$"
  "*Indicator shown for messages containing an attachments."
  :group 'vm-summary
  :type '(choice (string :tag "A string to display" "$")
		 (symbol :tag "Number of attachments prefixed by" ?$)))

(defcustom vm-summary-attachment-mime-types nil
  "*List of MIME types which should be listed as attachment. 
Mime parts with a disposition of attachment or a filename/name disposition
parameter will be automatically considered as attachment."
  :group 'vm-summary
  :type '(repeat (string :tag "MIME type" nil)))

(defcustom vm-summary-attachment-mime-type-exceptions nil
  "*List of MIME types which should not be listed as attachment."
  :group 'vm-summary
  :type '(repeat (string :tag "MIME type" nil)))

(defcustom vm-summary-arrow "->"
  "*String that is displayed to the left of the summary of the
message VM consider to be the current message.  The value takes
effect when the summary buffer is created.  Changing this
variable's value has no effect on existing summary buffers."
  :group 'vm-summary
  :type 'string)

(defface vm-summary-highlight '((t (:inherit bold)))
 "Default face to use to highlight the summary entry for the current message."
 :group 'vm-faces)
;; (copy-face 'bold 'vm-summary-highlight)

(defcustom vm-summary-highlight-face 'vm-summary-highlight
  "*Face to use to highlight the summary entry for the current message.
Nil means don't highlight the current message's summary entry."
  :group 'vm-faces
  :type 'symbol)

(defcustom vm-mouse-track-summary t
  "*Non-nil value means highlight summary lines as the mouse passes
over them."
  :group 'vm-summary
  :type 'boolean)

(defcustom vm-summary-show-threads nil
  "*Non-nil value means VM should display and maintain
message thread trees in the summary buffer.  This means that
messages with a common ancestor will be displayed contiguously in
the summary.  (If you have `vm-move-messages-physically' set
non-nil the folder itself will be reordered to match the thread
ordering.)  If you use the `%I' summary format specifier in your
`vm-summary-format', indentation will be provided as described in the
documentation for `vm-summary-thread-indent-level' (which see).

A nil value means don't display thread information.  The `%I'
specifier does nothing in the summary format.

This variable automatically becomes buffer-local when set in any
fashion.  You should set this variable only in your .vm or .emacs
file.  Use setq-default.  Once VM has been started, you should not
set this variable directly, rather you should use the command
`vm-toggle-threads-display', normally bound to C-t."
  :group 'vm-summary
  :type 'boolean)
(make-variable-buffer-local 'vm-summary-show-threads)

(defcustom vm-summary-thread-indentation-by-references t
  "*If non-nil, threaded messages are indented according to their
nesting level determined by their references headers.  This is
likely to be their original nesting level in the discussion.  If
it is nil, then the indentation level is determined by the number
of thread ancestors within the folder.  When some messages in the
thread are missing or deleted, this is likely to be less than the
original nesting level."
  :group 'vm-summary
  :type 'boolean)

(defcustom vm-summary-thread-indent-level 2
  "*Value should be a number that specifies how much
indentation the '%I' summary format specifier should provide per
thread level.  A message's `thread level' refers to the number of
direct ancestors from the message to the oldest ancestor the
message has that is in the current folder.  For example, the
first message of a thread is generally a message about a new
topic, e.g. a message that is not a reply to some other message.
Therefore it has no ancestor and would cause %I to generate no
indentation.  A reply to this message will be indented by the value
of `vm-summary-thread-indent-level'.  A reply to that reply will be
indented twice the value of `vm-summary-thread-indent-level'."
  :group 'vm-summary
  :type 'integer)

(defcustom vm-summary-maximum-thread-indentation 20
  "*The maximum number of thread nesting levels that should be
displayed by indentation in the folder summary."
  :group 'vm-summary
  :type 'integer)

(defcustom vm-thread-using-subject t
  "*Non-nil value causes VM to use the Subject header to thread messages.
Messages with the same subject will be grouped together.

A nil value means VM will disregard the Subject header when threading
messages."
  :group 'vm-summary
  :type 'boolean)

(defcustom vm-sort-subthreads t
"*Non-nil values causes VM to sort threads as well as their subthreads
by chosen sorting criteria.  Nil value causes it to sort all the
messages in a thread without grouping them into subthreads.  This
might be useful for very long threads."
  :group 'vm-summary
  :type 'boolean)

;; This variable is not used any more because threads can be sorted by
;; "activity".  USR, 2011-02-09.
;; (defcustom vm-sort-threads-by-youngest-date t
;; "*Non-nil values causes VM to sort threads by their youngest date,
;; i.e., a thread A will appear before B if the youngest message in the
;; thread A is dated before the youngest message in the thread B.  If the
;; variable is nil, threads are sorted by their oldest date."
;;   :group 'vm-summary
;;   :type 'boolean)
(make-obsolete 'vm-sort-threads-by-youngest-date
	       'vm-sort-messages "8.2.0")

(defcustom vm-summary-uninteresting-senders nil
  "*Non-nil value should be a regular expression that matches
addresses that you don't consider interesting enough to
appear in the summary.  When such senders would be displayed by
the %F or %f summary format specifiers VM will substitute the
value of `vm-summary-uninteresting-senders-arrow' (default \"To:
\") followed by what would be shown by the %T and %t specifiers
respectively."
  :group 'vm-summary
  :type '(choice (const nil) regexp))

(defvaralias 'vm-summary-uninteresting-senders-arrow
  'vm-summary-recipient-marker)
(defcustom vm-summary-recipient-marker "To: "
  "String to display before the recipients when displayed instead of an
\"uninteresting\" sender.  See `vm-summary-uninteresting-senders'."
  :group 'vm-summary
  :type 'string)

(defcustom vm-summary-principal-marker "For: "
  "*String to display before the principal when displayed instead of an
\"uninteresting\" sender.  See `vm-summary-uninteresting-senders'."
  :group 'vm-summary
  :type 'string)

(defcustom vm-auto-center-summary nil
  "*Value controls whether VM will keep the summary arrow vertically
centered within the summary window. A value of t causes VM to always
keep arrow centered.  A value of nil means VM will never bother centering
the arrow.  A value that is not nil and not t causes VM to center the
arrow only if the summary window is not the only existing window."
  :group 'vm-summary
  :type '(choice (const :tag "No" nil) 
		 (const :tag "Always" t) 
		 (const :tag "Yes, if not only window" yes-if-not-only-window)))

(defcustom vm-verbosity 8
  "*Level of chattiness in progress messages displayed in the
minibuffer.  Indicative levels are:
  1 - extremely quiet
  5 - normal level
  7 - detailed level
 10 - debugging information"
  :group 'vm-misc
  :type 'integer)

(defcustom vm-verbal-time 0
  "*Number of seconds for which to display VM's minibuffer messages.
This number should be normally 0.  Otherwise, it will delay VM's
operation."
  :group 'vm-misc
  :type 'integer)

(defcustom vm-report-subprocess-errors t
  "Boolean flag that controls whether VM should report errors from
running commands in subprocesses."
  :group 'vm-misc
  :type 'boolean)

(defvar vm-current-warning nil
  "Internal variable to keep track of the current warning message
shown to the user.")

;; These flags and variables are for debugging purposes

(defvar vm-debug nil
  "*Flag used by developers to control localized debugging features.")

(defvar vm-virtual-debug nil
  "*Flag used by developers to control localized debugging of virtual folders.")

(defvar vm-traced-message-ids nil
  "*List of message ID's whose activity is debugged.  This is for
developers' use only.")

(defvar vm-traced-message-subjects nil
  "*List of message subjectss whose activity is debugged.  This is for
developers' use only.")

(defvar vm-summary-debug nil
  "*Flag used by developers for tracing summary generation")

(defvar vm-summary-traced-messages nil
  "*List of message numbers whose activity is debugged during
summary generation.  This is for developers' use only.")

(defvar vm-thread-debug nil
  "*Flag that enables the integrity checking of threads.  This is for
developers' use only.") 

(defcustom vm-subject-ignored-prefix "^\\(re: *\\)+"
  "*Non-nil value should be a regular expression that matches
strings at the beginning of the Subject header that you want VM to ignore
when threading, sorting, marking, and killing messages by subject.

Matches are done case-insensitively."
  :group 'vm-summary
  :type 'regexp)

(defcustom vm-subject-ignored-suffix "\\( (fwd)\\| \\)+$"
  "*Non-nil value should be a regular expression that matches
strings at the end of the Subject header that you want VM to ignore
when threading, sorting, marking and killing messages by subject.

Matches are done case-insensitively."
  :group 'vm-summary
  :type 'regexp)

(defcustom vm-subject-tag-prefix nil
  "*Non-nil value should be a regular expression that matches the
\"subject tags\" included in subject lines by mailing lists.
Subject tags are always enclosed in square brackets and have white
space following them.  For example \"\\[[^]:]*][ \n\t]*\" matches all
subject tags enclosed in square brackets along with the trailing white
space following it.

Subject tags matching this regular expression will be ignored when
threading, sorting, marking and killing messages by subject.  They are
also removed from message summary lines if
`vm-summary-strip-subject-tags' is set to `t'.

Matches are done case-insensitively."
  :group 'vm-summary
  :type 'regexp)

(defcustom vm-subject-tag-prefix-exceptions nil
  "*Non-nil value should be a regular expression that matches the
\"subject tags\" included in subject lines by mailing lists.  See
`vm-subject-tag-prefix'.  Subject tags matching this pattern are not
removed during threading, sorting, summarizing, marking and
killing messages by subject.

Matches are done case-insensitively."
  :group 'vm-summary
  :type 'regexp)

(defcustom vm-summary-strip-subject-tags nil
  "*Set this to a non-nil value to ask VM to strip \"subject tags\" added
by mailing lists when displaying subjects in summary lines.

The subject tags that will be stripped are those matching
`vm-subject-tag-prefix' but not matching `vm-subject-tag-prefix-exceptions'."
  :group 'vm-summary
  :type 'boolean)

(defcustom vm-subject-significant-chars nil
  "*Number of characters in the normalized message subject considered
significant in message threading and sorting.  The normalized
subject is the contents of the Subject header after ignored
prefixes and suffixes have been removed and after consecutive
whitespace has been collapsed into single spaces.  The first
`vm-subject-significant-chars' will be considered significant.
Characters beyond this point in the subject string will be
ignored.

A nil value for this variable means all characters in the message
subject are significant."
  :group 'vm-summary
  :type '(choice (const :tag "All Characters" nil) 
		 (integer :tag "Number of characters")))

(defcustom vm-folders-summary-database "~/.vm.folders.db"
  "*Name of Berkeley DB file used to store summary information about folders.
This file is consulted to produce the folders summary."
  :group 'vm-summary
  :type 'file)

(defcustom vm-folders-summary-format
      "  %12f %4t total, %n new, %u unread, %s spooled\n"
  "*String that specifies the folders summary format.
The string may contain the printf-like `%' conversion specifiers which
substitute information about the folder into the final summary line.

Recognized specifiers are:
   d - the number of deleted messages in the folder
   f - the name of the folder without the directory part
   n - the number of new messages in the folder
   t - the total number of messages in the folder
   u - the number of old but still unread messages in the folder
   ( - starts a group, terminated by %).  Useful for specifying
       the field width and precision for the concatentation of
       group of format specifiers.  Example: \"%.35(%d, %t, %f%)\"
       specifies a maximum display width of 35 characters for the
       concatenation of the content description, content type and
       suggested file name.
   ) - ends a group.

Use %% to get a single %.

A numeric field width may be given between the `%' and the specifier;
this causes right justification of the substituted string.  A negative field
width causes left justification.

The field width may be followed by a `.' and a number specifying
the maximum allowed length of the substituted string.  If the
string is longer than this value the right end of the string is
truncated.  If the value is negative, the string is truncated on
the left instead of the right.

The summary format need not be one line per folder, but it should end with
a newline."
  :group 'vm-summary
  :type 'string)

(defcustom vm-folders-summary-directories
      (list (or vm-folder-directory (file-name-directory vm-primary-inbox)))
  "*List of directories containing folders to be listed in the folders summary.
List the directories in the order you wish them to appear in the summary."
  :group 'vm-summary
  :type '(repeat directory))

(defvaralias 'vm-mutable-windows 
  'vm-mutable-window-configuration)
(defcustom vm-mutable-window-configuration pop-up-windows
  "This variable's value controls VM's window usage.

A non-nil value gives VM free run of the Emacs display; it will commandeer
the entire screen for its purposes.

A value of nil restricts VM's window usage to the window from which
it was invoked.  VM will not create, delete, or use any other windows,
nor will it resize its own window."
  :group 'vm-frames
  :type 'boolean)

(defvaralias 'vm-mutable-frames 
  'vm-mutable-frame-configuration)
(defcustom vm-mutable-frame-configuration t
  "Non-nil value means VM is allowed to create and destroy frames
to display and undisplay buffers.  Whether VM actually does
so depends on the value of the variables with names prefixed by
``vm-frame-per-''.

VM can create a frame to display a buffer, and delete frame to
undisplay a buffer.  A nil value means VM should not create or
delete frames.

This variable does not apply to the VM commands whose
names end in -other-frame, which always create a new frame."
  :group 'vm-frames
  :type 'boolean)

(defcustom vm-raise-frame-at-startup t
  "*Specifies whether VM should raise its frame at startup.
A value of nil means never raise the frame.
A value of t means always raise the frame.
Other values are reserved for future use."
  :group 'vm-frames
  :type 'boolean)

(defcustom vm-frame-per-folder t
  "*Non-nil value causes the folder visiting commands to visit in a new frame.
Nil means the commands will use the current frame.  This variable
does not apply to the VM commands whose names end in
-other-frame, which always create a new frame.

This variable has no meaning if you're not running under an Emacs
capable of displaying multiple real or virtual frames.  Note that
Emacs supports multiple virtual frames on dumb terminals, and
VM will use them."
  :group 'vm-frames
  :type 'boolean)

(defcustom vm-frame-per-summary nil
  "*Non-nil value causes VM to display the folder summary in its own frame.
Nil means the `vm-summarize' command will use the current frame.
This variable does not apply to `vm-summarize-other-frame', which
always create a new frame.

This variable has no meaning if you're not running under an Emacs
capable of displaying multiple real or virtual frames.  Note that
Emacs supports multiple virtual frames on dumb terminals, and
VM will use them."
  :group 'vm-frames
  :type 'boolean)

(defcustom vm-frame-per-folders-summary nil
  "Non-nil value causes VM to display the \"all folders\" summary in its own frame.
Nil means the `vm-folders-summarize' command will use the current frame.

This variable has no meaning if you're not running under an Emacs
capable of displaying multiple real or virtual frames.  Note that
Emacs supports multiple virtual frames on dumb terminals, and
VM will use them."
  :group 'vm-frames
  :type 'boolean)

(defcustom vm-frame-per-composition t
  "*Non-nil value causes the mail composition commands to open a new frame.
Nil means the commands will use the current frame.  This variable
does not apply to the VM commands whose names end in
-other-frame, which always create a new frame.

This variable has no meaning if you're not running under an Emacs
capable of displaying multiple real or virtual frames.  Note that
Emacs supports multiple virtual frames on dumb terminals, and
VM will use them."
  :group 'vm-frames
  :type 'boolean)

(defcustom vm-frame-per-edit t
  "*Non-nil value causes `vm-edit-message' to open a new frame.
Nil means the `vm-edit-message' will use the current frame.  This
variable does not apply to `vm-edit-message-other-frame', which
always create a new frame.

This variable has no meaning if you're not running under an Emacs
capable of displaying multiple real or virtual frames.  Note that
Emacs support multiple virtual frames on dumb terminals, and
VM will use them."
  :group 'vm-frames
  :type 'boolean)

(defcustom vm-frame-per-help nil
  "*Non-nil value causes VM to open a new frame to display help buffers.
Nil means the VM will use the current frame.

This variable has no meaning if you're not running under an Emacs
capable of displaying multiple real or virtual frames.  Note that
Emacs supports multiple virtual frames on dumb terminals, and
VM will use them."
  :group 'vm-frames
  :type 'boolean)

(defcustom vm-frame-per-completion t
  "*Non-nil value causes VM to open a new frame on mouse
initiated completing reads.  A mouse initiated completing read
occurs when you invoke a VM command using the mouse, either with a
menu or a toolbar button.  That command must then prompt you for
information, and there must be a limited set of valid responses.

If these conditions are met and `vm-frame-per-completion''s value
is non-nil, VM will create a new frame containing a list of
responses that you can select with the mouse.

A nil value means the current frame will be used to display the
list of choices.

This variable has no meaning if you're not running Emacs native
under X Windows or some other window system that allows multiple
real Emacs frames.  Note that Emacs supports virtual frames under
ttys but VM will not use these to display completion information."
  :group 'vm-frames
  :type 'boolean)

(defcustom vm-frame-parameter-alist nil
  "*Non-nil value is an alist of types and lists of frame parameters.
This list tells VM what frame parameters to associate with each
new frame it creates of a specific type.

The alist should be of this form

  ((SYMBOL PARAMLIST) (SYMBOL2 PARAMLIST2) ...)

SYMBOL must be one of ``completion'', ``composition'', ``edit'',
``folder'', ``primary-folder'' or ``summary''.  It specifies the type
of frame that the following PARAMLIST applies to.

``completion'' specifies parameters for frames that display lists of
   choices generated by a mouse-initiated completing read.
   (See `vm-frame-per-completion'.)
``composition'' specifies parameters for mail composition frames.
``edit'' specifies parameters for message edit frames
   (e.g. created by `vm-edit-message-other-frame')
``folder'' specifies parameters for frames created by `vm' and the
   ``vm-visit-'' commands.
``folders-summary'' specifies parameters for frames created by the
   ``vm-folder-summarize'' command.
``primary-folder'' specifies parameters for the frame created by running
   `vm' without any arguments.
``summary'' specifies parameters for frames that display a summary buffer
   (e.g. created by `vm-summarize-other-frame')

PARAMLIST is a list of pairs as described in the documentation for
the function `make-frame'."
  :group 'vm-frames
  :type '(repeat (cons (choice (const completion)
			       (const composition)
			       (const edit)
			       (const folder)
			       (const folders-summary)
			       (const primary-folder)
			       (const summary))
		       (repeat (cons symbol sexp)))))

(defcustom vm-search-other-frames t
  "*Non-nil means VM should search frames other than the selected frame
when looking for a window that is already displaying a buffer that
VM wants to display or undisplay."
  :group 'vm-frames
  :type 'boolean)

(defvar vm-configure-datadir nil
  "A directory VM will search for data files.

It will be set at build time and should not be used by the user.")

(defvar vm-configure-pixmapdir nil
  "A directory VM will search for pixmaps.

It will be set at build time and should not be used by the user.")

(defvar vm-configure-docdir nil
  "A directory VM will search for documentation files.

It will be set at build time and should not be used by the user.")

(defvar vm-configure-infodir nil
  "A directory VM will search for info files.

It will be set at build time and should not be used by the user.")

(defun vm-pixmap-directory ()
  "Return the directory where the pixmaps are.

We look for the file followup-dn.xpm in order not to pickup the pixmaps of an
older VM installation." 
  (let* ((vm-dir (file-name-directory (locate-library "vm")))
	 (image-dirs (list (and vm-configure-pixmapdir
                                (expand-file-name vm-configure-pixmapdir))
                           (and vm-configure-datadir
                                (expand-file-name vm-configure-datadir))
                           (expand-file-name "pixmaps" vm-dir)
			   (expand-file-name "../pixmaps" vm-dir)
			   (let ((d (and (featurep 'xemacs)
					 (xemacs-locate-data-directory "vm"))))
			     (and d (expand-file-name "pixmaps" d)))))
         image-dir)
    (while image-dirs
      (setq image-dir (car image-dirs))
      (if (and image-dir
               (file-exists-p (expand-file-name "visit-up.xpm" image-dir)))
          (setq image-dirs nil)
	(setq image-dirs (cdr image-dirs))))
    image-dir))

(defcustom vm-image-directory nil
  "*The directory where VM finds the pixmaps for mime objects."
  :group 'vm-misc
  :type '(choice directory (const :tag "Automatic" nil)))

(defun vm-image-directory ()
  "Return the directory where the images for mime objects are."
  (or vm-image-directory
      (expand-file-name "mime" (vm-pixmap-directory))))

(defcustom vm-use-toolbar
  '(getmail 
    next previous delete/undelete autofile file
    reply followup forward compose print visit quit help)
  "*Non-nil value causes VM to provide a toolbar interface.
Value should be a list of symbols and integers that will determine which
toolbar buttons will appear and in what order.

If nil appears in the list, it should appear exactly once.  All
buttons after nil in the list will be displayed flushright in
top/bottom toolbars and flushbottom in left/right toolbars.

If a positive integer N appears in the list, a blank space will
appear in the toolbar with a width of N pixels for top/bottom
toolbars, and a height of N for left/right toolbars.

See also `vm-toolbar-orientation' to control where the toolbar is placed."
  :group 'vm-toolbar
  :type '(repeat (choice integer
			 (const autofile)
			 (const compose)
			 (const delete/undelete)
			 (const file)
			 (const getmail)
			 (const help)
			 (const mime)
			 (const next)
			 (const previous)
			 (const print)
			 (const quit)
			 (const reply)
			 (const followup)
			 (const forward)
			 (const visit)
			 (const nil))))

(defcustom vm-toolbar-orientation 'top
  "*Value is a symbol that specifies where the VM toolbar is located.
Legal values are `left', `right' `top' and `bottom'.  Any other
value will be interpreted as `top'.

This variable only has meaning under XEmacs.
Under FSF Emacs 21 the toolbar is always at the top of the frame."
  :group 'vm-toolbar
  :type '(choice (const left)
		 (const right)
		 (const top)
		 (const bottom)))

(defcustom vm-toolbar-pixmap-directory nil
  "*The directory VM should find its toolbar pixmaps."
  :group 'vm-toolbar
  :type '(choice directory (const :tag "Automatic" nil)))

(defvar vm-gtk-emacs-p (or (featurep 'gtk)
			 (string-match "'--with-gtk'" 
				       system-configuration-options)
			 (and (boundp 'device-type)
			      (eq (device-type) 'gtk)))
  "True when running in a GTK enabled Emacs.")

(defun vm-toolbar-pixmap-directory ()
  "Return the directory where the toolbar pixmaps are."
  (or vm-toolbar-pixmap-directory 
      (if vm-gtk-emacs-p
	  (concat (vm-pixmap-directory) "/gtk")
	(vm-pixmap-directory))))

(defcustom vm-toolbar nil
  "*Non-nil value should be a list of toolbar button descriptors.
See the documentation for the variable default-toolbar for a
definition of what a toolbar button descriptor is.

If `vm-toolbar' is set non-nil VM will use its value as a toolbar
instantiator instead of the usual behavior of building a button
list based on the value of `vm-use-toolbar'.  `vm-use-toolbar' still
must be set non-nil for a toolbar to appear, however.

Consider this variable experimental; it may not be supported forever."
  :group 'vm-toolbar
  :type 'sexp)

(defcustom vm-use-menus
  (nconc (list 'folder 'motion 'send 'mark 'label 'sort 'virtual)
	 (list 'undo)
	 (list 'dispose)
	 (list 'emacs)
	 (list nil 'help))
  "*Non-nil value causes VM to provide a menu interface.
A value that is a list causes VM to install its own menubar.
A value of 1 causes VM to install a \"VM\" item in the Emacs menubar.

If the value of `vm-use-menus' is a list, it should be a list of
symbols.  The symbols and the order in which they are listed
determine which menus will be in the menubar and how they are
ordered.  Valid symbol values are:

    dispose
    emacs
    folder
    help
    label
    mark
    motion
    send
    sort
    undo
    virtual
    nil

If nil appears in the list, it should appear exactly once.  All
menus after nil in the list will be displayed flushright in
menubar.

This variable only has meaning in Emacs environments where menus
are provided, which usually means Emacs has to be running under a
window system."
  :group 'vm-toolbar
  :type '(choice (const 1)
		 (repeat (choice (const dispose)
				 (const emacs)
				 (const folder)
				 (const help)
				 (const label)
				 (const mark)
				 (const motion)
				 (const send)
				 (const sort)
				 (const undo)
				 (const virtual)
				 (const nil)))))

(defcustom vm-use-menubar-buttons t
  "*Non-nil value means that VM should use buttons on menubars, such
as [Emacs] and [VM], in environments that support such buttons."
  :group 'vm-toolbar
  :type 'boolean)

(defcustom vm-popup-menu-on-mouse-3 t
  "*Non-nil value means VM should provide context-sensitive menus on mouse-3.
A nil value means VM should not change the binding of mouse-3."
  :group 'vm-toolbar
  :type 'boolean)

(defcustom vm-warp-mouse-to-new-frame nil
  "*Non-nil value causes VM to move the mouse cursor into newly created frames.
This is useful to give the new frame the focus under some window managers
that randomly place newly created frames.

Nil means don't move the mouse cursor."
  :group 'vm-frames
  :type 'boolean)

(defcustom vm-url-retrieval-methods '(lynx wget fetch curl w3m)
  "*Non-nil value specifies how VM is permitted to retrieve URLs.
VM needs to do this when supporting the message/external-body
MIME type, which provides a reference to an object instead of the
object itself.  The specification should be a list of symbols
with the following meanings

        lynx - means VM should try to use the lynx program.
        wget - means VM should try to use the wget program.
         w3m - means VM should try to use the w3m program.
       fetch - means VM should try to use the fetch program.
        curl - means VM should try to use the curl program.

The list can contain all these values and VM will try them all,
but not in any particular order, except that the url-w3 method
will likely be tried last since it is likely to be the slowest
retrieval method.

If `vm-url-retrieval-methods' value is nil, VM will not try to
use any URL retrieval methods."
  :group 'vm-url
  :type '(set (const lynx)
	      (const wget)
	      (const w3m)
	      (const fetch)
	      (const curl)
	      (const url-w3)))

(defcustom vm-url-browser 'browse-url
  "*The default web browser to be used for following URLs (hyperlinks)
in messages.  

Clicking mouse-2 on a URL will send it to the default browser.
Moving point to a character within the URL and pressing RETURN
will also send the URL to the default browser.

If the value of `vm-url-browser' is a string, it should specify
name of an external browser to run.  The URL will be passed to
the program as its first argument after the program switches
specified by `vm-url-browser-switches', if any.

If the value of `vm-url-browser' is a symbol, it should specify a
Lisp function to call.  The URL will be passed to the function as
its first and only argument.  The Emacs `browse-url' function is
an excellent choice.  It is the default value of the variable.
VM also defines a number of browser functions of the form
`vm-mouse-send-url-to-xxx', where xxx is the name of a browser.
The `xxx' can be netscape, mmosaic, mosaic, opera, mozilla,
konqueror, firefox, window-system or clipboard.  If it is
window-system then the URL is passed to the window system's
\"copy\" mechanism so that it can be pasted somwhere else.  If it
is clipboard, the URL is sent to the X clipboard.


A nil value means VM should not enable URL passing to browsers."
  :group 'vm-url
  :type '(choice (const :tag "Disable URL parsing" nil)
		 (function :tag "Browser function")
		 (string :tag "External browser")))

(defcustom vm-url-browser-switches nil
  "*List of command line flags passed to the command named by
`vm-url-browser'.  VM uses `vm-url-browser' to display URLs
in messages when you click on them."
  :group 'vm-url
  :type '(repeat string))

(defface vm-highlight-url '((t (:inherit link)))
 "Default face used to highlight URLs."
 :group 'vm-faces)
;; (copy-face 'bold-italic 'vm-highlight-url)

(defcustom vm-highlight-url-face 'vm-highlight-url
    "*Non-nil value should be a face to use display URLs found in messages.
Nil means don't highlight URLs."
  :group 'vm-faces
  :type 'symbol)

(defcustom vm-url-search-limit 12000
  "*Non-nil numeric value tells VM how hard to search for URLs.
The number specifies the maximum message size in characters that
VM will search for URLs.  For message larger than this value, VM
will search from the beginning of the message to a point
`vm-url-search-limit' / 2 characters into the message.  Then VM will
search from a point `vm-url-search-limit' / 2 characters from the
end of the message to the end of message."
  :group 'vm-url
  :type '(choice (const nil) integer))

(defcustom vm-display-xfaces nil
  "*Non-nil means display images as specified in X-Face headers.
This requires XEmacs with native xface support compiled in."
  :group 'vm-presentation
  :type 'boolean)

(defcustom vm-startup-with-summary t
  "*Value tells VM whether to generate a summary when a folder is visited.
Nil means don't automatically generate a summary.

A value of t means always generate a summary.

A positive numeric value N means only generate a summary if there
are N or more messages.

A negative numeric value -N means only generate a summary if
there are N or less messages."
  :group 'vm-summary
  :type '(choice (const :tag "Always" t) 
		 (const :tag "Never" nil) 
		 (integer :tag "Number of messages") ))

(defcustom vm-follow-summary-cursor t
  "*Non-nil value causes VM to select the message under the cursor in the
summary window before executing commands that operate on the current message.
This occurs only when the summary buffer window is the selected window."
  :group 'vm-summary
  :type 'boolean)

(defcustom vm-jump-to-new-messages t
  "*Non-nil value causes VM to jump to the first new message
whenever such messages arrive in a folder or the first time a
folder is visited.

See also `vm-jump-to-unread-messages'."
  :group 'vm-summary
  :type 'boolean)

(defcustom vm-jump-to-unread-messages t
  "*Non-nil value causes VM to jump to the first unread message
whenever such messages arrive in a folder or the first time a
folder is visited.  New messages are considered unread in this
context so new messages will be jumped to as well.

The value of `vm-jump-to-new-messages' takes precedence over the
setting of this variable.  So if there are unread messages and
new messages VM will jump to the first new message, even if an
unread message appears before it in the folder, provided
`vm-jump-to-new-messages' is non-nil."
  :group 'vm-summary
  :type 'boolean)

(defcustom vm-skip-deleted-messages t
  "Non-nil value causes VM's `n' and `p' commands to skip over
deleted messages.  A value of t causes deleted messages to always be skipped.
A value that is not nil and not t causes deleted messages to be skipped only
if there are other messages that are not flagged for deletion in the desired
direction of motion."
  :group 'vm-summary
  :type '(choice (const :tag "No" nil) 
		 (const :tag "Yes" t) 
		 (const :tag "Skip if some undeleted" skip-if-some-undeleted)))

(defcustom vm-skip-read-messages nil
  "*Non-nil value causes VM's `n' and `p' commands to skip over
messages that have already been read, in favor of new or unread messages.
A value of t causes read messages to always be skipped.  A value that is
not nil and not t causes read messages to be skipped only if there are
unread messages in the desired direction of motion."
  :group 'vm-summary 
  :type '(choice (const :tag "No" nil) 
		 (const :tag "Yes" t) 
		 (const :tag "Skip if some unread" skip-if-some-unread)))

(defcustom vm-move-after-deleting nil
  "*Non-nil value causes VM's `d' command to automatically invoke
`vm-next-message' or `vm-previous-message' after deleting, to move
past the deleted messages.  A value of t means motion should
honor the value of `vm-circular-folders'.  A value that is not t
and not nil means that motion should be done as if
`vm-circular-folders' is set to nil."
  :group 'vm-summary
  :type '(choice (const :tag "No" nil) 
		 (const :tag "Yes" t) 
		 (const :tag "Yes, without circular movement" 
			without-circular)))

(defcustom vm-move-after-undeleting nil
  "*Non-nil value causes VM's `u' command to automatically invoke
`vm-next-message' or `vm-previous-message' after undeleting, to move
past the undeleted messages.  A value of t means motion should
honor the value of `vm-circular-folders'.  A value that is not t
and not nil means that motion should be done as if
`vm-circular-folders' is set to nil."
  :group 'vm-summary
  :type '(choice (const :tag "No" nil) 
		 (const :tag "Yes" t) 
		 (const :tag "Yes, without circular movement" 
			without-circular)))

(defcustom vm-move-after-killing nil
  "*Non-nil value causes VM's `k' command to automatically invoke
`vm-next-message' or `vm-previous-message' after killing messages, to try
to move past the deleted messages.  A value of t means motion
should honor the value of `vm-circular-folders'.  A value that is
not t and not nil means that motion should be done as if
`vm-circular-folders' is set to nil."
  :group 'vm-summary
  :type '(choice (const :tag "No" nil) 
		 (const :tag "Yes" t) 
		 (const :tag "Yes, without circular movement" 
			without-circular)))

(defcustom vm-move-after-reading nil
  "*Non-nil value causes VM's `.' command to automatically invoke
`vm-next-message' or `vm-previous-message' after killing messages, to try
to move past the read messages.  A value of t means motion
should honor the value of `vm-circular-folders'.  A value that is
not t and not nil means that motion should be done as if
`vm-circular-folders' is set to nil."
  :group 'vm-summary
  :type '(choice (const :tag "No" nil) 
                 (const :tag "Yes" t) 
		 (const :tag "Yes, without circular movement" 
			without-circular)))

(defcustom vm-delete-after-saving nil
  "*Non-nil value causes VM automatically to mark messages for deletion
after successfully saving them to a folder."
  :group 'vm-dispose
  :type 'boolean)

(defcustom vm-delete-after-archiving nil
  "*Non-nil value causes VM to automatically mark messages for deletion
after successfully auto-archiving them with the `vm-auto-archive-messages'
command."
  :group 'vm-dispose
  :type 'boolean)

(defcustom vm-delete-after-bursting nil
  "*Non-nil value causes VM automatically to mark a message for deletion
after it has been successfully burst by the `vm-burst-digest' command."
  :group 'vm-dispose
  :type 'boolean)

(defcustom vm-confirm-for-auto-archive t
  "*Non-nil value causes VM to ask for confirmation when
`vm-auto-archive-messages' is invoked."
  :group 'vm-dispose
  :type 'boolean)

(defcustom vm-circular-folders nil
  "*Value determines whether VM folders will be considered circular by
various commands.  `Circular' means VM will wrap from the end of the folder
to the start and vice versa when moving the message pointer, or deleting,
undeleting or saving messages before or after the current message.

A value of t causes all VM commands to consider folders circular.

A value of nil causes all of VM commands to signal an error if the start
or end of the folder would have to be passed to complete the command.
For movement commands, this occurs after the message pointer has been
moved as far as possible in the specified direction.  For other commands,
the error occurs before any part of the command has been executed, i.e.
no deletions, saves, etc. will be done unless they can be done in their
entirety.

A value that is not nil and not t causes only VM's movement commands to
consider folders circular.  Saves, deletes and undelete commands will
behave the same as if the value is nil."
  :group 'vm-summary
  :type '(choice (const :tag "No" nil) 
		 (const :tag "Yes" t) 
		 (const :tag "For movement commands only" for-movement-only)))

(defcustom vm-search-using-regexps nil
  "*Non-nil value causes VM's search command to interpret user input as a
regular expression instead of as a literal string."
  :group 'vm-misc
  :type 'boolean)

(defcustom vm-move-messages-physically nil
  "*Non-nil value causes VM's commands that change the message order
of a folder to always move the physical messages involved and not
just change the presentation order.  Nil means that commands just
change the order in which VM displays messages and leave the
folder itself undisturbed."
  :group 'vm-folders
  :type 'boolean)

(defcustom vm-edit-message-mode 'text-mode
  "*Major mode to use when editing messages in VM."
  :group 'vm-dispose
  :type 'function)

(defvar lpr-command)
(defcustom vm-print-command (if (boundp 'lpr-command) lpr-command "lpr")
  "*Command VM uses to print messages."
  :group 'vm-print
  :type '(choice (string :tag "Command")
                 (const nil)))

(defvar lpr-switches)
(defcustom vm-print-command-switches (if (boundp 'lpr-switches) lpr-switches nil)
  "*List of command line flags passed to the command named by
`vm-print-command'.  VM uses `vm-print-command' to print
messages."
  :group 'vm-print
  :type '(repeat (const nil)
                 (string :tag "Switch")))

(defcustom vm-berkeley-mail-compatibility
  (memq system-type '(berkeley-unix netbsd))
  "*Non-nil means to read and write BSD Mail(1) style Status: headers.
This makes sense if you plan to use VM to read mail archives created by
Mail."
  :group 'vm-folders
  :type 'boolean)

(defcustom vm-strip-reply-headers nil
  "*Non-nil value causes VM to strip away all comments and extraneous text
from the headers generated in reply messages.  If you use the \"fakemail\"
program as distributed with Emacs, you probably want to set this variable
to t, because as of Emacs v18.52 \"fakemail\" could not handle unstripped
headers."
  :group 'vm-reply
  :type 'boolean)

(defcustom vm-select-new-message-hook nil
  "Hook run every time a message with the `new'
attribute is made to be the current message.  When the functions are run, the
current buffer is the folder containing the message and it is narrowed
to the start and end of the message."
  :group 'vm-hooks
  :type 'hook)

(defcustom vm-select-unread-message-hook nil
  "Hook run every time a message with the `unread'
attribute is made to be the current message.  When the functions are called,
the current buffer is the folder containing the message and it is narrowed to
the start and end of the message."
  :group 'vm-hooks
  :type 'hook)

(defcustom vm-select-message-hook nil
  "*List of hook functions called every time a message
is made to be the current message.  When the hooks are run, the
current buffer will be the folder containing the message and the
start and end of the message will be bracketed by (point-min) and
 (point-max)."
  :group 'vm-hooks
  :type 'hook)

(defcustom vm-showing-message-hook nil
  "*List of hook functions called every time a message is showed.
When the hooks are run, the current buffer will be the folder containing the
message and the start and end of the message will be bracketed by (point-min)
and (point-max)."
  :group 'vm-hooks
  :type 'hook)

(defcustom vm-arrived-message-hook nil
  "*List of hook functions called once for each message gathered from
the system mail spool, or from another folder with
`vm-get-new-mail', or from a digest with `vm-burst-digest'.  When the
hooks are run, the current buffer will be the folder containing
the message and the start and end of the message will be
bracketed by (point-min) and (point-max)."
  :group 'vm-hooks
  :type 'hook)

(defcustom vm-spooled-mail-waiting-hook nil
  "*List of functions called when VM first notices mail is spooled
for a folder.  The folder buffer will be current when the hooks are
run."
  :group 'vm-hooks 
  :type 'hook)

(defcustom vm-arrived-messages-hook nil
  "*List of hook functions called after VM has gathered a group of
messages from the system mail spool, or from another folder with
`vm-get-new-mail', or from a digest with `vm-burst-digest'.  When the
hooks are run, the new messages will have already been added to
the message list but may not yet appear in the summary.
Also, the current buffer will be the folder containing
the messages."
  :group 'vm-hooks
  :type 'hook)

(defcustom vm-reply-hook nil
  "*List of hook functions to be run after a Mail mode
composition buffer has been created for a reply.  VM runs this
hook and then runs `vm-mail-mode-hook' before leaving the user in
the Mail mode buffer."
  :group 'vm-hooks
  :type 'hook)

(defcustom vm-forward-message-hook nil
  "*List of hook functions to be run after a Mail mode
composition buffer has been created to forward a message.  VM
runs this hook and then runs `vm-mail-mode-hook' before leaving the
user in the Mail mode buffer."
  :group 'vm-hooks
  :type 'hook)

(defcustom vm-resend-bounced-message-hook nil
  "*List of hook functions to be run after a Mail mode
composition buffer has been created to resend a bounced message.
VM runs this hook and then runs `vm-mail-mode-hook' before leaving
the user in the Mail mode buffer."
  :group 'vm-hooks
  :type 'hook)

(defcustom vm-resend-message-hook nil
  "*List of hook functions to be run after a Mail mode
composition buffer has been created to resend a message.
VM runs this hook and then runs `vm-mail-mode-hook' before leaving
the user in the Mail mode buffer."
  :group 'vm-hooks
  :type 'hook)

(defcustom vm-send-digest-hook nil
  "*List of hook functions to be run after a Mail mode
composition buffer has been created to send a digest.
VM runs this hook and then runs `vm-mail-mode-hook' before leaving
the user in the Mail mode buffer."
  :group 'vm-hooks
  :type 'hook)

(defcustom vm-mail-hook nil
  "*List of hook functions to be run after a Mail mode
composition buffer has been created to send a non specialized
message, i.e. a message that is not a reply, forward, digest,
etc.  VM runs this hook and then runs `vm-mail-mode-hook' before
leaving the user in the Mail mode buffer."
  :group 'vm-hooks
  :type 'hook)

(defcustom vm-summary-update-hook nil
  "*List of hook functions called just after VM updates an existing
entry a folder summary."
  :group 'vm-hooks
  :type 'hook)

(defcustom vm-summary-redo-hook nil
  "*List of hook functions called just after VM adds or deletes
entries from a folder summary."
  :group 'vm-hooks
  :type 'hook)

(defgroup vm-summary-faces nil
  "VM additional faces for the summary buffer."
  :group 'vm-faces)

(defcustom vm-summary-faces-alist
  '(
    ;; Most important status info
    ((deleted)   	vm-summary-deleted)
    ((new)       	vm-summary-new)
    ((marked)    	vm-summary-marked)
    ((or (header "Priority: urgent")
         (header "Importance: high")
         (header "X-Priority: 1")
	 (flagged)
         (label "!")
	 (label "\\flagged")
         (header "X-VM-postponed-data:"))
     vm-summary-high-priority)
    ((unread)    	vm-summary-unread)
    ;; less important status info
    ((replied)   	vm-summary-replied)
    ((or (filed)
	 (written))     vm-summary-saved)
    ((or (forwarded) 
	 (redistributed)) vm-summary-forwarded)
    ((edited)    	vm-summary-edited)
    ;; 
    ((outgoing)  	vm-summary-outgoing)
    ((any)       	vm-summary-default))
  "List of condition-face pairs for deciding the faces for summary
lines.  Each element of the list is a pair, i.e., a two-element list.
The first element is a virtual folder condition as described in the
documentation of `vm-virtual-folder-alist'.  The second element is a
face name.

The order matters. The first condition that matches the message will
decide the face."
  :type '(repeat (group (sexp :tag "Virtual Selector") 
			(face :tag "Face")))
  :group 'vm-summary-faces)

;;---------------------------------------------------------------------------
;; Color coding
;;
;; Face                  light bgd     dark bgd      monochrome
;; ----                  ---------     --------      ----------
;;
;; deleted                grey50        grey70        dim
;; high-priority          red
;; low-priority           grey50
;; marked                 purple        magenta       underlined
;; new                    blue          cyan          italic
;; unread                 navy          magenta       italic
;; saved                  green
;; replied                grey30
;; forwarded              grey20
;; outgoing               grey30 
;; expanded
;; collapsed
;; --------------------------------------------------------------------------


(defface vm-summary-selected
  '(
    (((type x w32 mswindows mac) (class color) (background light))
     (:background "grey85"))
    (((type x w32 mswindows mac) (class color) (background dark))
     (:background "SlateBlue3"))
    (((class color) (background light))
     (:background "grey80"))
    (((class color) (background dark))
     (:background "Blue3"))
    (t 
     (:weight bold)))
  "The face used in VM Summary buffers for the selected message."
  :group 'vm-summary-faces)

(put 'vm-summary-selected-face 'face-alias 'vm-summary-selected)
(make-obsolete 'vm-summary-selected-face 'vm-summary-selected "8.2.0")

(defface vm-summary-marked
  '(
    (((type x w32 mswindows mac) (class color) (background light)) 
     (:foreground "Purple"))
    (((type x w32 mswindows mac) (class color) (background dark))
     (:foreground "Magenta"))
    ;; (((class color) (min-colors 16) (background light))
    ;;  (:foreground "Purple"))
    ;; (((class color) (min-colors 16) (background dark))
    ;;  (:foreground "Magenta"))
    (((class color) (background light)) ; (min-colors 8)
     (:foreground "Magenta" :weight bold))
    (((class color) (background dark))
     (:foreground "Magenta" :weight bold))
    (t (:underline t)))
  "The face used in VM Summary buffers for marked messages."
  :group 'vm-summary-faces)

(put 'vm-summary-marked-face 'face-alias 'vm-summary-marked)
(make-obsolete 'vm-summary-marked-face 'vm-summary-marked "8.2.0")

(if (featurep 'xemacs)
    (defface vm-summary-deleted
      '(
	(((class color) (background light))
	 (:foreground "grey50" :strikethru t))
	(((class color) (background dark))
	 (:foreground "grey70" :strikethru t))
	(((type tty) (class color) (background light)) 
	 (:foreground "yellow"))
	(((type tty) (class color) (background dark)) 
	 (:foreground "yellow"))
	(((class grayscale) (background light))
	 (:foreground "grey50" :strikethru t))
	(((class grayscale) (background dark))
	 (:foreground "grey70" :strikethru t))
	(((class mono))
	 (:strikethru t))
	(((type tty)) 
	 (:dim t))
	(t ()))
      "The face used in VM Summary buffers for deleted messages."
      :group 'vm-summary-faces)
  (defface vm-summary-deleted
    '(
      (((type x w32 mswindows mac) (class color) (background light)) 
       (:foreground "grey50" :strike-through "grey80"))
      (((type x w32 mswindows mac) (class color) (background dark)) 
       (:foreground "grey70" :strike-through "grey50"))
      ;; (((class color) (min-colors 16) (background light)) 
      ;;  (:foreground "grey50" :strike-through "grey70"))
      ;; (((class color) (min-colors 16) (background dark)) 
      ;;  (:foreground "grey70" :strike-trhough "grey50"))
      (((class color) (background light)) ;  (min-colors 8)
       (:foreground "yellow"))
      (((class color) (background dark)) 
       (:foreground "yellow"))
      (((class grayscale) (background light)) 
       (:foreground "grey50" :strike-through "grey70"))
      (((class grayscale) (background dark)) 
       (:foreground "grey70" :strike-trhough "grey50"))
      (((class mono))
       (:strike-through t))
      (((type tty)) 
       (:dim t))
      (t ()))
    "The face used in VM Summary buffers for deleted messages."
    :group 'vm-summary-faces))

(put 'vm-summary-deleted-face 'face-alias 'vm-summary-deleted)
(make-obsolete 'vm-summary-deleted-face 'vm-summary-deleted "8.2.0")

(defface vm-summary-new
  '(
    (((class color) (background light))
     (:foreground "blue"))
    (((class color) (background dark))
     (:foreground "cyan"))
    (((class grayscale) (background light))
     (:foreground "DimGray" :slant italic))
    (((class grayscale) (background dark))
     (:foreground "LightGray" :slant italic))
    (t 
     (:slant italic)))
  "The face used in VM Summary buffers for new messages."
  :group 'vm-summary-faces)

(put 'vm-summary-new-face 'face-alias 'vm-summary-new)
(make-obsolete 'vm-summary-new-face 'vm-summary-new "8.2.0")

(defface vm-summary-unread
  '(
    (((type x w32 mswindows mac) (class color) (background light))
     (:foreground "blue3"))
    (((type x w32 mswindows mac) (class color) (background dark))
     (:foreground "LightSkyBlue"))
    ;; (((class color) (min-colors 16) (background light))
    ;;  (:foreground "blue"))
    ;; (((class color) (min-colors 16) (background dark))
    ;;  (:foreground "magenta"))
    (((class color) (background light)) ;  (min-colors 8)
     (:foreground "blue"))
    (((class color) (background dark))
     (:foreground "magenta"))
    (((class grayscale) (background light))
     (:foreground "DimGray" :slant italic))
    (((class grayscale) (background dark))
     (:foreground "LightGray" :slant italic))
    (t 
     (:slant italic)))
  "The face used in VM Summary buffers for unread messages."
  :group 'vm-summary-faces)

(put 'vm-summary-unread-face 'face-alias 'vm-summary-unread)
(make-obsolete 'vm-summary-unread-face 'vm-summary-unread "8.2.0")

(defface vm-summary-saved
  '(
    (((type x w32 mswindows mac) (class color) (background light))
     (:foreground "green4"))
    (((type x w32 mswindows mac) (class color) (background dark))
     (:foreground "PaleGreen"))
    ;; (((class color) (min-colors 16) (background light))
    ;;  (:foreground "green"))
    ;; (((class color) (min-colors 16) (background dark))
    ;;  (:foreground "green"))
    (((class color))
     (:foreground "green")))
  "The face used in VM Summary buffers for saved messages."
  :group 'vm-summary-faces)

(put 'vm-summary-filed-face 'face-alias 'vm-summary-saved)
(make-obsolete 'vm-summary-filed 'vm-summary-saved "8.2.0")
(put 'vm-summary-written-face 'face-alias 'vm-summary-saved)
(make-obsolete 'vm-summary-written 'vm-summary-saved "8.2.0")

(defface vm-summary-replied
  '(
    (((type x w32 mswindows mac) (class color) (background light))
     (:foreground "MediumOrchid4"))
    (((type x w32 mswindows mac) (class color) (background dark))
     (:foreground "plum1"))
    ;; (((class color) (min-colors 16) (background light))
    ;;  (:foreground "Orchid"))
    ;; (((class color) (min-colors 16) (background dark))
    ;;  (:foreground "purple"))
    (((class color))
     (:foreground "magenta"))
    (t 
     ()))
  "The face used in VM Summary buffers for replied messages."
  :group 'vm-summary-faces)

(put 'vm-summary-replied-face 'face-alias 'vm-summary-replied)
(make-obsolete 'vm-summary-replied-face 'vm-summary-replied "8.2.0")

(defface vm-summary-forwarded
  '(
    (((type x w32 mswindows mac) (class color) (background light))
     (:foreground "MediumOrchid3"))
    (((type x w32 mswindows mac) (class color) (background dark))
     (:foreground "Thistle1"))
    ;; (((class color) (min-colors 16) (background light))
    ;;  (:foreground "Orchid"))
    ;; (((class color) (min-colors 16) (background dark))
    ;;  (:foreground "Yellow"))
    (((class color))
     (:foreground "Yellow"))
    (((class grayscale) (background light))
     (:foreground "LightGray"))
    (((class grayscale) (background dark))
     (:foreground "DimGray"))
    (t 
     ()))
  "The face used in VM Summary buffers for forwarded messages."
  :group 'vm-summary-faces)

(put 'vm-summary-forwarded-face 'face-alias 'vm-summary-forwarded)
(make-obsolete 'vm-summary-forwarded-face 'vm-summary-forwarded "8.2.0")
(put 'vm-summary-redistributed-face 'face-alias 'vm-summary-forwarded)
(make-obsolete 'vm-summary-redistributed-face 'vm-summary-forwarded "8.2.0")

(defface vm-summary-edited 
  '((t ()))
  "The face used in VM Summary buffers for edited messages."
  :group 'vm-summary-faces)

(put 'vm-summary-edited-face 'face-alias 'vm-summary-edited)
(make-obsolete 'vm-summary-edited-face 'vm-summary-edited "8.2.0")

(defface vm-summary-outgoing
  '(
    (((class color) (background light))
     (:foreground "grey40"))
    (((class color) (background dark))
     (:foreground "grey80"))
    (t 
     ()))
  "The face used in VM Summary buffers for outgoing messages."
  :group 'vm-summary-faces)

(put 'vm-summary-outgoing-face 'face-alias 'vm-summary-outgoing)
(make-obsolete 'vm-summary-outgoing-face 'vm-summary-outgoing "8.2.0")

(defface vm-summary-expanded
  '((t ()))
  "The face used in VM Summary buffers for the root messages of
expanded threads."
  :group 'vm-summary-faces)

(put 'vm-summary-expanded-face 'face-alias 'vm-summary-expanded)
(make-obsolete 'vm-summary-expanded-face 'vm-summary-expanded "8.2.0")

(defface vm-summary-collapsed
  '((t (:slant oblique)))
  "The face used in VM Summary buffers for the root messages of
collapsed threads."
  :group 'vm-summary-faces)

(put 'vm-summary-collapsed-face 'face-alias 'vm-summary-collapsed)
(make-obsolete 'vm-summary-collapsed-face 'vm-summary-collapsed "8.2.0")

(defface vm-summary-high-priority
  '(
    (((type x w32 mswindows mac) (class color) (background light))
     (:foreground "Red1"))
    (((type x w32 mswindows mac) (class color) (background dark))
     (:foreground "LightSalmon"))
    ;; (((class color) (min-colors 16) (background light))
    ;;  (:foreground "Red"))
    ;; (((class color) (min-colors 16) (background dark))
    ;;  (:foreground "Pink"))
    (((class color))		;  (min-colors 8)
     (:foreground "red"))
    (t
     (:inverse-video t :weight bold)))
  "The face used in VM Summary buffers for high-priority messages."
  :group 'vm-summary-faces)

(put 'vm-summary-high-priority-face 'face-alias 'vm-summary-high-priority)
(make-obsolete 'vm-summary-high-priority-face 'vm-summary-high-priority "8.2.0")

(defface vm-summary-low-priority
  '(
    (((class color) (background light))
     (:foreground "grey50"))
    (((class color) (background dark))
     (:foreground "grey70"))
    (((type tty) (class color) (background light)) 
     (:foreground "yellow"))
    (((type tty) (class color) (background dark)) 
     (:foreground "yellow"))
    (((class grayscale) (background light))
     (:foreground "grey50"))
    (((class grayscale) (background dark))
     (:foreground "grey70"))
    (((class mono))
     (:strikethru t))
    (((type tty)) 
     (:dim t))
    (t ()))
  "The face used in VM Summary buffers for low-priority messages."
  :group 'vm-summary-faces)

(defface vm-summary-default
  '((t ()))
  "The default face used in VM Summary buffers."
  :group 'vm-summary-faces)

(put 'vm-summary-default-face 'face-alias 'vm-summary-default)
(make-obsolete 'vm-summary-default-face 'vm-summary-default "8.2.0")

(defcustom vm-visit-folder-hook nil
  "*List of hook functions called just after VM visits a folder.
It doesn't matter if the folder buffer already exists, this hook
is run each time `vm' or `vm-visit-folder' is called interactively.
It is NOT run after `vm-mode' is called."
  :group 'vm-hooks
  :type 'hook)

(defcustom vm-retrieved-spooled-mail-hook nil
  "*List of hook functions called just after VM has retrieved
a group of messages from your system mailbox(es).  When these
hooks are run, the messages have been added to the folder buffer
but not the message list or summary.  When the hooks are run, the
current buffer will be the folder where the messages were
incorporated."
  :group 'vm-hooks
  :type 'hook)

(defcustom vm-edit-message-hook nil
  "*List of hook functions to be run just before a message is edited.
This is the last thing `vm-edit-message' does before leaving the user
in the edit buffer."
  :group 'vm-hooks
  :type 'hook)

(defcustom vm-mail-mode-hook nil
  "*List of hook functions to be run after a Mail mode
composition buffer has been created.  This is the last thing VM
does before leaving the user in the Mail mode buffer."
  :group 'vm-hooks
  :type 'hook)

(defcustom vm-mode-hook nil
  "*List of hook functions to run when a buffer enters `vm-mode'.
These hook functions should generally be used to set key bindings
and local variables."
  :group 'vm-hooks
  :type 'hook)

(defcustom vm-mode-hooks nil
  "*Old name for `vm-mode-hook'.
Supported for backward compatibility.
You should use the new name."
  :group 'vm-hooks
  :type 'hook)

(defcustom vm-summary-mode-hook nil
  "*List of hook functions to run when a VM summary buffer is created.
The current buffer will be that buffer when the hooks are run."
  :group 'vm-hooks
  :type 'hook)

(defcustom vm-summary-mode-hooks nil
  "*Old name for `vm-summary-mode-hook'.
Supported for backward compatibility.
You should use the new name."
  :group 'vm-hooks
  :type 'hook)

(defcustom vm-folders-summary-mode-hook nil
  "*List of hook functions to run when a VM folders summary buffer is created.
The current buffer will be that buffer when the hooks are run."
  :group 'vm-hooks
  :type 'hook)

(defcustom vm-virtual-mode-hook nil
  "*List of hook functions to run when a VM virtual folder buffer is created.
The current buffer will be that buffer when the hooks are run."
  :group 'vm-hooks
  :type 'hook)

(defcustom vm-presentation-mode-hook nil
  "*List of hook functions to run when a VM presentation buffer is created.
The current buffer will be the new presentation buffer when the hooks are run.
Presentation buffers are used to display messages when some type of decoding
must be done to the message to make it presentable.  E.g. MIME decoding."
  :group 'vm-hooks
  :type 'hook)

(defcustom vm-quit-hook nil
  "*List of hook functions to run when you quit VM.
This applies to any VM quit command.  The following global variables
may be used in your hook function.

  virtual - true if the current folder is a virtual folder
  no-expunge - true if no expunge was requested as part of quit
  no-change - true if the changes are being discarded
  `vm-expunge-before-quit' - user option controlling auto-expunge
"
  :group 'vm-hooks
  :type 'hook)

(defcustom vm-summary-pointer-update-hook nil
  "*List of hook functions to run when the VM summary pointer is updated.
When the hooks are run, the current buffer will be the summary buffer."
  :group 'vm-hooks 
  :type 'hook)

(defcustom vm-display-buffer-hook nil
  "*List of hook functions that are run every time VM wants to
display a buffer.  When the hooks are run, the current buffer will
be the buffer that VM wants to display.  The hooks are expected
to select a window and VM will display the buffer in that
window.

If you use display hooks, you should not use VM's builtin window
configuration system as the result is likely to be confusing."
  :group 'vm-hooks
  :type 'hook)

(defcustom vm-undisplay-buffer-hook nil
  "*List of hook functions that are run every time VM wants to
remove a buffer from the display.  When the hooks are run, the
current buffer will be the buffer that VM wants to disappear.
The hooks are expected to do the work of removing the buffer from
the display.  The hook functions should not kill the buffer.

If you use undisplay hooks, you should not use VM's builtin
window configuration system as the result is likely to be
confusing."
  :group 'vm-hooks
  :type 'hook)

(defcustom vm-iconify-frame-hook nil
  "*List of hook functions that are run whenever VM iconifies a frame."
  :group 'vm-hooks
  :type 'hook)

(defcustom vm-menu-setup-hook nil
  "*List of hook functions that are run just after all menus are initialized."
  :group 'vm-hooks
  :type 'hook)

(defcustom vm-mime-display-function nil
  "*If non-nil, this should name a function to be called inside
`vm-decode-mime-message' to do the MIME display the current
message.  The function is called with no arguments, and at the
time of the call the current buffer will be the `presentation'
buffer for the folder, which is a temporary buffer that VM uses
for the display of MIME messages.  A copy of the current message
will be in the presentation buffer at that time.  The normal work
that `vm-decode-mime-message' would do is not done, because this
function is expected to subsume all of it."
  :group 'vm-mime
  :type '(choice (const :tag "None" nil) 
		 function))

(defcustom vm-mime-deleted-object-label "[Deleted %f (%t)]\n"
  "*The label that will be inserted instead of the original mime object.
See `vm-mime-compile-format-1' for valid format specifiers."
  :group 'vm-mime
  :type 'string)

(defvar vm-mime-show-alternatives nil
  "This variable is deprecated.  You can set
`vm-mime-alternative-show-method' to `all' to get the same effect as
setting this one to t.")

(make-obsolete-variable 'vm-mime-show-alternatives 
			'vm-mime-alternative-show-method "8.2.0")

(defcustom vm-emit-messages-for-mime-decoding t
  "*Flag to allow minibuffer messages about the progress of MIME
decoding of messages.  Only nontrivial decodings are normally
reported.  So there is normally no need to change this from the default."
  :group 'vm-mime
  :type 'boolean)

(defcustom vm-imap-session-preauth-hook nil
  "*List of hook functions to call to generate an preauthenticated
IMAP session process.  This hook is only run if the
authentication method for the IMAP mailbox is ``preauth''.  Each
hook is called with five arguments: HOST, PORT, MAILBOX, USER,
PASSWORD.  (See the documentation for `vm-spool-files' to find out
about these arguments.)  It is the responsibility of the hook
function to create an Emacs process whose input/output streams
are connected to an authenticated IMAP session, and to return
this process.  If the hook cannot accomplish this,
it should return nil.  If all the hooks return nil, VM will
signal an error.

At the time the hook is run, the current buffer will be the
buffer any created process should be associated with. (The BUFFER
argument to start-process or open-network-stream should be
(current-bfufer).)"
  :group 'vm-hooks
  :type 'hook)

(defcustom vm-mail-send-hook nil
  "*List of hook functions to call just before sending a message.
The hooks are run after confirming that you want to send the
message (see `vm-confirm-mail-send') but before MIME encoding and
FCC processing."
  :group 'vm-hooks
  :type 'hook)

;; The following settings are disabled because they are defined in
;; mail-mode/sendmail.el. 

;; (defvar mail-yank-hooks nil
;;   "Hooks called after a message is yanked into a mail composition buffer.

;;    (This hook is deprecated, you should use mail-citation-hook instead.)

;; The value of this hook is a list of functions to be run.
;; Each hook function can find the newly yanked message between point and mark.
;; Each hook function should return with point and mark around the yanked message.

;; See the documentation for `vm-yank-message' to see when VM will run
;; these hooks.")

;; (defcustom mail-citation-hook nil
;;   "*Hook for modifying a citation just inserted in the mail buffer.
;; Each hook function can find the citation between (point) and (mark t).
;; And each hook function should leave point and mark around the citation
;; text as modified.

;; If this hook is entirely empty (nil), a default action is taken
;; instead of no action."
;;   :group 'vm
;;   :type 'hook)

;; (defcustom mail-default-headers nil
;;   "*A string containing header lines, to be inserted in outgoing messages.
;; It is inserted before you edit the message,
;; so you can edit or delete these lines."
;;   :group 'vm
;;   :type '(choice (const nil) string))

;; (defcustom mail-signature nil
;;   "*Text inserted at end of mail buffer when a message is initialized.
;; If t, it means to insert the contents of the file `~/.signature'."
;;   :group 'vm
;;   :type '(choice (const nil) (const t) string))

(defconst vm-rename-current-buffer-function nil
  "*Non-nil value should be a function to call to rename a buffer.
Value should be something that can be passed to `funcall'.  If
this variable is non-nil, VM will use this function instead of
its own buffer renaming code.  The buffer to be renamed will be
the current buffer when the function is called.")

(defvar mode-popup-menu nil
  "The mode-specific popup menu.  Automatically buffer local.
By default, when you press mouse-3 in VM, this menu is popped up.")
(make-variable-buffer-local 'mode-popup-menu)

(defcustom vm-movemail-program "movemail"
  "*Name of program to use to move mail from the system spool
to another location.  Normally this should be the movemail
program distributed with Emacs.  If you use another program, it must
accept as its last two arguments the spool file (or maildrop) from which
mail is retrieved, and the local file where the retrieved mail
should be stored."
  :group 'vm-helpers
  :type '(choice (const :tag "None" nil)
		 file))

(defcustom vm-movemail-program-switches nil
  "*List of command line flags to pass to the movemail program
named by `vm-movemail-program'."
  :group 'vm-helpers
  :type '(choice (const :tag "None" nil)
		 (repeat string)))

(defcustom vm-netscape-program "netscape"
  "*Name of program to use to run Netscape.
`vm-mouse-send-url-to-netscape' uses this."
  :group 'vm-helpers
  :type '(choice (const :tag "None" nil)
		 file))

(defcustom vm-netscape-program-switches nil
  "*List of command line switches to pass to Netscape."
  :group 'vm-helpers
  :type '(choice (const :tag "None" nil)
		 (repeat string)))

(defcustom vm-opera-program "opera"
  "*Name of program to use to run Opera.
`vm-mouse-send-url-to-opera' uses this."
  :group 'vm-helpers
  :type '(choice (const :tag "None" nil)
		 file))

(defcustom vm-opera-program-switches nil
  "*List of command line switches to pass to Opera."
  :group 'vm-helpers
  :type '(choice (const :tag "None" nil)
		 (repeat string)))

(defcustom vm-mozilla-program nil
  "*Name of program to use to run Mozilla.
`vm-mouse-send-url-to-mozilla' uses this."
  :group 'vm-helpers
  :type '(choice (const :tag "None" nil)
		 file))

(defcustom vm-mozilla-program-switches nil
  "*List of command line switches to pass to Mozilla."
  :group 'vm-helpers
  :type '(choice (const :tag "None" nil)
		 (repeat string)))

(defcustom vm-mosaic-program nil
  "*Name of program to use to run Mosaic.
`vm-mouse-send-url-to-mosaic' uses this."
  :group 'vm-helpers
  :type '(choice (const :tag "None" nil)
		 file))

(defcustom vm-mosaic-program-switches nil
  "*List of command line switches to pass to Mosaic."
  :group 'vm-helpers
  :type '(choice (const :tag "None" nil)
		 (repeat string)))

(defcustom vm-mmosaic-program nil
  "*Name of program to use to run mMosaic.
`vm-mouse-send-url-to-mosaic' uses this."
  :group 'vm-helpers
  :type '(choice (const :tag "None" nil)
		 file))

(defcustom vm-mmosaic-program-switches nil
  "*List of command line switches to pass to mMosaic."
  :group 'vm-helpers
  :type '(choice (const :tag "None" nil)
		 (repeat string)))

(defcustom vm-konqueror-program "konqueror"
  "*Name of program to use to run Konqueror.
`vm-mouse-send-url-to-konqueror' uses this."
  :group 'vm-helpers
  :type '(choice (const :tag "None" nil)
		 file))

(defcustom vm-konqueror-program-switches nil
  "*List of command line switches to pass to Konqueror."
  :group 'vm-helpers
  :type '(choice (const :tag "None" nil)
		 (repeat string)))

(defcustom vm-konqueror-client-program "kfmclient"
  "*Name of program to use to issue requests to Konqueror.
`vm-mouse-send-url-to-konqueror' uses this."
  :group 'vm-helpers
  :type '(choice (const :tag "None" nil)
		 file))

(defcustom vm-konqueror-client-program-switches nil
  "*List of command line switches to pass to Konqueror client."
  :group 'vm-helpers
  :type '(choice (const :tag "None" nil)
		 (repeat string)))

(defcustom vm-firefox-program "firefox"
  "*Name of program to use to run Mozilla Firefox.
`vm-mouse-send-url-to-firefox' uses this."
  :group 'vm-helpers
  :type '(choice (const :tag "None" nil)
		 file))

(defcustom vm-firefox-program-switches nil
  "*List of command line switches to pass to Mozilla Firefox."
  :group 'vm-helpers
  :type '(choice (const :tag "None" nil)
		 (repeat string)))

(defcustom vm-firefox-client-program "firefox"
  "*Name of program to use to issue requests to Mozilla Firefox.
`vm-mouse-send-url-to-firefox' uses this."
  :group 'vm-helpers
  :type '(choice (const :tag "None" nil)
		 file))

(defcustom vm-firefox-client-program-switches nil
  "*List of command line switches to pass to Mozilla Firefox client."
  ;; -remote is obsolete
  ;; https://developer.mozilla.org/en-US/docs/Mozilla/Command_Line_Options#Remote_Control
  :group 'vm-helpers
  :type '(choice (const :tag "None" nil) 
		 (repeat string)))

(defcustom vm-wget-program "wget"
  "*Name of program to use to run wget.
This is used to retrieve URLs."
  :group 'vm-helpers
  :type '(choice (const :tag "None" nil)
		 file))

(defcustom vm-w3m-program "w3m"
  "*Name of program to use to run w3m.
This is used to retrieve URLs."
  :group 'vm-helpers
  :type '(choice (const :tag "None" nil)
		 file))

(defcustom vm-fetch-program "fetch"
  "*Name of program to use to run fetch.
This is used to retrieve URLs.  Fetch is part of the standard
FreeBSD installation."
  :group 'vm-helpers
  :type '(choice (const :tag "None" nil)
		 file))

(defcustom vm-curl-program "curl"
  "*Name of program to use to run curl.
This is used to retrieve URLs."
  :group 'vm-helpers
  :type '(choice (const :tag "None" nil)
		 file))

(defcustom vm-lynx-program "lynx"
  "*Name of program to use to run lynx.
This is used to retrieve URLs."
  :group 'vm-helpers
  :type '(choice (const :tag "None" nil)
		 file))

(defcustom vm-grep-program "grep"
  "*Name of program to use to run grep.
This is used to count message separators in folders.
Set this to nil and VM will not use it."
  :group 'vm-helpers
  :type '(choice (const :tag "None" nil)
		 file))

(defcustom vm-stunnel-program
  (if (and (fboundp 'gnutls-available-p) (gnutls-available-p))
      nil
    "stunnel")
  "*Name of program to use to run stunnel.
This is used to make SSL connections to POP and IMAP servers that
support SSL.  If this is set to nil, VM will attempt to use the
built-in SSL functionality of Emacs.  Use this setting only if you
know that your version of Emacs has SSL capability, or any attempt to 
contact the server will likely hang.

If you do use an stunnel program, then see also the related variables
`vm-stunnel-program-switches' and
`vm-stunnel-program-additional-configuration-file'."
  :group 'vm-helpers
  :type '(choice (const :tag "None" nil)
		 file))

(defcustom vm-stunnel-program-switches nil
  "*List of command line switches to pass to stunnel.
Leave this set to nil unless you understand how VM uses stunnel
and know that you need to change something to get stunnel working.
This variable is ignored if you're running stunnel version 4 or
later versions, since those versions of stunnel are configurable
only with a configuration file."
  :group 'vm-helpers
  :type '(choice (const :tag "None" nil)
		 (repeat string)))

(defcustom vm-stunnel-wants-configuration-file t
  "Non-nil if stunnel version is controlled by a configuration file.
This is needed for stunnel version 4 or later.
Older versions of stunnel used command line arguments instead."
  :group 'vm-helpers
  :type '(choice (const :tag "Yes" t)
		 (const :tag "No" nil)
		 (const :tag "Automatically determine" unknown)))

(defcustom vm-stunnel-program-additional-configuration-file nil
  "*Name of a configuration file to append to the config file VM creates
when using stunnel version 4 or later.  Leave this set to nil
unless you understand how VM uses stunnel and know that you need
to change something to get stunnel working.

For stunnel version 4 and beyond stunnel relies on a configuration
file to tell it what to do.  VM builds the necessary configuration
file for each instance of stunnel that it runs.  If you have extra
configuration options you want stunnel to use, put them in a file
and set this variable to the name of that file.

This variable is ignored for stunnel versions prior to version 4 as VM
uses command line argument to control stunnel in those cases."
  :group 'vm-helpers
  :type '(choice (const :tag "None" nil)
		 (file :must-match t)))

(defcustom vm-stunnel-random-data-method 'generate
  "*Specifies what VM should do about sending the PRNG.
The stunnel program uses the OpenSSL library which requires a
certain amount of random data to seed its pseudo-random number
generator.  VM can generate this data using Emacs' random number
generator or it can rely on stunnel to find the data by itself
somehow.  Some systems have a /dev/urandom device that stunnel
can use.  Some system have a entropy gathering daemon that can be
tapped for random data.  If sufficient random data cannot be
found, the OpenSSL library will refuse to work and stunnel will
not be able to establish an SSL connection.

Setting `vm-stunnel-random-data-method' to the symbol `generate'
tells VM to generate the random data.

A nil value tells VM to do nothing and let stunnel find the data
if it can."
  :group 'vm-helpers
  :type '(choice (const :tag "Leave it to stunnel" nil)
		 (const generate)))

(defcustom vm-ssh-program "ssh"
  "*Name of program to use to run SSH.
This is used to build an SSH tunnel to remote POP and IMAP servers.
Set this to nil and VM will not use it."
  :group 'vm-helpers
  :type '(choice (const :tag "None" nil)
		 file))

(defcustom vm-ssh-program-switches nil
  "*List of command line switches to pass to SSH."
  :group 'vm-helpers
  :type '(choice (const :tag "None" nil)
		 (repeat string)))

(defcustom vm-ssh-remote-command "echo ready; sleep 15"
  "*Shell command to run to hold open the SSH connection.
This command must generate one line of output and then
sleep long enough for VM to open a port-forwarded connection.
The default should work on UNIX systems."
  :group 'vm-helpers
  :type '(string :tag "Shell command"))

(defcustom vm-uncompface-program (and (not (featurep 'xemacs))
				   (fboundp 'image-type-available-p)
				   (vm-locate-executable-file "uncompface"))
  "*Program used to convert X-Face data to Sun icon format.
Or if the program version is new enough, it will be called with
-X to produce XBM data.  This program is needed to support he
display of X-Faces under Emacs 21."
  :group 'vm-helpers
  :type '(choice (const :tag "None" nil)
		 file))

(defcustom vm-icontopbm-program (and (not (featurep 'xemacs))
				  (fboundp 'image-type-available-p)
				  (vm-locate-executable-file "icontopbm"))
  "*Program to convert Sun icon data to a PBM file.
This program is needed to support the display of X-Faces under
Emacs 21 if the uncompface program can't convert X-Face image
data to XBM data."
  :group 'vm-helpers
  :type '(choice (const :tag "None" nil)
		 file))

(defvar vm-uncompface-accepts-dash-x
  (and (not (featurep 'xemacs)) (fboundp 'image-type-available-p)
       (stringp vm-uncompface-program)
       (eq 0 (string-match "#define"
			   (shell-command-to-string
			    (format "%s -X" vm-uncompface-program)))))
  "Non-nil if the uncompface command accepts a -X argument.
This is only used for FSF Emacs currently.")

(defvaralias 'vm-tale-is-an-idiot 'vm-mail-check-recipient-format)
(defcustom vm-mail-check-recipient-format nil
  "Non-nil value causes `vm-mail-send' to check multi-line recipient
headers of outbound mail for lines that don't end with a
comma.  If such a line is found, an error is signaled and the
mail is not sent."
  :group 'vm-compose
  :type 'boolean)

(defcustom vm-dnd-protocol-alist
  '(("^file:///" . vm-dnd-attach-file)
    ("^file://"  . dnd-open-file)
    ("^file:"    . vm-dnd-attach-file))
  "The functions to call when a drag and drop into a message
composition buffer is done.
See `dnd-protocol-alist' for more information.  When nil, behave
as in other buffers."
  :group 'vm-compose
  :type '(choice (repeat (cons (regexp) (function)))
		 (const :tag "Behave as in other buffers" nil)))

(defun vm-octal (n)
  (let ((val 0) digit (expo 1))
    (while (> n 0)
      (setq digit (% n 10))
      (if (>= digit 8)
	  (error "invalid octal digit: %d" digit))
      (setq val (+ val (* digit expo))
	    n (/ n 10)
	    expo (* expo 8)))
    val ))

(defcustom vm-default-folder-permission-bits (vm-octal 600)
  "*Default UNIX permission bits for newly created folders."
  :group 'vm-folders
  :type 'integer)

(defcustom vm-coding-system-priorities nil ;'(iso-8859-1 iso-8859-15 utf-8)
  "*List of coding systems for VM to use, for outgoing mail, in order of
preference.

If you find that your outgoing mail is being encoded in `iso-2022-jp' and
you'd prefer something more widely used outside of Japan be used instead,
you could load the `latin-unity' and `un-define' libraries under XEmacs
21.4, and initialize this list to something like `(iso-8859-1 iso-8859-15
utf-8)'. "
  :group 'vm-compose
  :type '(choice (const nil)
		 (repeat :tag "Coding system" symbol)))

(defcustom vm-mime-ucs-list '(utf-8 iso-2022-jp ctext escape-quoted)
  "*List of coding systems that can encode all characters known to emacs."
  :group 'vm-mime
  :type '(repeat symbol))

(defcustom vm-drop-buffer-name-chars "[^ a-zA-Z0-9.,_\"'+-]"
  "*Regexp used to replace chars in composition buffer names.
If non-nil buffer names will be cleaned to avoid save problems.
If t, 8bit chars are replaced by a \"_\", if a string it should
be a regexp matching all chars to be replaced by a \"_\"."
  :group 'vm-compose
  :type '(choice (const :tag "Disabled" nil)
		 (regexp :tag "Enabled" "[^ a-zA-Z0-9.,_\"'+-]")
		 (regexp :tag "Custom regexp")))

(defconst vm-buffer-name-limit 80
  "*The limit for a generated buffer name.")

(defconst vm-maintainer-address "viewmail-bugs@nongnu.org"
  "Where to send VM bug reports.")

(defvar vm-use-v7-key-bindings nil
  "Retain all the optional key bindings of VM as per version 7.19.")

(defvar vm-mode-virtual-map
  (let ((map (make-sparse-keymap)))
    (define-key map "V" 'vm-visit-virtual-folder)
    (define-key map "C" 'vm-create-virtual-folder)
    (define-key map "T" 'vm-create-virtual-folder-of-threads)
    (define-key map "X" 'vm-apply-virtual-folder)
    (define-key map "A" 'vm-create-virtual-folder-same-author)
    (define-key map "R" 'vm-create-virtual-folder-same-recipient)
    (define-key map "S" 'vm-create-virtual-folder-same-subject)
    (define-key map "M" 'vm-toggle-virtual-mirror)

    (define-key map "a" 'vm-create-author-virtual-folder)
    (define-key map "r" 'vm-create-author-or-recipient-virtual-folder)
    (define-key map "d" 'vm-create-date-virtual-folder)
    (define-key map "l" 'vm-create-label-virtual-folder)
    (define-key map "s" 'vm-create-subject-virtual-folder)
    (define-key map "t" 'vm-create-text-virtual-folder)
    (define-key map "!" 'vm-create-flagged-virtual-folder)
    (define-key map "n" 'vm-create-new-virtual-folder)
    (define-key map "u" 'vm-create-unseen-virtual-folder)

    (define-key map "?" 'vm-virtual-help)
    map))

(defvar vm-mode-map
  (let ((map (make-keymap)))
    ;; FIXME: Do we need these vars?
    (defvar vm-mode-label-map (make-sparse-keymap))
    (defvar vm-mode-mark-map (make-sparse-keymap))
    (defvar vm-mode-window-map (make-sparse-keymap))
    (defvar vm-mode-pipe-map (make-sparse-keymap))
    ;; unneeded now that VM buffers all have buffer-read-only == t. 
    ;; but no harm in suppressing.  USR, 2011-04-27
    (suppress-keymap map)
    (define-key map "h" 'vm-summarize)
    (define-key map "H" 'vm-folders-summarize)
    (define-key map "\M-n" 'vm-next-unread-message)
    (define-key map "\M-p" 'vm-previous-unread-message)
    (define-key map "n" 'vm-next-message)
    (define-key map "p" 'vm-previous-message)
    (define-key map "N" 'vm-next-message-no-skip)
    (define-key map "P" 'vm-previous-message-no-skip)
    (define-key map "\C-\M-n" 'vm-move-message-forward)
    (define-key map "\C-\M-p" 'vm-move-message-backward)
    (define-key map "\t" 'vm-goto-message-last-seen)
    (define-key map "\r" 'vm-goto-message)
    (define-key map "\M-g" 'vm-optional-key)
    (define-key map "^" 'vm-goto-parent-message)
    (define-key map "t" 'vm-expose-hidden-headers)
    (define-key map " " 'vm-scroll-forward)
    (define-key map "b" 'vm-optional-key)
    (define-key map "\C-?" 'vm-scroll-backward)
    (define-key map [delete] 'vm-scroll-backward)
    (define-key map [backspace] 'vm-scroll-backward)
    (define-key map "D" 'vm-decode-mime-message)
    (define-key map "d" 'vm-delete-message)
    (define-key map "\C-d" 'vm-delete-message-backward)
    (define-key map "u" 'vm-undelete-message)
    (define-key map "U" 'vm-mark-message-unread)
    (define-key map "." 'vm-mark-message-read)
    (define-key map "e" 'vm-optional-key)
    (define-key map "\C-c\C-e" 'vm-edit-message)
    (define-key map "a" 'vm-optional-key)
    (define-key map "j" 'vm-discard-cached-data)
    (define-key map "k" 'vm-kill-subject)
    (define-key map "f" 'vm-followup)
    (define-key map "F" 'vm-followup-include-text)
    (define-key map "r" 'vm-reply)
    (define-key map "R" 'vm-reply-include-text)
    (define-key map "\M-r" 'vm-resend-bounced-message)
    (define-key map "B" 'vm-resend-message)
    (define-key map "z" 'vm-forward-message)
    (define-key map "Z" 'vm-forward-message-plain)
    (define-key map "c" 'vm-continue-composing-message)
    (define-key map "@" 'vm-send-digest)
    (define-key map "*" 'vm-optional-key)
    (define-key map "m" 'vm-mail-from-folder)
    (define-key map "g" 'vm-get-new-mail)
    (define-key map "G" 'vm-sort-messages)
    (define-key map "v" 'vm-visit-folder)
    (define-key map "s" 'vm-save-message)
    (define-key map "w" 'vm-optional-key)
    (define-key map "A" 'vm-auto-archive-messages)
    (define-key map "S" 'vm-save-folder)
    ;; these two key bindings are experimental
    (define-key map "o" 'vm-load-message)
    (define-key map "O" 'vm-unload-message)
    (define-key map "|" vm-mode-pipe-map)
    (define-key vm-mode-pipe-map "|" 'vm-pipe-message-to-command)
    (define-key vm-mode-pipe-map "d" 'vm-pipe-message-to-command-discard-output)
    (define-key vm-mode-pipe-map "s" 'vm-pipe-messages-to-command)
    (define-key vm-mode-pipe-map "n" 'vm-pipe-messages-to-command-discard-output)
    (define-key map "#" (make-sparse-keymap))
    (define-key map "##" (make-sparse-keymap))
    (define-key map "###" 'vm-expunge-folder)
    (cond ((fboundp 'set-keymap-prompt)
	   (set-keymap-prompt (lookup-key map "#")
			       "(Type # twice more to expunge)")
	   (set-keymap-prompt (lookup-key map "##")
			       "(Type # once more to expunge)")))
    (define-key map "q" 'vm-quit)
    (define-key map "x" 'vm-quit-no-change)
    (define-key map "i" 'vm-optional-key)
    (define-key map "?" 'vm-help)
    (define-key map "\C-_" 'vm-undo)
    (define-key map [(control /)] 'vm-undo)
    (define-key map "\C-xu" 'vm-undo)
    (define-key map "!" 'vm-optional-key)
    (define-key map "[" 'vm-move-to-previous-button)
    (define-key map "]" 'vm-move-to-next-button)
    (define-key map "\M-s" 'vm-isearch-forward)
    (define-key map "=" 'vm-optional-key)
    (define-key map "L" 'vm-optional-key)
    (define-key map "\M-l" 'vm-optional-key)
    (define-key map "l" vm-mode-label-map)
    (define-key vm-mode-label-map "a" 'vm-add-message-labels)
    (define-key vm-mode-label-map "e" 'vm-add-existing-message-labels)
    (define-key vm-mode-label-map "d" 'vm-delete-message-labels)
    (define-key map "V" vm-mode-virtual-map)
    (define-key map "M" vm-mode-mark-map)
    (define-key vm-mode-mark-map "N" 'vm-next-command-uses-marks)
    (define-key vm-mode-mark-map "n" 'vm-next-command-uses-marks)
    (define-key vm-mode-mark-map "M" 'vm-mark-message)
    (define-key vm-mode-mark-map "U" 'vm-unmark-message)
    (define-key vm-mode-mark-map "m" 'vm-mark-all-messages)
    (define-key vm-mode-mark-map "u" 'vm-clear-all-marks)
    (define-key vm-mode-mark-map "C" 'vm-mark-messages-by-selector)
    (define-key vm-mode-mark-map "c" 'vm-unmark-messages-by-selector)
    (define-key vm-mode-mark-map "T" 'vm-mark-thread-subtree)
    (define-key vm-mode-mark-map "t" 'vm-unmark-thread-subtree)
    (define-key vm-mode-mark-map "S" 'vm-mark-messages-same-subject)
    (define-key vm-mode-mark-map "s" 'vm-unmark-messages-same-subject)
    (define-key vm-mode-mark-map "A" 'vm-mark-messages-same-author)
    (define-key vm-mode-mark-map "a" 'vm-unmark-messages-same-author)
    (define-key vm-mode-mark-map "R" 'vm-mark-summary-region)
    (define-key vm-mode-mark-map "r" 'vm-unmark-summary-region)
    (define-key vm-mode-mark-map "V" 'vm-toggle-all-marks)
    (define-key vm-mode-mark-map "X" 'vm-mark-messages-by-virtual-folder)
    (define-key vm-mode-mark-map "x" 'vm-unmark-messages-by-virtual-folder)
    (define-key vm-mode-mark-map "?" 'vm-mark-help)
    (define-key map "W" vm-mode-window-map)
    (define-key vm-mode-window-map "W" 'vm-apply-window-configuration)
    (define-key vm-mode-window-map "S" 'vm-save-window-configuration)
    (define-key vm-mode-window-map "D" 'vm-delete-window-configuration)
    (define-key vm-mode-window-map "?" 'vm-window-help)
    (define-key map "\C-t" 'vm-toggle-threads-display)
    (define-key map "\C-x\C-s" 'vm-save-folder)
    (define-key map "\C-x\C-w" 'vm-write-file)
    (define-key map "\C-x\C-q" 'vm-toggle-read-only)
    (define-key map "%" 'vm-optional-key)
    (define-key map "\M-C" 'vm-show-copying-restrictions)
    (define-key map "\M-W" 'vm-show-no-warranty)
    (define-key map "\C-c\C-s" 'vm-save-all-attachments)
    (define-key map "\C-c\C-d" 'vm-delete-all-attachments)
    (define-key map "T" 'vm-toggle-thread)
    (define-key map "E" 'vm-expand-all-threads)
    (define-key map "C" 'vm-collapse-all-threads)
    (define-key map "K" 'vm-kill-thread-subtree)
    ;; suppress-keymap provides these, but now that we don't use
    ;; suppress-keymap anymore...
    (define-key map "0" 'digit-argument)
    (define-key map "1" 'digit-argument)
    (define-key map "2" 'digit-argument)
    (define-key map "3" 'digit-argument)
    (define-key map "4" 'digit-argument)
    (define-key map "5" 'digit-argument)
    (define-key map "6" 'digit-argument)
    (define-key map "7" 'digit-argument)
    (define-key map "8" 'digit-argument)
    (define-key map "9" 'digit-argument)
    (define-key map "-" 'negative-argument)
    (cond ((fboundp 'set-keymap-name)
           (set-keymap-name map 'vm-mode-map)
           (set-keymap-name (lookup-key map "l")
                            "VM mode message labels map")
           (set-keymap-name (lookup-key map "V")
                            "VM mode virtual folders map")
           (set-keymap-name (lookup-key map "M")
                            "VM mode message marks map")
           (set-keymap-name (lookup-key map "W")
                            "VM mode window configuration map")
           (set-keymap-name (lookup-key map "|")
                            "VM mode pipe-to-application map")))
    map )
  "Keymap for VM mode.  See also the following subsidiary keymaps:
`vm-mode-label-map'    VM mode message labels map  (`l')
`vm-mode-virtual-map'  VM mode virtual folders map (`V')
`vm-mode-mark-map'     VM mode message marking map (`M')
`vm-mode-window-map'   VM mode window configuration map (`W')
`vm-mode-pipe-map'     VM mode pipe-to-application map (`|')
")

(defun vm-v8-key-bindings ()
  "Install optional key bindings for VM modes, as per versions 8.2.0
and up."
  (interactive)
  (define-key vm-mode-map "!" 'vm-toggle-flag-message)
  (define-key vm-mode-map "<" 'vm-promote-subthread)
  (define-key vm-mode-map ">" 'vm-demote-subthread)
  (define-key vm-mode-virtual-map "O" 'vm-virtual-omit-message)
  (define-key vm-mode-virtual-map "U" 'vm-virtual-update-folders)
  (define-key vm-mode-virtual-map "D" 'vm-virtual-auto-delete-message)
  ;; (define-key vm-mode-virtual-map "S" 'vm-virtual-save-message)
  ;; (define-key vm-mode-virtual-map "A" 'vm-virtual-auto-archive-messages)
  (define-key vm-mode-virtual-map "?" 'vm-virtual-check-selector-interactive)
  )
(defalias 'vm-current-key-bindings 'vm-v8-key-bindings)

(defun vm-v7-key-bindings ()
  "Install optional key bindings for VM modes, as per version 7.19.

These key bindings are considered optional.  They can be rebound by
the users or bound to other functions in future versions of VM."
  (interactive)
  (define-key vm-mode-map "<" 'vm-beginning-of-message) ; infrequent
  (define-key vm-mode-map ">" 'vm-end-of-message) ; infrequent
  (define-key vm-mode-map "b" 'vm-scroll-backward) ; redundant, use <BSP>
  (define-key vm-mode-map "e" 'vm-edit-message) ; infrequent and dangerous
  (define-key vm-mode-map "w" 'vm-save-message-sans-headers) ; infrequent
  (define-key vm-mode-map "a" 'vm-set-message-attributes) ; infrequent
  (define-key vm-mode-map "i" 'vm-iconify-frame) ; redundant, C-x C-z
  (define-key vm-mode-map "*" 'vm-burst-digest) ; specialized
  (define-key vm-mode-map "!" 'shell-command) ; Emacs has a key binding
  (define-key vm-mode-map  "=" 'vm-summarize) ; redundant, use `h'
  (define-key vm-mode-map "L" 'vm-load-init-file) ; infrequent
  (define-key vm-mode-map "\M-l" 'vm-edit-init-file) ; infrequent
  (define-key vm-mode-map "%" 'vm-change-folder-type) ; infrequent
  (define-key vm-mode-map "\M-g" 'vm-goto-message)    ; redundant, use <RET>
  )
(defalias 'vm-legacy-key-bindings 'vm-v7-key-bindings)

(defun vm-optional-key ()
  "Certain VM keys have optional bindings in VM, which differ from
version to version.  Include \"(vm-legacy-key-bindings)\" in your
`vm-preferences-file' in order to bind them as in version 7.19.  For
other possibilities, see the NEWS file of VM."
  (interactive)
  (error "This key has an optional binding in VM.  Do C-h k for help."))

(defcustom vm-summary-enable-thread-folding nil
  "*If non-nil, enables folding of threads in VM summary
windows."
  :group 'vm-summary
  :type 'boolean)

(defcustom vm-summary-show-thread-count t
  "*If non-nil, thread folding displays the count of messages in
a thread along with the message number of the thread root.  Note
that this takes up 3 extra characters in each summary line."
  :group 'vm-summary
  :type 'boolean)

(defcustom vm-summary-thread-folding-on-motion nil
  "*If non-nil and thread folding is enabled, invoking
vm-next/previous-message-no-skip (`N' or `P' respectively)
will expand a thread upon moving into the thread and collapse it when 
you move out of the thread."
  :group 'vm-summary
  :type 'boolean)

(defcustom vm-summary-visible '((new))
  "*List of selectors identifying messages that should be visible in
folded thread summaries, i.e., such messages remain visible even if
their threads are shown collapsed.  The selectors are the same as
those used in `vm-virtual-folder-alist'."
  :group 'vm-summary
  :type '(repeat sexp))

(defcustom vm-enable-thread-operations nil
  "*If non-nil, VM operations on root messages of collapsed
threads will apply to all the messages in the threads.

\"Operations\" in this context include deleting, saving, setting
attributes, adding/deleting labels etc.

If the variable is set to t then thread operations are always
carried out.  If it is set to `ask', then the user is asked for
confirmation whether the operation should apply to all the
messages in the thread.  This can be overridden by invoking the
operation with a prefix argument using `C-u' and no questions will be
asked."
  :group 'vm-summary
  :type '(choice (const t) 
		 (const ask) 
		 (const nil)))

(defvar vm-summary-threads-collapsed t
  "If non-nil, indicates that threads should be
folded (collapsed) in VM summary windows.")
(make-variable-buffer-local 'vm-summary-threads-collapsed)

(defvar vm-summary-mode-map vm-mode-map
  "Keymap for VM Summary mode")

(defvar vm-folders-summary-mode-map vm-mode-map
  "Keymap for VM Folders Summary mode")

(defvar vm-mail-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "\C-c\C-v" vm-mode-map)
    (define-key map "\C-c\C-p" 'vm-preview-composition)
    (define-key map "\C-c\C-d" 'vm-postpone-message)
    (define-key map "\C-c\C-e" 'vm-mime-encode-composition)
    (define-key map "\C-c\C-a" 'vm-attach-file)
    (define-key map "\C-c\C-b" 'vm-attach-buffer)
    (define-key map "\C-c\C-m" 'vm-attach-message)
    (define-key map "\C-c\C-y" 'vm-yank-message)
    (define-key map "\C-c\C-s" 'vm-mail-send)
    (define-key map "\C-c\C-c" 'vm-mail-send-and-exit)
    ;; The following is a temporary binding for Mac/NextStep
    ;; It should be removed when dnd-protocol-alist is implemented
    (define-key map [ns-drag-file] 'vm-ns-attach-file)
    (cond ((fboundp 'set-keymap-name)
	   (set-keymap-name map 'vm-mail-mode-map)))
    map )
  "Keymap for VM Mail mode buffers.
Its parent keymap is mail-mode-map.")

(defvar vm-edit-message-map
  (let ((map (make-sparse-keymap)))
    (define-key map "\C-c\C-v" vm-mode-map)
    (define-key map "\C-c\e" 'vm-edit-message-end)
    (define-key map "\C-c\C-c" 'vm-edit-message-end)
    (define-key map "\C-c\C-]" 'vm-edit-message-abort)
    (cond ((fboundp 'set-keymap-name)
	   (set-keymap-name map 'vm-edit-message-map)))
    map )
  "Keymap for the buffers created by VM's `vm-edit-message' command.")

(defvar vm-mime-reader-map
  (let ((map (make-sparse-keymap)))
    (define-key map "\r" 'vm-mime-run-display-function-at-point)
    (define-key map "$\r" 'vm-mime-reader-map-display-using-default)
    (define-key map "$e" 'vm-mime-reader-map-display-using-external-viewer)
    (define-key map "$c" 'vm-mime-reader-map-convert-then-display)
    (define-key map "$v" 'vm-mime-reader-map-display-object-as-type)
    (define-key map "$w" 'vm-mime-reader-map-save-file)
    (define-key map "$s" 'vm-mime-reader-map-save-message)
    (define-key map "$p" 'vm-mime-reader-map-pipe-to-printer)
    (define-key map "$|" 'vm-mime-reader-map-pipe-to-command)
    (define-key map "$a" 'vm-mime-reader-map-attach-to-composition)
    (define-key map "$d" 'vm-delete-mime-object)
    (cond ((featurep 'xemacs)
	   (define-key map 'button3 'vm-menu-popup-mime-dispose-menu)))
    (cond ((fboundp 'set-keymap-name)
	   (set-keymap-name map 'vm-mime-reader-map)))
    map )
  "Keymap for the MIME buttons in VM folder buffers.")

(defvar vm-folder-history nil
  "List of folders visited this Emacs session.")

;; Do we need this variable in addition to the above?
(defvar vm-switch-to-folder-history nil
  "List of folders used with `vm-switch-to-folder'.")

;; for sixth arg of read-file-name in early version of Emacs 21.
(defun vm-folder-history (&rest _ignored) t)

;; internal vars
(defvar vm-skip-collapsed-sub-threads t)
(defvar vm-folder-type nil)
(make-variable-buffer-local 'vm-folder-type)
(defvar vm-folder-access-method nil
  "Indicates how a VM folder is accessed: `pop' for POP folders, `imap'
for IMAP folders and nil for local folders.")
(make-variable-buffer-local 'vm-folder-access-method)

(defvar vm-folder-access-data nil
  "Holds a vector of data about the mailbox on a mail server that this
folder is meant to access.")
(make-variable-buffer-local 'vm-folder-access-data)
(defconst vm-folder-pop-access-data-length 2)
(defconst vm-folder-imap-access-data-length 13)

(defvar vm-message-list nil)
(make-variable-buffer-local 'vm-message-list)
(defvar vm-fetched-messages nil)
(make-variable-buffer-local 'vm-fetched-messages)
(defvar vm-fetched-message-count 0)
(make-variable-buffer-local 'vm-fetched-message-count)

(defvar vm-virtual-folder-definition nil
  "The virtual folder definition of the folder in the current buffer,
which is normally an entry in `vm-virtual-folder-alist'.  It is of the
form: 
  (VIRTUAL-FOLDER-NAME
    ((FOLDER ...)
     (SELECTOR [ARG ...]) ...) 
    ... )
A FOLDER entry can be
- the name of a local folder, or
- an s-expression which, when evaluated, yields a folder buffer loaded
in VM." )
(make-variable-buffer-local 'vm-virtual-folder-definition)

(defvar vm-virtual-buffers nil)
(make-variable-buffer-local 'vm-virtual-buffers)
(defvar vm-real-buffers nil)
(make-variable-buffer-local 'vm-real-buffers)
(defvar vm-component-buffers nil
  "An a-list of folder buffers that make up the components of the current
virtual folder, and a flag indicating whether they are being visited
as a part of visiting this virtual folder.  All such folders will be
closed when the virtual folder is closed.")
(make-variable-buffer-local 'vm-component-buffers)

(defvar vm-message-pointer nil
  "A pointer into the `vm-message-list' indicating the position of the
current message.")
(make-variable-buffer-local 'vm-message-pointer)
(defvar vm-message-order-changed nil)
(make-variable-buffer-local 'vm-message-order-changed)
(defvar vm-message-order-header-present nil)
(make-variable-buffer-local 'vm-message-order-header-present)
(defvar vm-last-message-pointer nil
  "A pointer into the `vm-message-list' indicating the position of the
message last viewed.")
(make-variable-buffer-local 'vm-last-message-pointer)
(defvar vm-folders-summary-hash nil)
(defvar vm-folders-summary-spool-hash nil)
(defvar vm-folders-summary-folder-hash nil)
(defvar vm-folders-summary-buffer nil)
(defvar vm-mail-buffer nil
  "The folder buffer of the current buffer.")
(make-variable-buffer-local 'vm-mail-buffer)
(defvar vm-fetch-buffer nil
  "The fetch buffer, where message bodies are fetched, for the current
folder.  (Not in use.)")
(make-variable-buffer-local 'vm-fetch-buffer)
(defvar vm-presentation-buffer nil
  "The message presentation buffer for the current folder.")
(make-variable-buffer-local 'vm-presentation-buffer)
(defvar vm-presentation-buffer-handle nil
  "The message presentation buffer for the current folder.")
(make-variable-buffer-local 'vm-presentation-buffer-handle)
(defvar vm-mime-decoded nil
  "The MIME decoding state of the current folder."
  ;; What are the decoding states? nil, 'decoded or 'buttons? - USR, 2012-05-04
  )
(make-variable-buffer-local 'vm-mime-decoded)
(defvar vm-summary-buffer nil
  "The summary buffer for the current folder.")
(make-variable-buffer-local 'vm-summary-buffer)
(defvar vm-user-interaction-buffer nil
  "The buffer in which the current VM command was invoked.")
(defvar vm-summary-pointer nil)
(make-variable-buffer-local 'vm-summary-pointer)
(defvar vm-system-state nil)
(make-variable-buffer-local 'vm-system-state)
(defvar vm-undo-record-list nil
  "The list of undo records for the folder.")
(make-variable-buffer-local 'vm-undo-record-list)
(defvar vm-saved-undo-record-list nil
  "A saved version of the undo record list used in `vm-toggle-virtual-mirror'.")
(make-variable-buffer-local 'vm-saved-undo-record-list)
(defvar vm-undo-record-pointer nil
  "A pointer into the `vm-undo-record-list'.")
(make-variable-buffer-local 'vm-undo-record-pointer)
(defvar vm-last-save-folder nil)
(make-variable-buffer-local 'vm-last-save-folder)
(defvar vm-last-save-imap-folder nil)
(make-variable-buffer-local 'vm-last-save-imap-folder)
(defvar vm-last-written-file nil)
(make-variable-buffer-local 'vm-last-written-file)
(defvar vm-last-visit-folder nil)
(defvar vm-last-visit-pop-folder nil)
(defvar vm-last-visit-imap-folder nil)
(defvar vm-last-visit-imap-account nil)
(defvar vm-last-pipe-command nil)
(make-variable-buffer-local 'vm-last-pipe-command)
(defvar vm-messages-not-on-disk 0
  "Number of messages in the folder that are not on the disk copy
of the folder.  This is the count from the user's point of view but
may include some messages that are really on disk.")
(make-variable-buffer-local 'vm-messages-not-on-disk)
(defvar vm-totals nil)
(make-variable-buffer-local 'vm-totals)
(defvar vm-modification-counter 0)
(make-variable-buffer-local 'vm-modification-counter)
(defvar vm-flushed-modification-counter nil)
(make-variable-buffer-local 'vm-flushed-modification-counter)
(defvar vm-tempfile-counter 0)
(defvar vm-messages-needing-summary-update nil)
(defvar vm-buffers-needing-display-update nil
  "Obarray containing the names of VM buffers that need display
update.")
(defvar vm-buffers-needing-undo-boundaries nil
  "Obarray containing the names of VM buffers that need undo
boundaries.") 				; whatever they are!
(defvar vm-numbering-redo-start-point nil
  "A pointer into `vm-message-list' indicating the position from which
messages may need to be renumbered.")
(make-variable-buffer-local 'vm-numbering-redo-start-point)
(defvar vm-numbering-redo-end-point nil
  "A pointer into `vm-message-list' indicating the stopping point
for any needed message renumbering.")
(make-variable-buffer-local 'vm-numbering-redo-end-point)
(defvar vm-summary-redo-start-point nil
  "A pointer into `vm-message-list' indicating the position from which
summary lines may need to be redisplayed.")
(make-variable-buffer-local 'vm-summary-redo-start-point)
(defvar vm-need-summary-pointer-update nil
  "A boolean indicating whether the summary pointer for the current
folder needs to be updated.")
(make-variable-buffer-local 'vm-need-summary-pointer-update)
(defvar vm-thread-obarray 'bonk)
(make-variable-buffer-local 'vm-thread-obarray)
(defvar vm-thread-subject-obarray 'bonk)
(make-variable-buffer-local 'vm-thread-subject-obarray)
(defvar vm-label-obarray nil)
(make-variable-buffer-local 'vm-label-obarray)
(defvar vm-block-new-mail nil)
(make-variable-buffer-local 'vm-block-new-mail)
(defvar vm-global-block-new-mail nil)
(defvar vm-saved-buffer-modified-p nil)
(make-variable-buffer-local 'vm-saved-buffer-modified-p)
(defvar vm-kept-mail-buffers nil)
(defvar vm-inhibit-write-file-hook nil)
;; used to choose between the default and
;; mail-extract-address-components but I don't see the utility of
;; it anymore.  It tries to be too smart.
;;(defvar vm-chop-full-name-function 'vm-choose-chop-full-name-function)
(defvar vm-chop-full-name-function 'vm-default-chop-full-name)
(defvar vm-session-beginning t)
(defvar vm-init-file-loaded nil)
(defvar vm-window-configurations nil)
(defvar vm-window-configuration nil)
(defvar vm-message-id-number 0)
(defconst vm-spool-directory
  (or (and (boundp 'rmail-spool-directory) rmail-spool-directory)
      "/usr/spool/mail/"))
(defconst vm-content-length-search-regexp "^Content-Length:.*\n\\|\\(\n\n\\)")
(defconst vm-content-length-header "Content-Length:")
(defconst vm-references-header-regexp
  "^References:\\(.*\n\\([ \t].*\n\\)*\\)")
(defconst vm-attributes-header-regexp
  "^X-VM-\\(Attributes\\|v5-Data\\):\\(.*\n\\([ \t].*\n\\)*\\)")
(defconst vm-attributes-header "X-VM-v5-Data:")
(defconst vm-message-order-header-regexp "^X-VM-Message-Order:")
(defconst vm-message-order-header "X-VM-Message-Order:")
(defconst vm-bookmark-header-regexp "^X-VM-Bookmark:")
(defconst vm-bookmark-header "X-VM-Bookmark:")
(defconst vm-pop-retrieved-header-regexp "^X-VM-POP-Retrieved:")
(defconst vm-pop-retrieved-header "X-VM-POP-Retrieved:")
(defconst vm-imap-retrieved-header-regexp "^X-VM-IMAP-Retrieved:")
(defconst vm-imap-retrieved-header "X-VM-IMAP-Retrieved:")
(defconst vm-external-storage-header-regexp "^X-VM-Storage:")
(defconst vm-external-storage-header "X-VM-Storage:")
(defconst vm-last-modified-header-regexp "^X-VM-Last-Modified:")
(defconst vm-last-modified-header "X-VM-Last-Modified:")
(defconst vm-summary-header-regexp "^X-VM-Summary-Format:")
(defconst vm-summary-header "X-VM-Summary-Format:")
(defconst vm-vheader-header-regexp "^X-VM-VHeader:")
(defconst vm-vheader-header "X-VM-VHeader:")
(defconst vm-labels-header-regexp "^X-VM-Labels:")
(defconst vm-labels-header "X-VM-Labels:")
(defconst vm-berkeley-mail-status-header "Status: ")
(defconst vm-berkeley-mail-status-header-regexp "^Status: \\(..?\\)\n")
(defconst vm-internal-unforwarded-header-regexp
  "\\(X-VM-\\|X-Mozilla-\\|Status:\\|Content-Length:\\)")
(defvar vm-matched-header-vector (make-vector 6 nil))
(defconst vm-supported-folder-types
  '("From_" "BellFrom_" "From_-with-Content-Length" "mmdf" "babyl"))
(defconst vm-supported-window-configurations
  '(
    ("default")
    ("startup")
    ("quitting")
    ("composing-message")
    ("editing-message")
    ("marking-message")
    ("reading-message")
    ("searching-message")
    ("vm")
    ("vm-add-message-labels")
    ("vm-apply-virtual-folder")
    ("vm-auto-archive-messages")
    ("vm-beginning-of-message")
    ("vm-burst-digest")
    ("vm-burst-mime-digest")
    ("vm-burst-rfc1153-digest")
    ("vm-burst-rfc934-digest")
    ("vm-change-folder-type")
    ("vm-clear-all-marks")
    ("vm-continue-composing-message")
    ("vm-create-virtual-folder")
    ("vm-create-virtual-folder-same-author")
    ("vm-create-virtual-folder-same-subject")
    ("vm-decode-mime-message")
    ("vm-delete-duplicate-messages")
    ("vm-delete-message")
    ("vm-delete-message-backward")
    ("vm-delete-message-labels")
    ("vm-delete-mime-object")
    ("vm-discard-cached-data")
    ("vm-edit-message")
    ("vm-edit-message-abort")
    ("vm-edit-message-end")
    ("vm-edit-message-other-frame")
    ("vm-end-of-message")
    ("vm-expose-hidden-headers")
    ("vm-expunge-folder")
    ("vm-expunge-imap-messages")
    ("vm-expunge-pop-messages")
    ("vm-folders-summarize")
    ("vm-followup")
    ("vm-followup-include-text")
    ("vm-followup-include-text-other-frame")
    ("vm-followup-other-frame")
    ("vm-forward-message")
    ("vm-forward-message-encapsulated")
    ("vm-forward-message-all-headers")
    ("vm-forward-message-all-headers-other-frame")
    ("vm-forward-message-other-frame")
    ("vm-forward-message-encapsulated-other-frame")
    ("vm-get-new-mail")
    ("vm-goto-message")
    ("vm-goto-message-last-seen")
    ("vm-goto-parent-message")
    ("vm-help")
    ("vm-isearch-forward")
    ("vm-kill-subject")
    ("vm-load-init-file")
    ("vm-mail")
    ("vm-mail-other-frame")
    ("vm-mail-other-window")
    ("vm-mail-send")
    ("vm-mail-send-and-exit")
    ("vm-mark-all-messages")
    ("vm-mark-help")
    ("vm-mark-messages-by-selector")
    ("vm-mark-messages-by-virtual-folder")
    ("vm-mark-message")
    ("vm-mark-messages-same-author")
    ("vm-mark-messages-same-subject")
    ("vm-mark-summary-region")
    ("vm-mark-thread-subtree")
    ("vm-attach-buffer")
    ("vm-attach-file")
    ("vm-attach-message")
    ("vm-attach-mime-file")
    ("vm-attach-object-to-composition")
    ("vm-attach-message-to-composition")
    ("vm-mode")
    ("vm-move-message-backward")
    ("vm-move-message-backward-physically")
    ("vm-move-message-forward")
    ("vm-move-message-forward-physically")
    ("vm-move-to-previous-button")
    ("vm-move-to-next-button")
    ("vm-next-command-uses-marks")
    ("vm-next-message")
    ("vm-next-message-no-skip")
    ("vm-next-message-no-skip")
    ("vm-next-message-same-subject")
    ("vm-next-unread-message")
    ("vm-other-frame")
    ("vm-other-window")
    ("vm-pipe-message-to-command")
    ("vm-previous-message")
    ("vm-previous-message-no-skip")
    ("vm-previous-message-no-skip")
    ("vm-previous-message-same-subject")
    ("vm-previous-unread-message")
    ("vm-quit")
    ("vm-quit-just-bury")
    ("vm-quit-just-iconify")
    ("vm-quit-no-expunge")
    ("vm-quit-no-change")
    ("vm-reply")
    ("vm-reply-include-text")
    ("vm-reply-include-text-other-frame")
    ("vm-reply-other-frame")
    ("vm-resend-bounced-message")
    ("vm-resend-bounced-message-other-frame")
    ("vm-resend-message")
    ("vm-resend-message-other-frame")
    ("vm-save-and-expunge-folder")
    ("vm-save-buffer")
    ("vm-save-folder")
    ("vm-save-message")
    ("vm-save-message-sans-headers")
    ("vm-save-message-to-imap-folder")
    ("vm-scroll-backward")
    ("vm-scroll-backward-one-line")
    ("vm-scroll-forward")
    ("vm-scroll-forward-one-line")
    ("vm-send-digest")
    ("vm-send-digest-other-frame")
    ("vm-send-mime-digest")
    ("vm-send-mime-digest-other-frame")
    ("vm-send-rfc1153-digest")
    ("vm-send-rfc1153-digest-other-frame")
    ("vm-send-rfc934-digest")
    ("vm-send-rfc934-digest-other-frame")
    ("vm-set-message-attributes")
    ("vm-show-copying-restrictions")
    ("vm-show-no-warranty")
    ("vm-sort-messages")
    ("vm-submit-bug-report")
    ("vm-summarize")
    ("vm-summarize-other-frame")
    ("vm-toggle-all-marks")
    ("vm-toggle-read-only")
    ("vm-toggle-threads-display")
    ("vm-undelete-message")
    ("vm-undo")
    ("vm-unmark-messages-by-selector")
    ("vm-unmark-messages-by-virtual-folder")
    ("vm-unmark-message")
    ("vm-unmark-messages-same-author")
    ("vm-unmark-messages-same-subject")
    ("vm-unmark-summary-region")
    ("vm-unmark-thread-subtree")
    ("vm-mark-message-unread")
    ("vm-mark-message-read")
    ("vm-virtual-help")
    ("vm-visit-folder")
    ("vm-visit-folder-other-frame")
    ("vm-visit-folder-other-window")
    ("vm-visit-imap-folder")
    ("vm-visit-imap-folder-other-frame")
    ("vm-visit-imap-folder-other-window")
    ("vm-visit-pop-folder")
    ("vm-visit-pop-folder-other-frame")
    ("vm-visit-pop-folder-other-window")
    ("vm-visit-virtual-folder")
    ("vm-visit-virtual-folder-other-frame")
    ("vm-visit-virtual-folder-other-window")
    ("vm-write-file")
    ("vm-yank-message")
    ("vm-yank-message-other-folder")
))

(defconst vm-vs-attachment-regexp "^Content-Disposition: attachment"
  "Regexp used to detect attachments in a message.")

(defvar vm-spam-words nil
  "A list of words often contained in spam messages.")

(defvar vm-spam-words-regexp nil
  "A regexp matching those words in `vm-spam-words'.")

(defcustom vm-spam-words-file
  (expand-file-name "~/.spam-words")
  "A file storing a list of words contained in spam messages."
  :group 'vm-folders
  :type 'file)

(defvaralias 'vm-vs-spam-score-headers
  'vm-spam-score-headers)

(defcustom vm-spam-score-headers
  '(("X-Spam-Score:"  "[-+]?[0-9]*\\.?[0-9]+"  string-to-number)
    ("X-Spam-Status:" "[-+]?[0-9]*\\.?[0-9]+" string-to-number)
    ("X-Spam-Level:"  "\\*+"     length))
  "The value should be a list of lists, with each sublist of the form

     (HEADER-REGEXP SCORE-REGEXP SCORE-FN)

- HEADER-REGEXP is a regular expression matching the spam score
header line in email messages,

- SCORE-REGEXP is a regular expression matching the score, and

- SCORE-FN is a function that converts the score string into a number."
  :group 'vm-folders
  :type '(repeat (list (string :tag "Header regexp")
                       (regexp :tag "Regexp matching the spam-score")
                       (function :tag "Function to convert the spam-score string to a number"))))

(defvar vm-supported-sort-keys
  '("date" "reversed-date"
    "activity" "reversed-activity"
    "author" "reversed-author"
    "full-name" "reversed-full-name"
    "subject" "reversed-subject"
    "addressees" "reversed-addressees"
    "recipients" "reversed-recipients"
    "line-count" "reversed-line-count"
    "byte-count" "reversed-byte-count"
    "spam-score" "reversed-spam-score"
    "physical-order" "reversed-physical-order"))

(defvaralias 'vm-supported-interactive-virtual-selectors
  'vm-vs-interactive)

(defconst vm-vs-interactive
  '(("any")
    ("sexp")
    ("eval")
    ;; ("member") ; - yet to be defined
    ("virtual-folder-member")
    ("header")
    ("label")
    ("uid")
    ("uidl")
    ("message-id")
    ("text")
    ("header-or-text")
    ("author")
    ("addressee")
    ("recipient")
    ("principal")
    ("author-or-recipient")
    ("outgoing")
    ("uninteresting-senders")
    ("subject")
    ("sent-before")
    ("sent-after")
    ("older-than")
    ("newer-than")
    ("attachment")
    ("more-chars-than")
    ("less-chars-than")
    ("more-lines-than")
    ("less-lines-than")
    ("new")
    ("unread")
    ("read")
    ("unseen")
    ("recent")
    ("flagged")
    ("unflagged")
    ("deleted")
    ("replied")
    ("forwarded")
    ("redistributed")
    ("filed")
    ("written")
    ("edited")
    ("marked")
    ("undeleted")
    ("unreplied")
    ("unforwarded")
    ("unredistributed")
    ("unfiled")
    ("unwritten")
    ("unedited")
    ("unmarked")
    ("expanded")
    ("collapsed")
    ("spam-word")
    ("spam-score")
    )
  "This is the list of virtual selectors that can be used in creating
virtual folders (search folders) interactively.  You can get
individual help on each selector by checking the function
`vm-vs-SELECTOR', e.g., `vm-vs-spam-score' for the spam-score selector.")

(defvaralias 'vm-virtual-selector-function-alist
  'vm-vs-alist)

(defconst vm-vs-alist
  '((any . vm-vs-any)
    ;; (member . vm-vs-member) ; yet to be defined
    (virtual-folder-member . vm-vs-virtual-folder-member)
    (and . vm-vs-and)
    (or . vm-vs-or)
    (not . vm-vs-not)
    (sexp . vm-vs-sexp)
    (eval . vm-vs-eval)
    (thread . vm-vs-thread)
    (thread-all . vm-vs-thread-all)
    (header . vm-vs-header)
    (header-field . vm-vs-header-field)
    (label . vm-vs-label)
    (uid . vm-vs-uid)
    (uidl . vm-vs-uidl)
    (message-id . vm-vs-message-id)
    (text . vm-vs-text)
    (header-or-text . vm-vs-header-or-text)
    (addressee . vm-vs-addressee)
    (recipient . vm-vs-recipient)
    (author . vm-vs-author)
    (principal . vm-vs-principal)
    (author-or-recipient . vm-vs-author-or-recipient)
    (outgoing . vm-vs-outgoing)
    (uninteresting-senders . vm-vs-uninteresting-senders)
    (subject . vm-vs-subject)
    (sortable-subject . vm-vs-sortable-subject)
    (sent-before . vm-vs-sent-before)
    (sent-after . vm-vs-sent-after)
    (older-than . vm-vs-older-than)
    (newer-than . vm-vs-newer-than)
    (attachment . vm-vs-attachment)
    (more-chars-than . vm-vs-more-chars-than)
    (less-chars-than . vm-vs-less-chars-than)
    (more-lines-than . vm-vs-more-lines-than)
    (less-lines-than . vm-vs-less-lines-than)
    (new . vm-vs-new)
    (unread . vm-vs-unread)
    (read . vm-vs-read)
    (unseen . vm-vs-unseen)
    (recent . vm-vs-recent)
    (flagged . vm-vs-flagged)
    (unflagged . vm-vs-unflagged)
    (deleted . vm-vs-deleted)
    (replied . vm-vs-replied)
    (answered . vm-vs-answered)
    (forwarded . vm-vs-forwarded)
    (redistributed . vm-vs-redistributed)
    (filed . vm-vs-filed)
    (written . vm-vs-written)
    (edited . vm-vs-edited)
    (marked . vm-vs-marked)
    (undeleted . vm-vs-undeleted)
    (unreplied . vm-vs-unreplied)
    (unanswered . vm-vs-unanswered)
    (unforwarded . vm-vs-unforwarded)
    (unredistributed . vm-vs-unredistributed)
    (unfiled . vm-vs-unfiled)
    (unwritten . vm-vs-unwritten)
    (unedited . vm-vs-unedited)
    (unmarked . vm-vs-unmarked)
    (spam-word . vm-vs-spam-word)
    (spam-score . vm-vs-spam-score)
    (expanded . vm-vs-expanded)
    (collapsed . vm-vs-collapsed)
    ))

(defconst vm-supported-attribute-names
  '("new"
    "unread"
    "read"
    "deleted"
    "replied"
    "forwarded"
    "redistributed"
    "filed"
    "written"
    "edited"
    "undeleted"
    "unreplied"
    "unforwarded"
    "unredistributed"
    "unfiled"
    "unwritten"
    "unedited"
    "expanded"
    "collapsed"
    ;; for babyl cogniscenti
    "recent"
    "unseen"
    "flagged"
    "unflagged"
    "answered"
    "unanswered"
    ))

(defvar vm-key-functions nil
  "A list of sort-compare functions that should be used for sorting
the current folder (internal variable).  See `vm-sort-compare-xxxxxx'
for a full description.")
(defconst vm-digest-type-alist '(("rfc934") ("rfc1153") ("mime")))
(defvar vm-completion-auto-correct t
  "Non-nil means that minibuffer-complete-file should aggressively erase
the trailing part of a word that caused completion to fail, and retry
the completion with the resulting word.")
(defvar vm-minibuffer-completion-table nil
  "Completion table used by `vm-minibuffer-complete-word'.
Should be just a list of strings, not an alist or an obarray.")
(defvar vm-completion-auto-space t
  "Non-nil value means that `vm-minibuffer-complete-word' should automatically
append a space to words that complete unambiguously.")
(defconst vm-folder-summary-vector-length 15)
(defconst vm-startup-message-lines
  '("Please use \\[vm-submit-bug-report] to report bugs."
    "For discussion about the VM mail reader, see the gnu.emacs.vm.info newsgroup"
    "You may give out copies of VM.  Type \\[vm-show-copying-restrictions] to see the conditions"
    "VM comes with ABSOLUTELY NO WARRANTY; type \\[vm-show-no-warranty] for full details"))
(defconst vm-startup-message-displayed nil)
;; for the mode line
(defconst vm-mode-line-format-robf
  '("- " 
    (vm-compositions-exist ("" vm-ml-composition-buffer-count " / "))
    (vm-drafts-exist ("" vm-ml-draft-count " / "))
    ((vm-spooled-mail-waiting "New mail for ")
     (vm-folder-read-only "read-only ")
     (vm-virtual-folder-definition (vm-virtual-mirror "mirrored "))
     " %&%& "
     "%b"
     (vm-mail-buffer (vm-ml-sort-keys ("" " by " vm-ml-sort-keys)))
     (vm-message-list
      (" " vm-ml-message-number
       " (of " vm-ml-highest-message-number ")")
      (vm-folder-type
       " (unrecognized folder type)"
       " (no messages)")))
    (vm-message-list
     (" %[ " vm-ml-message-attributes-alist
      (vm-ml-labels ("; " vm-ml-labels)) " %] ")
     (" %[%] "))
    "%p"
    " (VM " (vm-version) ")"
    global-mode-string
    "%-"))
(defconst vm-mode-line-format-classic
  '("" "  %&%& "
    ("VM: "
     (vm-folder-read-only "read-only ")
     (vm-virtual-folder-definition (vm-virtual-mirror "mirrored "))
     "%b"
     (vm-mail-buffer (vm-ml-sort-keys ("" " by " vm-ml-sort-keys)))
     (vm-message-list
      ("   " vm-ml-message-number
       " (of " vm-ml-highest-message-number ")")
      (vm-folder-type
       "   (unrecognized folder type)"
       "   (no messages)")))
    (vm-spooled-mail-waiting " Mail")
    (vm-message-list
     ("  %[ " vm-ml-message-attributes-alist
      (vm-ml-labels ("; " vm-ml-labels)) " %]    ")
     ("  %[%]   "))
    "%p" "   " global-mode-string))

(defconst vm-mode-line-format vm-mode-line-format-classic)


(defconst vm-ml-message-attributes-alist
  '((vm-ml-message-new
     "new"
     (vm-ml-message-unread
      "unread"
      (vm-ml-message-read "read")))
    (vm-ml-message-edited " edited")
    (vm-ml-message-filed " filed")
    (vm-ml-message-written " written")
    (vm-ml-message-replied " replied")
    (vm-ml-message-forwarded " forwarded")
    (vm-ml-message-redistributed " redistributed")
    (vm-ml-message-deleted " deleted")
    (vm-ml-message-marked " MARKED")))
(defvar vm-ml-message-number nil)
(make-variable-buffer-local 'vm-ml-message-number)
(defvar vm-ml-highest-message-number nil)
(make-variable-buffer-local 'vm-ml-highest-message-number)
(defvar vm-ml-sort-keys nil
  "A string containing a list of sort keys to be used for sorting
the current folder (internal variable).")
(make-variable-buffer-local 'vm-ml-sort-keys)
(defvar vm-ml-labels nil)
(make-variable-buffer-local 'vm-ml-labels)
; unused now
;(defvar vm-ml-attributes-string nil)
;(make-variable-buffer-local 'vm-ml-attributes-string)
(defvar vm-ml-message-new nil)
(make-variable-buffer-local 'vm-ml-message-new)
(defvar vm-ml-message-unread nil)
(make-variable-buffer-local 'vm-ml-message-unread)
(defvar vm-ml-message-read nil)
(make-variable-buffer-local 'vm-ml-message-read)
(defvar vm-ml-message-edited nil)
(make-variable-buffer-local 'vm-ml-message-edited)
(defvar vm-ml-message-replied nil)
(make-variable-buffer-local 'vm-ml-message-replied)
(defvar vm-ml-message-forwarded nil)
(make-variable-buffer-local 'vm-ml-message-forwarded)
(defvar vm-ml-message-redistributed nil)
(make-variable-buffer-local 'vm-ml-message-redistributed)
(defvar vm-ml-message-deleted nil)
(make-variable-buffer-local 'vm-ml-message-deleted)
(defvar vm-ml-message-filed nil)
(make-variable-buffer-local 'vm-ml-message-filed)
(defvar vm-ml-message-written nil)
(make-variable-buffer-local 'vm-ml-message-written)
(defvar vm-ml-message-marked nil)
(make-variable-buffer-local 'vm-ml-message-marked)

(defcustom vm-remember-passwords-insecurely nil
  "If set to `t', VM uses its own storage for remembering passwords
for POP/IMAP accounts, which is insecure."
  :group 'vm-folders
  :type 'boolean)

;; to make the tanjed compiler shut up
(defvar vm-pop-read-point nil)
;; Variable indicating whether POP session handling functions can ask
;; questions to the user, typically if they are run from interactive
;; commands. 
(defvar vm-pop-ok-to-ask nil)
(defvar vm-pop-passwords nil)
;; Keep a list of messages retrieved from the POP maildrops
;; Prune the list when messages are expunged on the server
;; This variable is also used for POP folders, to selectively mark
;; messages that need to be expunged on the server
(defvar vm-pop-retrieved-messages nil)
(make-variable-buffer-local 'vm-pop-retrieved-messages)
;; list of messages to be expunged on the server during the next save
(defvar vm-pop-messages-to-expunge nil)
(make-variable-buffer-local 'vm-pop-messages-to-expunge)

(defvar vm-imap-read-point nil
  "Position in an IMAP process buffer where the next read must
take place.  In general, IMAP process reading functions move the
point.  No save-excursion's are used.  This variable holds the
position for the next read.")
;; Variable indicating whether IMAP session handling functions can ask
;; questions to the user, typically if they are run from interactive
;; commands. 
(defvar vm-imap-ok-to-ask nil)
;; Stored passwords for IMAP accounts during a VM session
(defvar vm-imap-passwords nil)
;; Keep a list of messages retrieved from the IMAP maildrops
;; Prune the list when messages are expunged on the server
;; This variable is also used for IMAP folders, to selectively mark
;; messages that need to be expunged on the server
(defvar vm-imap-retrieved-messages nil)
(make-variable-buffer-local 'vm-imap-retrieved-messages)
(defvar vm-imap-messages-to-expunge nil
  "Buffer local variable indicating messages to be expunged on the
server.  It is a list of pairs containing the UID and the
UIDVALIDITY for each message to be expunged.")
(make-variable-buffer-local 'vm-imap-messages-to-expunge)
(defvar vm-imap-capabilities nil)
(make-variable-buffer-local 'vm-imap-capabilities)
(defvar vm-imap-auth-methods nil)
(make-variable-buffer-local 'vm-imap-auth-methods)
;; The number of old ('failed') trace buffers to remember for debugging
;; purposes 
;; These are now subsumed in vm-...-keep-trace-buffer variables.  USR, 2011-11
;; (defvar vm-pop-keep-failed-trace-buffers 20)
;; (defvar vm-imap-keep-failed-trace-buffers 20)
;; Lists of trace buffers remembered for debugging purposes
(defvar vm-kept-pop-buffers nil
  "* Variable that holds the old trace buffers of POP sessions for
  debugging purposes.")
;; (make-variable-buffer-local 'vm-kept-pop-buffers)
(defvar vm-kept-imap-buffers nil
  "* Variable that holds the old trace buffers of IMAP sessions for
  debugging purposes.")
;; (make-variable-buffer-local 'vm-kept-imap-buffers)
;; Flag to make POP/IMAP code remember old trace buffers
(defcustom vm-pop-keep-trace-buffer 1
  "* The number of POP session trace buffers that should be
  retained for debugging purposes.  If it is nil, then no trace
  buffers are kept."
  :group 'vm-pop
  :type '(choice (integer :tag "Number of session buffers kept"
		 (const :tag "No session buffers kept" nil))))
(defcustom vm-imap-keep-trace-buffer 1
  "* The number of IMAP session trace buffers that should be
  retained for debugging purposes.  If it is nil, then no trace
  buffers are kept."
  :group 'vm-imap
  :type '(choice (integer :tag "Number of session buffers kept"
		 (const :tag "No session buffers kept" nil))))
(defvar vm-imap-session-done nil)
(defvar vm-reply-list nil
  "Buffer local variable in Composition buffers that holds the set of
  messages to which this composition is a reply.")
(defvar vm-forward-list nil
  "Buffer local variable in Composition buffers that holds the set of
  messages that are forwarded in this composition.")
(defvar vm-redistribute-list nil
  "Buffer local variable in Composition buffers that holds the set of
  messages that are redistributed in this composition.")

;; For verification of assertions

(defvar vm-assertion-checking-off t
  "* Set this to nil to enable assertion checking")

;; For verification of the correct buffer protocol
;; Possible values are 'folder, 'presentation, 'summary, 'process

(defvar vm-buffer-types (cons nil nil))

(defvar vm-imap-session-type nil
  "This buffer-local variable holds the status of the IMAP session.
Possible values are 
`active' - active session present
`valid' - message sequence numbers are valid 
	validity is preserved by FETCH, STORE and SEARCH operations
`inactive' - session is inactive")
(make-variable-buffer-local 'vm-imap-session-type)

(defvar vm-fsfemacs-toolbar-installed-p nil)
;; this defvar matches the XEmacs one so it doesn't matter if VM
;; is loaded before highlight-headers.el
(defconst highlight-headers-regexp "Subject[ \t]*:")
(defconst vm-url-regexp
  "<URL:\\([^>\n]+\\)>\\|\\(\\(file\\|sftp\\|ftp\\|gopher\\|http\\|https\\|news\\|wais\\|www\\)://[^ \t\n\f\r\"<>|()]*[^ \t\n\f\r\"<>|.!?(){}]\\)\\|\\(mailto:[^ \t\n\f\r\"<>|()]*[^] \t\n\f\r\"<>|.!?(){}]\\)\\|\\(file:/[^ \t\n\f\r\"<>|()]*[^ \t\n\f\r\"<>|.!?(){}]\\)"
  "Regular expression that matches an absolute URL.
The URL itself must be matched by a \\(..\\) grouping.
VM will extract the URL by copying the lowest number grouping
that has a match.")
(defconst vm-month-alist
  '(("jan" "January" "1")
    ("feb" "February" "2")
    ("mar" "March" "3")
    ("apr" "April" "4")
    ("may" "May" "5")
    ("jun" "June" "6")
    ("jul" "July" "7")
    ("aug" "August" "8")
    ("sep" "September" "9")
    ("oct" "October" "10")
    ("nov" "November" "11")
    ("dec" "December" "12")))
(defconst vm-weekday-alist
  '(("sun" "Sunday" "0")
    ("mon" "Monday" "1")
    ("tue" "Tuesday" "2")
    ("wed" "Wednesday" "3")
    ("thu" "Thursday" "4")
    ("fri" "Friday" "5")
    ("sat" "Saturday" "6")))
(defvar pop-up-frames nil)
(defvar vm-parse-date-workspace (make-vector 6 nil))
;; cache so we don't call timezone-make-date-sortable so much.
;; messages have their own cache; this is for the virtual folder
;; alist selectors.
(defvar vm-sortable-date-alist nil)
(make-variable-buffer-local 'vm-sortable-date-alist)
(defvar vm-summary-=> nil)
(defvar vm-summary-no-=> nil)
(defvar vm-summary-overlay nil)
(make-variable-buffer-local 'vm-summary-overlay)
(defvar vm-summary-tokenized-compiled-format-alist nil)
(defvar vm-summary-untokenized-compiled-format-alist nil)
(defvar vm-folders-summary-compiled-format-alist nil)
(defvar vm-folders-summary-overlay nil)
(defvar vm-spool-file-message-count-hash (make-vector 61 0))
(defvar vm-page-end-overlay nil)
(make-variable-buffer-local 'vm-page-end-overlay)
(defvar vm-begin-glyph-property (if (fboundp 'extent-property)
				       'begin-glyph
				     'before-string))
(defvar vm-thread-loop-obarray (make-vector 641 0))
(defvar vm-delete-duplicates-obarray (make-vector 29 0))
(defvar vm-image-obarray (make-vector 29 0))
(defvar vm-mail-mode-map-parented nil)
(defvar vm-xface-cache (make-vector 29 0))
(defvar vm-mf-default-action nil)
(defvar vm-mime-compiled-format-alist nil)
(defconst vm-mime-default-action-string-alist
  ;; old definition
  ;; '(("text" . "display text")
  ;;   ("multipart/alternative" . "display selected part")
  ;;   ("multipart/digest" . "read digest")
  ;;   ("multipart/parallel" . "display parts in parallel")
  ;;   ("multipart" . "display parts")
  ;;   ("message/partial" . "attempt message assembly")
  ;;   ("message/external-body" . "retrieve the object")
  ;;   ("message" . "display message")
  ;;   ("audio" . "play audio")
  ;;   ("video" . "display video")
  ;;   ("image" . "display image")
  ;;   ("model" . "display model")
  ;;   ("application/postscript" . "display PostScript")
  ;;   ("application/msword" . "display Word document")
  ;;   ("application" . "display attachment"))

  '(("text" . "display")
    ("multipart/alternative" . "display selected part")
    ("multipart/digest" . "read digest")
    ("multipart/parallel" . "display parts in parallel")
    ("multipart" . "display parts")
    ("message/partial" . "attempt message assembly")
    ("message/external-body" . "retrieve")
    ("message" . "display")
    ("audio" . "play")
    ("video" . "play")
    ("image" . "display")
    ("model" . "display")
    ("application" . "display")))

(defconst vm-mime-type-description-alist
  '(("multipart/digest" . "digest")
    ("multipart/alternative" . "multipart alternative")
    ("multipart/parallel" . "multipart parallel")
    ("multipart" . "multipart message")
    ("text/plain" . "plain text")
    ("text/enriched" . "enriched text")
    ("text/html" . "HTML")
    ("text/calendar" . "Calendar event")
    ("text/directory" . "VCard")
    ("text/x-vcard" . "VCard")
    ("image/gif" . "GIF image")
    ("image/tiff" . "TIFF image")
    ("image/jpeg" . "JPEG image")
    ("image/png" . "PNG image")
    ("message/rfc822" . "mail message")
    ("message/news" . "news article")
    ("message/partial" . "message fragment")
    ("message/external-body" . "external")
    ("application/pdf" . "PDF")
    ("application/postscript" . "PostScript")
    ("application/msword" . "Document")
    ("application/vnd.ms-excel" . "Spreadsheet")
    ("application/vnd.ms-powerpoint" . "Presentation")
    ("application/vnd-ms-access" . "Database")
    ("application/vnd.oasis.opendocument.text" . "Open Doc")
    ("application/vnd.oasis.opendocument.presentation" . "Prsentation")
    ("application/vnd.oasis.opendocument.spreadsheet" . "Spreadsheet")
    ("application/vnd.oasis.opendocument.graphics" . "Graphics")
    ("application/vnd.oasis.opendocument.formulae" . "Formulae")
    ("application/vnd.oasis.opendocument.databases" . "Database")
    ("application/vnd.openxmlformats-officedocument.wordprocessingml.document"
     . "Document")
    ("application/vnd.openxmlformats-officedocument.wordprocessingml.document"
     . "Document")
    ("application/vnd.openxmlformats-officedocument.presentationml.presentation"
     . "Presentation")
    ("application/vnd.openxmlformats-officedocument.presentationml.presentation"
     . "Presentation")
    ("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
     . "Spreadsheet")
    ("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
     . "Spreadsheet")
    ("application/x-dvi" . "DVI")
    ("application/octet-stream" . "Untyped binary data")
    ("application/mac-binhex40" . "Untyped Mac data")))

(defconst vm-mime-base64-alphabet
  (concat
   [
     65  66  67  68  69  70  71  72  73  74  75  76  77
     78  79  80  81  82  83  84  85  86  87  88  89  90
     97  98  99 100 101 102 103 104 105 106 107 108 109
    110 111 112 113 114 115 116 117 118 119 120 121 122
     48  49  50  51  52  53  54  55  56  57  43  47
   ]
  ))
(defconst vm-mime-base64-alphabet-decoding-vector
  [
     0  0  0  0  0  0  0  0  0  0  0  0  0  0  0  0
     0  0  0  0  0  0  0  0  0  0  0  0  0  0  0  0
     0  0  0  0  0  0  0  0  0  0  0 62  0  0  0 63
    52 53 54 55 56 57 58 59 60 61  0  0  0  0  0  0
     0  0  1  2  3  4  5  6  7  8  9 10 11 12 13 14
    15 16 17 18 19 20 21 22 23 24 25  0  0  0  0  0
     0 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40
    41 42 43 44 45 46 47 48 49 50 51  0  0  0  0  0
  ])

;;(defconst vm-mime-base64-alphabet-decoding-alist
;;  '(
;;    ( 65 . 00) ( 66 . 01) ( 67 . 02) ( 68 . 03) ( 69 . 04) ( 70 . 05)
;;    ( 71 . 06) ( 72 . 07) ( 73 . 08) ( 74 . 09) ( 75 . 10) ( 76 . 11)
;;    ( 77 . 12) ( 78 . 13) ( 79 . 14) ( 80 . 15) ( 81 . 16) ( 82 . 17)
;;    ( 83 . 18) ( 84 . 19) ( 85 . 20) ( 86 . 21) ( 87 . 22) ( 88 . 23)
;;    ( 89 . 24) ( 90 . 25) ( 97 . 26) ( 98 . 27) ( 99 . 28) (100 . 29)
;;    (101 . 30) (102 . 31) (103 . 32) (104 . 33) (105 . 34) (106 . 35)
;;    (107 . 36) (108 . 37) (109 . 38) (110 . 39) (111 . 40) (112 . 41)
;;    (113 . 42) (114 . 43) (115 . 44) (116 . 45) (117 . 46) (118 . 47)
;;    (119 . 48) (120 . 49) (121 . 50) (122 . 51) ( 48 . 52) ( 49 . 53)
;;    ( 50 . 54) ( 51 . 55) ( 52 . 56) ( 53 . 57) ( 54 . 58) ( 55 . 59)
;;    ( 56 . 60) ( 57 . 61) ( 43 . 62) ( 47 . 63)
;;   ))
;;
;;(defvar vm-mime-base64-alphabet-decoding-vector
;;  (let ((v (make-vector 123 nil))
;;	(p vm-mime-base64-alphabet-decoding-alist))
;;    (while p
;;      (aset v (car (car p)) (cdr (car p)))
;;      (setq p (cdr p)))
;;    v ))

(defvar vm-message-garbage-alist nil
  "An association list of files created for this message and the
actions to be taken to destroy them.")
(make-variable-buffer-local 'vm-message-garbage-alist)
(defvar vm-folder-garbage-alist nil
  "An association list of files created for this folder and the
actions to be taken to destroy them.")
(make-variable-buffer-local 'vm-folder-garbage-alist)
(defvar vm-global-garbage-alist nil
  "An association list of files created for this VM session and the
actions to be taken to destroy them.")
(defconst vm-mime-header-list '("MIME-Version:" "Content-"))
(defconst vm-mime-header-regexp "\\(MIME-Version:\\|Content-\\)")
(defconst vm-mime-mule-charset-to-coding-alist
  (cond ((not (featurep 'xemacs))
	 (let ((coding-systems (coding-system-list))
	       (alist nil)
	       val)
	   (while coding-systems
	     (setq val (coding-system-get (car coding-systems) 'mime-charset))
	     (if val
		 (setq alist (cons (list (symbol-name val)
					 (car coding-systems))
				   alist)))
	     (setq coding-systems (cdr coding-systems)))
	   (setq alist (append '(("us-ascii" raw-text)
				 ("unknown" iso-8859-1))
			       alist))
	   alist))
	 (t
	 '(
	   ("us-ascii"		no-conversion)
	   ("iso-8859-1"	no-conversion)
	   ("iso-8859-2"	iso-8859-2)
	   ("iso-8859-3"	iso-8859-3)
	   ("iso-8859-4"	iso-8859-4)
	   ("iso-8859-5"	iso-8859-5)
;	   ("iso-8859-6"	iso-8859-6)
	   ("iso-8859-7"	iso-8859-7)
	   ("iso-8859-8"	iso-8859-8)
	   ("iso-8859-8-i"	iso-8859-8)
	   ("iso-8859-9"	iso-8859-9)
	   ("iso-2022-jp"	iso-2022-jp)
	   ("big5"		big5)
	   ("koi8-r"		koi8-r)
	   ("ks_c_5601-1987"	euc-kr)
	   ("euc-jp"		euc-jp)
	   ;; probably not correct, but probably better than nothing.
	   ("iso-2022-jp-2"	iso-2022-jp)
	   ("iso-2022-int-1"	iso-2022-int-1)
	   ("iso-2022-kr"	iso-2022-kr)
	   ("euc-kr"		iso-2022-kr)
	  )
	 ))
  "Alist that maps MIME character sets to MULE coding systems.  The
information is generated from the `mime-charset' property of coding
systems, if it is defined in the Emacs version.  Otherwise, a
default alist is used.")
	  
(defconst vm-mime-mule-charset-to-charset-alist
  '(
    (latin-iso8859-1	"iso-8859-1")
    (latin-iso8859-2	"iso-8859-2")
    (latin-iso8859-3	"iso-8859-3")
    (latin-iso8859-4	"iso-8859-4")
    (cyrillic-iso8859-5	"iso-8859-5")
    (arabic-iso8859-6	"iso-8859-6")
    (greek-iso8859-7	"iso-8859-7")
    (hebrew-iso8859-8	"iso-8859-8")
    (latin-iso8859-9	"iso-8859-9")
    (japanese-jisx0208	"iso-2022-jp")
    (korean-ksc5601	"iso-2022-kr")
    (chinese-gb2312	"iso-2022-jp")
    (sisheng		"iso-2022-jp")
    (thai-tis620	"iso-2022-jp")
   )
  "Alist that maps MULE character sets to matching MIME character sets.")

(defconst vm-mime-mule-coding-to-charset-alist
  (cond ((not (featurep 'xemacs))
	 (let ((coding-systems (coding-system-list))
	       (alist nil)
	       val)
	   (while coding-systems
	     (setq val (coding-system-get (car coding-systems) 'mime-charset))
	     (if val
		 (setq alist (cons (list (car coding-systems)
					 (symbol-name val))
				   alist)))
	     (setq coding-systems (cdr coding-systems)))
	   (setq alist (append '((raw-text "us-ascii")) alist))
	   alist))
	(t
	 '(
	   (iso-2022-8		"iso-2022-jp")
	   (iso-2022-7-unix	"iso-2022-jp")
	   (iso-2022-7-dos	"iso-2022-jp")
	   (iso-2022-7-mac	"iso-2022-jp")
	  )))
  "Alist that maps MULE coding systems to MIME character sets.  The
information is generated from the `mime-charset' property of coding
systems, if it is defined in the Emacs version.  Otherwise, a
default alist is used.")

(defcustom vm-mime-charset-completion-alist
  (mapcar (lambda (a) (list (car a)))
    vm-mime-mule-charset-to-coding-alist)
  "The completion alist of MIME charsets known to VM.  The default
information is derived from `vm-mime-mule-charset-to-coding-alist' (which see)."
  :group 'vm-mime
  :type '(repeat (list string)))


(defconst vm-mime-type-completion-alist
  '(
    ("text/plain")
    ("text/enriched")
    ("text/html")
    ("audio/basic")
    ("image/jpeg")
    ("image/png")
    ("image/gif")
    ("image/tiff")
    ("video/mpeg")
    ("application/postscript")
    ("application/octet-stream")
    ("message/rfc822")
    ("message/news")
   ))

(defconst vm-mime-encoded-word-regexp
  "=\\?\\([^?*]+\\)\\(\\*\\([^?*]+\\)\\)?\\?\\([BbQq]\\)\\?\\([^?]+\\)\\?=")

;; for MS-DOS and Windows NT
;;    nil value means text file
;;      t value means binary file
;; presumably it controls whether LF -> CRLF mapping is done
;; when writing to files.
(defvar buffer-file-type)
(defvar vm-mf-attachment-file nil)
(defvar vm-frame-list nil)
(if (not (boundp 'shell-command-switch))
    (defvar shell-command-switch "-c"))
(defvar vm-stunnel-random-data-file nil)
(defvar vm-stunnel-configuration-file nil)
(defvar vm-fsfemacs-cached-scroll-bar-width nil)
(defvar vm-update-composition-buffer-name-timer nil)

(defcustom vm-enable-addons '(;; check-recipients -- removed on 2014-07-15
                              check-for-empty-subject
                              encode-headers)
  "*A list of addons to enable, t for all and nil to disable all.
Most addons are from `vm-rfaddons-infect-vm'.

You must restart VM after a change to cause any effects."
  :group 'vm-rfaddons
  :type '(set (const :tag "Enable shrinking of multi-line headers to one line."
		     shrunken-headers)
	      (const :tag "Open a line when typing in quoted text"
		     open-line)
	      (const :tag "Check the recipients before sending a message"
		     check-recipients)
	      (const :tag "Check for an empty subject before sending a message"
		     check-for-empty-subject)
	      (const :tag "MIME encode headers before sending a message"
		     encode-headers)
	      (const :tag "Clean up subject prefixes before sending a message"
		     clean-subject)
	      (const :tag "Do not replace Date: header when sending a message"
		     fake-date)
	      (const :tag "Bind '.' on attachment buttons to 'vm-mime-take-action-on-attachment'"
		     take-action-on-attachment)
	      (const :tag "Automatically save attachments of new messages" 
		     auto-save-all-attachments)
	      (const :tag "Delete external attachments of a message when expunging it." 
		     auto-delete-message-external-body)
	      (const :tag "Enable all addons" t)))

(defcustom vm-summary-enable-faces nil
  "A non-NIL value enables the use of faces in the summary buffer.

You should set this variable in the init-file.  For interactive use,
the command `vm-summary-faces-mode' should be used."
  :group 'vm-faces
  :type 'boolean)

;; The following functions are customizable by the users.
;; They might be turned into variables at some future date.  USR, 2012-05-23

(defun vm-virtual-folder-name (folder selector arg)
  "Returns an appropriate folder name for an interactive virtual
folder created from FOLDER using SELECTOR with ARG."
  (if arg
      (format "(%s %s %s)" folder selector arg)
    (format "(%s %s)" folder selector)))

(defun vm-virtual-application-folder-name (folder selector)
  "Return a virtual folder name for applying a virtual SELECTOR to FOLDER."
  (format "(%s/%s)" folder selector))

(defcustom vm-disable-modes-before-encoding 
  '(auto-fill-mode font-lock-mode ispell-minor-mode flyspell-mode
                   abbrev-mode adaptive-fill-mode)
  "*A list of minor modes to disable before encoding a message.
These modes may slow down (font-lock and *spell) encoding and may
cause trouble (abbrev-mode)."
  :group 'vm-compose
  :type '(repeat :tag "Mode" symbol))

(defvar vm-summary-faces-mode nil
  "Records whether VM Summary Faces mode is in use.")

(make-obsolete-variable 'vm-summary-faces-mode 
			'vm-summary-enable-faces "8.2.0")

;; Duplicate defintion. See above. TX
;; (defcustom vm-mail-mode-hidden-headers '("References" "In-Reply-To" "X-Mailer")
;;   "*A list of headers to hide in `vm-mail-mode'."
;;   :group 'vm
;;   :type '(choice (const :tag "Disabled" nil)
;;                  (set :tag "Header list"
;;                       (string "References")
;;                       (string "In-Reply-To")
;;                       (string "X-Mailer"))))

;; define this here so that the user can invoke it right away, if needed.

(defun vm-load-init-file (&optional init-only)
  "Load the VM's initialization files, normally named \".vm\" and
\".vm.preferences\".  If a prefix argument is given, then only the
\".vm\" file is loaded (which is useful testing or debugging the
preferences file).

The file names may be customized via the variables `vm-init-file' and
`vm-preferences-file'. "
  (interactive "P")
  (when (or (not vm-init-file-loaded) (vm-interactive-p))
    (when vm-init-file
      (load vm-init-file (not (vm-interactive-p)) (not (vm-interactive-p)) t))
    (when (and vm-preferences-file (not init-only))
      (load vm-preferences-file t t t)))
  (setq vm-init-file-loaded t)
  (vm-display nil nil '(vm-load-init-file) '(vm-load-init-file)))

(provide 'vm-vars)
;;; vm-vars.el ends here
