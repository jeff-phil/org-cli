;;; org-cli.el --- CLI tool for Org-mode -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Jeffrey Phillips
;;
;; Copyright (C) 2025 Laurynas Biveinis <laurynas.biveinis@gmail.com>

;; Author: jeff-phil <jeffphil@gmail.com>
;; Keywords: org, todos, notes, cli
;; Version: 0.0.1
;; Package-Requires: ((emacs "29.1"))
;; Homepage: https://github.com/jeff-phil/org-cli

;; This file is NOT part of GNU Emacs.

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see
;; <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This package provides a CLI tool for programmatically manipulating
;; Org-mode files.  It can be invoked from the command line as:
;;
;;   emacs --batch -l /path/to/init.el -l org-cli.el \
;;     --eval '(org-cli)' -- COMMAND [ARGS...]
;;
;; If `org-cli-allowed-files' is nil (not configured), all files are
;; allowed.  Otherwise, only listed files can be accessed.
;;
;; This package based on the original work @laurynas-biveinis/org-mcp v0.9.0.
;;
;; Note: Developed with AI assistance.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'org)
(require 'org-id)
(require 'url-util)

;; Error handling

(define-error 'org-cli-error "org-cli error" 'error)

(defconst org-cli-version "0.0.1"
  "Version of org-cli package.")

(defcustom org-cli-allowed-files nil
  "List of absolute paths to Org files that can be accessed.
When nil, all files are allowed (suitable for CLI usage).
When non-nil, only the listed files can be accessed."
  :type '(repeat file)
  :group 'org-cli)

(defconst org-cli--uri-headline-prefix "org-headline://"
  "URI prefix for headline resources.")

(defconst org-cli--uri-id-prefix "org-id://"
  "URI prefix for ID-based resources.")

(defun org-cli--extract-uri-suffix (uri prefix)
  "Extract suffix from URI after PREFIX.
Returns the suffix string if URI starts with PREFIX, nil otherwise."
  (when (string-prefix-p prefix uri)
    (substring uri (length prefix))))

;; Error handling helpers

(defun org-cli--headline-not-found-error (headline-path)
  "Throw error for HEADLINE-PATH not found."
  (signal 'org-cli-error
          (list (format "Cannot find headline: %s"
                        (mapconcat #'identity headline-path "/")))))

(defun org-cli--id-not-found-error (id)
  "Throw error for ID not found."
  (signal 'org-cli-error
          (list (format "Cannot find ID '%s'" id))))

(defun org-cli--validation-error (message &rest args)
  "Throw validation error MESSAGE with ARGS."
  (signal 'org-cli-error
          (list (apply #'format message args))))

(defun org-cli--resource-validation-error (message &rest args)
  "Signal validation error MESSAGE with ARGS."
  (signal 'org-cli-error
          (list (apply #'format message args))))

(defun org-cli--state-mismatch-error (expected found context)
  "Throw state mismatch error.
EXPECTED is the expected value, FOUND is the actual value,
CONTEXT describes what is being compared."
  (signal 'org-cli-error
          (list (format "%s mismatch: expected '%s', found '%s'"
                        context expected found))))

(defun org-cli--resource-not-found-error (resource-type identifier)
  "Signal resource not found error.
RESOURCE-TYPE is the type of resource,
IDENTIFIER is the resource identifier."
  (signal 'org-cli-error
          (list (format "Cannot find %s: '%s'" resource-type identifier))))

(defun org-cli--file-access-error (locator)
  "Throw file access error.
LOCATOR is the resource identifier (file path or ID) that was
denied access."
  (signal 'org-cli-error
          (list (format "'%s': the referenced file not in allowed list" locator))))

(defun org-cli--resource-file-access-error (locator)
  "Signal file access error.
LOCATOR is the resource identifier (file path or ID) that was
denied access."
  (signal 'org-cli-error
          (list (format "'%s': the referenced file not in allowed list" locator))))

;; Helpers

(defun org-cli--read-file (file-path)
  "Read and return the contents of FILE-PATH."
  (with-temp-buffer
    (insert-file-contents file-path)
    (buffer-string)))

(defun org-cli--paths-equal-p (path1 path2)
  "Return t if PATH1 and PATH2 refer to the same file.
Handles symlinks and path variations by normalizing both paths."
  (string= (file-truename path1) (file-truename path2)))

(defun org-cli--find-allowed-file (filename)
  "Find FILENAME in `org-cli-allowed-files'.
If `org-cli-allowed-files' is nil, all files are allowed and
FILENAME is returned expanded.
Returns the expanded path if found/allowed, nil if not in the
allowed list."
  (if (null org-cli-allowed-files)
      (expand-file-name filename)
    (when-let* ((found
                 (cl-find
                  (file-truename filename)
                  org-cli-allowed-files
                  :test #'org-cli--paths-equal-p)))
      (expand-file-name found))))

(defun org-cli--refresh-file-buffers (file-path)
  "Refresh all buffers visiting FILE-PATH.
Preserves narrowing state across the refresh operation."
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (when-let* ((buf-file (buffer-file-name)))
        (when (string= buf-file file-path)
          (let ((was-narrowed (buffer-narrowed-p))
                (narrow-start nil)
                (narrow-end nil))
            ;; Save narrowing markers if narrowed
            (when was-narrowed
              (setq narrow-start (point-min-marker))
              (setq narrow-end (point-max-marker)))
            (condition-case err
                (unwind-protect
                    (progn
                      (revert-buffer t t t)
                      ;; Check if buffer was modified by hooks
                      (when (buffer-modified-p)
                        (org-cli--validation-error
                         "Buffer for file %s was modified during \
refresh.  Check your `after-revert-hook' for functions that modify \
the buffer"
                         file-path)))
                  ;; Restore narrowing even if revert fails
                  (when was-narrowed
                    (narrow-to-region narrow-start narrow-end)))
              (error
               (org-cli--validation-error
                "Failed to refresh buffer for file %s: %s. \
Check your Emacs hooks (`before-revert-hook', \
`after-revert-hook', `revert-buffer-function')"
                file-path (error-message-string err))))))))))

(defun org-cli--complete-and-save (file-path response-alist)
  "Create ID if needed, save FILE-PATH, return JSON.
Creates or gets an Org ID for the current headline and returns it.
FILE-PATH is the path to save the buffer contents to.
RESPONSE-ALIST is an alist of response fields."
  (let ((id (org-id-get-create)))
    (write-region (point-min) (point-max) file-path)
    (org-cli--refresh-file-buffers file-path)
    (json-encode
     (append
      `((success . t))
      response-alist
      `((uri . ,(concat org-cli--uri-id-prefix id)))))))

(defun org-cli--fail-if-modified (file-path operation)
  "Check if FILE-PATH has unsaved change in any buffer.
OPERATION is a string describing the operation for error messages."
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (when (and (buffer-file-name)
                 (string= (buffer-file-name) file-path)
                 (buffer-modified-p))
        (org-cli--validation-error
         "Cannot %s: file has unsaved changes in buffer"
         operation)))))

(defmacro org-cli--with-org-file (file-path &rest body)
  "Execute BODY in a temp Org buffer with file at FILE-PATH."
  (declare (indent 1) (debug (form body)))
  `(with-temp-buffer
     (insert-file-contents ,file-path)
     (org-mode)
     (goto-char (point-min))
     ,@body))

(defmacro org-cli--modify-and-save
    (file-path operation response-alist &rest body)
  "Execute BODY to modify Org file at FILE-PATH, then save result.
First validates that FILE-PATH has no unsaved changes (using
OPERATION for error messages).  Then executes BODY in a temp buffer
set up for the Org file.  After BODY executes, creates an Org ID if
needed, saves the buffer, refreshes any visiting buffers, and
returns the result of `org-cli--complete-and-save' with FILE-PATH
and RESPONSE-ALIST.
BODY can access FILE-PATH, OPERATION, and RESPONSE-ALIST as
variables."
  (declare (indent 3) (debug (form form form body)))
  `(progn
     (org-cli--fail-if-modified ,file-path ,operation)
     (with-temp-buffer
       (set-visited-file-name ,file-path t)
       (insert-file-contents ,file-path)
       (org-mode)
       (goto-char (point-min))
       ,@body
       (org-cli--complete-and-save ,file-path ,response-alist))))

(defun org-cli--find-allowed-file-with-id (id)
  "Find an allowed file containing the Org ID.
First looks up in the org-id database, then validates the file is in
the allowed list.
Returns the expanded file path if found and allowed.
Throws an error if ID exists but file is not allowed, or if ID
is not found."
  (if-let* ((id-file (org-id-find-id-file id)))
      ;; ID found in database, check if file is allowed
      (if-let* ((allowed-file (org-cli--find-allowed-file id-file)))
          allowed-file
        (org-cli--file-access-error id))
    ;; ID not in database - might not exist or DB is stale
    ;; Fall back to searching allowed files manually
    (if (null org-cli-allowed-files)
        ;; No allowed files configured - can't search, ID must be in DB
        (org-cli--id-not-found-error id)
      ;; Search through allowed files
      (let ((found-file nil))
        (dolist (allowed-file org-cli-allowed-files)
          (unless found-file
            (when (file-exists-p allowed-file)
              (org-cli--with-org-file allowed-file
                                      (when (org-find-property "ID" id)
                                        (setq found-file (expand-file-name allowed-file)))))))
        (or found-file (org-cli--id-not-found-error id))))))

(defmacro org-cli--with-uri-prefix-dispatch
    (uri headline-body id-body)
  "Dispatch tool URI handling based on prefix.
URI is the URI string to dispatch on.
HEADLINE-BODY is executed when URI starts with
`org-cli--uri-headline-prefix', with the URI after the prefix bound
to `headline'.
ID-BODY is executed when URI starts with `org-cli--uri-id-prefix',
with the URI after the prefix bound to `id'.
Throws an error if neither prefix matches."
  (declare (indent 1))
  `(if-let* ((id
              (org-cli--extract-uri-suffix
               ,uri org-cli--uri-id-prefix)))
       ,id-body
     (if-let* ((headline
                (org-cli--extract-uri-suffix
                 ,uri org-cli--uri-headline-prefix)))
         ,headline-body
       (org-cli--validation-error
        "Invalid resource URI format: %s"
        ,uri))))

(defun org-cli--validate-file-access (filename)
  "Validate that FILENAME is in the allowed list.
FILENAME must be an absolute path.
Returns the full path if allowed, signals an error otherwise.
If `org-cli-allowed-files' is nil, all absolute paths are allowed."
  (unless (file-name-absolute-p filename)
    (org-cli--resource-validation-error "Path must be absolute: %s"
                                        filename))
  (let ((allowed-file (org-cli--find-allowed-file filename)))
    (unless allowed-file
      (org-cli--resource-file-access-error filename))
    allowed-file))

(defun org-cli--extract-children (target-level)
  "Extract children at TARGET-LEVEL until next lower level heading."
  (let ((children '()))
    (save-excursion
      (while (and (re-search-forward "^\\*+ " nil t)
                  (>= (org-current-level) target-level))
        (when (= (org-current-level) target-level)
          (let* ((title (org-get-heading t t t t))
                 (child
                  `((title . ,title)
                    (level . ,target-level)
                    (children . []))))
            (push child children)))))
    (vconcat (nreverse children))))

(defun org-cli--extract-headings ()
  "Extract heading structure from current org buffer."
  (let ((result '()))
    (goto-char (point-min))
    (while (re-search-forward "^\\* " nil t) ; Find level 1 headings
      (let* ((title (org-get-heading t t t t))
             ;; Get level 2 children
             (children (org-cli--extract-children 2))
             (heading
              `((title . ,title) (level . 1) (children . ,children))))
        (push heading result)))
    (vconcat (nreverse result))))

(defun org-cli--generate-outline (file-path)
  "Generate JSON outline structure for FILE-PATH."
  (org-cli--with-org-file file-path
                          (let ((headings (org-cli--extract-headings)))
                            `((headings . ,headings)))))

(defun org-cli--decode-file-path (encoded-path)
  "Decode special characters from ENCODED-PATH.
Specifically decodes %23 back to #."
  (replace-regexp-in-string "%23" "#" encoded-path))

(defun org-cli--split-headline-uri (path-after-protocol)
  "Split PATH-AFTER-PROTOCOL into (file-path . headline-path).
PATH-AFTER-PROTOCOL is the part after `org-headline://'.
Returns (FILE . HEADLINE) where FILE is the decoded file path and
HEADLINE is the part after the fragment separator.
File paths with # characters should be encoded as %23."
  (if-let* ((hash-pos (string-match "#" path-after-protocol)))
      (cons
       (org-cli--decode-file-path
        (substring path-after-protocol 0 hash-pos))
       (substring path-after-protocol (1+ hash-pos)))
    (cons (org-cli--decode-file-path path-after-protocol) nil)))

(defun org-cli--parse-resource-uri (uri)
  "Parse URI and return (file-path . headline-path).
Validates file access and returns expanded file path."
  (let (file-path
        headline-path)
    (org-cli--with-uri-prefix-dispatch
     uri
     ;; Handle org-headline:// URIs
     (let* ((split-result (org-cli--split-headline-uri headline))
            (filename (car split-result))
            (headline-path-str (cdr split-result))
            (allowed-file (org-cli--validate-file-access filename)))
       (setq file-path (expand-file-name allowed-file))
       (setq headline-path
             (when headline-path-str
               (mapcar
                #'url-unhex-string
                (split-string headline-path-str "/")))))
     ;; Handle org-id:// URIs
     (progn
       (setq file-path (org-cli--find-allowed-file-with-id id))
       (setq headline-path (list id))))
    (cons file-path headline-path)))

(defun org-cli--navigate-to-headline (headline-path)
  "Navigate to headline in HEADLINE-PATH.
HEADLINE-PATH is a list of headline titles forming a path.
Returns t if found, nil otherwise.  Point is left at the headline."
  (catch 'not-found
    (let ((search-start (point-min))
          (search-end (point-max))
          (current-level 0)
          (found nil)
          (path-index 0))
      (dolist (target-title headline-path)
        (setq found nil)
        (goto-char search-start)
        (while (and (not found)
                    (re-search-forward "^\\*+ " search-end t))
          (let ((title (org-get-heading t t t t))
                (level (org-current-level)))
            (when (and (string= title target-title)
                       (or (= current-level 0)
                           (= level (1+ current-level))))
              (setq found t)
              (setq current-level level)
              ;; Limit search to this subtree for nesting
              (when (< (1+ path-index) (length headline-path))
                (setq search-start (point))
                (setq search-end
                      (save-excursion
                        (org-end-of-subtree t t)
                        (point)))))))
        (unless found
          (throw 'not-found nil))
        (setq path-index (1+ path-index))))
    t))

(defun org-cli--extract-headline-content ()
  "Extract content of current headline including the headline itself.
Point should be at the headline."
  (let ((start (line-beginning-position)))
    (org-end-of-subtree t t)
    ;; Remove trailing newline if present
    (when (and (> (point) start) (= (char-before) ?\n))
      (backward-char))
    (buffer-substring-no-properties start (point))))

(defun org-cli--get-headline-content (file-path headline-path)
  "Get content for headline at HEADLINE-PATH in FILE-PATH.
HEADLINE-PATH is a list of headline titles to traverse.
Returns the content string or nil if not found."
  (org-cli--with-org-file file-path
                          (when (org-cli--navigate-to-headline headline-path)
                            (org-cli--extract-headline-content))))

(defun org-cli--goto-headline-from-uri (headline-path is-id)
  "Navigate to headline based on HEADLINE-PATH and IS-ID flag.
If IS-ID is non-nil, treats HEADLINE-PATH as containing an ID.
Otherwise, navigates using HEADLINE-PATH as title hierarchy."
  (if is-id
      ;; ID case - headline-path contains single ID
      (if-let* ((pos (org-find-property "ID" (car headline-path))))
          (goto-char pos)
        (org-cli--id-not-found-error (car headline-path)))
    ;; Path case - headline-path contains title hierarchy
    (unless (org-cli--navigate-to-headline headline-path)
      (org-cli--headline-not-found-error headline-path))))

(defun org-cli--get-content-by-id (file-path id)
  "Get content for org node with ID in FILE-PATH.
Returns the content string or nil if not found."
  (org-cli--with-org-file file-path
                          (when-let* ((pos (org-find-property "ID" id)))
                            (goto-char pos)
                            (org-cli--extract-headline-content))))

(defun org-cli--validate-todo-state (state)
  "Validate STATE is a valid TODO keyword."
  (let ((valid-states
         (delete
          "|"
          (org-remove-keyword-keys
           (apply #'append (mapcar #'cdr org-todo-keywords))))))
    (unless (member state valid-states)
      (org-cli--validation-error
       "Invalid TODO state: '%s' - valid states: %s"
       state (mapconcat #'identity valid-states ", ")))))

(defun org-cli--validate-and-normalize-tags (tags)
  "Validate and normalize TAGS.
TAGS can be a single tag string or list of tag strings.
Returns normalized tag list.
Validates:
- Tag names follow Org rules (alphanumeric, underscore, at-sign)
- Tags are in configured tag alist (if configured)
- Tags don't violate mutual exclusivity groups
Signals error for invalid tags."
  (let ((tag-list (org-cli--normalize-tags-to-list tags))
        (allowed-tags
         (append
          (mapcar
           #'org-cli--extract-tag-from-alist-entry org-tag-alist)
          (mapcar
           #'org-cli--extract-tag-from-alist-entry
           org-tag-persistent-alist))))
    ;; Remove special keywords like :startgroup
    (setq allowed-tags
          (cl-remove-if
           #'org-cli--is-tag-group-keyword-p allowed-tags))
    ;; If tag alists are configured, validate against them
    (when allowed-tags
      (dolist (tag tag-list)
        (unless (member tag allowed-tags)
          (org-cli--validation-error
           "Tag not in configured tag alist: %s"
           tag))))
    ;; Always validate tag names follow Org's rules
    (dolist (tag tag-list)
      (unless (string-match "^[[:alnum:]_@]+$" tag)
        (org-cli--validation-error
         "Invalid tag name (must be alphanumeric, _, or @): %s"
         tag)))
    ;; Validate mutual exclusivity if tag-alist is configured
    (when org-tag-alist
      (org-cli--validate-mutex-tag-groups tag-list org-tag-alist))
    (when org-tag-persistent-alist
      (org-cli--validate-mutex-tag-groups
       tag-list org-tag-persistent-alist))
    tag-list))

(defun org-cli--extract-tag-from-alist-entry (entry)
  "Extract tag name from an `org-tag-alist' ENTRY.
ENTRY can be a string or a cons cell (tag . key)."
  (if (consp entry)
      (car entry)
    entry))

(defun org-cli--is-tag-group-keyword-p (tag)
  "Check if symbol TAG is a special keyword like :startgroup."
  (and (symbolp tag) (string-match "^:" (symbol-name tag))))

(defun org-cli--parse-mutex-tag-groups (tag-alist)
  "Parse mutually exclusive tag groups from TAG-ALIST.
Returns a list of lists, where each inner list contains tags
that are mutually exclusive with each other."
  (let ((groups '())
        (current-group nil)
        (in-group nil))
    (dolist (entry tag-alist)
      (cond
       ;; Start of a mutex group
       ((eq entry :startgroup)
        (setq in-group t)
        (setq current-group '()))
       ;; End of a mutex group
       ((eq entry :endgroup)
        (when (and in-group current-group)
          (push current-group groups))
        (setq in-group nil)
        (setq current-group nil))
       ;; Inside a group - collect tags
       (in-group
        (let ((tag (org-cli--extract-tag-from-alist-entry entry)))
          (when (and tag (not (org-cli--is-tag-group-keyword-p tag)))
            (push tag current-group))))))
    groups))

(defun org-cli--validate-mutex-tag-groups (tags tag-alist)
  "Validate that TAGS don't violate mutex groups in TAG-ALIST.
TAGS is a list of tag strings.
Errors if multiple tags from same mutex group."
  (let ((mutex-groups (org-cli--parse-mutex-tag-groups tag-alist)))
    (dolist (group mutex-groups)
      (let ((tags-in-group
             (cl-intersection tags group :test #'string=)))
        (when (> (length tags-in-group) 1)
          (org-cli--validation-error
           "Tags %s are mutually exclusive (cannot use together)"
           (mapconcat (lambda (tag) (format "'%s'" tag)) tags-in-group
                      ", ")))))))

(defun org-cli--validate-headline-title (title)
  "Validate that TITLE is not empty or whitespace-only.
Throws an error if validation fails."
  (when (or (string-empty-p title)
            (string-match-p "^[[:space:]]*$" title)
            ;; Explicitly match NBSP for Emacs 27.2 compatibility
            ;; In Emacs 27.2, [[:space:]] doesn't match NBSP (U+00A0)
            (string-match-p "^[\u00A0]*$" title))
    (org-cli--validation-error
     "Headline title cannot be empty or contain only whitespace"))
  (when (string-match-p "[\n\r]" title)
    (org-cli--validation-error
     "Headline title cannot contain newlines")))

(defun org-cli--validate-body-no-headlines (body level)
  "Validate that BODY doesn't contain headlines at LEVEL or higher.
LEVEL is the Org outline level (1 for *, 2 for **, etc).
Throws an MCP tool error if invalid headlines are found."
  ;; Build regex to match headlines at the current level or higher
  ;; For level 3, this matches ^*, ^**, or ^***
  ;; Matches asterisks + space/tab (headlines need content)
  (let ((regex (format "^\\*\\{1,%d\\}[ \t]" level)))
    (when (string-match regex body)
      (org-cli--validation-error
       "Body cannot contain headlines at level %d or higher"
       level))))

(defun org-cli--validate-body-no-unbalanced-blocks (body)
  "Validate that BODY doesn't contain unbalanced blocks.
Uses a state machine: tracks if we're in a block, and which one.
Text inside blocks is literal and doesn't start/end other blocks.
Throws an error if unbalanced blocks are found."
  (with-temp-buffer
    (insert body)
    (goto-char (point-min))
    (let
        ((current-block nil)) ; Current block type or nil
      ;; Scan forward for all block markers
      ;; Block names can be any non-whitespace chars
      (while (re-search-forward
              "^#\\+\\(BEGIN\\|END\\|begin\\|end\\)_\\(\\S-+\\)"
              nil t)
        (let ((marker-type (upcase (match-string 1)))
              (block-type (upcase (match-string 2))))
          (cond
           ;; Found BEGIN
           ((string= marker-type "BEGIN")
            (if current-block
                ;; Already in block - BEGIN is literal
                nil
              ;; Not in a block - enter this block
              (setq current-block block-type)))
           ;; Found END
           ((string= marker-type "END")
            (cond
             ;; Not in any block - this END is orphaned
             ((null current-block)
              (org-cli--validation-error
               "Orphaned END_%s without BEGIN_%s"
               block-type block-type))
             ;; In matching block - exit the block
             ((string= current-block block-type)
              (setq current-block nil))
             ;; In different block - this END is just literal text
             (t
              nil))))))
      ;; After scanning, check if we're still in a block
      (when current-block
        (org-cli--validation-error
         "Body contains unclosed %s block"
         current-block)))))

(defun org-cli--normalize-tags-to-list (tags)
  "Normalize TAGS parameter to a list format.
TAGS can be:
- nil or empty list -> returns nil
- vector (JSON array) -> converts to list
- string -> wraps in list
- list -> returns as-is
Throws error for invalid types."
  (cond
   ((null tags)
    nil) ; No tags (nil or empty list)
   ((vectorp tags)
    (append tags nil)) ; Convert JSON array (vector) to list
   ((listp tags)
    tags) ; Already a list
   ((stringp tags)
    (list tags)) ; Single tag string
   (t
    (org-cli--validation-error "Invalid tags format: %s" tags))))

(defun org-cli--navigate-to-parent-or-top (parent-path parent-id)
  "Navigate to parent headline or top of file.
PARENT-PATH is a list of headline titles (or nil for top-level).
PARENT-ID is an ID string (or nil).
Returns parent level (integer) if parent exists, nil for top-level.
Assumes point is in an Org buffer."
  (if (or parent-path parent-id)
      (progn
        (org-cli--goto-headline-from-uri
         (or (and parent-id (list parent-id)) parent-path) parent-id)
        ;; Save parent level before moving point
        ;; Ensure we're at the beginning of headline
        (org-back-to-heading t)
        (org-current-level))
    ;; No parent specified - top level
    ;; Skip past any header comments (#+TITLE, #+AUTHOR, etc.)
    (while (and (not (eobp)) (looking-at "^#\\+"))
      (forward-line))
    ;; Position correctly: if blank line after headers,
    ;; skip it; if headline immediately after, stay
    (when (and (not (eobp)) (looking-at "^[ \t]*$"))
      ;; On blank line after headers, skip
      (while (and (not (eobp)) (looking-at "^[ \t]*$"))
        (forward-line)))
    nil))

(defun org-cli--position-for-new-child (after-uri parent-end)
  "Position point for inserting a new child under current heading.
AFTER-URI is an optional org-id:// URI of a sibling to insert after.
PARENT-END is the end position of the parent's subtree.
Assumes point is at parent heading.
If AFTER-URI is non-nil, positions after that sibling.
If nil, positions at end of parent's subtree.
Throws validation error if AFTER-URI is invalid or sibling not found."
  (if (and after-uri (not (string-empty-p after-uri)))
      (progn
        ;; Parse afterUri to get the ID
        (let ((after-id
               (org-cli--extract-uri-suffix
                after-uri org-cli--uri-id-prefix))
              (found nil))
          (unless after-id
            (org-cli--validation-error
             "Field after_uri is not %s: %s"
             org-cli--uri-id-prefix after-uri))
          ;; Find the sibling with the specified ID
          (org-back-to-heading t) ;; At parent
          ;; Search sibling in parent's subtree
          ;; Move to first child
          (if (org-goto-first-child)
              (progn
                ;; Now search among siblings
                (while (and (not found) (< (point) parent-end))
                  (let ((current-id (org-entry-get nil "ID")))
                    (when (string= current-id after-id)
                      (setq found t)
                      ;; Move to sibling end
                      (org-end-of-subtree t t)))
                  (unless found
                    ;; Move to next sibling
                    (unless (org-get-next-sibling)
                      ;; No more siblings
                      (goto-char parent-end)))))
            ;; No children
            (goto-char parent-end))
          (unless found
            (org-cli--validation-error
             "Sibling with ID %s not found under parent"
             after-id))))
    ;; No after_uri - insert at end of parent's subtree
    (org-end-of-subtree t t)
    ;; If we're at the start of a sibling, go back one char
    ;; to be at the end of parent's content
    (when (looking-at "^\\*+ ")
      (backward-char 1))))

(defun org-cli--ensure-newline ()
  "Ensure there is a newline or buffer start before point."
  (unless (or (bobp) (looking-back "\n" 1))
    (insert "\n")))

(defun org-cli--insert-heading (title parent-level)
  "Insert a new Org heading at the appropriate level.
TITLE is the headline text to insert.
PARENT-LEVEL is the parent's heading level (integer) if inserting
as a child, or nil if inserting at top-level.
Assumes point is positioned where the heading should be inserted.
After insertion, point is left on the heading line at end-of-line."
  (if parent-level
      ;; We're inside a parent
      (progn
        (org-cli--ensure-newline)
        ;; Insert heading manually at parent level + 1
        ;; We don't use `org-insert-heading' because when parent has
        ;; no children, it creates a sibling of the parent instead of
        ;; a child
        (let ((heading-start (point)))
          (insert (make-string (1+ parent-level) ?*) " " title "\n")
          ;; Set point to heading for `org-todo' and `org-set-tags'
          (goto-char heading-start)
          (end-of-line)))
    ;; Top-level heading
    ;; Check if there are no headlines yet (empty buffer or only
    ;; headers before us)
    (let ((has-headline
           (save-excursion
             (goto-char (point-min))
             (re-search-forward "^\\*+ " nil t))))
      (if (not has-headline)
          (progn
            (org-cli--ensure-newline)
            (insert "* "))
        ;; Has headlines - use `org-insert-heading'
        ;; Ensure proper spacing before inserting
        (org-cli--ensure-newline)
        (org-insert-heading nil nil t))
      (insert title))))

(defun org-cli--replace-body-content
    (old-body new-body body-content replace-all body-begin body-end)
  "Replace body content in the current buffer.
OLD-BODY is the substring to replace.  When empty, NEW-BODY replaces
the entire body content (set-body mode).
NEW-BODY is the replacement text.
BODY-CONTENT is the current body content string.
REPLACE-ALL if non-nil, replace all occurrences.
BODY-BEGIN is the buffer position where body starts.
BODY-END is the buffer position where body ends."
  (let ((new-body-content
         (cond
          ;; Set-body mode: empty oldBody = replace entire body
          ((string= old-body "")
           new-body)
          ;; Normal replacement with replaceAll
          (replace-all
           (replace-regexp-in-string
            (regexp-quote old-body) new-body body-content
            t t))
          ;; Normal single replacement
          (t
           (let ((pos
                  (string-match
                   (regexp-quote old-body) body-content)))
             (if pos
                 (concat
                  (substring body-content 0 pos)
                  new-body
                  (substring body-content (+ pos (length old-body))))
               body-content))))))
    ;; Replace the body content in the buffer
    (if (< body-begin body-end)
        (delete-region body-begin body-end)
      ;; Empty body - ensure we're at the right position
      (goto-char body-begin))
    (insert new-body-content)
    ;; Ensure body ends with a newline to prevent merging with
    ;; the next headline.  Check the character right after the
    ;; inserted content.
    (when (and (> (length new-body-content) 0)
               (not (string-suffix-p "\n" new-body-content))
               (< (point) (point-max)))
      (insert "\n"))))

;; Tool handlers

(defun org-cli-get-todo-config ()
  "Return the TODO keyword configuration."
  (let ((seq-list '())
        (sem-list '()))
    (dolist (seq org-todo-keywords)
      (let* ((type (car seq))
             (keywords (cdr seq))
             (type-str (symbol-name type))
             (keyword-vec [])
             (before-bar t))
        (dolist (kw keywords)
          (if (string= kw "|")
              (setq before-bar nil)
            ;; Check if this is the last keyword and no "|" seen
            (let ((is-last-no-bar
                   (and before-bar (equal kw (car (last keywords))))))
              (when is-last-no-bar
                (setq keyword-vec (vconcat keyword-vec ["|"])))
              (push `((state
                       .
                       ,(car (org-remove-keyword-keys (list kw))))
                      (isFinal
                       . ,(or is-last-no-bar (not before-bar)))
                      (sequenceType . ,type-str))
                    sem-list)))
          (setq keyword-vec (vconcat keyword-vec (vector kw))))
        (push
         `((type . ,type-str) (keywords . ,keyword-vec)) seq-list)))
    (json-encode
     `((sequences . ,(vconcat (nreverse seq-list)))
       (semantics . ,(vconcat (nreverse sem-list)))))))

(defun org-cli-get-tag-config ()
  "Return the tag configuration as literal Elisp strings."
  (json-encode
   `((org-use-tag-inheritance
      .
      ,(prin1-to-string org-use-tag-inheritance))
     (org-tags-exclude-from-inheritance
      . ,(prin1-to-string org-tags-exclude-from-inheritance))
     (org-tag-alist . ,(prin1-to-string org-tag-alist))
     (org-tag-persistent-alist
      . ,(prin1-to-string org-tag-persistent-alist)))))

(defun org-cli-get-allowed-files ()
  "Return the list of allowed Org files."
  (json-encode `((files . ,(vconcat org-cli-allowed-files)))))

(defun org-cli-update-todo-state (uri current_state new_state)
  "Update the TODO state of a headline at URI.
Creates an Org ID for the headline if one doesn't exist.
Returns the ID-based URI for the updated headline.
CURRENT_STATE is the current TODO state (empty string for no state).
NEW_STATE is the new TODO state to set."
  (let* ((parsed (org-cli--parse-resource-uri uri))
         (file-path (car parsed))
         (headline-path (cdr parsed)))
    (org-cli--validate-todo-state new_state)
    (org-cli--modify-and-save file-path "update"
                              `((previous_state
                                 .
                                 ,(or current_state ""))
                                (new_state . ,new_state))
                              (org-cli--goto-headline-from-uri
                               headline-path (string-prefix-p org-cli--uri-id-prefix uri))

                              ;; Check current state matches
                              (beginning-of-line)
                              (let ((actual-state (org-get-todo-state)))
                                (unless (string= actual-state current_state)
                                  (org-cli--state-mismatch-error
                                   (or current_state "(no state)")
                                   (or actual-state "(no state)") "State")))

                              ;; Update the state
                              (org-todo new_state))))

(defun org-cli-add-todo
    (title todo_state tags body parent_uri &optional after_uri)
  "Add a new TODO item to an Org file.
Creates an Org ID for the new headline and returns its ID-based URI.
TITLE is the headline text.
TODO_STATE is the TODO state from `org-todo-keywords'.
TAGS is a single tag string or list of tag strings.
BODY is optional body text.
PARENT_URI is the URI of the parent item.
AFTER_URI is optional URI of sibling to insert after."
  (org-cli--validate-headline-title title)
  (org-cli--validate-todo-state todo_state)
  (let* ((tag-list (org-cli--validate-and-normalize-tags tags))
         file-path
         parent-path
         parent-id)

    ;; Parse parent URI once to extract file-path and parent location
    (org-cli--with-uri-prefix-dispatch
     parent_uri
     ;; Handle org-headline:// URIs
     (let* ((split-result (org-cli--split-headline-uri headline))
            (filename (car split-result))
            (path-str (cdr split-result))
            (allowed-file (org-cli--validate-file-access filename)))
       (setq file-path (expand-file-name allowed-file))
       (when (and path-str (> (length path-str) 0))
         (setq parent-path
               (mapcar
                #'url-unhex-string (split-string path-str "/")))))
     ;; Handle org-id:// URIs
     (progn
       (setq file-path (org-cli--find-allowed-file-with-id id))
       (setq parent-id id)))

    ;; Add the TODO item
    (org-cli--modify-and-save file-path "add TODO"
                              `((file
                                 .
                                 ,(file-name-nondirectory file-path))
                                (title . ,title))
                              (let ((parent-level
                                     (org-cli--navigate-to-parent-or-top
                                      parent-path parent-id)))

                                ;; Handle positioning after navigation to parent
                                (when (or parent-path parent-id)
                                  (let ((parent-end
                                         (save-excursion
                                           (org-end-of-subtree t t)
                                           (point))))
                                    (org-cli--position-for-new-child after_uri parent-end)))

                                ;; Validate body before inserting heading
                                ;; Calculate the target level for validation
                                (let ((target-level
                                       (if (or parent-path parent-id)
                                           ;; Child heading - parent level + 1
                                           (1+ (or parent-level 0))
                                         ;; Top-level heading
                                         1)))

                                  ;; Validate body content if provided
                                  (when body
                                    (org-cli--validate-body-no-headlines body target-level)
                                    (org-cli--validate-body-no-unbalanced-blocks body)))

                                ;; Insert the new heading
                                (org-cli--insert-heading title parent-level)

                                (org-todo todo_state)

                                (when tag-list
                                  (org-set-tags tag-list))

                                ;; Add body if provided
                                (if body
                                    (progn
                                      (end-of-line)
                                      (insert "\n" body)
                                      (unless (string-suffix-p "\n" body)
                                        (insert "\n"))
                                      ;; Move back to the heading for org-id-get-create
                                      ;; org-id-get-create requires point to be on a heading
                                      (org-back-to-heading t))
                                  ;; No body - ensure newline after heading
                                  (end-of-line)
                                  (unless (looking-at "\n")
                                    (insert "\n")))))))

;; Resource handlers (internal, used by tool wrappers)

(defun org-cli-handle-outline-resource (params)
  "Handler for org://{filename}/outline template.
PARAMS is an alist containing the filename parameter."
  (let* ((filename (alist-get "filename" params nil nil #'string=))
         (allowed-file (org-cli--validate-file-access filename))
         (outline
          (org-cli--generate-outline
           (expand-file-name allowed-file))))
    (json-encode outline)))

(defun org-cli-handle-file-resource (params)
  "Handler for org://{filename} template.
PARAMS is an alist containing the filename parameter."
  (let* ((filename (alist-get "filename" params nil nil #'string=))
         (allowed-file (org-cli--validate-file-access filename)))
    (org-cli--read-file (expand-file-name allowed-file))))

(defun org-cli-handle-headline-resource (params)
  "Handler for org-headline://{filename} template.
PARAMS is an alist containing the filename parameter.
The filename parameter includes both file and headline path."
  (let* ((full-path (alist-get "filename" params nil nil #'string=))
         (split-result (org-cli--split-headline-uri full-path))
         (filename (car split-result))
         (allowed-file (org-cli--validate-file-access filename))
         (headline-path-str (cdr split-result))
         ;; Parse the path (URL-encoded headline path)
         (headline-path
          (when headline-path-str
            (mapcar
             #'url-unhex-string
             (split-string headline-path-str "/")))))
    (if headline-path
        (let ((content
               (org-cli--get-headline-content
                allowed-file headline-path)))
          (unless content
            (org-cli--resource-not-found-error
             "headline" (mapconcat #'identity headline-path "/")))
          content)
      ;; No headline path means get entire file
      (org-cli--read-file allowed-file))))

(defun org-cli-handle-id-resource (params)
  "Handler for org-id://{uuid} template.
PARAMS is an alist containing the uuid parameter."
  (let* ((id (alist-get "uuid" params nil nil #'string=))
         (file-path (org-id-find-id-file id)))
    (unless file-path
      (org-cli--resource-not-found-error "ID" id))
    (let ((allowed-file (org-cli--find-allowed-file file-path)))
      (unless allowed-file
        (org-cli--resource-file-access-error id))
      (org-cli--get-content-by-id allowed-file id))))

(defun org-cli-rename-headline (uri current_title new_title)
  "Rename headline title at URI from CURRENT_TITLE to NEW_TITLE.
Preserves the current TODO state and tags, creates an Org ID for the
headline if one doesn't exist.
Returns the ID-based URI for the renamed headline."
  (org-cli--validate-headline-title new_title)

  (let* ((parsed (org-cli--parse-resource-uri uri))
         (file-path (car parsed))
         (headline-path (cdr parsed)))

    ;; Rename the headline in the file
    (org-cli--modify-and-save file-path "rename"
                              `((previous_title . ,current_title)
                                (new_title . ,new_title))
                              ;; Navigate to the headline
                              (org-cli--goto-headline-from-uri
                               headline-path (string-prefix-p org-cli--uri-id-prefix uri))

                              ;; Verify current title matches
                              (beginning-of-line)
                              (let ((actual-title (org-get-heading t t t t)))
                                (unless (string= actual-title current_title)
                                  (org-cli--state-mismatch-error
                                   current_title actual-title "Title")))

                              (org-edit-headline new_title))))

(defun org-cli-edit-body
    (resource_uri old_body new_body replace_all)
  "Edit body content of an Org node using partial string replacement.
RESOURCE_URI is the URI of the node to edit.
OLD_BODY is the substring to replace.  Use \"\" to set the entire
body (replacing any existing content, or inserting into an empty body).
NEW_BODY is the replacement text.
REPLACE_ALL if non-nil, replace all occurrences."
  ;; Normalize JSON false to nil for proper boolean handling
  ;; JSON false can arrive as :false (keyword) or "false" (string)
  (let ((replace_all
         (cond
          ((eq replace_all :false)
           nil)
          ((equal replace_all "false")
           nil)
          (t
           replace_all))))
    (org-cli--validate-body-no-unbalanced-blocks new_body)

    (let* ((parsed (org-cli--parse-resource-uri resource_uri))
           (file-path (car parsed))
           (headline-path (cdr parsed)))

      (org-cli--modify-and-save file-path "edit body" nil
                                (org-cli--goto-headline-from-uri
                                 headline-path
                                 (string-prefix-p org-cli--uri-id-prefix resource_uri))

                                ;; Save heading position so we can restore point after body replacement.
                                ;; This ensures org-id-get-create operates on the correct heading.
                                (let ((heading-pos (point)))

                                  ;; Ensure the PROPERTIES drawer and ID exist before body replacement.
                                  ;; This prevents org-id-get-create from placing the drawer in the
                                  ;; wrong position after body content changes shift point.
                                  (org-id-get-create)

                                  (org-cli--validate-body-no-headlines
                                   new_body (org-current-level))

                                  ;; Skip past headline and properties
                                  (org-end-of-meta-data t)

                                  ;; Get body boundaries
                                  (let ((body-begin (point))
                                        (body-end nil)
                                        (body-content nil)
                                        (occurrence-count 0))

                                    ;; Find end of body (before next headline or end of subtree)
                                    (save-excursion
                                      (if (org-goto-first-child)
                                          ;; Has children - body ends before first child
                                          (setq body-end (point))
                                        ;; No children - find end of the direct body content.
                                        ;; Use outline-next-heading to find the next heading
                                        ;; at any level, which marks where our body ends.
                                        (if (outline-next-heading)
                                            (setq body-end (point))
                                          ;; Last heading in file - body extends to end
                                          (goto-char (point-max))
                                          (setq body-end (point)))))

                                    ;; Extract body content
                                    (setq body-content
                                          (buffer-substring-no-properties body-begin body-end))

                                    ;; Trim leading newline if present
                                    ;; (`org-end-of-meta-data' includes it)
                                    (when (and (> (length body-content) 0)
                                               (= (aref body-content 0) ?\n))
                                      (setq body-content (substring body-content 1))
                                      (setq body-begin (1+ body-begin)))

                                    ;; Build trimmed version for matching (without trailing whitespace)
                                    ;; while keeping untrimmed version for replacement boundaries.
                                    (let ((body-for-match body-content))
                                      (when (string-match "[[:space:]]+\\'" body-for-match)
                                        (setq body-for-match
                                              (substring body-for-match 0 (match-beginning 0))))

                                      (cond
                                       ;; Case 1: old_body is empty string = set entire body
                                       ((string= old_body "")
                                        ;; Replace the entire body with new_body.
                                        ;; Works for both empty and non-empty bodies.
                                        (org-cli--replace-body-content
                                         "" new_body body-content replace_all
                                         body-begin body-end)
                                        ;; Restore point to the saved heading position so that
                                        ;; complete-and-save's org-id-get-create operates on
                                        ;; the correct heading.
                                        (goto-char heading-pos))

                                       ;; Case 2: body is empty, old_body is non-empty = error
                                       ((string-match-p "\\[`][[:space:]]*\\'" body-for-match)
                                        (org-cli--validation-error
                                         "Node has no body content"))

                                       ;; Case 3: normal partial replacement
                                       (t
                                        ;; Count occurrences using trimmed content
                                        (let ((case-fold-search nil)
                                              (search-pos 0))
                                          (while (string-match
                                                  (regexp-quote old_body) body-for-match
                                                  search-pos)
                                            (setq occurrence-count (1+ occurrence-count))
                                            (setq search-pos (match-end 0))))

                                        ;; Validate occurrences
                                        (cond
                                         ((= occurrence-count 0)
                                          (org-cli--validation-error
                                           "Body text not found: %s" old_body))
                                         ((and (> occurrence-count 1) (not replace_all))
                                          (org-cli--validation-error
                                           "Text appears %d times (use replace_all)"
                                           occurrence-count)))

                                        ;; Perform replacement using trimmed content for matching
                                        (org-cli--replace-body-content
                                         old_body new_body body-for-match replace_all
                                         body-begin body-end)
                                        ;; Restore point to the saved heading position so that
                                        ;; complete-and-save's org-id-get-create operates on
                                        ;; the correct heading.
                                        (goto-char heading-pos))))))))))

(defun org-cli-set-planning (uri planning_type timestamp)
  "Set or remove a planning item on an Org headline.
URI identifies the headline (org-headline:// or org-id://).
PLANNING_TYPE is one of \='deadline\=', \='scheduled\=', or \='closed\='.
TIMESTAMP is an Org date like \='2025-04-28\=', or nil/empty to remove.
Creates an Org ID property if one doesn\='t exist.
Returns JSON with success, planning_type, timestamp, uri,
and current planning state (deadline, scheduled, closed)."
  ;; Validate planning_type
  (unless (memq planning_type '(deadline scheduled closed))
    (org-cli--validation-error
     "Invalid planning_type: %S. Must be deadline, scheduled, or closed"
     planning_type))
  ;; Validate timestamp format when provided
  (when (and timestamp (not (string-empty-p timestamp)))
    (unless (string-match-p
             (rx bos (opt "<")
                 (= 4 (any "0-9")) "-" (= 2 (any "0-9")) "-" (= 2 (any "0-9"))
                 (opt (1+ " " (1+ (any "A-Za-z"))))
                 (opt " " (= 2 (any "0-9")) ":" (= 2 (any "0-9")))
                 (opt ">") eos)
             timestamp)
      (org-cli--validation-error
       "Invalid timestamp format: %S. Expected format: YYYY-MM-DD or <YYYY-MM-DD Day>"
       timestamp)))
  (let* ((parsed (org-cli--parse-resource-uri uri))
         (file-path (car parsed))
         (headline-path (cdr parsed))
         (is-id (string-prefix-p org-cli--uri-id-prefix uri))
         (remove-p (or (null timestamp) (string-empty-p timestamp)))
         ;; Normalize timestamp: ensure angle-bracket format
         (norm-ts
          (cond
           (remove-p nil)
           ((string-prefix-p "<" timestamp) timestamp)
           (t (concat "<" timestamp ">")))))
    ;; Perform the modification
    (org-cli--modify-and-save
     file-path "set-planning"
     `((planning_type . ,planning_type)
       (timestamp . ,(or timestamp "")))
     (org-cli--goto-headline-from-uri headline-path is-id)
     (beginning-of-line)
     ;; Read current planning values before modification
     (let ((old-deadline (org-entry-get (point) "DEADLINE"))
           (old-scheduled (org-entry-get (point) "SCHEDULED"))
           (old-closed (org-entry-get (point) "CLOSED")))
       (if remove-p
           (org-add-planning-info nil nil planning_type)
         (org-add-planning-info planning_type norm-ts)
         ;; Re-set other planning types that may have been cleared
         (when (and old-deadline (not (eq planning_type 'deadline)))
           (org-add-planning-info 'deadline old-deadline))
         (when (and old-scheduled (not (eq planning_type 'scheduled)))
           (org-add-planning-info 'scheduled old-scheduled))
         (when (and old-closed (not (eq planning_type 'closed)))
           (org-add-planning-info 'closed old-closed)))))
    ;; Read back the final planning state
    (org-cli--with-org-file file-path
                            (org-cli--goto-headline-from-uri headline-path is-id)
                            (beginning-of-line)
                            (let ((id (org-id-get))
                                  (dl (org-entry-get (point) "DEADLINE"))
                                  (sc (org-entry-get (point) "SCHEDULED"))
                                  (cl (org-entry-get (point) "CLOSED")))
                              (json-encode
                               `((success . t)
                                 (planning_type . ,planning_type)
                                 (timestamp
                                  . ,(pcase planning_type
                                       ('deadline (or dl ""))
                                       ('scheduled (or sc ""))
                                       ('closed (or cl ""))))
                                 (deadline . ,dl)
                                 (scheduled . ,sc)
                                 (closed . ,cl)
                                 (uri . ,(concat org-cli--uri-id-prefix id))))))))

;; Tool wrappers duplicating resource templates

(defun org-cli-read-file (file)
  "Read an Org file.
FILE is the absolute path to an Org file."
  (org-cli-handle-file-resource `(("filename" . ,file))))

(defun org-cli-read-outline (file)
  "Read outline of an Org file.
FILE is the absolute path to an Org file."
  (org-cli-handle-outline-resource `(("filename" . ,file))))

(defun org-cli-read-headline (file headline_path)
  "Read a specific Org headline.
FILE is the absolute path to an Org file.
HEADLINE_PATH is the non-empty slash-separated path to headline."
  (unless (stringp headline_path)
    (org-cli--validation-error
     "Parameter headline_path must be a string, got: %S (type: %s)"
     headline_path (type-of headline_path)))
  (when (string-empty-p headline_path)
    (org-cli--validation-error
     "Parameter headline_path must be non-empty; use \
org-read-file tool to read entire files"))
  (let ((full-path (concat file "#" headline_path)))
    (org-cli-handle-headline-resource `(("filename" . ,full-path)))))

(defun org-cli-read-by-id (uuid)
  "Read Org headline by its unique ID property.
UUID is the UUID from headline's ID property."
  (org-cli-handle-id-resource `(("uuid" . ,uuid))))

(defun org-cli--extract-todo-item ()
  "Extract TODO item data from the headline at point.
Returns an alist with state, title, tags, priority, deadline, scheduled,
and id, or nil if the headline has no TODO state."
  (let ((state (org-get-todo-state)))
    (when state
      (let* ((title (org-get-heading t t t t))
             (level (org-current-level))
             (tags (org-get-tags))
             (priority (org-entry-get nil "PRIORITY"))
             (deadline (org-entry-get nil "DEADLINE"))
             (scheduled (org-entry-get nil "SCHEDULED"))
             (id (org-entry-get nil "ID")))
        `((state . ,state)
          (title . ,title)
          (level . ,level)
          (tags . ,(vconcat tags))
          (priority . ,(or priority ""))
          (deadline . ,(or deadline ""))
          (scheduled . ,(or scheduled ""))
          (id . ,(or id "")))))))

(defun org-cli--extract-all-todos (file-path &optional section-path)
  "Extract all TODO items from FILE-PATH.
If SECTION-PATH is non-nil, limit to todos under that headline.
Returns a list of alists, each with state, title, level, tags,
priority, deadline, scheduled, and id."
  (org-cli--with-org-file file-path
    (when section-path
      (if (org-cli--navigate-to-headline section-path)
          (narrow-to-region (point)
                            (save-excursion (org-end-of-subtree t t) (point)))
        (org-cli--headline-not-found-error section-path)))
    (let ((todos '()))
      (goto-char (point-min))
      (while (re-search-forward "^\\*+ " nil t)
        (when-let* ((item (org-cli--extract-todo-item)))
          (push item todos)))
      (nreverse todos))))

(defun org-cli--format-todo-item-markdown (item)
  "Format a single TODO ITEM as a markdown table row.
ITEM is an alist with state, title, level, tags, priority, deadline,
scheduled, and id."
  (let ((state (alist-get 'state item))
        (title (alist-get 'title item))
        (tags (let ((tags-vec (alist-get 'tags item)))
                (if (> (length tags-vec) 0)
                    (mapconcat (lambda (tag) (format "\=%s\=" tag))
                               (append tags-vec nil) " ")
                  "")))
        (priority (let ((p (alist-get 'priority item)))
                    (if (member p '("" nil "B"))
                        ""
                      (format "[#%s]" p))))
        (deadline (let ((d (alist-get 'deadline item)))
                    (if (or (string-empty-p d) (not d))
                        ""
                      (org-cli--format-timestamp d))))
        (scheduled (let ((s (alist-get 'scheduled item)))
                     (if (or (string-empty-p s) (not s))
                         ""
                       (org-cli--format-timestamp s)))))
    (format "| %s | %s%s | %s | %s | %s |"
            state title priority tags deadline scheduled)))

(defun org-cli--format-timestamp (ts)
  "Format an Org timestamp TS for display.
Strips angle brackets and day-of-week if present.
Handles both date and date+time formats."
  (let ((s (replace-regexp-in-string "^<" "" ts)))
    (setq s (replace-regexp-in-string ">$" "" s))
    ;; Remove day-of-week: "2025-04-28 Mon" -> "2025-04-28"
    ;; But preserve time: "2026-05-01 Fri 13:00" -> "2026-05-01 13:00"
    (setq s (replace-regexp-in-string
             "\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\) [A-Za-z]\\{2,3\\}\\(?: \\([0-9]\\{2\\}:[0-9]\\{2\\}\\)\\)?"
             (lambda (m)
               (let ((date (match-string 1 m))
                     (time (match-string 2 m)))
                 (if time
                     (concat date " " time)
                   date)))
             s))))

(defun org-cli--todos-to-markdown (todos)
  "Format TODOS list as a markdown table.
TODOS is a list of alists from `org-cli--extract-all-todos'."
  (if (null todos)
      "No TODO items found."
    (concat
     "| State | Title | Tags | Deadline | Scheduled |\n"
     "|-------|-------|------|----------|-----------|\n"
     (mapconcat #'org-cli--format-todo-item-markdown todos "\n"))))

(defun org-cli--todos-to-kanban (todos)
  "Format TODOS list as a kanban-style markdown table.
States become columns, items are stacked under their state.
TODOS is a list of alists from `org-cli--extract-all-todos'."
  (if (null todos)
      "No TODO items found."
    (let* ((states (delete-dups
                    (mapcar (lambda (item) (alist-get 'state item)) todos)))
           ;; Preserve TODO keyword order: todo-states first, done-states last
           (todo-keywords
            (delete "|"
                    (org-remove-keyword-keys
                     (apply #'append (mapcar #'cdr org-todo-keywords)))))
           (todo-half (cl-member-if
                       (lambda (kw) (member kw states)) todo-keywords))
           (done-half (cdr (cl-member "|" todo-keywords :test #'string=)))
           (ordered-states
            (cl-remove-if-not
             (lambda (s) (member s states))
             (append todo-half done-half)))
           ;; Any states not found in org-todo-keywords
           (remaining-states
            (cl-remove-if (lambda (s) (member s ordered-states)) states))
           (all-states (append ordered-states remaining-states))
           ;; Build alist: state -> list of formatted titles
           (state-items
            (let ((table (mapcar (lambda (s) (cons s '())) all-states)))
              (dolist (item todos)
                (let* ((state (alist-get 'state item))
                       (title (alist-get 'title item))
                       (tags-vec (alist-get 'tags item))
                       (tags (if (> (length tags-vec) 0)
                                 (concat " "
                                         (mapconcat
                                          (lambda (tag) (format "\=%s\=" tag))
                                          (append tags-vec nil) " "))
                               ""))
                       (d (alist-get 'deadline item))
                       (deadline (if (or (string-empty-p d) (not d))
                                     ""
                                   (concat " " (org-cli--format-timestamp d))))
                       (cell (concat title tags deadline)))
                  (setcdr (assoc state table)
                          (nconc (cdr (assoc state table)) (list cell)))))
              table))
           (max-count (apply #'max (or (mapcar
                                          (lambda (pair) (length (cdr pair)))
                                          state-items)
                                         '(0)))))
      (concat
       ;; Header row: state names as columns
       "| " (mapconcat #'identity all-states " | ") " |\n"
       ;; Separator row
       "|" (mapconcat (lambda (_) "---") all-states "|") "|\n"
       ;; Data rows: one per slot, empty cells where a state has fewer items
       (mapconcat
        (lambda (row-idx)
          (concat
           "| "
           (mapconcat
            (lambda (state-pair)
              (let ((items (cdr state-pair)))
                (if (< row-idx (length items))
                    (nth row-idx items)
                  "")))
            state-items " | ")
           " |"))
        (number-sequence 0 (1- max-count)) "\n")))))

(defun org-cli-list-todos (file &optional headline_path format)
  "List all TODO items in FILE, optionally under HEADLINE_PATH.
FORMAT controls output format: \='json\=' (default), \='markdown\=', or \='kanban\='.
Returns JSON with a \='todos\=' array, a markdown table, or a kanban board."
  (let* ((allowed-file (org-cli--validate-file-access file))
         (section-path (when (and headline_path
                                  (not (string-empty-p headline_path)))
                         (mapcar #'url-unhex-string
                                 (split-string headline_path "/"))))
         (todos (org-cli--extract-all-todos allowed-file section-path))
         (fmt (or format "json")))
    (cond
     ((equal fmt "kanban")
      (org-cli--todos-to-kanban todos))
     ((equal fmt "markdown")
      (org-cli--todos-to-markdown todos))
     (t
      (json-encode `((todos . ,(vconcat todos))))))))

;;; CLI Entry Point

(defun org-cli-usage ()
  "Print usage information to stdout."
  (princ (format "org-cli CLI v%s

Usage: emacs --batch -l init.el -l org-cli.el --eval '(org-cli)' -- COMMAND [ARGS...]

Commands:
  get-todo-config                   Get TODO keyword configuration
  get-tag-config                    Get tag configuration
  get-allowed-files                 List allowed Org files
  read-file FILE                    Read complete Org file
  read-outline FILE                 Read hierarchical outline of Org file
  read-headline FILE HEADLINE-PATH  Read specific headline by path
  read-by-id UUID                   Read headline by its ID property
  list-todos FILE [HEADLINE-PATH] [FORMAT]
                                    List TODO items (FORMAT: json, markdown, or kanban)
  update-todo-state URI CURRENT NEW Update TODO state of a headline
  add-todo TITLE STATE PARENT-URI [TAGS] [BODY] [AFTER-URI]
                                    Add a new TODO item
  rename-headline URI CURRENT NEW   Rename a headline
  edit-body URI OLD NEW [REPLACE-ALL]
                                    Edit body content of a headline
  set-planning URI TYPE [TIMESTAMP]  Set/remove deadline, scheduled, or closed

URI formats:
  org-headline://ABSOLUTE-PATH#HEADLINE-PATH
  org-id://UUID

Notes:
  - If org-cli-allowed-files is nil (not configured), all files are allowed
  - TAGS: comma-separated list (e.g., work,urgent)
  - AFTER-URI: optional, org-id:// URI of sibling to insert after
  - REPLACE-ALL: \"true\" or \"false\" (default: \"false\")
  - Arguments starting with @ read content from file (@- for stdin)
" org-cli-version)))

(defun org-cli--resolve-arg (arg)
  "Resolve ARG, handling @file convention.
If ARG starts with @, read content from the specified file.
@- means read from stdin.
Otherwise, return ARG unchanged."
  (cond
   ((string= arg "@-")
    (with-temp-buffer
      (let ((coding-system-for-read 'utf-8))
        (condition-case nil
            (progn
              (insert-file-contents "/dev/stdin" nil nil nil t)
              (buffer-string))
          (file-error
           (message "Warning: cannot read from stdin")
           arg)))))
   ((string-prefix-p "@" arg)
    (let ((filename (substring arg 1)))
      (unless (file-exists-p filename)
        (error "File not found: %s" filename))
      (with-temp-buffer
        (insert-file-contents filename)
        (buffer-string))))
   (t arg)))

(defun org-cli--parse-tags (tags-string)
  "Parse TAGS-STRING into a list of tag strings.
TAGS-STRING is a comma-separated list of tags.
Returns nil if TAGS-STRING is empty."
  (if (or (null tags-string) (string-empty-p tags-string))
      nil
    (split-string tags-string "," t "[[:space:]]*")))

(defun org-cli--read-file-arg (arg)
  "Read a file argument, handling @ convention.
If ARG starts with @, read from the file.
Otherwise return ARG as-is."
  (org-cli--resolve-arg arg))

(defun org-cli ()
  "CLI entry point for org-cli.
Reads CMD and args from `command-line-args-left'."
  (unless command-line-args-left
    (org-cli-usage)
    (kill-emacs 0))
  (let ((command (car command-line-args-left))
        (args (cdr command-line-args-left)))
    ;; Consume args so Emacs doesn't try to process them as file names
    (setq command-line-args-left nil)
    (condition-case err
        (let ((result (org-cli-dispatch command args)))
          (when result
            (princ result)
            (terpri)))
      (org-cli-error
       (message "Error: %s" (cadr err))
       (kill-emacs 1))
      (error
       (message "Error: %s" (error-message-string err))
       (kill-emacs 1)))))

(defun org-cli-dispatch (command args)
  "Dispatch COMMAND with ARGS to the appropriate handler.
Returns the result string, or nil if no output needed."
  (pcase command
    ;; No-arg commands
    ("get-todo-config"
     (org-cli-get-todo-config))
    ("get-tag-config"
     (org-cli-get-tag-config))
    ("get-allowed-files"
     (org-cli-get-allowed-files))

    ;; Single file arg commands
    ("read-file"
     (unless (>= (length args) 1)
       (error "Usage: read-file FILE"))
     (org-cli-read-file (nth 0 args)))
    ("read-outline"
     (unless (>= (length args) 1)
       (error "Usage: read-outline FILE"))
     (org-cli-read-outline (nth 0 args)))

    ;; File + headline path
    ("read-headline"
     (unless (>= (length args) 2)
       (error "Usage: read-headline FILE HEADLINE-PATH"))
     (org-cli-read-headline (nth 0 args) (nth 1 args)))

    ;; Read by ID
    ("read-by-id"
     (unless (>= (length args) 1)
       (error "Usage: read-by-id UUID"))
     (org-cli-read-by-id (nth 0 args)))

    ;; List TODOs
    ("list-todos"
     (unless (>= (length args) 1)
       (error "Usage: list-todos FILE [HEADLINE-PATH] [FORMAT]"))
     (org-cli-list-todos (nth 0 args)
                         (when (>= (length args) 2) (nth 1 args))
                         (when (>= (length args) 3) (nth 2 args))))

    ;; Update TODO state
    ("update-todo-state"
     (unless (>= (length args) 3)
       (error "Usage: update-todo-state URI CURRENT-STATE NEW-STATE"))
     (org-cli-update-todo-state
      (nth 0 args) (nth 1 args) (nth 2 args)))

    ;; Add TODO
    ("add-todo"
     (unless (>= (length args) 3)
       (error "Usage: add-todo TITLE STATE PARENT-URI [TAGS] [BODY] [AFTER-URI]"))
     (let ((title (nth 0 args))
           (state (nth 1 args))
           (parent-uri (nth 2 args))
           (tags (when (>= (length args) 4)
                   (org-cli--parse-tags (nth 3 args))))
           (body (when (>= (length args) 5)
                   (org-cli--read-file-arg (nth 4 args))))
           (after-uri (when (>= (length args) 6)
                        (nth 5 args))))
       (org-cli-add-todo title state tags body parent-uri after-uri)))

    ;; Rename headline
    ("rename-headline"
     (unless (>= (length args) 3)
       (error "Usage: rename-headline URI CURRENT-TITLE NEW-TITLE"))
     (org-cli-rename-headline
      (nth 0 args) (nth 1 args) (nth 2 args)))

    ;; Edit body
    ("edit-body"
     (unless (>= (length args) 3)
       (error "Usage: edit-body URI OLD-BODY NEW-BODY [REPLACE-ALL]"))
     (let* ((old-body (org-cli--read-file-arg (nth 1 args)))
            (new-body (org-cli--read-file-arg (nth 2 args)))
            (replace-all (when (>= (length args) 4)
                           (equal (nth 3 args) "true"))))
       (org-cli-edit-body
        (nth 0 args) old-body new-body replace-all)))

    ;; Set planning
    ("set-planning"
     (unless (>= (length args) 2)
       (error "Usage: set-planning URI PLANNING-TYPE [TIMESTAMP]"))
     (let ((uri (nth 0 args))
           (planning-type (intern (nth 1 args)))
           (timestamp (when (>= (length args) 3) (nth 2 args))))
       (unless (memq planning-type '(deadline scheduled closed))
         (error "PLANNING-TYPE must be deadline, scheduled, or closed"))
       (org-cli-set-planning uri planning-type timestamp)))

    ;; Help
    ("help"
     (org-cli-usage)
     nil)

    (_
     (error "Unknown command: %s\nRun with 'help' for usage information"
            command))))

(provide 'org-cli)
;;; org-cli.el ends here
