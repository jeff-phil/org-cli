---
name: emacs-org-cli
description: Manage Org mode files — checklists, TODOs, outlines, headlines, and body editing via org-cli.el
---

# emacs-org-cli Skill

Manage Org mode files using the org-cli.el extension tools.

## Installation

The `org-cli.el` script and `org-cli.sh` wrapper are installed at:

```
$PI_CODING_AGENT_DIR/skills/emacs-org-cli/scripts/
```

The extension resolves this path automatically. If you need to use a different
copy (e.g. during development), set these environment variables:

| Variable | Default | Description |
|---|---|---|
| `ORG_CLI_DIR` | `$PI_CODING_AGENT_DIR/skills/emacs-org-cli/scripts` | Directory containing `org-cli.sh` and `org-cli.el` |
| `ORG_CLI_INIT_EL` | *(none)* | Path to Emacs init file to load before org-cli.el. Set this to load custom `org-todo-keywords`, `org-tag-alist`, etc. |
| `EMACS` | `emacs` | Path to the emacs binary |

Run `/org-cli-info` in the Pi agent to verify the resolved paths and settings.

## Available Tools

### Reading
- `org-read-file(file)` — Read complete Org file contents
- `org-read-outline(file)` — Get hierarchical outline as JSON
- `org-read-headline(file, headline_path)` — Read a specific headline and its subtree
- `org-read-by-id(uuid)` — Read a headline by its Org ID property
- `org-list-todos(file, [headline_path], [format])` — List TODO items. Use `format="kanban"` for a board view with states as columns, `format="markdown"` for a table, or `format="json"` (default) for structured data

### Configuration
- `org-get-todo-config()` — List valid TODO keywords and their transitions
- `org-get-tag-config()` — List valid Org tags and inheritance settings
- `org-get-allowed-files()` — List accessible Org files

### Help
- `org-usage()` — Show CLI usage information and available commands

### Mutation
- `org-update-todo(uri, current_state, new_state)` — Change a headline's TODO state
- `org-add-todo(title, state, parent_uri, [tags], [body], [after_uri])` — Add a new Org headline
- `org-rename-headline(uri, current_title, new_title)` — Rename a headline
- `org-edit-body(uri, old_body, new_body, [replace_all])` — Edit body text. Use empty `old_body` to set/replace the entire body
- `org-set-planning(uri, planning_type, [timestamp])` — Set/remove DEADLINE, SCHEDULED, or CLOSED

## Workflow

1. Use `org-get-allowed-files` to discover which Org files are available
2. Use `org-read-outline` to understand a file's structure
3. Use `org-read-headline` or `org-read-by-id` to read specific sections
4. Use mutation tools to update TODO states, add items, rename headlines, or edit body text

## URI Formats

Headlines are identified by URIs:
- `org-headline:///absolute/path/to/file.org#Headline%20Path` — by headline path
- `org-id://uuid` — by the headline's ID property (preferred for mutations)

When a mutation tool is used, an Org ID is automatically created if the headline doesn't have one. The returned URI in the response uses `org-id://` format for stable references.

## Headline Path Encoding

In `org-read-headline`, the `headline_path` parameter uses URL-encoding:
- Spaces → `%20`
- `#` → `%23`
- `/` within a title → `%2F`
- The path separator `/` navigates hierarchy levels

Example: `Parent%20Task/First%20Child%2050%25%20Complete`

## Common Patterns

### Working with Deadlines and Scheduling
```
1. org-set-planning(uri, "deadline", "2025-04-28") to set a deadline
2. org-set-planning(uri, "scheduled", "2025-04-25") to set a scheduled date
3. org-set-planning(uri, "deadline", "") to remove a deadline
4. org-set-planning(uri, "closed", "2025-04-20") to close a task with a timestamp
```

### Working with Checklists
```
1. org-read-outline(file) to see structure
2. org-list-todos(file, null, "kanban") to see all TODO items in a kanban board
3. org-list-todos(file, "Project%20Tasks", "markdown") to list TODOs under a specific section as a table
4. org-update-todo(uri, "TODO", "DONE") to check off items
5. org-add-todo("New item", "TODO", parent_uri) to add items
```

### Adding a New Task
```
1. org-get-todo-config() to see valid states
2. org-get-tag-config() to see valid tags
3. org-add-todo("Task name", "TODO", "org-headline:///path/to/file.org#", "work")
```

## Using org-cli.sh Standalone

The `org-cli.sh` script can be used directly from any shell or coding agent:

```bash
# Available at:
$PI_CODING_AGENT_DIR/skills/emacs-org-cli/scripts/org-cli.sh

# Examples:
org-cli.sh list-todos notes.org "" kanban
org-cli.sh read-file notes.org
org-cli.sh read-headline notes.org "Shopping%20List"
org-cli.sh --help
```

FILE arguments accept relative paths (resolved to absolute automatically).
