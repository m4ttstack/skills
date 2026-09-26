---
name: mcp-tools
description: "Reference: every tool on the mattstack MCP server, generated from rt. Read when writing a skill or fill that would otherwise tell an agent to run rt, glab or a git write in Bash."
disable-model-invocation: true
---

# mattstack MCP tools

`reference.md` beside this file is generated from `rt mcp tools --json` and
lists every tool with its input schema. The rule for skill authors: if a
skill does something as part of its normal flow and it is an rt call, a
forge call or a git write, it is a tool call, named in the sentence that
would otherwise carry the command. `rt skills check` lints for the shell
forms the tools replace; `rt skills audit --pack <pack>` reads for the
plain-words cases a lint cannot see.

Kept on Bash on purpose: `rt gate answer <id> --answers <json> --by shepherd`,
`rt gate wait <id>`, `rt chat tail`, `rt events wait`, `git commit`, `git add`,
`git fetch`, `git merge-base`, `git rebase --continue` and `--skip`, and project tooling.
