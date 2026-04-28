;;; org-cli-test.el --- Tests for org-cli -*- lexical-binding: t; -*-

;;; Commentary:

;; Test suite for org-cli package.

;;; Code:

(require 'ert)
(require 'org-cli)
(require 'json)


;;; Test Data Constants

;; Initial content strings for various test scenarios

(defconst org-cli-test--content-empty ""
  "Empty org file content.")

(defconst org-cli-test--content-with-id-id
  "550e8400-e29b-41d4-a716-446655440000"
  "ID value for org-cli-test--content-with-id.")

(defconst org-cli-test--content-with-id-uri
  (format "org-id://%s" org-cli-test--content-with-id-id)
  "URI for org-cli-test--content-with-id.")

(defconst org-cli-test--content-nested-siblings-parent-id
  "nested-siblings-parent-id-002"
  "ID for Parent Task in org-cli-test--content-nested-siblings.")

(defconst org-cli-test--content-nested-siblings
  (format
   "#+TITLE: My Org Document

* Parent Task
:PROPERTIES:
:ID:       %s
:END:
Some parent content.
** First Child 50%% Complete
First child content.
It spans multiple lines.
** Second Child
:PROPERTIES:
:ID:       %s
:END:
Second child content.
** Third Child #3"
   org-cli-test--content-nested-siblings-parent-id
   org-cli-test--content-with-id-id)
  "Parent with multiple child tasks and doc file header.")

(defconst org-cli-test--level2-parent-level3-sibling-id
  "level2-parent-level3-sibling-id-001"
  "ID for Review org-cli.el in level2-parent-level3-children.")

(defconst org-cli-test--content-level2-parent-level3-children
  (format
   "* Top Level
** Review the package
*** Review org-cli.el
:PROPERTIES:
:ID:       %s
:END:
Main package file"
   org-cli-test--level2-parent-level3-sibling-id)
  "Level 2 parent with level 3 children - matches emacs.org structure.")

(defconst org-cli-test--content-simple-todo
  "* TODO Original Task
First line of body.
Second line of body.
Third line of body."
  "Simple TODO task with three-line body.")

(defconst org-cli-test--content-with-id-todo
  (format
   "* TODO Task with ID
:PROPERTIES:
:ID:       %s
:END:
First line of content.
Second line of content.
Third line of content."
   org-cli-test--content-with-id-id)
  "Task with an Org ID property, TODO state, and multiline content.")


(defconst org-cli-test--timestamp-id "20240101T120000"
  "Timestamp-format ID value.")

(defconst org-cli-test--content-timestamp-id
  (format
   "* TODO Task with timestamp ID
:PROPERTIES:
:ID:       %s
:END:
Task content."
   org-cli-test--timestamp-id)
  "Task with a timestamp-format ID property.")

(defconst org-cli-test--content-with-id-no-body
  (format
   "* TODO Task with ID but no body
:PROPERTIES:
:ID:       %s
:END:"
   org-cli-test--timestamp-id)
  "Task with an ID property but no body content.")

(defconst org-cli-test--body-text-multiline
  (concat
   "This is the body text.\n"
   "It has multiple lines.\n"
   "With some content.")
  "Multi-line body text for testing TODO items with content.")

(defconst org-cli-test--content-wrong-levels
  "* First Parent
Some content in first parent.
* Second Parent
** Other Child
*** Target Headline
This should NOT be found via First Parent/Target Headline path.
* Third Parent
** Target Headline
This is actually a child of Third Parent, not First Parent!"
  "Test content with same headline names at different levels.")

(defconst org-cli-test--content-todo-with-tags
  "* TODO Task with Tags :work:urgent:\nTask description."
  "TODO task with tags and body.")

(defconst org-cli-test--content-slash-not-nested-before
  "* Parent
** Real Child
Content here.
* Parent/Child
This is a single headline with a slash, not nested under Parent."
  "Content with Parent having a child and separate Parent/Child headline.")

(defconst org-cli-test--content-with-id-repeated-text
  "* Test Heading
:PROPERTIES:
:ID: test-id
:END:
First occurrence of pattern.
Some other text.
Second occurrence of pattern.
More text.
Third occurrence of pattern."
  "Heading with ID and repeated text patterns.")

(defconst org-cli-test--content-duplicate-headlines-before
  "* Team Updates
** Project Review
First review content.
* Development Tasks
** Project Review
Second review content.
* Planning
** Project Review
Third review content."
  "Content with duplicate 'Project Review' headlines under different parents.")

(defconst org-cli-test--content-hierarchy-before
  "* First Section
** Target
Some content.
* Second Section
** Other Item
More content.
** Target
This Target is under Second Section, not First Section."
  "Content with duplicate 'Target' headlines under different parents.")

(defconst org-cli-test--content-todo-keywords-before
  "* Project Management
** TODO Review Documents
This task needs to be renamed
** DONE Review Code
This is already done"
  "Parent with TODO and DONE children for testing keyword handling.")

;; Expected patterns and validation regexes
;;
;; Note on property drawer patterns: The patterns use ` *` (zero or more
;; spaces) before :PROPERTIES:, :ID:, and :END: lines to maintain compatibility
;; across Emacs versions. Emacs 27.2 indents property drawers with 3 spaces,
;; while Emacs 28+ does not add indentation.

(defconst org-cli-test--expected-parent-task-from-nested-siblings
  (format
   "* Parent Task
:PROPERTIES:
:ID:       nested-siblings-parent-id-002
:END:
Some parent content.
** First Child 50%% Complete
First child content.
It spans multiple lines.
** Second Child
:PROPERTIES:
:ID:       %s
:END:
Second child content.
** Third Child #3"
   org-cli-test--content-with-id-id)
  "Expected content when extracting Parent Task from nested-siblings.")

(defconst org-cli-test--regex-after-sibling-level3
  (concat "\\`\\* Top Level\n"
          "\\*\\* Review the package\n"
          "\\*\\*\\* Review org-cli\\.el\n"
          " *:PROPERTIES:\n"
          " *:ID: +" org-cli-test--level2-parent-level3-sibling-id "\n"
          " *:END:\n"
          "Main package file\n"
          "\\*\\*\\* TODO Review org-cli-test\\.el +.*:internet:.*\n"
          " *:PROPERTIES:\n"
          " *:ID: +[a-fA-F0-9-]+\n"
          " *:END:\n\\'")
  "Expected pattern after adding TODO after level 3 sibling.")

(defconst org-cli-test--expected-regex-renamed-second-child
  (format
   (concat
    "\\`#\\+TITLE: My Org Document\n"
    "\n"
    "\\* Parent Task\n"
    ":PROPERTIES:\n"
    ":ID: +nested-siblings-parent-id-002\n"
    ":END:\n"
    "Some parent content\\.\n"
    "\\*\\* First Child 50%% Complete\n"
    "First child content\\.\n"
    "It spans multiple lines\\.\n"
    "\\*\\* Renamed Second Child\n"
    ":PROPERTIES:\n"
    ":ID: +%s\n"
    ":END:\n"
    "Second child content\\.\n"
    "\\*\\* Third Child #3\\'")
   org-cli-test--content-with-id-id)
  "Regex matching complete buffer after renaming Second Child.")

(defconst org-cli-test--expected-regex-todo-to-in-progress-with-id
  (format
   (concat
    "\\`"
    "\\* IN-PROGRESS Task with ID\n"
    ":PROPERTIES:\n"
    ":ID: +%s\n"
    ":END:\n"
    "First line of content\\.\n"
    "Second line of content\\.\n"
    "Third line of content\\."
    "\\'")
   org-cli-test--content-with-id-id)
  "Expected regex for TODO to IN-PROGRESS state change with ID.")

(defconst org-cli-test--expected-timestamp-id-done-regex
  (concat
   "\\`\\* DONE Task with timestamp ID"
   "\\(?:\n:PROPERTIES:\n:ID:[ \t]+[A-Fa-f0-9-]+\n:END:\\)?"
   "\\(?:.\\|\n\\)*\\'")
  "Regex matching complete buffer after updating timestamp ID task to DONE.")

(defconst org-cli-test--expected-task-with-id-in-progress-regex
  (concat
   "\\`\\* IN-PROGRESS Task with ID"
   "\\(?:\n:PROPERTIES:\n:ID:[ \t]+[A-Fa-f0-9-]+\n:END:\\)?"
   "\\(?:.\\|\n\\)*\\'")
  "Regex matching complete buffer with Task with ID in IN-PROGRESS state.")

(defconst org-cli-test--expected-regex-top-level-with-header
  (concat
   "\\`#\\+TITLE: My Org Document\n"
   "\n"
   "\\* TODO New Top Task +.*:urgent:\n"
   "\\(?: *:PROPERTIES:\n"
   " *:ID: +[^\n]+\n"
   " *:END:\n\\)?"
   "\n?"
   "\\* Parent Task\n"
   ":PROPERTIES:\n"
   ":ID: +" org-cli-test--content-nested-siblings-parent-id "\n"
   ":END:\n"
   "Some parent content\\.\n"
   "\\*\\* First Child 50% Complete\n"
   "First child content\\.\n"
   "It spans multiple lines\\.\n"
   "\\*\\* Second Child\n"
   ":PROPERTIES:\n"
   ":ID: +" org-cli-test--content-with-id-id "\n"
   ":END:\n"
   "Second child content\\.\n"
   "\\*\\* Third Child #3\\'")
  "Regex matching complete buffer after adding top-level TODO with headers.")

(defconst org-cli-test--regex-child-under-parent
  (format
   (concat
    "^\\* Parent Task\n"
    "\\(?: *:PROPERTIES:\n *:ID: +nested-siblings-parent-id-002\n *:END:\n\\)?"
    "Some parent content\\.\n"
    "\\*\\* First Child 50%% Complete\n"
    "First child content\\.\n"
    "It spans multiple lines\\.\n"
    "\\*\\* Second Child\n"
    "\\(?: *:PROPERTIES:\n *:ID: +%s\n *:END:\n\\)?"
    "Second child content\\.\n"
    "\\*\\* Third Child #3\n"
    "\\*\\* TODO Child Task +.*:work:.*\n"
    "\\(?: *:PROPERTIES:\n *:ID: +[^\n]+\n *:END:\n\\)?")
   org-cli-test--content-with-id-id)
  "Pattern for child TODO (level 2) added under parent (level 1) with existing child (level 2).")

(defconst org-cli-test--regex-second-child-same-level
  (concat
   "\\`\\* Top Level\n"
   "\\*\\* Review the package\n"
   "\\*\\*\\* Review org-cli\\.el\n"
   "\\(?: *:PROPERTIES:\n *:ID: +[^\n]+\n *:END:\n\\)?"  ; Review org-cli.el has ID
   "Main package file\n"
   "\\*\\*\\* TODO Second Child +.*:work:.*\n"
   "\\(?: *:PROPERTIES:\n *:ID: +[^\n]+\n *:END:\n\\)?\\'")  ; Second Child may have ID
  "Pattern for second child (level 3) added at same level as first child (level 3) under parent (level 2).")

(defconst org-cli-test--regex-todo-with-body
  (concat
   "^\\* TODO Task with Body +:[^\n]*\n"
   "\\(?: *:PROPERTIES:\n *:ID: +[^\n]+\n *:END:\n\\)?" ; Optional properties
   (regexp-quote org-cli-test--body-text-multiline)
   "\n?$")
  "Pattern for TODO with body text.")

(defconst org-cli-test--regex-todo-with-literal-block-end
  (concat
   "^\\* TODO Task with literal END_SRC +:work:\n"
   "\\(?: *:PROPERTIES:\n"
   " *:ID: +[^\n]+\n"
   " *:END:\n\\)?"
   "Example of source block:\n"
   "#\\+BEGIN_EXAMPLE\n"
   "#\\+END_SRC\n"
   "#\\+END_EXAMPLE\n"
   "Text after\\.$")
  "Pattern for TODO with body containing literal END_SRC inside EXAMPLE block.")

(defconst org-cli-test--regex-todo-after-sibling
  (concat
   "^#\\+TITLE: My Org Document\n\n"
   "\\* Parent Task\n"
   ":PROPERTIES:\n"
   ":ID: +" org-cli-test--content-nested-siblings-parent-id "\n"
   ":END:\n"
   "Some parent content\\.\n"
   "\\*\\* First Child 50% Complete\n"
   ":PROPERTIES:\n"
   ":ID: +[^\n]+\n"
   ":END:\n"
   "First child content\\.\n"
   "It spans multiple lines\\.\n\n?"
   "\\*\\* TODO New Task After First +:[^\n]*\n"
   "\\(?: *:PROPERTIES:\n *:ID: +[^\n]+\n *:END:\n\\)?"
   "\\*\\* Second Child\n"
   ":PROPERTIES:\n"
   ":ID: +" org-cli-test--content-with-id-id "\n"
   ":END:\n"
   "Second child content\\.\n"
   "\\*\\* Third Child #3\\'")
  "Pattern for TODO added after specific sibling.")

(defconst org-cli-test--regex-todo-after-second-child
  (concat
   "^#\\+TITLE: My Org Document\n\n"
   "\\* Parent Task\n"
   ":PROPERTIES:\n"
   ":ID: +" org-cli-test--content-nested-siblings-parent-id "\n"
   ":END:\n"
   "Some parent content\\.\n"
   "\\*\\* First Child 50% Complete\n"
   "First child content\\.\n"
   "It spans multiple lines\\.\n"
   "\\*\\* Second Child\n"
   ":PROPERTIES:\n"
   ":ID: +" org-cli-test--content-with-id-id "\n"
   ":END:\n"
   "Second child content\\.\n\n?"
   "\\*\\* TODO New Task After Second +:[^\n]*\n"
   "\\(?: *:PROPERTIES:\n *:ID: +[^\n]+\n *:END:\n\\)?"
   "\\*\\* Third Child #3\\'")
  "Pattern for TODO added after Second Child sibling.")

(defconst org-cli-test--regex-todo-without-tags
  (concat
   "^\\* TODO Task Without Tags *\n" ; No tags, optional spaces
   "\\(?: *:PROPERTIES:\n" " *:ID: +[^\n]+\n" " *:END:\n\\)?$")
  "Pattern for TODO item without any tags.")

(defconst org-cli-test--regex-top-level-todo
  (concat
   "^\\* TODO New Task +:.*work.*urgent.*:\n"
   "\\(?: *:PROPERTIES:\n"
   " *:ID: +[^\n]+\n"
   " *:END:\n\\)?$")
  "Pattern for top-level TODO item with work and urgent tags.")

(defconst org-cli-test--pattern-add-todo-parent-id-uri
  (concat
   "^\\* Parent Task\n"
   "\\(?: *:PROPERTIES:\n"
   " *:ID: +[^\n]+\n"
   " *:END:\n\\)?"
   "Some parent content\\.\n"
   "\\*\\* First Child 50% Complete\n"
   "First child content\\.\n"
   "It spans multiple lines\\.\n"
   "\\*\\* Second Child\n"
   "\\(?: *:PROPERTIES:\n"
   " *:ID: +[^\n]+\n"
   " *:END:\n\\)?"
   "Second child content\\.\n"
   "\\*\\* Third Child #3\n"
   "\\*\\* TODO Child via ID +:work:\n"
   "\\(?: *:PROPERTIES:\n"
   " *:ID: +[^\n]+\n"
   " *:END:\n\\)?$")
  "Pattern for TODO added via parent ID URI.")

(defconst org-cli-test--pattern-renamed-simple-todo
  (concat
   "\\`\\* TODO Updated Task\n"
   " *:PROPERTIES:\n"
   " *:ID:[ \t]+[A-Fa-f0-9-]+\n"
   " *:END:\n"
   "First line of body\\.\n"
   "Second line of body\\.\n"
   "Third line of body\\.\\'")
  "Pattern for renamed simple TODO with generated ID.")

(defconst org-cli-test--pattern-renamed-todo-with-tags
  (concat
   "^\\* TODO Renamed Task[ \t]+:work:urgent:\n"
   " *:PROPERTIES:\n"
   " *:ID:[ \t]+[A-Fa-f0-9-]+\n"
   " *:END:\n"
   "Task description\\.$")
  "Pattern for renamed TODO task preserving tags.")

(defconst org-cli-test--pattern-renamed-headline-no-todo
  (format
   (concat
    "\\`#\\+TITLE: My Org Document\n"
    "\n"
    "\\* Parent Task\n"
    "\\(?: *:PROPERTIES:\n *:ID: +nested-siblings-parent-id-002\n *:END:\n\\)?"
    "Some parent content\\.\n"
    "\\*\\* Updated Child\n"
    " *:PROPERTIES:\n"
    " *:ID:[ \t]+[A-Fa-f0-9-]+\n"
    " *:END:\n"
    "First child content\\.\n"
    "It spans multiple lines\\.\n"
    "\\*\\* Second Child\n"
    "\\(?: *:PROPERTIES:\n *:ID: +%s\n *:END:\n\\)?"
    "Second child content\\.\n"
    "\\*\\* Third Child #3\n?"
    "\\'")
   org-cli-test--content-with-id-id)
  "Pattern for renamed headline without TODO state.")

(defconst org-cli-test--pattern-renamed-headline-with-id
  (format
   (concat
    "\\`#\\+TITLE: My Org Document\n"
    "\n"
    "\\* Parent Task\n"
    "\\(?: *:PROPERTIES:\n *:ID: +nested-siblings-parent-id-002\n *:END:\n\\)?"
    "Some parent content\\.\n"
    "\\*\\* First Child 50%% Complete\n"
    "\\(?: *:PROPERTIES:\n *:ID:[ \t]+[A-Fa-f0-9-]+\n *:END:\n\\)?"
    "First child content\\.\n"
    "It spans multiple lines\\.\n"
    "\\*\\* Second Child\n"
    "\\(?: *:PROPERTIES:\n *:ID: +%s\n *:END:\n\\)?"
    "Second child content\\.\n"
    "\\*\\* Renamed Child\n"
    " *:PROPERTIES:\n"
    " *:ID:[ \t]+[A-Fa-f0-9-]+\n"
    " *:END:\n?\\'")
   org-cli-test--content-with-id-id)
  "Pattern for headline renamed with ID creation.")

(defconst org-cli-test--pattern-renamed-slash-headline
  (concat
   "\\`\\* Parent\n"
   "\\*\\* Real Child\n"
   "Content here\\.\n"
   "\\* Parent/Child Renamed\n"
   " *:PROPERTIES:\n"
   " *:ID:[ \t]+[A-Fa-f0-9-]+\n"
   " *:END:\n"
   "This is a single headline with a slash, not nested under Parent\\.\\'")
  "Pattern for renamed headline containing slash character.")

(defconst org-cli-test--regex-slash-not-nested-after
  (concat
   "\\`\\* Parent\n"
   "\\*\\* Real Child\n"
   "Content here\\.\n"
   "\\* Parent-Child Renamed\n"
   " *:PROPERTIES:\n"
   " *:ID:[ \t]+[A-Fa-f0-9-]+\n"
   " *:END:\n"
   "This is a single headline with a slash, not nested under Parent\\.\\'")
  "Regex for slash-not-nested test after renaming Parent/Child.")

(defconst org-cli-test--regex-percent-after
  (format
   (concat
    "\\`#\\+TITLE: My Org Document\n"
    "\n"
    "\\* Parent Task\n"
    ":PROPERTIES:\n"
    ":ID: +%s\n"
    ":END:\n"
    "Some parent content\\.\n"
    "\\*\\* First Child 75%% Complete\n"
    " *:PROPERTIES:\n"
    " *:ID:[ \t]+[A-Fa-f0-9-]+\n"
    " *:END:\n"
    "First child content\\.\n"
    "It spans multiple lines\\.\n"
    "\\*\\* Second Child\n"
    ":PROPERTIES:\n"
    ":ID: +%s\n"
    ":END:\n"
    "Second child content\\.\n"
    "\\*\\* Third Child #3\\'")
   org-cli-test--content-nested-siblings-parent-id
   org-cli-test--content-with-id-id)
  "Expected pattern after renaming headline with percent sign.")

(defconst org-cli-test--regex-duplicate-first-renamed
  (concat
   "\\`\\* Team Updates\n"
   "\\*\\* Q1 Review\n"
   " *:PROPERTIES:\n"
   " *:ID:[ \t]+[A-Fa-f0-9-]+\n"
   " *:END:\n"
   "First review content\\.\n"
   "\\* Development Tasks\n"
   "\\*\\* Project Review\n"
   "Second review content\\.\n"
   "\\* Planning\n"
   "\\*\\* Project Review\n"
   "Third review content\\.\\'")
  "Regex for duplicate headlines after renaming first occurrence.")

(defconst org-cli-test--regex-hierarchy-second-target-renamed
  (concat
   "\\`\\* First Section\n"
   "\\*\\* Target\n"
   "Some content\\.\n"
   "\\* Second Section\n"
   "\\*\\* Other Item\n"
   "More content\\.\n"
   "\\*\\* Renamed Target\n"
   " *:PROPERTIES:\n"
   " *:ID:[ \t]+[A-Fa-f0-9-]+\n"
   " *:END:\n"
   "This Target is under Second Section, not First Section\\.\\'")
  "Regex for hierarchy test after renaming second Target.")

(defconst org-cli-test--regex-add-todo-with-mutex-tags
  (concat
   "\\`#\\+TITLE: Test Org File\n"
   "\n"
   "\\* TODO Test Task[ \t]+\\(:[^:\n]+\\)+:\n"
   " *:PROPERTIES:\n"
   " *:ID:[ \t]+[A-Fa-f0-9-]+\n"
   " *:END:\n?\\'")
  "Regex for add-todo test accepting any tag order.")

(defconst org-cli-test--regex-todo-keywords-after
  (concat
   "\\`\\* Project Management\n"
   "\\*\\* TODO Q1 Planning Review\n"
   " *:PROPERTIES:\n"
   " *:ID:[ \t]+[A-Fa-f0-9-]+\n"
   " *:END:\n"
   "This task needs to be renamed\n"
   "\\*\\* DONE Review Code\n"
   "This is already done\\'")
  "Regex for todo-keywords test after renaming TODO headline.")

(defconst org-cli-test--pattern-edit-body-single-line
  (format (concat
           "\\`#\\+TITLE: My Org Document\n"
           "\n"
           "\\* Parent Task\n"
           ":PROPERTIES:\n"
           ":ID: +nested-siblings-parent-id-002\n"
           ":END:\n"
           "Some parent content\\.\n"
           "\\*\\* First Child 50%% Complete\n"
           "First child content\\.\n"
           "It spans multiple lines\\.\n"
           "\\*\\* Second Child\n"
           ":PROPERTIES:\n"
           ":ID: +%s\n"
           ":END:\n"
           "Updated second child content\\.\n"
           "\\*\\* Third Child #3\n"
           "?\\'")
          org-cli-test--content-with-id-id)
  "Pattern for single-line edit-body test result.")

(defconst org-cli-test--pattern-edit-body-multiline
  (format (concat
           "\\`\\* TODO Task with ID\n"
           ":PROPERTIES:\n"
           ":ID: +%s\n"
           ":END:\n"
           "First line of content\\.\n"
           "This has been replaced\n"
           "with new multiline\n"
           "content here\\.\n"
           "Third line of content\\.\n"
           "?\\'")
          org-cli-test--content-with-id-id)
  "Pattern for multiline edit-body test result.")

(defconst org-cli-test--pattern-edit-body-replace-all
  (concat
   "\\`\\* Test Heading\n"
   ":PROPERTIES:\n"
   ":ID: +test-id\n"
   ":END:\n"
   "First REPLACED\\.\n"
   "Some other text\\.\n"
   "Second REPLACED\\.\n"
   "More text\\.\n"
   "Third REPLACED\\.\n"
   "?\\'")
  "Pattern for replace-all edit-body test result.")

(defconst org-cli-test--pattern-edit-body-nested-headlines
  (format
   (concat
    "\\`#\\+TITLE: My Org Document\n"
    "\n"
    "\\* Parent Task\n"
    "\\(?: *:PROPERTIES:\n *:ID: +nested-siblings-parent-id-002\n *:END:\n\\)?"
    "Updated parent content\n"
    "\\*\\* First Child 50%% Complete\n"
    "\\(?: *:PROPERTIES:\n *:ID:[ \t]+[A-Fa-f0-9-]+\n *:END:\n\\)?"
    "First child content\\.\n"
    "It spans multiple lines\\.\n"
    "\\*\\* Second Child\n"
    "\\(?: *:PROPERTIES:\n *:ID: +%s\n *:END:\n\\)?"
    "Second child content\\.\n"
    "\\*\\* Third Child #3\n?"
    "\\(?: *:PROPERTIES:\n *:ID:[ \t]+[A-Fa-f0-9-]+\n *:END:\n\\)?"
    "\\'")
   org-cli-test--content-with-id-id)
  "Pattern for nested headlines edit-body test result.")

(defconst org-cli-test--pattern-edit-body-empty
  (concat
   "\\*\\* Third Child #3
"
   " *:PROPERTIES:
"
   " *:ID:[ \t]+[A-Fa-f0-9-]+
"
   " *:END:
"
   " *New content added\\.")
  "Pattern for edit-body test with empty body adding content.")

(defconst org-cli-test--pattern-edit-body-empty-with-props
  (format (concat
           " *:PROPERTIES:\n"
           " *:ID:[ \t]+[A-Fa-f0-9-]+\n"
           " *:END:\n"
           " *:PROPERTIES:\n"
           " *:ID: +%s\n"
           " *:END:Content added after properties\\.")
          org-cli-test--timestamp-id)
  "Pattern for edit-body with existing properties adding content.")

(defconst org-cli-test--pattern-edit-body-accept-lower-level
  (concat
   "\\* Parent Task\n"
   " *:PROPERTIES:\n"
   " *:ID: +nested-siblings-parent-id-002\n"
   " *:END:\n"
   "Some parent content\\.\n"
   "\\*\\* First Child 50% Complete\n"
   "First child content\\.\n"
   "It spans multiple lines\\.\n"
   "\\*\\* Second Child\n"
   " *:PROPERTIES:\n"
   " *:ID: +"
   org-cli-test--content-with-id-id
   "\n"
   " *:END:\n"
   "some text\n"
   "\\*\\*\\* Subheading content\n"
   "\\(?: *:PROPERTIES:\n" ; Subheading gets ID
   " *:ID:[ \t]+[A-Fa-f0-9-]+\n"
   " *:END:\n\\)?"
   "\\*\\* Third Child #3")
  "Pattern for edit-body accepting lower-level headlines.")

(defconst org-cli-test--pattern-tool-read-headline-single
  (concat
   "\\`\\* Parent/Child\n"
   "This is a single headline with a slash, not nested under Parent\\.\n"
   "?\\'")
  "Pattern for org-read-headline tool single-level path result.")

(defconst org-cli-test--pattern-tool-read-headline-nested
  (concat
   "\\`\\*\\* First Child 50% Complete\n"
   "First child content\\.\n"
   "It spans multiple lines\\.\n"
   "?\\'")
  "Pattern for org-read-headline tool nested path result.")

(defconst org-cli-test--pattern-tool-read-by-id
  (format
   (concat
    "\\`\\*\\* Second Child\n"
    ":PROPERTIES:\n"
    ":ID: +%s\n"
    ":END:\n"
    "Second child content\\.\n"
    "?\\'")
   org-cli-test--content-with-id-id)
  "Pattern for org-read-by-id tool result.")

(defconst org-cli-test--content-id-resource-id
  "12345678-abcd-efgh-ijkl-1234567890ab"
  "ID value for org-cli-test--content-id-resource.")

(defconst org-cli-test--content-id-resource
  (format
   "* Section with ID
:PROPERTIES:
:ID: %s
:END:
Content of section with ID."
   org-cli-test--content-id-resource-id)
  "Content for ID resource tests.")

(defconst org-cli-test--content-headline-resource
  "* First Section
Some content in first section.
** Subsection 1.1
Content of subsection 1.1.
** Subsection 1.2
Content of subsection 1.2.
* Second Section
Content of second section.
*** Deep subsection
Very deep content."
  "Test content with hierarchical headlines for resource read tests.")

(defconst org-cli-test--expected-first-section
  (concat
   "* First Section\n"
   "Some content in first section.\n"
   "** Subsection 1.1\n"
   "Content of subsection 1.1.\n"
   "** Subsection 1.2\n"
   "Content of subsection 1.2.")
  "Expected content when reading 'First Section' top-level headline.")

(defconst org-cli-test--expected-subsection-1-1
  (concat
   "** Subsection 1.1\n"
   "Content of subsection 1.1.")
  "Expected content when reading 'First Section/Subsection 1.1' nested headline.")

;; Test helpers

(defun org-cli-test--read-file (file)
  "Read and return the contents of FILE as a string."
  (with-temp-buffer
    (insert-file-contents file)
    (buffer-string)))

(defun org-cli-test--verify-file-matches (test-file expected-pattern)
  "Verify TEST-FILE content matches EXPECTED-PATTERN regexp."
  (should (string-match-p expected-pattern (org-cli-test--read-file test-file))))

(defmacro org-cli-test--assert-error-and-file (test-file error-form)
  "Assert that ERROR-FORM throws an error and TEST-FILE remains unchanged."
  (declare (indent 1) (debug t))
  `(let ((original-content (org-cli-test--read-file ,test-file)))
     (should-error ,error-form :type 'org-cli-error)
     (should (string= (org-cli-test--read-file ,test-file) original-content))))

(defmacro org-cli-test--with-enabled (&rest body)
  "Run BODY."
  (declare (indent defun))
  `(progn ,@body))

(defmacro org-cli-test--with-temp-org-files (file-specs &rest body)
  "Create temporary Org files, execute BODY, and ensure cleanup.
FILE-SPECS is a list of file specifications.
Each spec is (VAR CONTENT [FILENAME-PREFIX]).
VAR is the variable to bind the temp file path to.
CONTENT is the initial content to write to the file.
FILENAME-PREFIX is optional, defaults to \"org-cli-test\".
All created files are automatically added to `org-cli-allowed-files'.
BODY is executed with org-cli enabled."
  (declare (indent 1))
  (let* ((vars (mapcar #'car file-specs))
         (temp-vars (mapcar (lambda (v) (gensym (symbol-name v)))
                            vars))
         (bindings (cl-mapcar
                    (lambda (var temp-var)
                      `(,var ,temp-var))
                    vars temp-vars))
         (inits (cl-mapcar
                 (lambda (temp-var spec)
                   (let ((content (nth 1 spec))
                         (filename (or (nth 2 spec) "org-cli-test")))
                     `(setq ,temp-var
                            (make-temp-file ,filename nil ".org" ,content))))
                 temp-vars file-specs))
         (cleanups (mapcar
                    (lambda (temp-var)
                      `(when ,temp-var
                         (delete-file ,temp-var)))
                    temp-vars)))
    `(let (,@temp-vars)
       (unwind-protect
           (progn
             ,@inits
             (let (,@bindings
                   (org-cli-allowed-files (list ,@temp-vars)))
               (org-cli-test--with-enabled
                 ,@body)))
         ,@cleanups))))

(defmacro org-cli-test--with-id-tracking
    (allowed-files id-locations &rest body)
  "Set up org-id tracking with ID-LOCATIONS and run BODY.
ALLOWED-FILES is the list of files to bind to `org-cli-allowed-files'.
ID-LOCATIONS is a list of (ID . FILE) cons cells to register.
Sets up `org-id-track-globally' and `org-id-locations-file',
then registers each ID location."
  (declare (indent 2) (debug t))
  `(let ((org-id-track-globally t)
         (org-id-locations-file nil) ; Prevent saving to disk
         (org-id-locations nil)
         (org-cli-allowed-files ,allowed-files))
     (dolist (id-loc ,id-locations)
       (org-id-add-location (car id-loc) (cdr id-loc)))
     ,@body))

(defmacro org-cli-test--with-id-setup (file-var initial-content ids &rest body)
  "Create temp file, set up org-id tracking with IDS, run BODY.
FILE-VAR is the variable to bind the temp file path to.
INITIAL-CONTENT is the initial content to write to the file.
IDS is a list of ID strings to register.
Sets up `org-id-track-globally' and `org-id-locations-file',
then registers each ID location and enables MCP for BODY.
The created temp file is automatically added to `org-cli-allowed-files'."
  (declare (indent 2) (debug t))
  `(org-cli-test--with-temp-org-files
    ((,file-var ,initial-content))
    (org-cli-test--with-id-tracking
     (list ,file-var)
     (mapcar (lambda (id) (cons id ,file-var)) ,ids)
     ,@body)))

(defmacro org-cli-test--with-file-buffer (buffer file &rest body)
  "Open FILE in BUFFER and execute BODY, ensuring buffer is killed.
BUFFER is the variable name to bind the buffer to.
FILE is the file path to open.
BODY is the code to execute with the buffer."
  (declare (indent 2) (debug t))
  `(let ((,buffer (find-file-noselect ,file)))
     (unwind-protect
         (progn ,@body)
       (kill-buffer ,buffer))))

;; Helpers for testing org-get-todo-config MCP tool

(defun org-cli-test--check-todo-config-sequence
    (seq expected-type expected-keywords)
  "Check sequence SEQ has EXPECTED-TYPE and EXPECTED-KEYWORDS."
  (should (= (length seq) 2))
  (should (equal (alist-get 'type seq) expected-type))
  (should (equal (alist-get 'keywords seq) expected-keywords)))

(defun org-cli-test--check-todo-config-semantic
    (sem expected-state expected-final expected-type)
  "Check semantic SEM properties.
EXPECTED-STATE is the TODO keyword.
EXPECTED-FINAL is whether it's a final state.
EXPECTED-TYPE is the sequence type."
  (should (= (length sem) 3))
  (should (equal (alist-get 'state sem) expected-state))
  (should (equal (alist-get 'isFinal sem) expected-final))
  (should (equal (alist-get 'sequenceType sem) expected-type)))

(defmacro org-cli-test--with-get-todo-config-result (keywords &rest body)
  "Call get-todo-config tool with KEYWORDS and run BODY with result bindings.
Sets `org-todo-keywords' to KEYWORDS, calls the get-todo-config MCP tool,
and binds `sequences' and `semantics' from the result for use in BODY."
  (declare (indent 1) (debug t))
  `(let ((org-todo-keywords ,keywords))
     (org-cli-test--with-enabled
      (let ((result (json-read-from-string
                     (org-cli-get-todo-config))))
        (should (= (length result) 2))
        (let ((sequences (cdr (assoc 'sequences result)))
              (semantics (cdr (assoc 'semantics result))))
          ,@body)))))

;; Helpers for testing org-get-tag-config MCP tool

(defmacro org-cli-test--get-tag-config-and-check
    (expected-alist expected-persistent expected-inheritance expected-exclude)
  "Call org-get-tag-config tool and check result against expected values.
EXPECTED-ALIST is the expected value for org-tag-alist (string).
EXPECTED-PERSISTENT is the expected value for org-tag-persistent-alist (string).
EXPECTED-INHERITANCE is the expected value for org-use-tag-inheritance (string).
EXPECTED-EXCLUDE is the expected value for
org-tags-exclude-from-inheritance (string)."
  (declare (indent defun) (debug t))
  `(org-cli-test--with-enabled
    (let ((result
           (json-read-from-string
            (org-cli-get-tag-config))))
      (should (= (length result) 4))
      (should (equal (alist-get 'org-tag-alist result) ,expected-alist))
      (should (equal (alist-get 'org-tag-persistent-alist result)
                     ,expected-persistent))
      (should (equal (alist-get 'org-use-tag-inheritance result)
                     ,expected-inheritance))
      (should (equal (alist-get 'org-tags-exclude-from-inheritance result)
                     ,expected-exclude)))))

;; Helpers for testing org-get-allowed-files MCP tool

(defun org-cli-test--get-allowed-files-and-check (allowed-files expected-files)
  "Call org-get-allowed-files tool and verify the result.
ALLOWED-FILES is the value to bind to org-cli-allowed-files.
EXPECTED-FILES is a list of expected file paths."
  (let ((org-cli-allowed-files allowed-files))
    (org-cli-test--with-enabled
     (let* ((result-text
             (org-cli-get-allowed-files))
            (result (json-read-from-string result-text)))
       (should (= (length result) 1))
       (let ((files (cdr (assoc 'files result))))
         (should (vectorp files))
         (should (= (length files) (length expected-files)))
         (dotimes (i (length expected-files))
           (should (string= (aref files i) (nth i expected-files)))))))))

;; Helper functions for testing org-add-todo MCP tool

(defmacro org-cli-test--with-add-todo-setup
    (file-var initial-content todo-keywords tag-alist ids &rest body)
  "Helper for org-add-todo test.
Sets up FILE-VAR with INITIAL-CONTENT and org configuration.
TODO-KEYWORDS is the org-todo-keywords config (nil for default).
TAG-ALIST is the org-tag-alist config (nil for default).
IDS is optional list of ID strings to register (nil for no ID tracking).
Executes BODY with org-cli enabled and standard variables set."
  (declare (indent 2))
  (let ((todo-kw (or todo-keywords ''((sequence "TODO" "IN-PROGRESS" "|" "DONE"))))
        (tag-al (or tag-alist ''("work" "personal" "urgent"))))
    `(org-cli-test--with-temp-org-files
      ((,file-var ,initial-content))
      (let ((org-todo-keywords ,todo-kw)
            (org-tag-alist ,tag-al)
            ,@(unless ids '((org-id-locations-file nil))))
        ,(if ids
             `(org-cli-test--with-id-tracking
               (list ,file-var)
               (mapcar (lambda (id) (cons id ,file-var)) ,ids)
               ,@body)
           `(progn ,@body))))))

(defmacro org-cli-test--call-add-todo-expecting-error
    (initial-content todo-keywords tag-alist title todoState tags body parentUri
                     &optional afterUri)
  "Call org-add-todo MCP tool expecting an error and verify file unchanged.
INITIAL-CONTENT is the initial Org file content.
TODO-KEYWORDS is the org-todo-keywords config (nil for default).
TAG-ALIST is the org-tag-alist config (nil for default).
TITLE is the headline text.
TODOSTATE is the TODO state.
TAGS is a list of tag strings or nil.
BODY is the body text or nil.
PARENTURI is the URI of the parent item.
AFTERURI is optional URI of sibling to insert after."
  `(org-cli-test--with-add-todo-setup
    test-file ,initial-content ,todo-keywords
    ,tag-alist nil
    (org-cli-test--assert-error-and-file
     test-file
     (org-cli-add-todo ,title ,todoState ,tags ,body ,parentUri ,afterUri))))

(defun org-cli-test--assert-add-todo-rejects-body-headline
    (initial-content parent-headline body-with-headline)
  "Test that adding TODO with BODY-WITH-HEADLINE is rejected.
INITIAL-CONTENT is the initial file content.
PARENT-HEADLINE is the parent headline path (empty string for top-level).
BODY-WITH-HEADLINE is the body containing invalid headline."
  (org-cli-test--call-add-todo-expecting-error
   initial-content nil nil
   "Test Task" "TODO" '("work") body-with-headline
   (format "org-headline://%s#%s" test-file parent-headline)))

(defun org-cli-test--assert-add-todo-invalid-title (invalid-title)
  "Assert that adding TODO with INVALID-TITLE throws an error.
Tests that the given title is rejected when creating a TODO."
  (org-cli-test--call-add-todo-expecting-error
   org-cli-test--content-empty nil nil
   invalid-title "TODO" nil nil
   (format "org-headline://%s#" test-file)))

(defmacro org-cli-test--add-todo-and-check
    (initial-content todo-keywords tag-alist ids
                     title todoState tags body parentUri afterUri
                     basename expected-pattern
                     &optional override-bindings)
  "Add TODO item with setup and verify the result.
INITIAL-CONTENT is the initial Org file content.
TODO-KEYWORDS is the org-todo-keywords config (nil for default).
TAG-ALIST is the org-tag-alist config (nil for default).
IDS is optional list of ID strings to register (nil for no ID tracking).
TITLE is the headline text.
TODOSTATE is the TODO state.
TAGS is a list of tag strings or nil.
BODY is the body text or nil.
PARENTURI is the URI of the parent item.
AFTERURI is optional URI of sibling to insert after.
BASENAME is the expected file basename.
EXPECTED-PATTERN is a regexp that the file content should match.
OVERRIDE-BINDINGS is optional list of let-style bindings to override
variables after setup, e.g., ((org-tag-alist nil))."
  (declare (indent 2))
  (let ((checking-logic
         `(let* ((result-text
                  (org-cli-add-todo ,title ,todoState ,tags ,body ,parentUri ,afterUri))
                 (result (json-read-from-string result-text)))
            ;; Check result structure
            (should (= (length result) 4))
            (should (equal (alist-get 'success result) t))
            (should (string-match-p "\\`org-id://.+" (alist-get 'uri result)))
            (should (equal (alist-get 'file result) ,basename))
            (should (equal (alist-get 'title result) ,title))
            (org-cli-test--verify-file-matches test-file ,expected-pattern))))
    `(org-cli-test--with-add-todo-setup
      test-file
      ,initial-content ,todo-keywords ,tag-alist ,ids
      ,(if override-bindings
           `(let ,override-bindings
              ,checking-logic)
         checking-logic))))

;; Helper functions for testing org-update-todo-state MCP tool

(defun org-cli-test--call-update-todo-state-expecting-error
    (test-file resource-uri current-state new-state)
  "Call org-update-todo-state tool expecting an error and verify file unchanged.
TEST-FILE is the test file path to verify remains unchanged.
RESOURCE-URI is the URI to update.
CURRENT-STATE is the current TODO state.
NEW-STATE is the new TODO state to set."
  (let ((org-todo-keywords
         '((sequence "TODO" "IN-PROGRESS" "|" "DONE"))))
    (org-cli-test--assert-error-and-file
     test-file
     (org-cli-update-todo-state resource-uri current-state new-state))))

(defun org-cli-test--update-todo-state-and-check
    (resource-uri old-state new-state test-file expected-content-regex)
  "Update TODO state and verify the result via MCP JSON-RPC.
RESOURCE-URI is the URI to update.
OLD-STATE is the current TODO state to update from.
NEW-STATE is the new TODO state to update to.
TEST-FILE is the file to verify content after update.
EXPECTED-CONTENT-REGEX is an anchored regex that matches the complete buffer."
  (let* ((result-text
          (org-cli-update-todo-state resource-uri old-state new-state))
         (result (json-read-from-string result-text)))
    (should (= (length result) 4))
    (should (equal (alist-get 'success result) t))
    (should (equal (alist-get 'previous_state result) old-state))
    (should (equal (alist-get 'new_state result) new-state))
    (should (stringp (alist-get 'uri result)))
    (should (string-prefix-p "org-id://" (alist-get 'uri result)))
    ;; For ID-based URIs, verify the returned URI matches the input
    (when (string-prefix-p "org-id://" resource-uri)
      (should (equal (alist-get 'uri result) resource-uri)))
    (org-cli-test--verify-file-matches test-file expected-content-regex)))

;; Helper functions for testing org-read-headline MCP tool

(defun org-cli-read-headline-and-check (initial-content headline-path expected-pattern-regex)
  "Call org-read-headline tool via JSON-RPC and verify the result.
INITIAL-CONTENT is the content to write to the temp file.
HEADLINE-PATH is the slash-separated path to the headline.
EXPECTED-PATTERN-REGEX is an anchored regex that matches the expected result."
  (org-cli-test--with-temp-org-files
      ((test-file initial-content))
    (let* ((result-text (org-cli-read-headline test-file headline-path)))
      (should
       (string-match-p expected-pattern-regex result-text)))))

(defmacro org-cli-test--call-read-headline-expecting-error (content headline-path)
  "Call org-read-headline expecting an error.
CONTENT is the Org file content to use.
HEADLINE-PATH is the headline path string."
  (declare (indent 0))
  `(org-cli-test--with-temp-org-files
    ((test-file ,content))
    (should-error
     (org-cli-read-headline test-file ,headline-path)
     :type 'org-cli-error)))

;; Helper functions for testing org-rename-headline MCP tool

(defun org-cli-test--call-rename-headline-and-check
    (initial-content headline-path-or-uri current-title new-title
                     expected-content-regex
                     &optional ids-to-register)
  "Call org-rename-headline tool via JSON-RPC and verify the result.
INITIAL-CONTENT is the initial Org file content.
HEADLINE-PATH-OR-URI is either a headline path fragment or full URI.
CURRENT-TITLE is the expected current title.
NEW-TITLE is the new title to set.
EXPECTED-CONTENT-REGEX is an anchored regex that matches the complete buffer.
IDS-TO-REGISTER is optional list of IDs to register for the temp file."
  (org-cli-test--with-temp-org-files
   ((test-file initial-content))
   (when ids-to-register
     (let ((org-id-track-globally t)
           (org-id-locations-file nil)
           (org-id-locations nil))
       (dolist (id ids-to-register)
         (org-id-add-location id test-file))))
   (let* ((uri (if (string-prefix-p "org-" headline-path-or-uri)
                   headline-path-or-uri
                 (format "org-headline://%s#%s" test-file headline-path-or-uri)))
          (result-text
           (org-cli-rename-headline uri current-title new-title))
          (result (json-read-from-string result-text))
          (result-uri (alist-get 'uri result)))
     (should (= (length result) 4))
     (should (equal (alist-get 'success result) t))
     (should (equal (alist-get 'previous_title result) current-title))
     (should (equal (alist-get 'new_title result) new-title))
     (should (stringp result-uri))
     (should (string-prefix-p "org-id://" result-uri))
     ;; If input URI was ID-based, result URI should remain ID-based
     (when (string-prefix-p "org-id://" uri)
       (should (equal result-uri uri)))
     (org-cli-test--verify-file-matches test-file expected-content-regex))))

(defun org-cli-test--assert-rename-headline-rejected
    (initial-content headline-title new-title)
  "Assert renaming headline to NEW-TITLE is rejected.
INITIAL-CONTENT is the Org content to test with.
HEADLINE-TITLE is the current headline to rename.
NEW-TITLE is the invalid new title that should be rejected."
  (org-cli-test--call-rename-headline-expecting-error
   initial-content
   (url-hexify-string headline-title)
   headline-title
   new-title))

(defun org-cli-test--call-rename-headline-expecting-error
    (initial-content headline-path-or-uri current-title new-title)
  "Call org-rename-headline tool expecting an error and verify file unchanged.
INITIAL-CONTENT is the initial Org file content.
HEADLINE-PATH-OR-URI is either a headline path fragment or full URI.
CURRENT-TITLE is the current title for validation.
NEW-TITLE is the new title to set."
  (org-cli-test--with-temp-org-files
   ((test-file initial-content))
   (let ((uri (if (string-prefix-p "org-" headline-path-or-uri)
                  headline-path-or-uri
                (format "org-headline://%s#%s" test-file headline-path-or-uri))))
     (org-cli-test--assert-error-and-file
      test-file
      (org-cli-rename-headline uri current-title new-title)))))

;; Helper functions for testing org-edit-body MCP tool

(defun org-cli-test--call-edit-body-and-check
    (test-file resource-uri old-body new-body expected-pattern
               &optional replace-all expected-id)
  "Call org-edit-body tool and check result structure and file content.
TEST-FILE is the path to the file to check.
RESOURCE-URI is the URI of the node to edit.
OLD-BODY is the substring to search for within the node's body.
NEW-BODY is the replacement text.
EXPECTED-PATTERN is a regexp that the file content should match.
REPLACE-ALL if true, replace all occurrences (default: nil).
EXPECTED-ID if provided, check the returned URI has this exact ID."
  (let* ((params
          `((resource_uri . ,resource-uri)
            (old_body . ,old-body)
            (new_body . ,new-body)
            (replace_all . ,replace-all)))
         (result-text (org-cli-edit-body resource-uri old-body new-body replace-all))
         (result (json-read-from-string result-text)))
    (should (= (length result) 2))
    (should (equal (alist-get 'success result) t))
    (let ((uri (alist-get 'uri result)))
      (if expected-id
          (should (equal uri (concat "org-id://" expected-id)))
        (should (string-prefix-p "org-id://" uri))))
    (org-cli-test--verify-file-matches test-file expected-pattern)))

(defun org-cli-test--call-edit-body-expecting-error
    (test-file resource-uri old-body new-body &optional replace-all)
  "Call org-edit-body tool expecting an error and verify file unchanged.
TEST-FILE is the test file path to verify remains unchanged.
RESOURCE-URI is the URI of the node to edit.
OLD-BODY is the substring to search for within the node's body.
NEW-BODY is the replacement text.
REPLACE-ALL if true, replace all occurrences (default: nil)."
  (org-cli-test--assert-error-and-file
   test-file
   (org-cli-edit-body resource-uri old-body new-body replace-all)))

;; Helper functions for testing org-read-file MCP tool

(defun org-cli-test--call-read-file (file)
  "Call org-read-file tool via JSON-RPC and return the result.
FILE is the file path to read."
  (let ((params `((file . ,file))))
    (org-cli-read-file file)))

;; Helper functions for testing org-read-outline MCP tool

(defun org-cli-test--call-read-outline (file)
  "Call org-read-outline tool via JSON-RPC and return the result.
FILE is the file path to read the outline from."
  (let* ((params `((file . ,file)))
         (result-json
          (org-cli-read-outline file)))
    (json-parse-string result-json :object-type 'alist)))

;; Helper functions for testing org-read-by-id MCP tool

(defun org-cli-test--call-read-by-id-and-check (uuid expected-pattern)
  "Call org-read-by-id tool via JSON-RPC and verify the result.
UUID is the ID property of the headline to read.
EXPECTED-PATTERN is a regex pattern the result should match."
  (let* ((params `((uuid . ,uuid)))
         (result-text (org-cli-read-by-id uuid)))
    (should (string-match-p expected-pattern result-text))))

;; Helper functions for testing MCP resources

(defun org-cli-test--verify-resource-read (uri text)
  "Verify reading at URI returns TEXT."
  (let ((result
         (cond
          ((string-prefix-p "org-id://" uri)
           (org-cli-read-by-id
            (substring uri (length "org-id://"))))
          ((string-prefix-p "org-headline://" uri)
           (let* ((full-path (substring uri (length "org-headline://")))
                  (hash-pos (string-match "#" full-path)))
             (if hash-pos
                 (org-cli-read-headline
                  (substring full-path 0 hash-pos)
                  (substring full-path (1+ hash-pos)))
               (org-cli-read-file full-path))))
          ((string-prefix-p "org-outline://" uri)
           (org-cli-read-outline
            (substring uri (length "org-outline://"))))
          ((string-prefix-p "org://" uri)
           (org-cli-read-file
            (substring uri (length "org://")))))))
    (should (equal result text))))

(defun org-cli-test--read-resource-expecting-error
    (uri expected-error-message)
  "Read at URI expecting an error with EXPECTED-ERROR-MESSAGE."
  (condition-case err
      (progn
        (cond
         ((string-prefix-p "org-id://" uri)
          (org-cli-read-by-id
           (substring uri (length "org-id://"))))
         ((string-prefix-p "org-headline://" uri)
          (let* ((full-path (substring uri (length "org-headline://")))
                 (hash-pos (string-match "#" full-path)))
            (if hash-pos
                (org-cli-read-headline
                 (substring full-path 0 hash-pos)
                 (substring full-path (1+ hash-pos)))
              (org-cli-read-file full-path))))
         ((string-prefix-p "org-outline://" uri)
          (org-cli-read-outline
           (substring uri (length "org-outline://"))))
         ((string-prefix-p "org://" uri)
          (org-cli-read-file
           (substring uri (length "org://")))))
        (error "Expected error but got success for URI: %s" uri))
    (org-cli-error
     (should (string-match-p (regexp-quote expected-error-message)
                             (cadr err))))))

(defun org-cli-test--test-headline-resource-with-extension (extension)
  "Test headline resource with file having EXTENSION.
EXTENSION can be a string like \".txt\" or nil for no extension."
  (let ((test-file
         (make-temp-file
          "org-cli-test" nil extension org-cli-test--content-nested-siblings)))
    (unwind-protect
        (let ((org-cli-allowed-files (list test-file))
              (uri
               (format "org-headline://%s#Parent%%20Task"
                       test-file)))
          (org-cli-test--with-enabled
           (org-cli-test--verify-resource-read
            uri
            org-cli-test--expected-parent-task-from-nested-siblings)))
      (delete-file test-file))))

;;; Tests

;; org-get-todo-config tests

(ert-deftest org-cli-test-tool-get-todo-config-empty ()
  "Test org-get-todo-config with empty `org-todo-keywords'."
  (org-cli-test--with-get-todo-config-result
   nil
   (should (assoc 'sequences result))
   (should (assoc 'semantics result))
   (should (equal sequences []))
   (should (equal semantics []))))

(ert-deftest org-cli-test-tool-get-todo-config-default ()
  "Test org-get-todo-config with default `org-todo-keywords'."
  (org-cli-test--with-get-todo-config-result '((sequence "TODO(t!)" "DONE(d!)"))
    (should (= (length sequences) 1))
    (org-cli-test--check-todo-config-sequence
     (aref sequences 0) "sequence" ["TODO(t!)" "|" "DONE(d!)"])
    (should (= (length semantics) 2))
    (org-cli-test--check-todo-config-semantic
     (aref semantics 0) "TODO" nil "sequence")
    (org-cli-test--check-todo-config-semantic
     (aref semantics 1) "DONE" t "sequence")))

(ert-deftest org-cli-test-tool-get-todo-config-single-keyword ()
  "Test org-get-todo-config with single keyword."
  (org-cli-test--with-get-todo-config-result '((sequence "DONE"))
    (should (= (length sequences) 1))
    (org-cli-test--check-todo-config-sequence
     (aref sequences 0) "sequence" ["|" "DONE"])
    (should (= (length semantics) 1))
    (org-cli-test--check-todo-config-semantic
     (aref semantics 0) "DONE" t "sequence")))

(ert-deftest org-cli-test-tool-get-todo-config-explicit-bar ()
  "Test org-get-todo-config with explicit | and multiple states."
  (org-cli-test--with-get-todo-config-result '((sequence
                                "TODO" "NEXT" "|" "DONE" "CANCELLED"))
    (should (= (length sequences) 1))
    (org-cli-test--check-todo-config-sequence
     (aref sequences 0)
     "sequence"
     ["TODO" "NEXT" "|" "DONE" "CANCELLED"])
    (should (= (length semantics) 4))
    (org-cli-test--check-todo-config-semantic
     (aref semantics 0) "TODO" nil "sequence")
    (org-cli-test--check-todo-config-semantic
     (aref semantics 1) "NEXT" nil "sequence")
    (org-cli-test--check-todo-config-semantic
     (aref semantics 2) "DONE" t "sequence")
    (org-cli-test--check-todo-config-semantic
     (aref semantics 3) "CANCELLED" t "sequence")))

(ert-deftest org-cli-test-tool-get-todo-config-type ()
  "Test org-get-todo-config with type keywords."
  (org-cli-test--with-get-todo-config-result '((type "Fred" "Sara" "Lucy" "|" "DONE"))
    (should (= (length sequences) 1))
    (org-cli-test--check-todo-config-sequence
     (aref sequences 0) "type" ["Fred" "Sara" "Lucy" "|" "DONE"])
    (should (= (length semantics) 4))
    (org-cli-test--check-todo-config-semantic
     (aref semantics 0) "Fred" nil "type")
    (org-cli-test--check-todo-config-semantic
     (aref semantics 1) "Sara" nil "type")
    (org-cli-test--check-todo-config-semantic
     (aref semantics 2) "Lucy" nil "type")
    (org-cli-test--check-todo-config-semantic
     (aref semantics 3) "DONE" t "type")))

(ert-deftest org-cli-test-tool-get-todo-config-multiple-sequences ()
  "Test org-get-todo-config with multiple sequences."
  (org-cli-test--with-get-todo-config-result '((sequence "TODO" "|" "DONE")
                               (type "BUG" "FEATURE" "|" "FIXED"))
    (should (= (length sequences) 2))
    ;; First sequence
    (org-cli-test--check-todo-config-sequence
     (aref sequences 0) "sequence" ["TODO" "|" "DONE"])
    ;; Second sequence
    (org-cli-test--check-todo-config-sequence
     (aref sequences 1) "type" ["BUG" "FEATURE" "|" "FIXED"])
    (should (= (length semantics) 5))
    ;; Semantics from first sequence
    (org-cli-test--check-todo-config-semantic
     (aref semantics 0) "TODO" nil "sequence")
    (org-cli-test--check-todo-config-semantic
     (aref semantics 1) "DONE" t "sequence")
    ;; Semantics from second sequence
    (org-cli-test--check-todo-config-semantic (aref semantics 2) "BUG" nil "type")
    (org-cli-test--check-todo-config-semantic
     (aref semantics 3) "FEATURE" nil "type")
    (org-cli-test--check-todo-config-semantic
     (aref semantics 4) "FIXED" t "type")))

(ert-deftest org-cli-test-tool-get-todo-config-no-done-states ()
  "Test org-get-todo-config with no done states."
  (org-cli-test--with-get-todo-config-result '((sequence "TODO" "NEXT" "|"))
    (should (= (length sequences) 1))
    (org-cli-test--check-todo-config-sequence
     (aref sequences 0) "sequence" ["TODO" "NEXT" "|"])
    (should (= (length semantics) 2))
    (org-cli-test--check-todo-config-semantic
     (aref semantics 0) "TODO" nil "sequence")
    (org-cli-test--check-todo-config-semantic
     (aref semantics 1) "NEXT" nil "sequence")))

(ert-deftest org-cli-test-tool-get-todo-config-type-no-separator ()
  "Test org-get-todo-config with type keywords and no separator."
  (org-cli-test--with-get-todo-config-result
   '((type "BUG" "FEATURE" "ENHANCEMENT"))
   (should (= (length sequences) 1))
   (org-cli-test--check-todo-config-sequence
    (aref sequences 0) "type" ["BUG" "FEATURE" "|" "ENHANCEMENT"])
   (should (= (length semantics) 3))
   (org-cli-test--check-todo-config-semantic (aref semantics 0) "BUG" nil "type")
   (org-cli-test--check-todo-config-semantic
    (aref semantics 1) "FEATURE" nil "type")
   (org-cli-test--check-todo-config-semantic
    (aref semantics 2) "ENHANCEMENT" t "type")))

;; org-get-tag-config tests

(ert-deftest org-cli-test-tool-get-tag-config-empty ()
  "Test org-get-tag-config with empty `org-tag-alist'."
  (let ((org-tag-alist nil)
        (org-tag-persistent-alist nil)
        (org-use-tag-inheritance t))
    (org-cli-test--get-tag-config-and-check "nil" "nil" "t" "nil")))

(ert-deftest org-cli-test-tool-get-tag-config-simple ()
  "Test org-get-tag-config with simple tags."
  (let ((org-tag-alist '("work" "personal" "urgent"))
        (org-tag-persistent-alist nil)
        (org-use-tag-inheritance t)
        (org-tags-exclude-from-inheritance nil))
    (org-cli-test--get-tag-config-and-check
     "(\"work\" \"personal\" \"urgent\")" "nil" "t" "nil")))

(ert-deftest org-cli-test-tool-get-tag-config-with-keys ()
  "Test org-get-tag-config with fast selection keys."
  (let ((org-tag-alist
         '(("work" . ?w) ("personal" . ?p) "urgent" ("@home" . ?h)))
        (org-tag-persistent-alist nil)
        (org-use-tag-inheritance t))
    (org-cli-test--get-tag-config-and-check
     "((\"work\" . 119) (\"personal\" . 112) \"urgent\" (\"@home\" . 104))"
     "nil"
     "t"
     "nil")))

(ert-deftest org-cli-test-tool-get-tag-config-with-groups ()
  "Test org-get-tag-config with tag groups."
  (let ((org-tag-alist
         '((:startgroup)
           ("@office" . ?o)
           ("@home" . ?h)
           ("@errand" . ?e)
           (:endgroup)
           "laptop"
           (:startgrouptag)
           ("project")
           (:grouptags)
           ("proj_a")
           ("proj_b")
           (:endgrouptag)))
        (org-tag-persistent-alist nil))
    (org-cli-test--get-tag-config-and-check
     "((:startgroup) (\"@office\" . 111) (\"@home\" . 104) (\"@errand\" . 101) (:endgroup) \"laptop\" (:startgrouptag) (\"project\") (:grouptags) (\"proj_a\") (\"proj_b\") (:endgrouptag))"
     "nil"
     "t"
     "nil")))

(ert-deftest org-cli-test-tool-get-tag-config-persistent ()
  "Test org-get-tag-config with persistent tags."
  (let ((org-tag-alist '(("work" . ?w)))
        (org-tag-persistent-alist '(("important" . ?i) "recurring"))
        (org-tags-exclude-from-inheritance nil))
    (org-cli-test--get-tag-config-and-check
     "((\"work\" . 119))" "((\"important\" . 105) \"recurring\")"
     "t"
     "nil")))

(ert-deftest org-cli-test-tool-get-tag-config-inheritance-enabled ()
  "Test org-get-tag-config with inheritance enabled."
  (let ((org-tag-alist '("work" "personal"))
        (org-tags-exclude-from-inheritance nil)
        (org-tag-persistent-alist nil)
        (org-use-tag-inheritance t))
    (org-cli-test--get-tag-config-and-check
     "(\"work\" \"personal\")" "nil" "t" "nil")))

(ert-deftest org-cli-test-tool-get-tag-config-inheritance-disabled ()
  "Test org-get-tag-config with inheritance disabled."
  (let ((org-tag-alist '("work" "personal"))
        (org-tags-exclude-from-inheritance nil)
        (org-tag-persistent-alist nil)
        (org-use-tag-inheritance nil))
    (org-cli-test--get-tag-config-and-check
     "(\"work\" \"personal\")" "nil" "nil" "nil")))

(ert-deftest org-cli-test-tool-get-tag-config-inheritance-selective ()
  "Test org-get-tag-config with selective inheritance (list)."
  (let ((org-tag-alist '("work" "personal"))
        (org-tags-exclude-from-inheritance nil)
        (org-tag-persistent-alist nil)
        (org-use-tag-inheritance '("work")))
    (org-cli-test--get-tag-config-and-check
     "(\"work\" \"personal\")" "nil" "(\"work\")"
     "nil")))

;; org-get-allowed-files tests

(ert-deftest org-cli-test-tool-get-allowed-files-empty ()
  "Test org-get-allowed-files with empty configuration."
  (org-cli-test--get-allowed-files-and-check nil nil))

(ert-deftest org-cli-test-tool-get-allowed-files-single ()
  "Test org-get-allowed-files with single file."
  (org-cli-test--get-allowed-files-and-check
   '("/home/user/tasks.org")
   '("/home/user/tasks.org")))

(ert-deftest org-cli-test-tool-get-allowed-files-multiple ()
  "Test org-get-allowed-files with multiple files."
  (org-cli-test--get-allowed-files-and-check
   '("/home/user/tasks.org"
     "/home/user/projects.org"
     "/home/user/notes.org")
   '("/home/user/tasks.org"
     "/home/user/projects.org"
     "/home/user/notes.org")))

(ert-deftest org-cli-test-file-not-in-allowed-list-returns-error ()
  "Test that reading a file not in allowed list returns an error."
  (org-cli-test--with-temp-org-files
   ((allowed-file "Allowed content")
    (forbidden-file "Forbidden content"))
   (let ((org-cli-allowed-files (list allowed-file)))
     ;; Try to read the forbidden file
     (let ((uri (format "org://%s" forbidden-file)))
       (org-cli-test--read-resource-expecting-error
        uri
        (format "'%s': the referenced file not in allowed list" forbidden-file))))))

;;; org-update-todo-state tests

(ert-deftest org-cli-test-update-todo-state-success ()
  "Test successful TODO state update."
  (let ((test-content org-cli-test--content-with-id-todo))
    (org-cli-test--with-temp-org-files
     ((test-file test-content))
     (let ((org-todo-keywords
            '((sequence "TODO(t!)" "IN-PROGRESS(i!)" "|" "DONE(d!)"))))
       ;; Update TODO to IN-PROGRESS
       (let ((resource-uri
              (format "org-headline://%s#Task%%20with%%20ID" test-file)))
         (org-cli-test--update-todo-state-and-check
          resource-uri "TODO" "IN-PROGRESS"
          test-file org-cli-test--expected-task-with-id-in-progress-regex))))))

(ert-deftest org-cli-test-update-todo-state-mismatch ()
  "Test TODO state update fails on state mismatch."
  (let ((test-content org-cli-test--content-with-id-todo))
    (org-cli-test--with-temp-org-files
        ((test-file test-content))
      ;; Try to update with wrong current state
      (let ((resource-uri
             (format "org-headline://%s#Task%%20with%%20ID" test-file)))
        (org-cli-test--call-update-todo-state-expecting-error
         test-file resource-uri "IN-PROGRESS" "DONE")))))

(ert-deftest org-cli-test-update-todo-with-timestamp-id ()
  "Test updating TODO state using timestamp-format ID (not UUID)."
  (let ((test-content org-cli-test--content-timestamp-id))
    (let ((org-todo-keywords '((sequence "TODO" "|" "DONE"))))
      (org-cli-test--with-id-setup test-file test-content
          `("20240101T120000")
        (let ((uri "org-id://20240101T120000"))
          (org-cli-test--update-todo-state-and-check
           uri "TODO" "DONE"
           test-file
           org-cli-test--expected-timestamp-id-done-regex))))))

(ert-deftest org-cli-test-update-todo-state-empty-newstate-invalid ()
  "Test that empty string for newState is rejected."
  (let ((test-content org-cli-test--content-with-id-todo))
    (org-cli-test--with-temp-org-files
        ((test-file test-content))
      ;; Try to set empty state
      (let ((resource-uri
             (format "org-headline://%s#Task%%20with%%20ID" test-file)))
        (org-cli-test--call-update-todo-state-expecting-error
         test-file resource-uri "TODO" "")))))

(ert-deftest org-cli-test-update-todo-state-invalid ()
  "Test TODO state update fails for invalid new state."
  (let ((test-content org-cli-test--content-with-id-todo))
    (org-cli-test--with-temp-org-files
        ((test-file test-content))
      ;; Try to update to invalid state
      (let ((resource-uri
             (format "org-headline://%s#Task%%20with%%20ID" test-file)))
        (org-cli-test--call-update-todo-state-expecting-error
         test-file resource-uri "TODO" "INVALID-STATE")))))

(ert-deftest org-cli-test-update-todo-state-with-open-buffer ()
  "Test TODO state update works when file is open in another buffer."
  (let ((test-content org-cli-test--content-with-id-todo))
    (org-cli-test--with-temp-org-files
        ((test-file test-content))
      (let ((org-todo-keywords
             '((sequence "TODO" "IN-PROGRESS" "|" "DONE"))))
        ;; Open the file in a buffer
        (org-cli-test--with-file-buffer buffer test-file
          ;; Update TODO state while buffer is open
          (let ((resource-uri
                 (format "org-headline://%s#Task%%20with%%20ID"
                         test-file)))
            (org-cli-test--update-todo-state-and-check
             resource-uri "TODO" "IN-PROGRESS"
             test-file org-cli-test--expected-task-with-id-in-progress-regex)
            ;; Verify the buffer was also updated
            (with-current-buffer buffer
              (goto-char (point-min))
              (should
               (re-search-forward "^\\* IN-PROGRESS Task with ID"
                                  nil t)))))))))

(ert-deftest org-cli-test-update-todo-state-with-modified-buffer ()
  "Test TODO state update fails when buffer has unsaved changes."
  (let ((test-content org-cli-test--content-simple-todo))
    (org-cli-test--with-temp-org-files
        ((test-file test-content))
      ;; Open the file in a buffer and modify it elsewhere
      (org-cli-test--with-file-buffer buffer test-file
        ;; Make a modification at an unrelated location
        (with-current-buffer buffer
          (goto-char (point-max))
          (insert "\n* TODO Another Task\nAdded in buffer.")
          ;; Buffer is now modified but not saved
          (should (buffer-modified-p)))

        ;; Try to update while buffer has unsaved changes
        (let ((resource-uri
               (format "org-headline://%s#Original%%20Task"
                       test-file)))
          (org-cli-test--call-update-todo-state-expecting-error
           test-file resource-uri "TODO" "IN-PROGRESS")
          ;; Verify buffer still has unsaved changes
          (with-current-buffer buffer
            (should (buffer-modified-p))))))))

(ert-deftest org-cli-test-update-todo-state-nonexistent-id ()
  "Test TODO state update fails for non-existent UUID."
  (let ((test-content org-cli-test--content-with-id-todo))
    (org-cli-test--with-id-setup test-file test-content '()
      ;; Try to update a non-existent ID
      (let ((resource-uri "org-id://nonexistent-uuid-12345"))
        (org-cli-test--call-update-todo-state-expecting-error
         test-file resource-uri "TODO" "IN-PROGRESS")))))

(ert-deftest org-cli-test-update-todo-state-by-id ()
  "Test updating TODO state using org-id:// URI."
  (let ((test-content org-cli-test--content-with-id-todo))
    (let ((org-todo-keywords
           '((sequence "TODO" "IN-PROGRESS" "|" "DONE"))))
      (org-cli-test--with-id-setup test-file test-content
          `(,org-cli-test--content-with-id-id)
        (org-cli-test--update-todo-state-and-check
         org-cli-test--content-with-id-uri "TODO" "IN-PROGRESS"
         test-file
         org-cli-test--expected-task-with-id-in-progress-regex)))))

(ert-deftest org-cli-test-update-todo-state-nonexistent-headline ()
  "Test TODO state update fails for non-existent headline path."
  (let ((test-content org-cli-test--content-simple-todo))
    (org-cli-test--with-temp-org-files
     ((test-file test-content))
     ;; Try to update a non-existent headline
     (let ((resource-uri
            (format "org-headline://%s#Nonexistent%%20Task"
                    test-file)))
       (org-cli-test--call-update-todo-state-expecting-error
        test-file resource-uri "TODO" "IN-PROGRESS")))))

;; org-add-todo tests

(ert-deftest org-cli-test-add-todo-top-level ()
  "Test adding a top-level TODO item."
  (org-cli-test--add-todo-and-check
   org-cli-test--content-empty nil nil nil
   "New Task"
   "TODO"
   '("work" "urgent")
   nil ; no body
   (format "org-headline://%s#" test-file)
   nil ; no afterUri
   (file-name-nondirectory test-file)
   org-cli-test--regex-top-level-todo))

(ert-deftest org-cli-test-add-todo-top-level-with-header ()
  "Test adding top-level TODO after header comments."
  (let ((initial-content org-cli-test--content-nested-siblings))
    (org-cli-test--add-todo-and-check
     initial-content nil nil nil
     "New Top Task"
     "TODO"
     '("urgent")
     nil ; no body
     (format "org-headline://%s#" test-file)
     nil ; no afterUri
     (file-name-nondirectory test-file)
     org-cli-test--expected-regex-top-level-with-header)))

(ert-deftest org-cli-test-add-todo-invalid-state ()
  "Test that adding TODO with invalid state throws error."
  (org-cli-test--call-add-todo-expecting-error
   org-cli-test--content-empty nil nil
   "New Task"
   "INVALID-STATE" ; Not in org-todo-keywords
   '("work")
   nil
   (format "org-headline://%s#" test-file)))

(ert-deftest org-cli-test-add-todo-empty-title ()
  "Test that adding TODO with empty title throws error."
  (org-cli-test--assert-add-todo-invalid-title ""))

(ert-deftest org-cli-test-add-todo-spaces-only-title ()
  "Test that adding TODO with spaces-only title throws error."
  (org-cli-test--assert-add-todo-invalid-title "   "))

(ert-deftest org-cli-test-add-todo-mixed-whitespace-title ()
  "Test that adding TODO with mixed whitespace title throws error."
  (org-cli-test--assert-add-todo-invalid-title "	  	"))

(ert-deftest org-cli-test-add-todo-unicode-nbsp-title ()
  "Test that adding TODO with Unicode non-breaking space throws error."
  ;; U+00A0 is the non-breaking space character
  (org-cli-test--assert-add-todo-invalid-title "\u00A0"))

(ert-deftest org-cli-test-add-todo-embedded-newline-title ()
  "Test that adding TODO with embedded newline in title throws error."
  (org-cli-test--assert-add-todo-invalid-title
   "First Line\nSecond Line"))

(ert-deftest org-cli-test-add-todo-tag-reject-invalid-with-alist ()
  "Test that tags not in `org-tag-alist' are rejected."
  ;; Should reject tags not in org-tag-alist
  (org-cli-test--call-add-todo-expecting-error
   org-cli-test--content-empty nil nil
   "Task" "TODO" '("invalid") nil
   (format "org-headline://%s#" test-file)))

(ert-deftest org-cli-test-add-todo-tag-accept-valid-with-alist ()
  "Test that tags in `org-tag-alist' are accepted."
  ;; Should accept tags in org-tag-alist (work, personal, urgent)
  (org-cli-test--add-todo-and-check
   org-cli-test--content-empty nil nil nil
   "ValidTask"
   "TODO"
   '("work")
   nil
   (format "org-headline://%s#" test-file)
   nil
   (file-name-nondirectory test-file)
   (concat
    "^\\* TODO ValidTask +:work:\n"
    "\\(?: *:PROPERTIES:\n"
    " *:ID: +[^\n]+\n"
    " *:END:\n\\)?$")))

(ert-deftest org-cli-test-add-todo-tag-validation-without-alist ()
  "Test valid tag names are accepted when `org-tag-alist' is empty."
  ;; Should accept valid tag names (alphanumeric, _, @)
  (org-cli-test--add-todo-and-check
   org-cli-test--content-empty nil nil nil
   "Task1"
   "TODO"
   '("validtag" "tag123" "my_tag" "@home")
   nil
   (format "org-headline://%s#" test-file)
   nil
   (file-name-nondirectory test-file)
   (concat
    "^\\* TODO Task1 +:"
    ".*validtag.*tag123.*my_tag.*@home.*:\n"
    "\\(?: *:PROPERTIES:\n"
    " *:ID: +[^\n]+\n"
    " *:END:\n\\)?$")
   ((org-tag-alist nil)
    (org-tag-persistent-alist nil))))

(ert-deftest org-cli-test-add-todo-tag-invalid-exclamation ()
  "Test that tags with exclamation mark are rejected."
  (let ((org-tag-alist nil)
        (org-tag-persistent-alist nil))
    (org-cli-test--call-add-todo-expecting-error
     org-cli-test--content-empty nil nil
     "Task" "TODO" '("invalid-tag!") nil
     (format "org-headline://%s#" test-file))))

(ert-deftest org-cli-test-add-todo-tag-invalid-dash ()
  "Test that tags with dash character are rejected."
  (let ((org-tag-alist nil)
        (org-tag-persistent-alist nil))
    (org-cli-test--call-add-todo-expecting-error
     org-cli-test--content-empty nil nil
     "Task" "TODO" '("tag-with-dash") nil
     (format "org-headline://%s#" test-file))))

(ert-deftest org-cli-test-add-todo-tag-invalid-hash ()
  "Test that tags with hash character are rejected."
  (let ((org-tag-alist nil)
        (org-tag-persistent-alist nil))
    (org-cli-test--call-add-todo-expecting-error
     org-cli-test--content-empty nil nil
     "Task" "TODO" '("tag#hash") nil
     (format "org-headline://%s#" test-file))))

(ert-deftest org-cli-test-add-todo-child-under-parent ()
  "Test adding a child TODO under an existing parent."
  (org-cli-test--add-todo-and-check
   org-cli-test--content-nested-siblings nil nil nil
   "Child Task"
   "TODO"
   '("work")
   nil ; no body
   (format "org-headline://%s#Parent%%20Task" test-file)
   nil ; no afterUri
   (file-name-nondirectory test-file)
   org-cli-test--regex-child-under-parent))

(ert-deftest org-cli-test-add-todo-child-empty-after-uri ()
  "Test adding a child TODO with empty string for after_uri.
Empty string should be treated as nil - append as last child."
  (org-cli-test--add-todo-and-check
   org-cli-test--content-nested-siblings nil nil nil
   "Child Task"
   "TODO"
   '("work")
   nil ; no body
   (format "org-headline://%s#Parent%%20Task" test-file)
   "" ; empty string after_uri
   (file-name-nondirectory test-file)
   org-cli-test--regex-child-under-parent))

(ert-deftest org-cli-test-add-todo-second-child-same-level ()
  "Test that adding a second child creates it at the same level as first child.
This tests the bug where the second child was created at level 4 instead of level 3."
  (org-cli-test--add-todo-and-check
   org-cli-test--content-level2-parent-level3-children nil nil nil
   "Second Child"
   "TODO"
   '("work")
   nil  ; no body
   (format "org-headline://%s#Top%%20Level/Review%%20the%%20package"
           test-file)
   nil ; no after_uri
   (file-name-nondirectory test-file)
   org-cli-test--regex-second-child-same-level))

(ert-deftest org-cli-test-add-todo-with-after-uri ()
  "Test adding TODO after a sibling using after_uri.
Tests that adding after a level 3 sibling correctly creates level 3 (not level 1).
Reproduces the emacs.org scenario: level 2 parent (via path), level 3 sibling (via ID)."
  ;; BUG: org-insert-heading creates level 1 (*) instead of level 3 (***)
  (org-cli-test--add-todo-and-check
   org-cli-test--content-level2-parent-level3-children
   '((sequence "TODO" "|" "DONE"))
   '("internet")
   `(,org-cli-test--level2-parent-level3-sibling-id)
   "Review org-cli-test.el"
   "TODO"
   '("internet")
   nil
   (format "org-headline://%s#Top%%20Level/Review%%20the%%20package"
           test-file)
   (format "org-id://%s"
           org-cli-test--level2-parent-level3-sibling-id)
   (file-name-nondirectory test-file)
   org-cli-test--regex-after-sibling-level3))

(ert-deftest org-cli-test-add-todo-with-body ()
  "Test adding TODO with body text."
  (org-cli-test--add-todo-and-check
   org-cli-test--content-empty nil nil nil
   "Task with Body"
   "TODO"
   '("work")
   org-cli-test--body-text-multiline
   (format "org-headline://%s#" test-file)
   nil
   (file-name-nondirectory test-file)
   org-cli-test--regex-todo-with-body))

(ert-deftest org-cli-test-add-todo-body-with-same-level-headline ()
  "Test that adding TODO with body containing same-level headline is rejected."
  (org-cli-test--assert-add-todo-rejects-body-headline
   org-cli-test--content-empty
   "" ; top-level parent
   "Some initial text.\n* Another headline\nMore text."))

(ert-deftest org-cli-test-add-todo-body-with-higher-level-headline ()
  "Test that adding TODO with body containing higher-level headline is rejected."
  (org-cli-test--assert-add-todo-rejects-body-headline
   "* Parent\n"
   "Parent"
   "Some initial text.\n* Top level headline\nMore text."))

(ert-deftest org-cli-test-add-todo-body-with-headline-at-eof ()
  "Test that adding TODO with body ending in headline at EOF is rejected."
  (org-cli-test--assert-add-todo-rejects-body-headline
   org-cli-test--content-empty
   "" ; top-level parent
   "Some initial text.\n* Headline at EOF"))

(ert-deftest org-cli-test-add-todo-body-with-asterisk-only-at-eof ()
  "Test that body ending with just asterisk at EOF is correctly accepted.
A single asterisk without space is not a valid Org headline."
  ;; Should succeed since * without space is not a headline
  (org-cli-test--add-todo-and-check
   org-cli-test--content-empty nil nil nil
   "Task"
   "TODO"
   '("work")
   "Some initial text.\n*"
   (format "org-headline://%s#" test-file)
   nil
   (file-name-nondirectory test-file)
   (concat
    "^\\* TODO Task +:work:\n"
    "\\(?: *:PROPERTIES:\n"
    " *:ID: +[^\n]+\n"
    " *:END:\n\\)?"
    "Some initial text\\.\n"
    "\\*$")))

(ert-deftest org-cli-test-add-todo-body-with-unbalanced-block ()
  "Test that adding TODO with body containing unbalanced block is rejected.
Unbalanced blocks like #+BEGIN_EXAMPLE without #+END_EXAMPLE should be
rejected in TODO body content."
  ;; Should reject unbalanced blocks
  (org-cli-test--call-add-todo-expecting-error
   org-cli-test--content-empty nil nil
   "Task with unbalanced block"
   "TODO"
   '("work")
   "Here's an example:\n#+BEGIN_EXAMPLE\nsome code\nMore text after block"
   (format "org-headline://%s#" test-file)))

(ert-deftest org-cli-test-add-todo-body-with-unbalanced-end-block ()
  "Test that adding TODO with body containing unbalanced END block is rejected.
An #+END_EXAMPLE without matching #+BEGIN_EXAMPLE should be rejected."
  ;; Should reject unbalanced END blocks
  (org-cli-test--call-add-todo-expecting-error
   org-cli-test--content-empty nil nil
   "Task with unbalanced END block"
   "TODO"
   '("work")
   "Some text before\n#+END_EXAMPLE\nMore text after"
   (format "org-headline://%s#" test-file)))

(ert-deftest org-cli-test-add-todo-body-with-literal-block-end ()
  "Test that TODO body with END_SRC inside EXAMPLE block is accepted.
#+END_SRC inside an EXAMPLE block is literal text, not a block delimiter.
This is valid Org-mode syntax and should be allowed."
  ;; Should succeed - #+END_SRC is just literal text inside EXAMPLE block
  (org-cli-test--add-todo-and-check
   org-cli-test--content-empty nil nil nil
   "Task with literal END_SRC"
   "TODO"
   '("work")
   "Example of source block:\n#+BEGIN_EXAMPLE\n#+END_SRC\n#+END_EXAMPLE\nText after."
   (format "org-headline://%s#" test-file)
   nil
   (file-name-nondirectory test-file)
   org-cli-test--regex-todo-with-literal-block-end))

(ert-deftest org-cli-test-add-todo-after-sibling ()
  "Test adding TODO after a specific sibling."
  (org-cli-test--add-todo-and-check
   org-cli-test--content-nested-siblings
   '((sequence "TODO" "|" "DONE"))
   '("work")
   (list org-cli-test--content-nested-siblings-parent-id
         org-cli-test--content-with-id-id)
   "New Task After Second"
   "TODO"
   '("work")
   nil
   (format "org-headline://%s#Parent%%20Task"
           test-file)
   org-cli-test--content-with-id-uri
   (file-name-nondirectory test-file)
   org-cli-test--regex-todo-after-second-child))

(ert-deftest org-cli-test-add-todo-afterUri-not-sibling ()
  "Test error when afterUri is not a child of parentUri."
  ;; Error: Other Child is not a child of First Parent
  (org-cli-test--call-add-todo-expecting-error
   org-cli-test--content-wrong-levels nil nil
   "New Task" "TODO" '("work") nil
   (format "org-headline://%s#First%%20Parent" test-file)
   (format "org-headline://%s#Second%%20Parent/Other%%20Child" test-file)))

(ert-deftest org-cli-test-add-todo-parent-id-uri ()
  "Test adding TODO with parent specified as org-id:// URI."
  ;; Use org-id:// for parent instead of org-headline://
  (org-cli-test--add-todo-and-check
   org-cli-test--content-nested-siblings
   '((sequence "TODO(t!)" "|" "DONE(d!)"))
   '("work")
   (list org-cli-test--content-nested-siblings-parent-id
         org-cli-test--content-with-id-id)
   "Child via ID"
   "TODO"
   '("work")
   nil
   (format "org-id://%s"
           org-cli-test--content-nested-siblings-parent-id)
   nil
   (file-name-nondirectory test-file)
   org-cli-test--pattern-add-todo-parent-id-uri))

(ert-deftest org-cli-test-add-todo-mutex-tags-error ()
  "Test that mutually exclusive tags are rejected."
  (org-cli-test--call-add-todo-expecting-error
   "#+TITLE: Test Org File\n\n"
   '((sequence "TODO" "|" "DONE"))
   '(("work" . ?w)
     :startgroup
     ("@office" . ?o)
     ("@home" . ?h)
     :endgroup)
   "Test Task"
   "TODO"
   ["work" "@office" "@home"] ; conflicting tags
   nil
   (format "org-headline://%s#" test-file)
   nil))

(ert-deftest org-cli-test-add-todo-mutex-tags-valid ()
  "Test that non-conflicting tags from mutex groups are accepted."
  (org-cli-test--add-todo-and-check
   "#+TITLE: Test Org File\n\n"
   '((sequence "TODO" "|" "DONE"))
   '(("work" . ?w)
     :startgroup
     ("@office" . ?o)
     ("@home" . ?h)
     :endgroup ("project" . ?p))
   nil
   "Test Task"
   "TODO"
   ["work" "@office" "project"] ; no conflict
   nil
   (format "org-headline://%s#" test-file)
   nil
   (file-name-nondirectory test-file)
   org-cli-test--regex-add-todo-with-mutex-tags))

(ert-deftest org-cli-test-add-todo-nil-tags ()
  "Test that adding TODO with nil tags creates headline without tags."
  (org-cli-test--add-todo-and-check
   org-cli-test--content-empty nil nil nil
   "Task Without Tags"
   "TODO"
   nil ; nil for tags
   nil ; no body
   (format "org-headline://%s#" test-file)
   nil ; no afterUri
   (file-name-nondirectory test-file)
   org-cli-test--regex-todo-without-tags))

(ert-deftest org-cli-test-add-todo-empty-list-tags ()
  "Test that adding TODO with empty list tags creates headline without tags."
  (org-cli-test--add-todo-and-check
   org-cli-test--content-empty nil nil nil
   "Task Without Tags"
   "TODO"
   '() ; empty list for tags
   nil ; no body
   (format "org-headline://%s#" test-file)
   nil ; no afterUri
   (file-name-nondirectory test-file)
   org-cli-test--regex-todo-without-tags))

;; org-rename-headline tests

(ert-deftest org-cli-test-rename-headline-simple ()
  "Test renaming a simple TODO headline."
  (let ((org-todo-keywords '((sequence "TODO" "IN-PROGRESS" "|" "DONE"))))
    (org-cli-test--call-rename-headline-and-check
     org-cli-test--content-simple-todo
     "Original%20Task"
     "Original Task"
     "Updated Task"
     org-cli-test--pattern-renamed-simple-todo)))

(ert-deftest org-cli-test-rename-headline-title-mismatch ()
  "Test that rename fails when current title doesn't match."
  (let ((org-todo-keywords '((sequence "TODO" "|" "DONE"))))
    (org-cli-test--call-rename-headline-expecting-error
     org-cli-test--content-simple-todo
     "Original%20Task"
     "Wrong Title"
     "Updated Task")))

(ert-deftest org-cli-test-rename-headline-preserve-tags ()
  "Test that renaming preserves tags."
  (let ((org-todo-keywords '((sequence "TODO" "|" "DONE")))
        (org-tag-alist '("work" "urgent" "personal")))
    (org-cli-test--call-rename-headline-and-check
     org-cli-test--content-todo-with-tags
     "Task%20with%20Tags"
     "Task with Tags"
     "Renamed Task"
     org-cli-test--pattern-renamed-todo-with-tags)))

(ert-deftest org-cli-test-rename-headline-no-todo ()
  "Test renaming a regular headline without TODO state."
  (org-cli-test--call-rename-headline-and-check
   org-cli-test--content-nested-siblings
   "Parent%20Task/First%20Child%2050%25%20Complete"
   "First Child 50% Complete"
   "Updated Child"
   org-cli-test--pattern-renamed-headline-no-todo))

(ert-deftest org-cli-test-rename-headline-nested-path-navigation ()
  "Test correct headline path navigation in nested structures.
Verifies that the implementation correctly navigates nested headline
paths and only matches headlines at the appropriate hierarchy level."
  ;; Try to rename "First Parent/Target Headline"
  ;; But there's no Target Headline under First Parent!
  ;; The function should fail, but it might incorrectly
  ;; find Third Parent's Target Headline
  ;; This should throw an error because First Parent has no Target Headline
  (org-cli-test--call-rename-headline-expecting-error
   org-cli-test--content-wrong-levels
   "First%20Parent/Target%20Headline"
   "Target Headline"
   "Renamed Target Headline"))

(ert-deftest org-cli-test-rename-headline-by-id ()
  "Test renaming a headline accessed by org-id URI."
  (org-cli-test--call-rename-headline-and-check
   org-cli-test--content-nested-siblings
   org-cli-test--content-with-id-uri
   "Second Child"
   "Renamed Second Child"
   org-cli-test--expected-regex-renamed-second-child
   `(,org-cli-test--content-with-id-id)))

(ert-deftest org-cli-test-rename-headline-id-not-found ()
  "Test error when ID doesn't exist."
  (let ((org-id-track-globally nil)
        (org-id-locations-file nil))
    (org-cli-test--call-rename-headline-expecting-error
     org-cli-test--content-nested-siblings
     "org-id://non-existent-id-12345"
     "Whatever"
     "Should Fail")))

(ert-deftest org-cli-test-rename-headline-with-slash ()
  "Test renaming a headline containing a slash character.
Slashes must be properly URL-encoded to avoid path confusion."
  (org-cli-test--call-rename-headline-and-check
   org-cli-test--content-slash-not-nested-before
   "Parent%2FChild"
   "Parent/Child"
   "Parent/Child Renamed"
   org-cli-test--pattern-renamed-slash-headline))

(ert-deftest org-cli-test-rename-headline-slash-not-nested ()
  "Test that headline with slash is not treated as nested path.
Verifies that 'Parent/Child' is treated as a single headline,
not as Child under Parent."
  (org-cli-test--call-rename-headline-and-check
   org-cli-test--content-slash-not-nested-before
   "Parent%2FChild"
   "Parent/Child"
   "Parent-Child Renamed"
   org-cli-test--regex-slash-not-nested-after))

(ert-deftest org-cli-test-rename-headline-with-percent ()
  "Test renaming a headline containing a percent sign.
Percent signs must be properly URL-encoded to avoid double-encoding issues."
  (org-cli-test--call-rename-headline-and-check
   org-cli-test--content-nested-siblings
   "Parent%20Task/First%20Child%2050%25%20Complete"
   "First Child 50% Complete"
   "First Child 75% Complete"
   org-cli-test--regex-percent-after))

(ert-deftest org-cli-test-rename-headline-reject-empty-string ()
  "Test that renaming to an empty string is rejected."
  (org-cli-test--assert-rename-headline-rejected
   "* Important Task
This task has content."
   "Important Task" ""))

(ert-deftest org-cli-test-rename-headline-reject-whitespace-only ()
  "Test that renaming to whitespace-only is rejected."
  (org-cli-test--assert-rename-headline-rejected
   "* Another Task
More content."
   "Another Task" "   "))

(ert-deftest org-cli-test-rename-headline-reject-newline ()
  "Test that renaming to a title with embedded newline is rejected."
  (org-cli-test--assert-rename-headline-rejected
   org-cli-test--content-nested-siblings
   "Parent Task/First Child 50% Complete"
   "First Line\nSecond Line"))

(ert-deftest org-cli-test-rename-headline-duplicate-first-match ()
  "Test that when multiple headlines have the same name, first match is renamed.
This test documents the first-match behavior when duplicate headlines exist."
  (org-cli-test--call-rename-headline-and-check
   org-cli-test--content-duplicate-headlines-before
   "Project%20Review"
   "Project Review"
   "Q1 Review"
   org-cli-test--regex-duplicate-first-renamed))

(ert-deftest org-cli-test-rename-headline-creates-id ()
  "Test that renaming a headline creates an Org ID and returns it."
  (let ((org-id-track-globally t)
        (org-id-locations-file (make-temp-file "test-org-id")))
    (org-cli-test--call-rename-headline-and-check
     org-cli-test--content-nested-siblings
     "Parent%20Task/Third%20Child%20%233"
     "Third Child #3"
     "Renamed Child"
     org-cli-test--pattern-renamed-headline-with-id)))


(ert-deftest org-cli-test-rename-headline-hierarchy ()
  "Test that headline hierarchy is correctly navigated.
Ensures that when searching for nested headlines, the function
correctly restricts search to the parent's subtree."
  (org-cli-test--call-rename-headline-and-check
   org-cli-test--content-hierarchy-before
   "Second%20Section/Target"
   "Target"
   "Renamed Target"
   org-cli-test--regex-hierarchy-second-target-renamed))

(ert-deftest org-cli-test-rename-headline-with-todo-keyword ()
  "Test that headlines with TODO keywords can be renamed.
The navigation function should find headlines even when they have TODO keywords."
  (org-cli-test--call-rename-headline-and-check
   org-cli-test--content-todo-keywords-before
   "Project%20Management/Review%20Documents"
   "Review Documents"
   "Q1 Planning Review"
   org-cli-test--regex-todo-keywords-after))

;;; org-edit-body tests

(ert-deftest org-cli-test-edit-body-single-line ()
  "Test org-edit-body tool for single-line replacement."
  (org-cli-test--with-id-setup
   test-file
   org-cli-test--content-nested-siblings
   `(,org-cli-test--content-with-id-id)
   (org-cli-test--call-edit-body-and-check
    test-file
    org-cli-test--content-with-id-uri
    "Second child content."
    "Updated second child content."
    org-cli-test--pattern-edit-body-single-line
    nil
    org-cli-test--content-with-id-id)))

(ert-deftest org-cli-test-edit-body-multiline ()
  "Test org-edit-body tool for multi-line replacement."
  (org-cli-test--with-id-setup test-file
      org-cli-test--content-with-id-todo
      `(,org-cli-test--content-with-id-id)
    (org-cli-test--call-edit-body-and-check
     test-file
     org-cli-test--content-with-id-uri
     "Second line of content."
     "This has been replaced
with new multiline
content here."
     org-cli-test--pattern-edit-body-multiline
     nil
     org-cli-test--content-with-id-id)))

(ert-deftest org-cli-test-edit-body-multiple-without-replaceall ()
  "Test error for multiple occurrences without replaceAll."
  (org-cli-test--with-id-setup test-file
      org-cli-test--content-with-id-repeated-text
      `("test-id")
    (org-cli-test--call-edit-body-expecting-error
     test-file "org-id://test-id" "occurrence of pattern" "REPLACED" nil)))

(ert-deftest org-cli-test-edit-body-replace-all ()
  "Test org-edit-body tool with replaceAll functionality."
  (org-cli-test--with-id-setup test-file
      org-cli-test--content-with-id-repeated-text
      `("test-id")
    (org-cli-test--call-edit-body-and-check
     test-file
     "org-id://test-id"
     "occurrence of pattern"
     "REPLACED"
     org-cli-test--pattern-edit-body-replace-all
     t)))

(ert-deftest org-cli-test-edit-body-replace-all-explicit-false ()
  "Test that explicit replace_all=false triggers error on multiple matches."
  (org-cli-test--with-id-setup test-file
      org-cli-test--content-with-id-repeated-text
      `("test-id")
    ;; Should error because multiple occurrences exist
    (org-cli-test--call-edit-body-expecting-error
     test-file
     "org-id://test-id"
     "occurrence of pattern"
     "REPLACED"
     :false)))

(ert-deftest org-cli-test-edit-body-not-found ()
  "Test org-edit-body tool error when text is not found."
  (org-cli-test--with-id-setup test-file
      org-cli-test--content-nested-siblings
      `(,org-cli-test--content-with-id-id)
    (org-cli-test--call-edit-body-expecting-error
     test-file
     org-cli-test--content-with-id-uri
     "nonexistent text"
     "replacement"
     nil)))

(ert-deftest org-cli-test-edit-body-empty ()
  "Test org-edit-body tool can add content to empty body."
  (org-cli-test--with-temp-org-files
      ((test-file org-cli-test--content-nested-siblings))
    (let ((resource-uri
           (format "org-headline://%s#Parent%%20Task/Third%%20Child%%20%%233"
                   test-file)))
      (org-cli-test--call-edit-body-and-check
       test-file
       resource-uri
       ""
       "New content added."
       org-cli-test--pattern-edit-body-empty))))

(ert-deftest org-cli-test-edit-body-empty-old-replaces-entire-body ()
  "Test that empty oldBody replaces the entire body content."
  (org-cli-test--with-temp-org-files
   ((file "* Task\nSome existing content.\n"))
   (let* ((uri (format "org-headline://%s#Task" file))
          (result (org-cli-edit-body uri "" "New content." nil)))
     (should (string-match "\"success\":true" result))
     (should-not (string-match "existing" (org-cli-read-file file)))
     (should (string-match "New content." (org-cli-read-file file))))))

(ert-deftest org-cli-test-edit-body-empty-with-properties ()
  "Test adding content to empty body with properties drawer."
  (org-cli-test--with-id-setup test-file
      org-cli-test--content-with-id-no-body
      `(,org-cli-test--timestamp-id)
    (org-cli-test--call-edit-body-and-check
     test-file
     (format "org-id://%s" org-cli-test--timestamp-id)
     ""
     "Content added after properties."
     org-cli-test--pattern-edit-body-empty-with-props)))

(ert-deftest org-cli-test-edit-body-nested-headlines ()
  "Test org-edit-body preserves nested headlines."
  (org-cli-test--with-temp-org-files
      ((test-file org-cli-test--content-nested-siblings))
    (org-cli-test--call-edit-body-and-check
     test-file
     (format "org-headline://%s#Parent%%20Task" test-file)
     "Some parent content."
     "Updated parent content"
     org-cli-test--pattern-edit-body-nested-headlines)))

(ert-deftest org-cli-test-edit-body-reject-headline-in-middle ()
  "Test org-edit-body rejects newBody with headline marker in middle."
  (org-cli-test--with-id-setup test-file
      org-cli-test--content-nested-siblings
      `(,org-cli-test--content-with-id-id)
    (org-cli-test--call-edit-body-expecting-error
     test-file
     org-cli-test--content-with-id-uri
     "Second child content."
     "replacement text
* This would become a headline"
     nil)))

(ert-deftest org-cli-test-edit-body-accept-lower-level-headline ()
  "Test org-edit-body accepts newBody with lower-level headline."
  (org-cli-test--with-id-setup test-file
      org-cli-test--content-nested-siblings
      `(,org-cli-test--content-with-id-id)
    (org-cli-test--call-edit-body-and-check
     test-file
     org-cli-test--content-with-id-uri
     "Second child content."
     "some text
*** Subheading content"
     org-cli-test--pattern-edit-body-accept-lower-level)))

(ert-deftest org-cli-test-edit-body-reject-higher-level-headline ()
  "Test org-edit-body rejects newBody with higher-level headline.
When editing a level 2 node, level 1 headlines should be rejected."
  (org-cli-test--with-temp-org-files
      ((test-file org-cli-test--content-nested-siblings))
    (org-cli-test--call-edit-body-expecting-error
     test-file
     (format "org-headline://%s#Parent%%20Task/Second%%20Child"
             test-file)
     "Second child content."
     "New text
* Top level heading"
     nil)))

(ert-deftest org-cli-test-edit-body-reject-headline-at-start ()
  "Test org-edit-body rejects newBody with headline at beginning."
  (org-cli-test--with-id-setup test-file
      org-cli-test--content-nested-siblings
      `(,org-cli-test--content-with-id-id)
    (org-cli-test--call-edit-body-expecting-error
     test-file
     org-cli-test--content-with-id-uri
     "Second child content."
     "* Heading at start"
     nil)))

(ert-deftest org-cli-test-edit-body-reject-unbalanced-begin-block ()
  "Test org-edit-body rejects newBody with unbalanced BEGIN block."
  (org-cli-test--with-id-setup test-file
      org-cli-test--content-nested-siblings
      `(,org-cli-test--content-with-id-id)
    (org-cli-test--call-edit-body-expecting-error
     test-file
     org-cli-test--content-with-id-uri
     "Second child content."
     "Some text
#+BEGIN_EXAMPLE
Code without END_EXAMPLE"
     nil)))

(ert-deftest org-cli-test-edit-body-reject-orphaned-end-block ()
  "Test org-edit-body rejects newBody with orphaned END block."
  (org-cli-test--with-id-setup test-file
      org-cli-test--content-nested-siblings
      `(,org-cli-test--content-with-id-id)
    (org-cli-test--call-edit-body-expecting-error
     test-file
     org-cli-test--content-with-id-uri
     "Second child content."
     "Some text
#+END_SRC
Without BEGIN_SRC"
     nil)))

(ert-deftest org-cli-test-edit-body-reject-mismatched-blocks ()
  "Test org-edit-body rejects newBody with mismatched blocks."
  (org-cli-test--with-id-setup
   test-file
   org-cli-test--content-nested-siblings
   `(,org-cli-test--content-with-id-id)
   (org-cli-test--call-edit-body-expecting-error
    test-file
    org-cli-test--content-with-id-uri
    "Second child content."
    "Text here
#+BEGIN_QUOTE
Some quote
#+END_EXAMPLE"
    nil)))

;; org-read-file tests

(ert-deftest org-cli-test-tool-read-file ()
  "Test org-read-file tool returns same content as file resource."
  (org-cli-test--with-temp-org-files
   ((test-file org-cli-test--content-nested-siblings))
   (let ((result-text (org-cli-test--call-read-file test-file)))
     (should (string= result-text org-cli-test--content-nested-siblings)))))

;; org-read-outline tests

(ert-deftest org-cli-test-tool-read-outline ()
  "Test org-read-outline tool returns valid JSON outline structure."
  (org-cli-test--with-temp-org-files
   ((test-file org-cli-test--content-nested-siblings))
   (let* ((result (org-cli-test--call-read-outline test-file))
          (headings (alist-get 'headings result)))
     (should (= (length headings) 1))
     (should (string= (alist-get 'title (aref headings 0)) "Parent Task")))))

;; org-read-headline test

(ert-deftest org-cli-test-tool-read-headline-empty-path ()
  "Test org-read-headline with empty headline_path signals validation error."
  (org-cli-test--call-read-headline-expecting-error
   org-cli-test--content-nested-siblings ""))

(ert-deftest org-cli-test-tool-read-headline-single-level ()
  "Test org-read-headline with single-level path."
  (org-cli-read-headline-and-check
   org-cli-test--content-slash-not-nested-before
   "Parent%2FChild"
   org-cli-test--pattern-tool-read-headline-single))

(ert-deftest org-cli-test-tool-read-headline-nested ()
  "Test org-read-headline with nested path."
  (org-cli-read-headline-and-check
   org-cli-test--content-nested-siblings
   "Parent%20Task/First%20Child%2050%25%20Complete"
   org-cli-test--pattern-tool-read-headline-nested))

(ert-deftest org-cli-test-tool-read-by-id ()
  "Test org-read-by-id tool returns headline content by ID."
  (org-cli-test--with-id-setup
   test-file org-cli-test--content-nested-siblings
   `(,org-cli-test--content-with-id-id)
   (org-cli-test--call-read-by-id-and-check
    org-cli-test--content-with-id-id
    org-cli-test--pattern-tool-read-by-id)))

;; Resource tests





(ert-deftest org-cli-test-file-resource-read ()
  "Test that reading a resource returns file content."
  (let ((test-content "* Test Heading\nThis is test content."))
    (org-cli-test--with-temp-org-files
     ((test-file test-content))
     (let ((uri (format "org://%s" test-file)))
       (org-cli-test--verify-resource-read
        uri
        test-content)))))

(ert-deftest org-cli-test-outline-resource-returns-structure ()
  "Test that outline tool returns document structure."
  (org-cli-test--with-temp-org-files
   ((test-file org-cli-test--content-headline-resource))
   (let* ((result (org-cli-test--call-read-outline test-file))
          (headings (alist-get 'headings result)))
     (should (= (length headings) 2))
     (let ((first (aref headings 0)))
       (should
        (equal (alist-get 'title first) "First Section"))
       (should (= (alist-get 'level first) 1))
       (let ((children (alist-get 'children first)))
         (should (= (length children) 2))
         (should
          (equal
           (alist-get 'title (aref children 0))
           "Subsection 1.1"))
         (should
          (= (length (alist-get 'children (aref children 0))) 0))
         (should
          (equal
           (alist-get 'title (aref children 1))
           "Subsection 1.2"))
         (should
          (= (length (alist-get 'children (aref children 1))) 0))))
     (let ((second (aref headings 1)))
       (should
        (equal (alist-get 'title second) "Second Section"))
       (should (= (alist-get 'level second) 1))
       ;; Deep subsection is empty (level 3 under level 1)
       (should
        (= (length (alist-get 'children second)) 0))))))

(ert-deftest org-cli-test-headline-resource-returns-top-level-content ()
  "Test that headline resource returns top-level headline content."
  (org-cli-test--with-temp-org-files
   ((test-file org-cli-test--content-headline-resource))
   (let ((uri
          (format "org-headline://%s#First%%20Section"
                  test-file)))
     (org-cli-test--verify-resource-read
      uri
      org-cli-test--expected-first-section))))

(ert-deftest org-cli-test-headline-resource-returns-nested-content ()
  "Test that headline resource returns nested headline content."
  (org-cli-test--with-temp-org-files
   ((test-file org-cli-test--content-headline-resource))
   (let ((uri
          (format (concat
                   "org-headline://%s#"
                   "First%%20Section/Subsection%%201.1")
                  test-file)))
     (org-cli-test--verify-resource-read
      uri
      org-cli-test--expected-subsection-1-1))))

(ert-deftest org-cli-test-headline-resource-not-found ()
  "Test headline resource error for non-existent headline."
  (let ((test-content "* Existing Section\nSome content."))
    (org-cli-test--with-temp-org-files
     ((test-file test-content))
     (let ((uri
            (format "org-headline://%s#Nonexistent" test-file)))
       (org-cli-test--read-resource-expecting-error
        uri "Cannot find headline: 'Nonexistent'")))))

(ert-deftest org-cli-test-headline-resource-file-with-hash ()
  "Test headline resource with # in filename."
  (org-cli-test--with-temp-org-files
   ((file org-cli-test--content-nested-siblings "org-cli-test-file#"))
   ;; Test accessing the file with # encoded as %23
   (let* ((encoded-path (replace-regexp-in-string "#" "%23" file))
          (uri
           (format "org-headline://%s#Parent%%20Task/First%%20Child%%2050%%25%%20Complete"
                   encoded-path)))
     (org-cli-test--verify-resource-read
      uri
      "** First Child 50% Complete\nFirst child content.\nIt spans multiple lines."))))

(ert-deftest org-cli-test-headline-resource-headline-with-hash ()
  "Test headline resource with # in headline title."
  (let ((test-content org-cli-test--content-nested-siblings))
    (org-cli-test--with-temp-org-files
     ((file test-content))
     ;; Test accessing headline with # encoded as %23
     (let ((uri
            (format "org-headline://%s#Parent%%20Task/Third%%20Child%%20%%233"
                    file)))
       (org-cli-test--verify-resource-read
        uri
        "** Third Child #3")))))

(ert-deftest
    org-cli-test-headline-resource-file-and-headline-with-hash
    ()
  "Test headline resource with # in both filename and headline."
  (org-cli-test--with-temp-org-files
   ((file org-cli-test--content-nested-siblings "org-cli-test-file#"))
   ;; Test with both file and headline containing #
   (let* ((encoded-path (replace-regexp-in-string "#" "%23" file))
          (uri
           (format "org-headline://%s#Parent%%20Task/Third%%20Child%%20%%233"
                   encoded-path)))
     (org-cli-test--verify-resource-read
      uri
      "** Third Child #3"))))

(ert-deftest org-cli-test-headline-resource-txt-extension ()
  "Test that headline resource works with .txt files, not just .org files."
  (org-cli-test--test-headline-resource-with-extension ".txt"))

(ert-deftest org-cli-test-headline-resource-no-extension ()
  "Test that headline resource works with files having no extension."
  (org-cli-test--test-headline-resource-with-extension nil))

(ert-deftest org-cli-test-headline-resource-path-traversal ()
  "Test that path traversal with ../ in org-headline URIs is rejected."
  (org-cli-test--with-temp-org-files
   ((test-file org-cli-test--content-nested-siblings))
   ;; Test with ../ in the filename part
   (let ((uri
          (format "org-headline://../%s#Parent%%20Task"
                  (file-name-nondirectory test-file))))
     (org-cli-test--read-resource-expecting-error
      uri
      (format "Path must be absolute: ../%s"
              (file-name-nondirectory test-file))))))

(ert-deftest org-cli-test-headline-resource-encoded-path-traversal ()
  "Test that URL-encoded path traversal in org-headline URIs is rejected."
  (org-cli-test--with-temp-org-files
   ((test-file org-cli-test--content-nested-siblings))
   ;; Test with URL-encoded ../ (%2E%2E%2F) in the filename part
   ;; The encoding is NOT decoded, so %2E%2E%2F remains literal
   (let ((uri
          (format "org-headline://%%2E%%2E%%2F%s#Parent%%20Task"
                  (file-name-nondirectory test-file))))
     (org-cli-test--read-resource-expecting-error
      uri
      (format "Path must be absolute: %%2E%%2E%%2F%s"
              (file-name-nondirectory test-file))))))

(ert-deftest org-cli-test-headline-resource-navigation ()
  "Test that headline navigation respects structure."
  (org-cli-test--with-temp-org-files
   ((test-file org-cli-test--content-wrong-levels))
   ;; Test accessing "Target Headline" under "First Parent"
   ;; Should get the level-2 headline, NOT the level-3 one
   (let ((uri
          (format
           "org-headline://%s#First%%20Parent/Target%%20Headline"
           test-file)))
     ;; This SHOULD throw an error because First Parent has no such child
     ;; But the bug causes it to return the wrong headline
     (org-cli-test--read-resource-expecting-error
      uri
      "Cannot find headline: 'First Parent/Target Headline'"))))

(ert-deftest org-cli-test-id-resource-returns-content ()
  "Test that ID resource returns content for valid ID."
  (org-cli-test--with-id-setup
   test-file org-cli-test--content-id-resource
   `(,org-cli-test--content-id-resource-id)
   (let ((uri (format "org-id://%s" org-cli-test--content-id-resource-id)))
     (org-cli-test--verify-resource-read
      uri
      org-cli-test--content-id-resource))))

(ert-deftest org-cli-test-id-resource-not-found ()
  "Test ID resource error for non-existent ID."
  (let ((test-content "* Section without ID\nNo ID here."))
    (org-cli-test--with-id-setup test-file test-content '()
                                 (let ((uri "org-id://nonexistent-id-12345"))
                                   (org-cli-test--read-resource-expecting-error
                                    uri "Cannot find ID: 'nonexistent-id-12345'")))))

(ert-deftest org-cli-test-id-resource-file-not-allowed ()
  "Test ID resource validates file is in allowed list."
  ;; Create two files - one allowed, one not
  (org-cli-test--with-temp-org-files
   ((allowed-file "* Allowed\n")
    (other-file org-cli-test--content-id-resource))
   (org-cli-test--with-id-tracking
    (list allowed-file)
    `((,org-cli-test--content-id-resource-id . ,other-file))
    (let ((uri (format "org-id://%s" org-cli-test--content-id-resource-id)))
      ;; Should get an error for file not allowed
      (org-cli-test--read-resource-expecting-error
       uri
       (format "'%s': the referenced file not in allowed list"
               org-cli-test--content-id-resource-id))))))


;;;; set-planning tests

(ert-deftest org-cli-test-set-planning-deadline ()
  "Test setting a DEADLINE on a headline."
  (org-cli-test--with-temp-org-files
   ((file "* TODO Task\nBody text\n"))
   (let* ((uri (format "org-headline://%s#Task" file))
          (result (org-cli-set-planning uri 'deadline "2025-04-28")))
     (should (string-match "\"success\":true" result))
     (should (string-match "\"planning_type\":\"deadline\"" result))
     (should (string-match "2025-04-28" result))
     (should (string-match "\"uri\":\"org-id://" result))
     ;; Verify file contents
     (should (string-match "DEADLINE: <2025-04-28" (org-cli-read-file file))))))

(ert-deftest org-cli-test-set-planning-scheduled ()
  "Test setting a SCHEDULED timestamp on a headline."
  (org-cli-test--with-temp-org-files
   ((file "* TODO Task\nBody text\n"))
   (let* ((uri (format "org-headline://%s#Task" file))
          (result (org-cli-set-planning uri 'scheduled "2025-04-25")))
     (should (string-match "\"success\":true" result))
     (should (string-match "\"planning_type\":\"scheduled\"" result))
     (should (string-match "2025-04-25" result))
     (should (string-match "SCHEDULED: <2025-04-25" (org-cli-read-file file))))))

(ert-deftest org-cli-test-set-planning-closed ()
  "Test setting a CLOSED timestamp on a headline."
  (org-cli-test--with-temp-org-files
   ((file "* DONE Task\nBody text\n"))
   (let* ((uri (format "org-headline://%s#Task" file))
          (result (org-cli-set-planning uri 'closed "2025-04-20")))
     (should (string-match "\"success\":true" result))
     (should (string-match "\"planning_type\":\"closed\"" result))
     (should (string-match "2025-04-20" result))
     (should (string-match "CLOSED: \\[" (org-cli-read-file file))))))

(ert-deftest org-cli-test-set-planning-remove ()
  "Test removing a planning item by passing empty timestamp."
  (org-cli-test--with-temp-org-files
   ((file "* TODO Task\nDEADLINE: <2025-04-28 Mon>\nBody text\n"))
   (let* ((uri (format "org-headline://%s#Task" file))
          (result (org-cli-set-planning uri 'deadline "")))
     (should (string-match "\"success\":true" result))
     (should (string-match "\"timestamp\":\"\"" result))
     ;; DEADLINE should be gone
     (should-not (string-match "DEADLINE:" (org-cli-read-file file))))))

(ert-deftest org-cli-test-set-planning-preserve-others ()
  "Test that setting one planning type preserves existing others."
  (org-cli-test--with-temp-org-files
   ((file "* TODO Task\nDEADLINE: <2025-04-28 Mon>\nBody text\n"))
   (let* ((uri (format "org-headline://%s#Task" file))
          (result (org-cli-set-planning uri 'scheduled "2025-04-25"))
          (contents (org-cli-read-file file)))
     (should (string-match "\"success\":true" result))
     ;; Both DEADLINE and SCHEDULED should be present
     (should (string-match "DEADLINE: <2025-04-28" contents))
     (should (string-match "SCHEDULED: <2025-04-25" contents)))))

(ert-deftest org-cli-test-set-planning-invalid-type ()
  "Test that invalid planning_type signals validation error."
  (org-cli-test--with-temp-org-files
   ((file "* TODO Task\n"))
   (let ((uri (format "org-headline://%s#Task" file)))
     (should-error (org-cli-set-planning uri 'invalid "2025-04-28")
                   :type 'org-cli-error))))

(ert-deftest org-cli-test-set-planning-invalid-timestamp ()
  "Test that invalid timestamp format signals validation error."
  (org-cli-test--with-temp-org-files
   ((file "* TODO Task\n"))
   (let ((uri (format "org-headline://%s#Task" file)))
     (should-error (org-cli-set-planning uri 'deadline "not-a-date")
                   :type 'org-cli-error))))

(ert-deftest org-cli-test-set-planning-by-id ()
  "Test setting planning item using org-id:// URI."
  (org-cli-test--with-temp-org-files
   ((file "* TODO Task\n:PROPERTIES:\n:ID: test-planning-id-42\n:END:\nBody\n"))
   (let ((uri "org-id://test-planning-id-42"))
     (org-cli-test--with-id-tracking
      (list file)
      `(("test-planning-id-42" . ,file))
      (let ((result (org-cli-set-planning uri 'deadline "2025-05-01")))
        (should (string-match "\"success\":true" result))
        (should (string-match "2025-05-01" result)))))))

(ert-deftest org-cli-test-set-planning-returns-all-planning ()
  "Test that response includes all planning types in current state."
  (org-cli-test--with-temp-org-files
   ((file "* TODO Task\nDEADLINE: <2025-04-28 Mon>\nBody text\n"))
   (let* ((uri (format "org-headline://%s#Task" file))
          (result (org-cli-set-planning uri 'scheduled "2025-04-25")))
     ;; Response should include both deadline and scheduled
     (should (string-match "\"deadline\":\"<2025-04-28" result))
     (should (string-match "\"scheduled\":\"<2025-04-25" result))
     (should (string-match "\"closed\":null" result)))))

;;;; list-todos tests

(ert-deftest org-cli-test-list-todos-all ()
  "Test list-todos returns all TODO items in a file."
  (org-cli-test--with-temp-org-files
   ((test-file org-cli-test--content-todo-keywords-before))
   (let* ((result-json (org-cli-list-todos test-file))
          (result (json-read-from-string result-json))
          (todos (alist-get 'todos result)))
     ;; Should find TODO and DONE items
     (should (vectorp todos))
     (should (>= (length todos) 2)))))

(ert-deftest org-cli-test-list-todos-empty-file ()
  "Test list-todos on file with no TODO items."
  (org-cli-test--with-temp-org-files
   ((test-file org-cli-test--content-empty))
   (let* ((result-json (org-cli-list-todos test-file))
          (result (json-read-from-string result-json))
          (todos (alist-get 'todos result)))
     (should (vectorp todos))
     (should (= (length todos) 0)))))

(ert-deftest org-cli-test-list-todos-item-fields ()
  "Test list-todos returns correct fields for each TODO item."
  (org-cli-test--with-temp-org-files
   ((test-file org-cli-test--content-simple-todo))
   (let* ((result-json (org-cli-list-todos test-file))
          (result (json-read-from-string result-json))
          (todos (alist-get 'todos result)))
     (should (= (length todos) 1))
     (let ((item (aref todos 0)))
       (should (equal (alist-get 'state item) "TODO"))
       (should (equal (alist-get 'title item) "Original Task"))
       (should (equal (alist-get 'level item) 1))
       (should (stringp (alist-get 'id item)))))))

(ert-deftest org-cli-test-list-todos-with-tags ()
  "Test list-todos includes tags for tagged TODO items."
  (org-cli-test--with-temp-org-files
   ((test-file org-cli-test--content-todo-with-tags))
   (let* ((result-json (org-cli-list-todos test-file))
          (result (json-read-from-string result-json))
          (todos (alist-get 'todos result)))
     (should (= (length todos) 1))
     (let ((item (aref todos 0)))
       (should (equal (alist-get 'state item) "TODO"))
       (should (equal (alist-get 'title item) "Task with Tags"))
       (let ((tags (alist-get 'tags item)))
         (should (vectorp tags))
         (should (member "work" (append tags nil)))
         (should (member "urgent" (append tags nil))))))))

(ert-deftest org-cli-test-list-todos-multiple-items ()
  "Test list-todos returns multiple TODO items from nested content."
  (org-cli-test--with-temp-org-files
   ((test-file org-cli-test--content-todo-keywords-before))
   (let* ((result-json (org-cli-list-todos test-file))
          (result (json-read-from-string result-json))
          (todos (alist-get 'todos result)))
     ;; Should find both TODO and DONE items
     (should (>= (length todos) 2))
     (let ((states (mapcar (lambda (item) (alist-get 'state item))
                            (append todos nil))))
       (should (member "TODO" states))
       (should (member "DONE" states))))))

(ert-deftest org-cli-test-list-todos-with-section-path ()
  "Test list-todos with headline_path limits to section."
  (org-cli-test--with-temp-org-files
   ((test-file org-cli-test--content-hierarchy-before))
   (let* ((result-json (org-cli-list-todos test-file "Second%20Section"))
          (result (json-read-from-string result-json))
          (todos (alist-get 'todos result)))
     ;; Should return successfully even if no TODOs in section
     (should (vectorp todos)))))

(ert-deftest org-cli-test-list-todos-nonexistent-section ()
  "Test list-todos with nonexistent headline_path signals error."
  (org-cli-test--with-temp-org-files
   ((test-file org-cli-test--content-simple-todo))
   (should-error (org-cli-list-todos test-file "Nonexistent%20Section")
                  :type 'org-cli-error)))

(ert-deftest org-cli-test-list-todos-markdown ()
  "Test list-todos with markdown format returns a table."
  (org-cli-test--with-temp-org-files
   ((test-file org-cli-test--content-simple-todo))
   (let ((result (org-cli-list-todos test-file nil "markdown")))
     (should (string-prefix-p "| State |" result))
     (should (string-match "Original Task" result))
     (should (string-match "TODO" result)))))

(ert-deftest org-cli-test-list-todos-markdown-empty ()
  "Test list-todos markdown format with no TODOs."
  (org-cli-test--with-temp-org-files
   ((test-file org-cli-test--content-empty))
   (let ((result (org-cli-list-todos test-file nil "markdown")))
     (should (equal result "No TODO items found.")))))

(ert-deftest org-cli-test-list-todos-kanban ()
  "Test list-todos kanban format returns a board table."
  (org-cli-test--with-temp-org-files
   ((test-file org-cli-test--content-simple-todo))
   (let ((result (org-cli-list-todos test-file nil "kanban")))
     (should (string-prefix-p "| " result))
     (should (string-match "^| " result))
     (should (string-match "TODO" result))
     (should (string-match "Original Task" result)))))

(ert-deftest org-cli-test-list-todos-kanban-multi-state ()
  "Test kanban format groups items into state columns."
  (org-cli-test--with-temp-org-files
   ((test-file (concat "* TODO First task\n"
                        "* DONE Second task\n")))
   (let ((result (org-cli-list-todos test-file nil "kanban")))
     (should (string-match "| TODO | DONE |" result))
     (should (string-match "First task" result))
     (should (string-match "Second task" result)))))

(ert-deftest org-cli-test-list-todos-kanban-empty ()
  "Test list-todos kanban format with no TODOs."
  (org-cli-test--with-temp-org-files
   ((test-file org-cli-test--content-empty))
   (let ((result (org-cli-list-todos test-file nil "kanban")))
     (should (equal result "No TODO items found.")))))

(provide 'org-cli-test)
;;; org-cli-test.el ends here
