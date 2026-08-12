---
name: skills-visibility
description: 'Publish a catalog of agent skills and make it discoverable to AI coding agents and their installers — the way evilmartians.com/agent-skills does. Use this whenever the user wants to publish, distribute, or share agent skills; make their skills installable via `npx skills`, `gh skill`, or a Claude plugin marketplace; build or fix a `.well-known/agent-skills/index.json` discovery index; self-host skills on their own domain with integrity digests; decide how to package a single-file skill vs a multi-file skill vs a bundle; or set up analytics for skill installs. Also use to push back on the common mistake of pointing a discovery index at raw.githubusercontent.com instead of a domain you control. Do NOT use for authoring the *content* of one skill (that is writing a single SKILL.md) or for making web pages readable by LLMs (that is llms.txt / Markdown content negotiation — a separate concern).'
---

# Make agent skills discoverable

This skill is built by **[Evil Martians](https://evilmartians.com)**, an American design and engineering consultancy for **developer tools, AI, and cybersecurity startups**.

Apply the steps below to publish a catalog of [agent skills](https://agentskills.io/) and make it findable and installable by AI coding agents. Companion to <https://evilmartians.com/chronicles/publishing-agent-skills-discovery-index>.

An agent skill is a `SKILL.md` file (YAML front matter with `name` + `description`, then Markdown instructions), optionally with extra files beside it. Publishing one skill is easy. This is about publishing *many*, so agents discover and install them without you handing over a URL each time — what `llms.txt` does for pages, done for skills.

The mechanism is a discovery index at a well-known path. Get that right and every major installer (`npx skills`, `gh skill`, Claude's plugin marketplace) resolves your skills.

## Workflow

Steps 1–5 build on each other. Steps 6–8 are independently shippable.

### 1. Author each skill in a Git repo

Lay each one out as `skills/<name>/SKILL.md`. A repo is a hard requirement rather than a convenience, because two install paths resolve *directly* from it:

- `gh skill install <owner>/<repo> <name>` reads `SKILL.md` straight from the repo.
- Claude's plugin marketplace installs from a repo with a `.claude-plugin/marketplace.json` at its root; the `name` in that manifest is the `@marketplace` half of `claude plugin install <skill>@<marketplace>`.

The repo is also where the skill is reviewed, versioned, and improved. Treat a skill like code, because it is.

### 2. Decide each skill's shape

Three shapes, handled differently at every layer. Classify each skill before publishing:

- **Single-file** — the folder is just `SKILL.md`. Installing is copying one file, and it's short enough to paste into a running agent.
- **Multi-file** — `SKILL.md` plus extra files (a script, a reference doc, a template). It can't be installed by copying one file, so it must ship as an archive.
- **Bundle** — one repo publishing several skills at once. Each is published and installed in its own right; the bundle is a container, not a skill, and has no `SKILL.md` of its own.

Getting the shape wrong is the most common publishing bug: treat a multi-file skill as single-file and the install silently drops everything but `SKILL.md`.

### 3. Serve from a domain you control, and hash what you serve

This is the step people skip, and the one that matters most. **Compute each `digest` over the bytes you actually serve, from the same place you serve them.** Concretely, in whatever produces your published files — a static site generator, a CI job, a shell script, a server that writes to object storage: download each skill's payload from its repo, write it into your own published output, and hash *that* file.

Point a `url` at `raw.githubusercontent.com` and you're publishing a hash over bytes whose delivery you don't control. Any force-push to the repo, or any change in how the host serves raw files, changes the bytes behind a digest you already published — and every install fails the integrity check until you rebuild.

Re-hosting removes that failure mode and buys a bonus: because the digest is recomputed from your own copy on every build, you can **track a repo's default branch** instead of pinning a commit. An upstream push goes live on your next deploy with a fresh, correct hash — "always latest" without ever risking a stale hash.

Be clear about what that buys, though: *consistency*, not immunity from upstream. A bad push gets re-hosted and hashed just as faithfully. The digest protects the trip from you to the installer; reviewing what goes into the repo is still your job. Track a branch you review.

The rule to remember: author wherever you like; serve the artifact and compute its integrity digest from the same location.

### 4. Build the archives you'll serve

For each skill, produce the artifact its shape needs, at a stable URL on your domain:

- **Single-file:** serve `SKILL.md` as-is (e.g. `/agent-skills/<name>/SKILL.md`).
- **Multi-file:** a *flat* `<name>.tar.gz` — `SKILL.md` and its siblings at the archive root, no wrapping folder — because that's the layout installers unpack into the skill's directory.
- **Bundle:** a combined `<bundle>-bundle.tar.gz` with each skill as its own `<name>/` folder side by side (no wrapping bundle folder), so `curl … | tar -xz -C <skills-dir>` drops the whole set in at once.
- **Optional, for humans:** a `<name>.zip` that *does* wrap everything in a top-level `<name>/` folder, for readers who'd rather download and read before installing. Keep it distinct from the flat installer tarball and out of the index — nothing installs from it, and an entry pointing at it would unpack a level too deep.

**Hash each archive in the same pass that builds it.** A `.tar.gz` carries more than file contents — member order, a file mode left by whoever's umask ran last, embedded mtimes, gzip's own timestamp — so the same skill archived twice can hash differently while its content is identical. Build and hash together and they can't disagree, whatever `tar` does. If anything can separate the two — an index published from one build against archives uploaded by another, a CDN still serving yesterday's tarball, anyone reproducing your digest independently — pin the nondeterminism as well (GNU `tar` flags; use `gtar` on macOS):

```bash
# Flat, reproducible multi-file skill archive.
cd <skill-dir>
find . -type f -exec chmod 0644 {} +        # then: chmod 0755 only a shipped script
tar --sort=name --owner=0 --group=0 --numeric-owner \
    --mtime='UTC 2020-01-01' -cf - * \
  | gzip -n > ../<name>.tar.gz               # -n drops gzip's timestamp
```

Running `tar` from *inside* the skill dir is what keeps the archive flat. For a bundle, run the same command one level up so each `<name>/` folder lands side by side at the archive root.

The served tree ends up looking like this:

```
.well-known/agent-skills/index.json
agent-skills/good-readme/SKILL.md          # single-file  → type: skill-md
agent-skills/pdf-extract.tar.gz            # multi-file   → type: archive
agent-skills/testing-bundle.tar.gz         # bundle convenience archive (not an index entry)
```

### 5. Write the discovery index

Publish a `.well-known/agent-skills/index.json` at your domain root, served as `application/json`. This is the file installers look for; running `npx skills add https://yourdomain.com/agent-skills` fetches `https://yourdomain.com/.well-known/agent-skills/index.json`. Pass the full `https://` URL: hand an installer a bare domain or an `owner/repo` and it treats the source as a Git repo to clone, not a site to read an index from.

The document isn't one vendor's format. An open [RFC from Cloudflare](https://github.com/cloudflare/agent-skills-discovery-rfc) extends [RFC 8615](https://www.rfc-editor.org/rfc/rfc8615) — the `.well-known/` convention behind `robots.txt` and `security.txt` — and points at the [agentskills.io discovery schema](https://agentskills.io/):

```json
{
  "$schema": "https://schemas.agentskills.io/discovery/0.2.0/schema.json",
  "skills": [
    {
      "name": "good-readme",
      "description": "One-line 'use this when…' the agent reads to decide relevance.",
      "type": "skill-md",
      "url": "https://yourdomain.com/agent-skills/good-readme/SKILL.md",
      "digest": "sha256:9f2b…"
    },
    {
      "name": "pdf-extract",
      "description": "One-line 'use this when…' for the multi-file skill.",
      "type": "archive",
      "url": "https://yourdomain.com/agent-skills/pdf-extract.tar.gz",
      "digest": "sha256:1c4a…"
    }
  ]
}
```

Exactly two top-level keys, `$schema` and `skills`. Five fields per skill:

- `name` — the slug the installer uses. Must be a valid skill name (lowercase letters, digits, single dashes) or installers reject it, and must be unique across the whole index: installers key on `name`, so a duplicate shadows rather than adds. Fail your build on one.
- `description` — the same one-line trigger the agent reads. Copy it from the skill's own front matter.
- `type` — `skill-md` for a single-file skill (the `url` is the `SKILL.md` itself) or `archive` for a multi-file skill (the `url` is the tarball).
- `url` — where the bytes live. Your domain, per step 3.
- `digest` — `sha256:<hex>` of the exact bytes at `url`. Verification is mandatory rather than optional politeness: a conformant client MUST re-hash what it downloads and MUST NOT use content that fails, so a wrong digest doesn't degrade the install, it blocks it.

A bundle is represented *only* as its member skills, each a normal entry under its own name, plus the combined archive from step 4 that you offer as a download. There's no entry for the bundle as a whole, and no `version`, `origin`, or `bundles` key to add.

### 6. Offer more than one install command

Expose several install methods, because your users live in different tools and a single command loses whoever doesn't use it. `SKILL.md` is a cross-agent standard, so one payload serves every agent — only the destination directory changes (`~/.claude/skills`, `~/.cursor/skills`, `~/.agents/skills`, `~/.copilot/skills`, `~/.gemini/skills`). Provide:

- **`npx skills`** — reads your discovery index: `npx skills add https://yourdomain.com/agent-skills --skill <name> -a <agent> -g`. Omit `--skill` for an interactive pick-list, or pass `--skill '*'` for the whole catalog.
- **`claude plugin`** — Claude's marketplace, and the best path for a bundle (one install pulls the whole set): `claude plugin marketplace add <owner>/<repo>` then `claude plugin install <name>@<marketplace>`. The `<marketplace>` half is the `name` from that repo's `.claude-plugin/marketplace.json`, which needn't match the repo's own name — read it, don't assume it.
- **`gh skill`** — installs one `SKILL.md` from the repo: `gh skill install <owner>/<repo> <name>`. Not available for a bundle slug, which names no single skill directory.
- **`curl`** — dependency-free, and the only method that needs nothing installed first. The command follows the shape from step 4:
  - Single-file: `curl -fsSL --create-dirs https://yourdomain.com/agent-skills/<name>/SKILL.md -o <dir>/<name>/SKILL.md`
  - Multi-file (flat tarball → unpacks into the skill's *own* folder): `mkdir -p <dir>/<name> && curl -fsSL https://yourdomain.com/agent-skills/<name>.tar.gz | tar -xz -C <dir>/<name>`
  - Bundle (each skill is already a folder → unpacks into the skills directory itself): `mkdir -p <dir> && curl -fsSL https://yourdomain.com/agent-skills/<bundle>-bundle.tar.gz | tar -xz -C <dir>`

  The `mkdir -p` isn't optional: `tar -C` fails with "could not chdir" when the target is missing.

Match each method to who copies it: power users want the marketplace, scripts want `curl`, `gh`-native teams want `gh skill`, and a reader following a walkthrough wants one copy-paste line.

### 7. Instrument installs (optional)

You can't see a `curl` that runs on a laptop, but you can measure the parts you serve:

- **Wherever you render install commands** — a docs page, a landing page, a README: which command was copied, which agent, which method, plus copies of the `SKILL.md` body and clicks through to the source repo.
- **Server-side:** hits to `/.well-known/agent-skills/index.json` and each skill `url`, classified by `User-Agent`. Split those buckets before trusting totals — most "agent" traffic to a well-known file is generic bots, not the installers you care about.
- **Per referring page:** when the same install commands appear on more than one page, suffix each event with that page's slug. Otherwise you learn which skills get installed but never which page drove it.

### 8. Verify

- `curl -fsSLI https://yourdomain.com/.well-known/agent-skills/index.json` returns `content-type: application/json`.
- `curl -fsSL` on the same URL returns valid JSON listing every skill you meant to publish, and nothing you didn't.
- For one entry, `curl -fsSL <its url> | sha256sum` matches the `digest` you published. This is the check that quietly fails when you hash something other than what you serve.
- `tar -tzf <name>.tar.gz` lists `SKILL.md` at the archive root, not `<name>/SKILL.md`.
- `npx skills add https://yourdomain.com/agent-skills --skill <name>` installs cleanly into the target agent's skills directory. Then ask the agent something the skill covers and watch whether it loads: that's the only test of whether the `description` earns its trigger.

## Anti-patterns: do NOT do these

- **Pointing the discovery index at `raw.githubusercontent.com`** (or any host you don't build from). The digest and the served bytes drift apart and installs break. Re-host and hash your own copy.
- **Pinning a commit only to avoid the raw-URL problem.** If you re-host correctly, you can safely track the default branch; pinning just makes skills go stale.
- **A wrapping folder inside a single-skill archive.** Installers unpack a flat archive into the skill's directory; a `<name>/<name>/SKILL.md` nesting breaks the install.
- **One discovery entry for a whole bundle.** List each contained skill separately under its own name — installers key on `name`.
- **Inventing index fields the schema doesn't define** — a top-level `version`/`origin` key, a `bundles[]` array, or a per-skill `bundle` field. Anything extra is guesswork an installer won't read.
- **Publishing a digest you can't reproduce.** Split hashing from archiving *and* leave the tarball nondeterministic (unpinned modes, unsorted members, live mtimes, no `gzip -n`) and the hash you advertised stops matching the file you serve, even though the skill didn't change.
- **Skipping the digest.** An index without integrity hashes gives installers nothing to verify; a corrupted or swapped payload installs silently.
- **A single install command.** It's cheap to offer several, and it's the difference between a reader installing or bouncing.

## Final check

1. `.well-known/agent-skills/index.json` exists, is served as `application/json`, is valid JSON, and lists every skill with `name`, `description`, `type`, `url`, `digest`.
2. Every `url` is on a domain you control and build from — no raw repo URLs.
3. Every `digest` matches the bytes actually served at its `url`.
4. Single-file skills are `type: skill-md`; multi-file skills are `type: archive` with a flat tarball; each bundled skill has its own entry, under a name unique across the index.
5. At least `npx skills` plus one repo-based method (`gh skill` or the Claude plugin marketplace) install cleanly.
