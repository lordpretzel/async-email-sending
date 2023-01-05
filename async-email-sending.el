;;; async-email-sending.el --- send emacs asynchronously -*- lexical-binding: t -*-

;; Author: Boris Glavic <lordpretzel@gmail.com>
;; Maintainer: Boris Glavic <lordpretzel@gmail.com>
;; Version: 0.1
;; Package-Requires: ((async "1.9") (bui "1.2.1") (dash "2.11.0") (emacs "29"))
;; Homepage: https://github.com/lordpretzel/async-email-sending
;; Keywords: email


;; This file is not part of GNU Emacs

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; For a full copy of the GNU General Public License
;; see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Send email in an asynchronous, but safe way. Also hooks into mu4e if
;; available and provides a tabulated list interface to browse outstanding email
;; that has not been send (successfully yet). Requires Emacs with built-in
;; support for sqlite, so Emacs 29+ only, sorry.
;;
;; To active asynchronous sending of email set
;; `async-email-sending-use-async-send-mail' to true in customize (setq will not
;; work as this calls a function to override send mail functions and installs
;; advice.
;;
;; If mu4e is installed then this package shows unsend email count in the mu4e
;; main view.
;;
;; To see a list of pending emails (and the errors that happened when trying to
;; send them if applicable), call `async-email-sending-queued-mail-show-bui'.

;;; Code:

;; ********************************************************************************
;; IMPORTS
(require 'async)
(require 'bui)
(require 'smtpmail)
(require 'message)
(require 'dash)
;; load mu4e but only if it exists
(require 'mu4e nil t)
(require 'mu4e-main nil t)

;; ********************************************************************************
;; CUSTOM
(defconst async-email-sending-send-mail-sqlite-db
  "send-mail.db"
  "This SQLite database in the user .emacs.d directory stores mail to send.")

(defun async-email-sending-advice-add-if-def (f type theadvice)
  "Add advice THEADVICE as type TYPE to function F.

Only do this if the function to be advised (F) and the advising
function (THEADVICE) both exists."
  (when (and (fboundp f)  (fboundp theadvice))
    (advice-add f type theadvice)))

(defun async-email-sending-unadvice-if-def (sym)
  "Remove all advices from symbol SYM."
  (when (fboundp sym)
    (advice-mapc (lambda (advice _props) (advice-remove sym advice)) sym)))

(defun async-email-sending-set-mail-send-funcs (async-sending)
  "If ASYNC-SENDING is non-nil, then overwrite send-mail functions."
  (if async-sending
      (progn
        (setq send-mail-function 'async-email-sending-send-mail-async
              message-send-mail-function 'async-email-sending-send-mail-async)
        (async-email-sending-advice-add-if-def
         'mu4e--main-queue-size
         :override #'async-email-sending--num-queued-emails)
        (async-email-sending-advice-add-if-def
         #'smtpmail-send-queued-mail
         :override #'async-email-sending--flush-queued-emails))
    ;; restore original function and uninstall advice
    (setq send-mail-function 'sendmail-query-once
          message-send-mail-function 'smtpmail-send-it)
    (async-email-sending-unadvice-if-def 'mu4e--main-queue-size)
    (async-email-sending-unadvice-if-def #'smtpmail-send-queued-mail)))

(defun async-email-sending--set-mail-async (key value)
  "Set function for `async-email-sending-use-async-send-mail'.

Sets KEY to VALUE. This function also installs advice and sets
 `send-mail-function' to use async database-backed mail sending."
  (set-default-toplevel-value key value)
  (async-email-sending-set-mail-send-funcs value))

(defcustom async-email-sending-use-async-send-mail
  nil
  "If non-nil, then send mail asynchronously.

This uses the async package, but to avoid loosing mail when
sending fails, mail information is stored in an SQLite database."
  :group 'mu4e-pimped
  :set #'async-email-sending--set-mail-async
  :require 'mu4e-pimped
  :type 'boolean)

;; ********************************************************************************
;; FUNCTIONS
;; ********************************************************************************
;; ALIASES FOR MU 1.7+
(when (require 'mu4e nil 'noerror)
  (if (not (version-list-< (version-to-list mu4e-mu-version) '(1 7)))
      (defalias 'mu4e~main-redraw-buffer 'mu4e--main-redraw-buffer))
  (declare-function mu4e~main-redraw-buffer nil t))

(defun async-email-sending-redraw-mu4e-main-if-need-be ()
  "If the current buffer is the mu4e main view, then refresh it."
  (when (require 'mu4e nil 'noerror)
    (when (string-equal (buffer-name (current-buffer)) mu4e-main-buffer-name)
	  (mu4e~main-redraw-buffer))))

(defun async-email-sending--get-send-mail-db ()
  "Return SQlite file storing send mail database."
  (expand-file-name async-email-sending-send-mail-sqlite-db user-emacs-directory))

(defmacro async-email-sending--with-send-db (&rest body)
  "Locally bind `db' to the database for send mail and execute BODY."
  `(let ((db (sqlite-open (async-email-sending--get-send-mail-db))))
     (unless (sqlite-available-p)
       (error "Cannot send email async if Emacs is not build with support for\
 sqlite"))
     (unless (sqlitep db)
       (error "Cannot open sqlitedb storing emails: %s"
              (async-email-sending--get-send-mail-db)))
     ,@body))

(defun async-email-sending--store-email (content)
  "Store email CONTENT as a message in sqlite db.

This function returns a plist with the emails date: an sha1 hash
of the content and the content. If the email
already exists, then just return plist without modifying the
database."
  (async-email-sending--with-send-db
   (let ((hash (sha1 content)))
     (sqlite-execute db "CREATE TABLE IF NOT EXISTS emails \
(hash VARCHAR PRIMARY KEY, content VARCHAR, ts VARCHAR, error \
VARCHAR);")
     (unless (sqlite-select db "SELECT * FROM emails WHERE hash = ?;" `(,hash))
       (sqlite-execute db "INSERT INTO emails VALUES (?, ?, datetime(), NULL);"
                       `(,hash ,content)))
     `(:hash ,hash :content ,content))))

(defun async-email-sending--get-queued-emails ()
  "Get all email queued in sqlite db that have not been send yet."
  (async-email-sending--with-send-db
   (--map `(:hash ,(car it)
                  :content ,(cadr it)
                  :ts ,(caddr it)
                  :error ,(cadddr it))
          (sqlite-select db "SELECT * FROM emails ORDER BY ts ASC;"))))

(defun async-email-sending--num-queued-emails ()
  "Determine how many emails are currently queued."
  (async-email-sending--with-send-db
   (let ((res (sqlite-select db "SELECT count(*) FROM emails;")))
     (if res (caar res) 0))))

(defun async-email-sending--flush-queued-emails ()
  "Send emails that did not end up geeting send.

Loops over emails stored in sqlite database that where supposed
to be send but did not end up being send and try to send them."
  (dolist (e (async-email-sending--get-queued-emails))
    (message "trying to flush %s" (async-email-sending--email-to-string e))
    (with-temp-buffer
      (insert (plist-get e :content))
      (async-email-sending--send-a-mail-async (current-buffer) t))))

(defun async-email-sending--email-to-string (e)
  "Create a human friendly text representations of email E."
  (let ((email (async-email-sending--queued-mail-entry e)))
    (concat
     "to: " (alist-get 'to email)
     " from: " (alist-get 'from email)
     " subject: " (truncate-string-to-width (alist-get 'subject email) 100)
     " date: " (alist-get 'date email))))

(defun async-email-sending-send-mail-async ()
  "Send email from current buffer asynchronously.

Outgoing emails are recorded in a sqlite db to be able to recover
from failures."
  (async-email-sending--send-a-mail-async (current-buffer)))

(defun async-email-sending--send-a-mail-async (buf &optional force)
  "Send mail from BUF asynchronously.

State is maintained in a SQLite db to be able to recover from
failures to send the email. If FORCE is provided, then always try
sending the email even if `smtpmail-queue-mail' is non-nil."
  (with-current-buffer buf
    (let* ((to (message-field-value "To"))
           (buf-content (buffer-substring-no-properties
                         (point-min) (point-max)))
           (dbentry (async-email-sending--store-email buf-content))
           (hash (plist-get dbentry :hash))
           (dosend (or force (not smtpmail-queue-mail)))
           (smtpmail-queue-mail nil))
      ;; only try sending if we have not queued
      (when dosend
        ;; start other emacs that does the sending
        (async-start
         ;; async lambda to send email and
         `(lambda ()
            (require 'smtpmail)
            (with-temp-buffer
              (insert ,buf-content)
              (set-buffer-multibyte nil)
              ;; Pass in the variable environment for smtpmail
              ,(async-inject-variables
                "\\`\\(smtpmail\\|async-smtpmail\\|\\(user-\\)?mail\\)-\\|auth-sources\\|epg\\|nsm"
                nil "\\`\\(mail-header-format-function\\|smtpmail-address-buffer\\|mail-mode-abbrev-table\\)")
              (run-hooks 'async-smtpmail-before-send-hook)
              (condition-case
                  e
                  (progn
                    ;; actually send email
                    (smtpmail-send-it)
                    ;; if no error, then delete email
                    (let ((db (sqlite-open ,(async-email-sending--get-send-mail-db))))
                      (unless (sqlite-available-p)
                        (error "Cannot send email async if Emacs is not build\
 with support for sqlite"))
                      (unless (sqlitep db)
                        (error "Cannot open sqlitedb storing emails: %s"
                               ,(async-email-sending--get-send-mail-db)))
                      (sqlite-execute db "DELETE FROM emails WHERE hash = ?;" (list ,hash)))
                    nil)
                ('error
                 (let ((db (sqlite-open ,(async-email-sending--get-send-mail-db))))
                   (unless (sqlite-available-p)
                     (error "Cannot send email async if Emacs is\
 not build with support for sqlite"))
                   (unless (sqlitep db)
                     (error "Cannot open sqlitedb storing emails: %s"
                            ,(async-email-sending--get-send-mail-db)))
                   (sqlite-execute db "UPDATE emails SET error = ? WHERE hash = ?;"
                                   (list  (error-message-string e) ,hash)))))))
         ;; determine success and
         (lambda (&optional msg)
           (if msg
               (message "Delivering message to %s...failed:\n\n%s"
                        to
                        msg)
             (message "Delivering message to %s...done" to))
           (async-email-sending-redraw-mu4e-main-if-need-be)))))))

;; bui list of unsend email
(defun async-email-sending--queued-mail-entry (e)
  "Create bui list element for unsend email E."
  (cl-destructuring-bind (&key hash content error &allow-other-keys) e
    (with-temp-buffer
      (insert content)
      `((id . ,hash)
        (from . ,(message-field-value "From"))
        (to . ,(message-field-value "To"))
        (subject . ,(message-field-value "Subject"))
        (content . ,(buffer-substring (message-goto-body) (point-max)))
        (date . ,(message-field-value "Date"))
        (emsg . ,error)))))

(defun async-email-sending--queued-mail-entries ()
  "Return list of queued emails for bui presentation."
  (-map #'async-email-sending--queued-mail-entry
        (async-email-sending--get-queued-emails)))

(defun async-email-sending--bui-queued-mail-entries
    (&optional search-type &rest search-values)
  "Search for queued emails with SEARCH-TYPE being one of SEARCH-VALUES."
  (cl-case search-type
    (id (-filter (lambda (x) (--some (string= (alist-get 'id x) it) search-values))
                 (async-email-sending--queued-mail-entries)))
    (t (async-email-sending--queued-mail-entries))))

;; show content
(defun async-email-sending--bui-info-content (content entry)
  "Show email CONTENT from ENTRY."
  (ignore entry)
  (insert content))

;; define entry types
(bui-define-entry-type async-email-sending-queued-mail-bui-entries
  :get-entries-function #'async-email-sending--bui-queued-mail-entries)

(defun async-email-sending--bui-describe (&rest emails)
  "Display infos for EMAILS."
  (bui-get-display-entries
   'async-email-sending-queued-mail-bui-entries
   'info
   (cons 'id emails)))

;; main tabulated list interface
(bui-define-interface async-email-sending-queued-mail-bui-entries list
  :buffer-name "*Pending emails*"
  :describe-function #'async-email-sending--bui-describe
  :format '((from nil 40)
            (to nil 40)
            (date nil 40)
            (subject nil 150 t)
            (emsg nil 20 t))
  :sort-key '(date from to))

;; detailed info list
(bui-define-interface async-email-sending-queued-mail-bui-entries info
  :format '((from format (format))
            (to format (format))
            (subject format (format))
            (date format (format))
            nil
            (content nil async-email-sending--bui-info-content)))

;;;###autoload
(defun async-email-sending-queued-mail-show-bui ()
  "Display pending emails."
  (interactive)
  (bui-get-display-entries 'async-email-sending-queued-mail-bui-entries 'list))

(provide 'async-email-sending)
;;; async-email-sending.el ends here
