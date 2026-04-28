/**
 * emacs-org-cli Extension for Pi Coding Agent
 *
 * Provides tools for managing Org mode files: checklists, TODOs,
 * outlines, headlines, and body editing. Backed by org-cli.el.
 *
 * Tools registered:
 * - org-read-file:       Read complete Org file contents
 * - org-read-outline:    Get hierarchical outline as JSON
 * - org-read-headline:   Read a specific headline and its subtree
 * - org-read-by-id:      Read a headline by its ID property
 * - org-get-todo-config: Get TODO keyword configuration
 * - org-get-tag-config:  Get tag configuration
 * - org-get-allowed-files: List allowed Org files
 * - org-update-todo:     Update TODO state of a headline
 * - org-add-todo:        Add a new TODO/item to an Org file
 * - org-rename-headline: Rename a headline (preserving state/tags)
 * - org-edit-body:       Edit body text of a headline
 * - org-set-planning:    Set/remove deadline, scheduled, or closed timestamps
 * - org-list-todos:      List TODO items in a file or section
 *
 * Commands registered:
 * - /org-cli-info:     Quick info about emacs-org-cli
 *                      List allowed Org files
 *                      Show TODO keyword configuration
 *                      Show tag configuration
 */

import { StringEnum } from "@mariozechner/pi-ai";
import { getAgentDir } from "@mariozechner/pi-coding-agent";
import type {
    ExtensionAPI,
    ExtensionContext,
} from "@mariozechner/pi-coding-agent";
import { Type } from "@sinclair/typebox";
import * as path from "node:path";

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

/**
 * Default path to the directory containing org-cli.el and org-cli.sh.
 *
 * Resolved relative to PI_CODING_AGENT_DIR or ~/.pi/agent.
 * The skill's scripts directory contains both org-cli.el and org-cli.sh:
 *   $PI_CODING_AGENT_DIR/skills/emacs-org-cli/scripts/
 *
 * Override via ORG_CLI_DIR environment variable if needed.
 * Override the Emacs binary via EMACS environment variable.
 * Load custom Emacs init via ORG_CLI_INIT_EL environment variable.
 */
const DEFAULT_ORG_CLI_DIR = path.join(
    getAgentDir(),
    "skills",
    "emacs-org-cli",
    "scripts",
);

/** Resolve the directory containing org-cli.sh and org-cli.el. */
function resolveOrgCliDir(): string {
    return process.env.ORG_CLI_DIR ?? DEFAULT_ORG_CLI_DIR;
}

/**
 * Run an org-cli command via the org-cli.sh wrapper script.
 *
 * Invokes: org-cli.sh COMMAND ARGS...
 *
 * Environment variables are passed through:
 * - ORG_CLI_DIR:     resolved automatically by this extension
 * - ORG_CLI_INIT_EL: optional Emacs init file for custom org config
 * - EMACS:           optional override for the emacs binary
 */
async function runOrgCli(
    pi: ExtensionAPI,
    command: string,
    args: string[] = [],
    ctx?: ExtensionContext,
): Promise<string> {
    const dir = resolveOrgCliDir();
    const scriptPath = path.join(dir, "org-cli.sh");

    const env: Record<string, string> = {
        ...(process.env as Record<string, string>),
        ORG_CLI_DIR: dir,
    };

    const { stdout, stderr, code } = await pi.exec(
        scriptPath,
        [command, ...args],
        { env },
    );

    if (code !== 0) {
        const detail = stderr?.trim() || `exit code ${code}`;
        throw new Error(`org-cli ${command} failed: ${detail}`);
    }

    return stdout.trim();
}

// ---------------------------------------------------------------------------
// Parameter schemas
// ---------------------------------------------------------------------------

const ReadFileParams = Type.Object({
    file: Type.String({ description: "Absolute path to an Org file" }),
});

const ReadOutlineParams = Type.Object({
    file: Type.String({ description: "Absolute path to an Org file" }),
});

const ReadHeadlineParams = Type.Object({
    file: Type.String({ description: "Absolute path to an Org file" }),
    headline_path: Type.String({
        description:
            "Slash-separated URL-encoded path to headline (e.g. 'Parent%20Task/Child')",
    }),
});

const ReadByIdParams = Type.Object({
    uuid: Type.String({ description: "UUID from the headline's ID property" }),
});

const UpdateTodoParams = Type.Object({
    uri: Type.String({
        description: "Headline URI (org-headline:// or org-id://)",
    }),
    current_state: Type.String({
        description: "Current TODO state ('' for no state)",
    }),
    new_state: Type.String({ description: "New TODO state keyword" }),
});

const AddTodoParams = Type.Object({
    title: Type.String({ description: "Headline text for the new item" }),
    state: Type.String({ description: "TODO keyword (e.g. TODO, DONE)" }),
    parent_uri: Type.String({
        description: "URI of parent (org-headline://path# or org-id://uuid)",
    }),
    tags: Type.Optional(
        Type.String({
            description: "Comma-separated tags (e.g. work,urgent)",
        }),
    ),
    body: Type.Optional(
        Type.String({ description: "Body text for the new item" }),
    ),
    after_uri: Type.Optional(
        Type.String({
            description: "org-id:// URI of sibling to insert after",
        }),
    ),
});

const RenameHeadlineParams = Type.Object({
    uri: Type.String({
        description: "Headline URI (org-headline:// or org-id://)",
    }),
    current_title: Type.String({
        description: "Current headline title (without TODO state or tags)",
    }),
    new_title: Type.String({ description: "New headline title" }),
});

const EditBodyParams = Type.Object({
    uri: Type.String({
        description: "Headline URI (org-headline:// or org-id://)",
    }),
    old_body: Type.String({ description: "Substring to find in the body" }),
    new_body: Type.String({ description: "Replacement text" }),
    replace_all: Type.Optional(
        Type.String({
            description:
                '"true" to replace all occurrences, "false" (default) for first only',
        }),
    ),
});

const SetPlanningParams = Type.Object({
    uri: Type.String({
        description: "Headline URI (org-headline:// or org-id://)",
    }),
    planning_type: StringEnum(["deadline", "scheduled", "closed"] as const, {
        description: "Type of planning item to set",
    }),
    timestamp: Type.Optional(
        Type.String({
            description:
                "Org timestamp (e.g. '2025-04-28' or '<2025-04-28 Mon>'). Omit or empty to remove.",
        }),
    ),
});

// ---------------------------------------------------------------------------
// Extension entry point
// ---------------------------------------------------------------------------

export default function emacsOrgCliExtension(pi: ExtensionAPI) {
    // ----- Read tools -----

    pi.registerTool({
        name: "org-read-file",
        label: "Org Read File",
        description:
            "Read the complete contents of an Org file. " +
            "Returns the raw Org text including all headlines, bodies, and properties.",
        promptSnippet: "org-read-file(file) — read an entire Org file",
        parameters: ReadFileParams,

        async execute(_id, params, _signal, _onUpdate, ctx) {
            const output = await runOrgCli(pi, "read-file", [params.file], ctx);
            return {
                content: [{ type: "text", text: output }],
            };
        },
    });

    pi.registerTool({
        name: "org-read-outline",
        label: "Org Read Outline",
        description:
            "Read the hierarchical outline of an Org file. " +
            "Returns JSON with title, level, and children for each heading. " +
            "Use this to understand file structure before reading specific headlines.",
        promptSnippet:
            "org-read-outline(file) — get structured outline of an Org file",
        parameters: ReadOutlineParams,

        async execute(_id, params, _signal, _onUpdate, ctx) {
            const output = await runOrgCli(
                pi,
                "read-outline",
                [params.file],
                ctx,
            );
            return {
                content: [{ type: "text", text: output }],
            };
        },
    });

    pi.registerTool({
        name: "org-read-headline",
        label: "Org Read Headline",
        description:
            "Read a specific Org headline and its entire subtree (body + nested headlines). " +
            "headline_path is a slash-separated, URL-encoded path (spaces as %20, # as %23). " +
            "Example: 'Parent%20Task/First%20Child' navigates to the 'First Child' " +
            "headline under the 'Parent Task' top-level heading.",
        promptSnippet:
            "org-read-headline(file, headline_path) — read a specific headline subtree",
        parameters: ReadHeadlineParams,

        async execute(_id, params, _signal, _onUpdate, ctx) {
            const output = await runOrgCli(
                pi,
                "read-headline",
                [params.file, params.headline_path],
                ctx,
            );
            return {
                content: [{ type: "text", text: output }],
            };
        },
    });

    pi.registerTool({
        name: "org-read-by-id",
        label: "Org Read by ID",
        description:
            "Read an Org headline by its ID property. " +
            "Returns the headline text including todo state, tags, properties, body, " +
            "and all nested subheadings.",
        promptSnippet:
            "org-read-by-id(uuid) — read a headline by its Org ID property",
        parameters: ReadByIdParams,

        async execute(_id, params, _signal, _onUpdate, ctx) {
            const output = await runOrgCli(
                pi,
                "read-by-id",
                [params.uuid],
                ctx,
            );
            return {
                content: [{ type: "text", text: output }],
            };
        },
    });

    // ----- Config tools -----

    pi.registerTool({
        name: "org-get-todo-config",
        label: "Org TODO Config",
        description:
            "Get the TODO keyword configuration from org-todo-keywords. " +
            "Returns JSON with sequences (type + keywords) and semantics " +
            "(state, isFinal, sequenceType per keyword). " +
            "Use before updating TODO states to know valid transitions.",
        promptSnippet:
            "org-get-todo-config() — list valid TODO keywords and transitions",
        parameters: Type.Object({}),

        async execute(_id, _params, _signal, _onUpdate, ctx) {
            const output = await runOrgCli(pi, "get-todo-config", [], ctx);
            return {
                content: [{ type: "text", text: output }],
            };
        },
    });

    pi.registerTool({
        name: "org-get-tag-config",
        label: "Org Tag Config",
        description:
            "Get the tag configuration from org-tag-alist and org-tag-persistent-alist. " +
            "Returns JSON with tag definitions, groups, and inheritance settings. " +
            "Use before adding TODOs to know valid tags.",
        promptSnippet: "org-get-tag-config() — list valid Org tags",
        parameters: Type.Object({}),

        async execute(_id, _params, _signal, _onUpdate, ctx) {
            const output = await runOrgCli(pi, "get-tag-config", [], ctx);
            return {
                content: [{ type: "text", text: output }],
            };
        },
    });

    pi.registerTool({
        name: "org-get-allowed-files",
        label: "Org Allowed Files",
        description:
            "List the Org files that org-cli is configured to access. " +
            "If org-cli-allowed-files is nil, all files are allowed.",
        promptSnippet: "org-get-allowed-files() — list accessible Org files",
        parameters: Type.Object({}),

        async execute(_id, _params, _signal, _onUpdate, ctx) {
            const output = await runOrgCli(pi, "get-allowed-files", [], ctx);
            return {
                content: [{ type: "text", text: output }],
            };
        },
    });

    // ----- Mutation tools -----

    pi.registerTool({
        name: "org-update-todo",
        label: "Org Update TODO",
        description:
            "Update the TODO state of an Org headline. " +
            "current_state must match the headline's actual TODO keyword " +
            '(use "" for items with no TODO state). ' +
            "new_state must be a valid keyword from org-todo-keywords. " +
            "Returns JSON with previous_state, new_state, and the headline's URI. " +
            "Creates an Org ID property if one doesn't exist.",
        promptSnippet:
            "org-update-todo(uri, current_state, new_state) — change a headline's TODO state",
        parameters: UpdateTodoParams,

        async execute(_id, params, _signal, _onUpdate, ctx) {
            const args = [params.uri, params.current_state, params.new_state];
            const output = await runOrgCli(pi, "update-todo-state", args, ctx);
            return {
                content: [{ type: "text", text: output }],
            };
        },
    });

    pi.registerTool({
        name: "org-add-todo",
        label: "Org Add TODO",
        description:
            "Add a new TODO item (headline) to an Org file. " +
            "parent_uri specifies where to add it: use 'org-headline:///path/to/file.org#' " +
            "for top-level or 'org-headline:///path#Parent%20Headline' for a child. " +
            "tags is an optional comma-separated list (e.g. 'work,urgent'). " +
            "after_uri is an optional org-id:// URI of a sibling to insert after. " +
            "Returns JSON with the new headline's URI, file, and title.",
        promptSnippet:
            "org-add-todo(title, state, parent_uri, [tags], [body], [after_uri]) — add a new Org headline",
        parameters: AddTodoParams,

        async execute(_id, params, _signal, _onUpdate, ctx) {
            const args = [params.title, params.state, params.parent_uri];
            if (params.tags) args.push(params.tags);
            if (params.body) args.push(params.body);
            if (params.after_uri) args.push(params.after_uri);
            const output = await runOrgCli(pi, "add-todo", args, ctx);
            return {
                content: [{ type: "text", text: output }],
            };
        },
    });

    pi.registerTool({
        name: "org-rename-headline",
        label: "Org Rename Headline",
        description:
            "Rename an Org headline while preserving its TODO state, tags, and properties. " +
            "current_title must match the actual title (without TODO keyword or tags). " +
            "Creates an Org ID property if one doesn't exist. " +
            "Returns JSON with previous_title, new_title, and the headline's URI.",
        promptSnippet:
            "org-rename-headline(uri, current_title, new_title) — rename a headline",
        parameters: RenameHeadlineParams,

        async execute(_id, params, _signal, _onUpdate, ctx) {
            const output = await runOrgCli(
                pi,
                "rename-headline",
                [params.uri, params.current_title, params.new_title],
                ctx,
            );
            return {
                content: [{ type: "text", text: output }],
            };
        },
    });

    pi.registerTool({
        name: "org-edit-body",
        label: "Org Edit Body",
        description:
            "Edit body content of an Org headline by partial string replacement. " +
            "old_body is the substring to find; new_body is the replacement. " +
            "Use empty string for old_body to set or replace the entire body " +
            "(works for both empty and non-empty bodies). " +
            "Creates an Org ID property if one doesn't exist. " +
            "Returns JSON with success status and the headline's URI.",
        promptSnippet:
            "org-edit-body(uri, old_body, new_body, [replace_all]) — edit body text of a headline",
        parameters: EditBodyParams,

        async execute(_id, params, _signal, _onUpdate, ctx) {
            const args = [params.uri, params.old_body, params.new_body];
            if (params.replace_all) args.push(params.replace_all);
            const output = await runOrgCli(pi, "edit-body", args, ctx);
            return {
                content: [{ type: "text", text: output }],
            };
        },
    });

    pi.registerTool({
        name: "org-set-planning",
        label: "Org Set Planning",
        description:
            "Set or remove a planning item (DEADLINE, SCHEDULED, CLOSED) on an Org headline. " +
            "planning_type must be 'deadline', 'scheduled', or 'closed'. " +
            "timestamp is an Org date like '2025-04-28' or '<2025-04-28 Mon>'. " +
            "Omit timestamp or pass empty string to remove the planning item. " +
            "Returns JSON with success, planning_type, timestamp, and current planning state.",
        promptSnippet:
            "org-set-planning(uri, planning_type, [timestamp]) — set deadline/scheduled/closed on a headline",
        parameters: SetPlanningParams,

        async execute(_id, params, _signal, _onUpdate, ctx) {
            const args = [params.uri, params.planning_type];
            if (params.timestamp) args.push(params.timestamp);
            const output = await runOrgCli(pi, "set-planning", args, ctx);
            return {
                content: [{ type: "text", text: output }],
            };
        },
    });

    pi.registerTool({
        name: "org-list-todos",
        label: "Org List TODOs",
        description:
            "List all TODO items in an Org file or under a specific headline. " +
            "Returns JSON with a todos array containing state, title, level, tags, " +
            "priority, deadline, scheduled, and id for each item. " +
            "Use headline_path to list TODOs under a specific section. " +
            "If headline_path is omitted, lists all TODOs in the file. " +
            'Use format="markdown" for a readable table, format="kanban" for a board view, ' +
            'or format="json" (default) for structured data.',
        promptSnippet:
            "org-list-todos(file, [headline_path], [format]) — list TODO items",
        parameters: Type.Object({
            file: Type.String({ description: "Absolute path to an Org file" }),
            headline_path: Type.Optional(
                Type.String({
                    description:
                        "Slash-separated URL-encoded path to a headline section (e.g. 'Project%20Tasks'). " +
                        "If omitted, lists all TODOs in the file.",
                }),
            ),
            format: Type.Optional(
                Type.String({
                    description:
                        'Output format: "json" (default) for structured data, "markdown" for a readable table, "kanban" for a board view with states as columns.',
                }),
            ),
        }),

        async execute(_id, params, _signal, _onUpdate, ctx) {
            const args = [params.file];
            if (params.headline_path) args.push(params.headline_path);
            else args.push("");
            if (params.format) args.push(params.format);
            const output = await runOrgCli(pi, "list-todos", args, ctx);
            return {
                content: [{ type: "text", text: output }],
            };
        },
    });

    // ----- Help tool -----

    pi.registerTool({
        name: "org-usage",
        label: "Org Usage",
        description:
            "Show usage information for org-cli, including available commands, " +
            "URI formats, and argument conventions.",
        promptSnippet: "org-usage() — show org-cli help and available commands",
        parameters: Type.Object({}),

        async execute(_id, _params, _signal, _onUpdate, ctx) {
            const output = await runOrgCli(pi, "help", [], ctx);
            return {
                content: [{ type: "text", text: output }],
            };
        },
    });

    // ----- Slash commands -----

    pi.registerCommand("org-cli-info", {
        description:
            "Show org-cli configuration: settings, allowed files, TODO keywords, and tags",
        async handler(_args, ctx) {
            try {
                const [files, todos, tags] = await Promise.all([
                    runOrgCli(pi, "get-allowed-files", [], ctx),
                    runOrgCli(pi, "get-todo-config", [], ctx),
                    runOrgCli(pi, "get-tag-config", [], ctx),
                ]);

                const t = ctx.ui.theme;
                const header = (text: string) =>
                    t.bold(t.fg("mdHeading", text));
                const label = (text: string) => t.fg("accent", text);
                const dim = (text: string) => t.fg("dim", text);

                const resolvedDir = resolveOrgCliDir();
                const overrideNote = process.env.ORG_CLI_DIR
                    ? ` ${dim("(overridden via ORG_CLI_DIR)")}`
                    : "";
                const initEl = process.env.ORG_CLI_INIT_EL ?? "(none)";

                ctx.ui.notify(
                    `${header("[org-cli Info]")}\n\n` +
                        `${label("[emacs-org-cli Extension]")}\n14 tools registered ` +
                        `${dim("(org-read-file, org-read-outline,")} ` +
                        `${dim("org-read-headline, org-read-by-id, org-get-todo-config, org-get-tag-config, ")} ` +
                        `${dim("org-get-allowed-files, org-update-todo, org-add-todo, org-rename-headline, ")} ` +
                        `${dim("org-edit-body, org-set-planning, org-usage, org-list-todos)")}\n\n` +
                        `${label("[Settings]")}\n` +
                        `${dim("org-cli dir:")} ${resolvedDir}${overrideNote}\n` +
                        `${dim("init.el:")} ${initEl}\n` +
                        `${dim("PI_CODING_AGENT_DIR:")} ${process.env.PI_CODING_AGENT_DIR ?? "(not set using: " + getAgentDir()}\n\n` +
                        `${label("[Allowed files]")}\n${files}\n\n` +
                        `${label("[TODO config]")}\n${todos}\n\n` +
                        `${label("[Tag config]")}\n${tags}`,
                    "info",
                );
            } catch (err: any) {
                ctx.ui.notify(`Error: ${err.message}`, "error");
            }
        },
    });
}
