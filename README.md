# Evil Martians Agent Skills

Agent Skills we build and use at Evil Martians, packaged so you can install them into your own AI coding agent.

A [skill](https://agentskills.io/specification) is a folder with a `SKILL.md` in it: a name, a description that tells the agent when to reach for it, and the instructions to follow once it does. The format is shared across agents, so these work the same in Claude Code, Codex, Cursor, Gemini CLI, and GitHub Copilot.

Browse them at **<https://evilmartians.com/agent-skills>**.

<img src="https://cdn.evilmartians.com/badges/logo-no-label.svg" alt="Evil Martians logo" width="22" height="16" /> <b>Agent Skills</b> are built by <b><a href="https://evilmartians.com">Evil Martians</a></b>, an American design and engineering consultancy for <b>developer tools, AI, and cybersecurity startups</b>.

## Skills

| Skill | What it does |
| --- | --- |
| [good-readme](skills/good-readme/SKILL.md) | Writes or improves a README.md for an open source project, based on Evil Martians' real experience of successfully promoting PostCSS, Nano ID, and other popular projects. Companion to [How to make your open source popular](https://evilmartians.com/chronicles/how-to-make-your-open-source-popular). |
| [llms-visibility](skills/llms-visibility/SKILL.md) | Makes a site visible and readable to LLMs and AI agents. Covers Markdown routes, `Accept` content negotiation, `llms.txt`, and crawler signals in `robots.txt`. Pushes back on popular patterns that don't work. Companion to [How to make your website visible to LLMs](https://evilmartians.com/chronicles/how-to-make-your-website-visible-to-llms). |
| [secure-npm-package](skills/secure-npm-package/SKILL.md) | Sets up a secure npm release process — Trusted Publishing with staged publishes from GitHub Actions, hardened workflows, dependency cooldowns — and walks the user through the manual npmjs.com and GitHub settings with links resolved for their repo. Companion to [The secure way to release an npm package in 2026](https://evilmartians.com/chronicles/the-secure-way-to-release-an-npm-package). |
| [skills-visibility](skills/skills-visibility/SKILL.md) | Publishes a catalog of agent skills and makes it discoverable and installable by AI coding agents — a `.well-known` discovery index, self-hosted archives with integrity digests, and several install commands. Pushes back on pointing an index at raw GitHub URLs. Companion to [Ship agent skills like packages: discovery index, digests, and install sources](https://evilmartians.com/chronicles/publishing-agent-skills-discovery-index). |
| [tailwind-best-practices](skills/tailwind-best-practices/SKILL.md) | Writes and audits Tailwind CSS with the five practices that keep a fast-to-write codebase maintainable: design tokens over magic values, short and consistently ordered class lists, semantically grouped tokens, and fixed variants for design-system components instead of arbitrary className props. Companion to [5 best practices for preventing chaos in Tailwind CSS](https://evilmartians.com/chronicles/5-best-practices-for-preventing-chaos-in-tailwind-css). |

## Install

Skills install one at a time. Swap `llms-visibility` for whichever one you want.

```sh
npx skills add evilmartians/agent-skills --skill llms-visibility -a claude-code -g
```

Pass your agent to `-a`: `claude-code`, `codex`, `cursor`, `gemini-cli`, or `github-copilot`. Drop `-g` to install into the current project instead of your home directory.

Claude Code can install a skill from this repo's plugin marketplace instead:

```sh
claude plugin marketplace add evilmartians/agent-skills
claude plugin install llms-visibility@evilmartians
```

Alternatively, GitHub CLI's `gh skill` can install a skill and prompts you to pick which agent to install it into:

```sh
gh skill install evilmartians/agent-skills llms-visibility
```

Or copy the skill folder into a skills directory yourself: `.claude/skills` for Claude Code, `.codex/skills` for Codex, or the agent-agnostic `.agents/skills`, which any agent reads. Prefix the path with `~/` to install it globally, or use it at a project root to keep it local. Copy the whole folder, not just the `SKILL.md`, since a skill can ship scripts, references, and other assets alongside it.

## Adding a skill

We curate this repo ourselves and don't take outside contributions. The skills are MIT licensed, so fork one and make it your own if you want to.

Maintainers: add `skills/<slug>/SKILL.md` with `name` (the same as the directory) and `description` in the front matter, then add a matching entry to the [marketplace manifest](.claude-plugin/marketplace.json) and a row to the Skills table above. Whatever else the skill needs at runtime goes in that same folder and ships with it. CI checks the front matter and the manifest, but the table is on you.

## License

[MIT](LICENSE) © Evil Martians
