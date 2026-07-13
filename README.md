# Evil Martians Agent Skills

Agent Skills we build and use at Evil Martians, packaged so you can install them into your own AI coding agent.


<a href="https://evilmartians.com/?utm_source=agent-skills">
<img src="https://evilmartians.com/badges/sponsored-by-evil-martians.svg" alt="Sponsored by Evil Martians" width="100%" height="54"></a>


A [skill](https://agentskills.io/specification) is a folder with a `SKILL.md` in it: a name, a description that tells the agent when to reach for it, and the instructions to follow once it does. The format is shared across agents, so these work the same in Claude Code, Codex, Cursor, Gemini CLI, and GitHub Copilot.

Browse them at **<https://evilmartians.com/agent-skills>**.

## Skills

| Skill | What it does |
| --- | --- |
| [llms-visibility](skills/llms-visibility/SKILL.md) | Makes a site visible and readable to LLMs and AI agents. Covers Markdown routes, `Accept` content negotiation, `llms.txt`, and crawler signals in `robots.txt`. Pushes back on popular patterns that don't work. Companion to [How to make your website visible to LLMs](https://evilmartians.com/chronicles/how-to-make-your-website-visible-to-llms). |

## Install

Skills install one at a time. Swap `llms-visibility` for whichever one you want.

```sh
npx skills add evilmartians/agent-skills --skill llms-visibility -a claude-code -g
```

Pass your agent to `-a`: `claude-code`, `codex`, `cursor`, `gemini-cli`, or `github-copilot`. Drop `-g` to install into the current project instead of your home directory.

Claude Code can install this repo as a plugin instead:

```sh
claude plugin marketplace add evilmartians/agent-skills
claude plugin install llms-visibility@evilmartians
```

Codex can too:

```sh
codex plugin marketplace add evilmartians/agent-skills
codex plugin install llms-visibility@evilmartians
```

Or copy the skill folder into your agent's skills directory yourself: `~/.claude/skills` for Claude Code, `~/.codex/skills` for Codex, or `.agents/skills` to install it into a single project. Copy the whole folder, not just the `SKILL.md`, since a skill can ship scripts, references, and other assets alongside it.

## Adding a skill

We curate this repo ourselves and don't take outside contributions. The skills are MIT licensed, so fork one and make it your own if you want to.

Maintainers: add `skills/<slug>/SKILL.md` with `name` (the same as the directory) and `description` in the front matter, then add a matching entry to the [marketplace manifest](.claude-plugin/marketplace.json) and a row to the Skills table above. Whatever else the skill needs at runtime goes in that same folder and ships with it. CI checks the front matter and the manifest, but the table is on you.

## License

[MIT](LICENSE) © Evil Martians
