---
name: secure-npm-package
description: 'Set up a secure release process for an npm package to protect it from supply chain attacks. Use for any request to create and publish a new npm package, secure npm publishing or releasing, set up npm Trusted Publishing, provenance, or Staged Publishing, harden a release workflow.'
---

# Release an npm package securely

Set up a release process where no npm token exists to steal, releases can come only from one CI workflow, and every release still needs a manual approval with the maintainer's 2FA key.

## How to run this skill

The setup is half repo files, half settings on npmjs.com and github.com that **only the user can change**. The settings are the part that needs the user, and if you do the repo changes first the instructions scroll past and get missed — so the user acts before you do. For the settings, produce click-by-click instructions with **direct links resolved from the repo's real data** — package names from `package.json`, owner/repo from the `repository` field — and the exact values to enter. Never say "go to your package settings"; always give the resolved URL.

The order is strict — **questions, then manual settings, then CLI and files**:

1. **Gather facts** (Step 1), read-only and silent, to learn the project's shape.
2. **Ask all questions together.** Gather every decision you need from the user — cooldown length (1 or 3 days), whether to move build tools into `dependencies` for the `--omit=dev` hack in a monorepo, the `repository` field if it's missing, and anything else the project raises — and ask them all in one message. Do not drip questions out one at a time. Wait for the answers.
3. **Hand off the manual settings** (Step 2) on npmjs.com and github.com and ask the user to make every change.
4. **Wait for the user to confirm** they have changed everything — do not run any repo-changing command or touch any files until they say so.
5. **Run the CLI and change files** (Step 3).

The only commands allowed before the user answers the questions and confirms the settings are the **read-only** fact-gathering ones in Step 1 (`npm view`, `git tag`, reading `package.json`). Every mutating command — `npm config set`, writing workflow files, editing `package.json` — waits for Step 3.

## Step 1: Gather facts

Collect before changing anything:

- **Packages.** Read the root `package.json`. If it has `workspaces` (or `pnpm-workspace.yaml` exists), it's a monorepo: enumerate every workspace `package.json`. Only packages without `"private": true` need npm settings.
- **GitHub owner/repo.** From the `repository` field (normalize `git+https://github.com/owner/repo.git`, `github:owner/repo`, `owner/repo`), falling back to `git remote get-url origin`. If neither exists, ask the user, then add the `repository` field.
- **Org or personal.** Whether the owner is a GitHub organization or a user account (changes the 2FA instructions).
- **Package manager and version.** From the `packageManager` field and lockfiles.
- **Published or not.** `npm view <name> version` for each public package. An E404 means not yet published — see [Not yet published packages](#not-yet-published-packages).
- **Tag format.** Check existing version tags with `git tag --sort=-creatordate | head` — some repos use `v1.0.0`, others `1.0.0`, monorepos often `<name>@1.0.0`. Keep the existing format in the workflow trigger and release instructions; only if there are no tags yet, default to `v1.0.0`.
- **Build step.** Is there a `build` script, and what directory does it emit?
- **Existing workflows** in `.github/workflows/`, especially any current release workflow and any use of `secrets.NPM_TOKEN`.

## Step 2: Manual settings (ask the user first)

Present these _before_ changing any repo files, so the user doesn't miss them. Give a numbered checklist with resolved links and exact values, grouped by website. The workflow filename you reference below (`publish.yaml`) is fixed — you'll create the file in Step 3, but the user can enter the name now without waiting for it. Ask the user to work through the whole checklist and then confirm back that everything is done. After they confirm, verify what you can (`npm view <name>`, `gh api repos/<owner>/<repo>/rulesets` if `gh` is authenticated) and re-ask about anything still not set. Only once the settings are confirmed do you move on to the repo changes.

### On npmjs.com — for every public package

Repeat this block per package in a monorepo, each with its own link:

> Open `https://www.npmjs.com/package/<name>/access` (you must be logged in as a maintainer).
>
> 1. In **Trusted Publisher** select **GitHub Actions** and enter:
>    - Organization or user: `<owner>`
>    - Repository: `<repo>`
>    - Workflow filename: `publish.yaml`
>    - Environment: leave empty
>    - Enable only **Allow npm stage publish** — deny plain `npm publish`, so even hacked CI can't release without your approval.
> 2. In **Publishing access** select **Require two-factor authentication and disallow tokens**. This revokes all existing tokens — warn me first if any other automation publishes this package with a token.

If the old setup used an `NPM_TOKEN` secret, also:

> Delete the `NPM_TOKEN` secret at `https://github.com/<owner>/<repo>/settings/secrets/actions` and revoke the token itself at <https://www.npmjs.com/settings/~/tokens>.

### On github.com

**2FA for everyone.** If the repo belongs to an organization:

> Open `https://github.com/organizations/<org>/settings/security` and enable **Require two-factor authentication** under Authentication security.

For a personal account, ask the user to confirm 2FA is on at <https://github.com/settings/security> — prefer a hardware key or passkey.

**Tag ruleset** — with CI publishing, whoever can push a `v*` tag can trigger a release, so restrict tag creation:

> Open `https://github.com/<owner>/<repo>/settings/rules/new?target=tag` and create:
>
> - Ruleset Name: `Tags only by admins`
> - Enforcement status: `Active`
> - Bypass list: add `Repository admins`
> - Target tags: `Include all tags`
> - Tag rules: enable **Restrict creations**

**Immutable releases** — once a release is published, its tag and assets can never be changed or deleted, so an attacker can't silently swap artifacts under an existing version:

> Open `https://github.com/<owner>/<repo>/settings` and in the **Releases** section enable **Immutable releases**.

## Step 3: Repo changes (do these yourself)

**Do not start until the user confirms they have changed everything in Step 2.** Ask them to confirm the npm and github settings are all done, and wait for their explicit yes. Only then make the repo changes. Ask before overwriting an existing release workflow; carry over intentional extras (changelog generation, GitHub Releases) into separate jobs without `id-token`.

### 3a. `.github/workflows/publish.yaml`

The core rules, whatever the project's shape:

- Trigger on version tags, matching the repo's existing tag format (`v*`, `[0-9]*`, …).
- **The publish job installs no dependencies, uses no cache, and no third-party actions** beyond checkout/setup-node/download-artifact. Anything running in a job with `id-token: write` can publish the package.
- Build in a **separate job**, pass output via artifacts. Only the publish job gets `id-token: write`; every job gets `contents: read` and `persist-credentials: false` on checkout.
- `--ignore-scripts` on every install and on publish.
- `npm stage publish`, not `npm publish` — CI stages the release, a human approves it with 2FA.
- **Use `npm` for the publish command even when the project uses pnpm, yarn, or bun.** . The only exception is a project that genuinely needs its own package manager's staged-publish command (e.g. `workspace:` or `beforePacking`); there, use that tool's command instead.
- If there is no build script, drop the build job and the artifact steps entirely (best case — see [Nano ID's workflow](https://github.com/nanostores/nanostores/blob/main/.github/workflows/release.yml)).

Template (adapt Node version, build output path, and install commands to the project's package manager, update versions to latest keeping SHA-commits pinning):

```yaml
name: Release
on:
  push:
    tags:
      - 'v*'
jobs:
  test:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - name: Checkout the repository
        uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
        with:
          persist-credentials: false
      - name: Install Node.js
        uses: actions/setup-node@48b55a011bda9f5d6aeb4c2d9c7362e8dae4041e # v6.4.0
        with:
          node-version: 26
          cache: npm
      - name: Install dependencies
        run: npm ci --ignore-scripts
      - name: Run tests
        run: npm test

  build: # Separate job so build-time dependencies can't publish
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - name: Checkout the repository
        uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
        with:
          persist-credentials: false
      - name: Install Node.js
        uses: actions/setup-node@48b55a011bda9f5d6aeb4c2d9c7362e8dae4041e # v6.4.0
        with:
          node-version: 26
          package-manager-cache: false # Slower, but no cache poisoning risk
      - name: Install dependencies
        run: npm ci --ignore-scripts
        # For a monorepo with build tools in root `dependencies`:
        # run: npm ci --omit=dev --ignore-scripts
      - name: Build package
        run: npm run build
      - name: Upload build artifacts
        uses: actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7.0.1
        with:
          name: build-artifacts
          path: dist/
          retention-days: 1

  publish: # The critical job: no dependencies installed at all
    runs-on: ubuntu-latest
    needs:
      - test
      - build
    permissions:
      contents: read
      id-token: write
    steps:
      - name: Checkout the repository
        uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
        with:
          persist-credentials: false
      - name: Download build artifacts
        uses: actions/download-artifact@3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c # v8.0.1
        with:
          name: build-artifacts
          path: dist/
      - name: Install Node.js
        uses: actions/setup-node@48b55a011bda9f5d6aeb4c2d9c7362e8dae4041e # v6.4.0
        with:
          node-version: 26
          package-manager-cache: false
      - name: Publish npm package
        run: npm stage publish --ignore-scripts
```

If an old workflow used `secrets.NPM_TOKEN`, remove it from the YAML now — deleting the secret and revoking the token is already covered by the Step 2 checklist (from the facts gathered in Step 1).

### 3b. Run zizmor locally and fix every finding

```bash
docker run --rm -t -v "$(pwd):/repo:ro" ghcr.io/zizmorcore/zizmor:latest /repo/.github/workflows
```

Run it yourself if Docker is available; otherwise ask the user to run this command and paste the output. Fix everything it reports in the existing workflows (`pull_request_target` misuse, shell injection, unpinned actions), then re-run until clean. Remind the user to **delete stale branches** that still contain old vulnerable workflows — attackers exploit old branches (that's how Nx was hit).

### 3c. `.github/workflows/check-workflows.yaml` — keep linting on CI

```yaml
name: Lint CI workflows
on:
  push:
    branches: ['main']
  pull_request:
    branches: ['**']
jobs:
  zizmor:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      actions: read
    steps:
      - name: Checkout the repository
        uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
        with:
          persist-credentials: false
      - name: Run zizmor
        uses: zizmorcore/zizmor-action@6599ee8b7a49aef6a770f63d261d214911a7ce02 # v0.6.0
        with:
          advanced-security: false
```

### 3d. Dependency cooldown

Apply the cooldown the user already chose in the batched questions — the fast (1 day) or more secure (3 days). If for some reason it wasn't settled then, use this fact to decide:

> A 3-day delay before adopting new dependency versions blocks ~94% of malicious releases (median takedown is 14 hours).

Apply the one matching the project's package manager:

```bash
npm config set --location=project min-release-age 3
pnpm config set --location=project minimumReleaseAge 4320
yarn config set npmMinimalAgeGate 3d
```

For bun, add to `bunfig.toml`:

```toml
[install]
minimumReleaseAge = 259200
```

**pnpm 11+ already turns cooldown on** — `minimumReleaseAge` defaults to `1440` (1 day). So on pnpm 11 you're only _raising_ it to 3 days (`4320`).

### 3e. Make sure `postinstall` scripts are disabled locally

Dependency `postinstall`/`preinstall` scripts run arbitrary code on every developer machine. npm 12, pnpm 10, yarn 4.14, and bun disable them by default — check the version actually in use (`packageManager` field, `npm --version` etc.):

- Version is new enough → nothing to add, just confirm.
- Older → add an explicit config:

  ```bash
  npm config set --location=project ignore-scripts true
  yarn config set enableScripts false
  ```

  Warn with npm's `ignore-scripts=true`: it also skips the project's own lifecycle scripts (`prepare`, husky hooks) — check nothing depends on them.

If some dependency genuinely needs its build script, allowlist that one package instead of re-enabling everything.

## Not yet published packages

Trusted Publishing is configured on the package's npm settings page, which doesn't exist until the package is published. If `npm view <name>` returned E404:

1. Check the name is actually free (an E404 with the registry reachable) and warn about typosquatting-adjacent names.
2. The **first release happens manually** from the maintainer's machine: `npm publish --ignore-scripts` (add `--access public` for a scoped package), authenticating interactively with 2FA. No token, no CI for this one release; it won't have the provenance badge — every later release will.
3. Immediately after the first publish, run the full Step 2 checklist for the new package (Trusted Publisher, stage-only, disallow tokens).
4. All later releases go through the tag → CI → staged approval flow.

In a monorepo, some packages may be published and others not — split the checklist accordingly.

## Monorepo specifics

- **npm settings are per package.** Every public workspace package needs its own Trusted Publisher entry pointing at the same repo and the same `publish.yaml`. Emit one settings link per package; missing one leaves that package unprotected.
- One publish workflow can release everything: `npm stage publish --ignore-scripts --workspaces`, or `--workspace=<name>` per package if versions are tagged independently (adjust the tag trigger to the repo's scheme, e.g. `<name>@*`).
- **Publish with `npm`, unless the package relies on a pnpm-only feature** npm can't reproduce — the `workspace:` protocol, or a `beforePacking` hook in `.pnpmfile.cjs`. Then publish with `pnpm stage publish` instead. In that case drop `actions/setup-node` from the publish job and let pnpm provide Node (`use-node-version` in `pnpm-workspace.yaml`) — one tool in the critical job, not two. First check the pnpm version supports staged/trusted publishing; if not, tell the user the tradeoff rather than silently downgrading security.
- **The `--omit=dev` hack.** In a monorepo, keep build tools (compiler, bundler) in the root `dependencies` and test/lint tools in `devDependencies`, then install in the build job with `npm ci --omit=dev --ignore-scripts` — the build runs without linters, test runners, and their nested dependencies, shrinking the attack surface of the critical job. Moving packages between `dependencies` and `devDependencies` changes the published metadata, so this is one of the decisions you **ask up front in the batched questions**, not mid-edit; on the user's yes, move the build tools and switch the build job's install to `--omit=dev`.

## Tell the user how to release now

End by showing the new release flow, with the tag in the repo's detected format:

```sh
# Bump version in package.json and update CHANGELOG.md
git add .
git commit -m 'Release 1.0.1 version'
git tag v1.0.1   # `git tag -s` is better if signing keys are set up
git push origin v1.0.1
```

Then CI stages the release, and the user approves it in **Staged Packages** (npm user menu on npmjs.com) or with `npm stage approve` — this is the manual 2FA step that hacked CI can't fake. Suggest a patch release as an end-to-end test of the pipeline.

## Suggest the next step: fewer dependencies

Every nested dependency is attack surface no setting can remove. After the setup is done, run:

```bash
npx @e18e/cli analyze
```

Show the user which dependency branches pull in the most nested packages, and offer to draft a plan (an issue or TODO) for replacing the biggest ones later with lighter alternatives — see the [e18e replacements list](https://e18e.dev/docs/replacements/) — or with small local modules. Don't do the replacements now; it's a separate, larger task.

## Final checklist

1. `publish.yaml` publishes with `npm stage publish --ignore-scripts`; only the publish job has `id-token: write`; no dependency installs or caches in it.
2. zizmor workflow added and existing workflows pass it; stale branches deleted.
3. All actions pinned by SHA.
4. Cooldown configured and dependency `postinstall` scripts disabled (by version or by config).
5. Every public package has a Trusted Publisher (stage-only) and tokens disallowed — confirmed by the user, per package.
6. No `NPM_TOKEN` left in workflows or repo secrets.
7. Tag ruleset active; immutable releases enabled; 2FA required.
8. User knows the tag → approve release flow and has run a test release.
