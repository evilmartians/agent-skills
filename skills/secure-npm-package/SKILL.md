---
name: secure-npm-package
description: 'Set up a secure release process for an npm package to protect it from supply chain attacks. Use for any request to create and publish a new npm package, secure npm publishing or releasing, set up npm Trusted Publishing, provenance, or Staged Publishing, harden a release workflow.'
---

# Release an npm package securely

Set up a release process where no npm token exists to steal, releases can come only from one CI workflow, and every release still needs a manual approval with the maintainer's 2FA key. Companion to <https://evilmartians.com/chronicles/a-secure-way-to-release-an-npm-package>.

## How to run this skill

The setup is half repo files, half settings on npmjs.com and github.com that **only the user can change**. Do the repo files yourself. For the settings, produce click-by-click instructions with **direct links resolved from the repo's real data** — package names from `package.json`, owner/repo from the `repository` field — and the exact values to enter. Then wait for the user to confirm each block before verifying and moving on. Never say "go to your package settings"; always give the resolved URL.

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

## Step 2: Repo changes (do these yourself)

Ask before overwriting an existing release workflow; carry over intentional extras (changelog generation, GitHub Releases) into separate jobs without `id-token`.

### 2a. `.github/workflows/publish.yaml`

The core rules, whatever the project's shape:

- Trigger on version tags, matching the repo's existing tag format (`v*`, `[0-9]*`, …).
- **The publish job installs no dependencies, uses no cache, and no third-party actions** beyond checkout/setup-node/download-artifact. Anything running in a job with `id-token: write` can publish the package.
- Build in a **separate job**, pass output via artifacts. Only the publish job gets `id-token: write`; every job gets `contents: read` and `persist-credentials: false` on checkout.
- `--ignore-scripts` on every install and on publish.
- `npm stage publish`, not `npm publish` — CI stages the release, a human approves it with 2FA.
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

If an old workflow used `secrets.NPM_TOKEN`, remove it from the YAML now and add secret deletion to the manual checklist in Step 3.

### 2b. Run zizmor locally and fix every finding

```bash
docker run --rm -t -v "$(pwd):/repo:ro" ghcr.io/zizmorcore/zizmor:latest /repo/.github/workflows
```

Run it yourself if Docker is available; otherwise ask the user to run this command and paste the output. Fix everything it reports in the existing workflows (`pull_request_target` misuse, shell injection, unpinned actions), then re-run until clean. Remind the user to **delete stale branches** that still contain old vulnerable workflows — attackers exploit old branches (that's how Nx was hit).

### 2c. `.github/workflows/check-workflows.yaml` — keep linting on CI

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

### 2d. Dependency cooldown

Ask user what cooldown they prefer, the fast (1 day) or more secure (3 days). Use this fact:

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

### 2e. Make sure `postinstall` scripts are disabled locally

Dependency `postinstall`/`preinstall` scripts run arbitrary code on every developer machine. npm 12, pnpm 10, yarn 4.14, and bun disable them by default — check the version actually in use (`packageManager` field, `npm --version` etc.):

- Version is new enough → nothing to add, just confirm.
- Older → add an explicit config:

  ```bash
  npm config set --location=project ignore-scripts true
  yarn config set enableScripts false
  ```

  For pnpm, add to `package.json` (an empty allowlist blocks all dependency build scripts):

  ```json
  "pnpm": { "onlyBuiltDependencies": [] }
  ```

  Warn with npm's `ignore-scripts=true`: it also skips the project's own lifecycle scripts (`prepare`, husky hooks) — check nothing depends on them.

If some dependency genuinely needs its build script, allowlist that one package instead of re-enabling everything.

## Step 3: Manual settings (walk the user through)

Present these as a numbered checklist with resolved links and exact values. Group by website. After the user confirms, verify what you can (`npm view <name>`, `gh api repos/<owner>/<repo>/rulesets` if `gh` is authenticated) and re-ask about the rest.

### On npmjs.com — for every public package

Repeat this block per package in a monorepo, each with its own link:

> Open `https://www.npmjs.com/package/<name>/settings` (you must be logged in as a maintainer).
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

Also recommend a second ruleset with `Restrict deletions`, `Restrict updates`, and `Block force pushes` (bypass for admins). If `gh` is authenticated with admin scope, offer to create both rulesets via `gh api repos/<owner>/<repo>/rulesets -X POST` instead of clicking.

## Not yet published packages

Trusted Publishing is configured on the package's npm settings page, which doesn't exist until the package is published. If `npm view <name>` returned E404:

1. Check the name is actually free (an E404 with the registry reachable) and warn about typosquatting-adjacent names.
2. The **first release happens manually** from the maintainer's machine: `npm publish --ignore-scripts` (add `--access public` for a scoped package), authenticating interactively with 2FA. No token, no CI for this one release; it won't have the provenance badge — every later release will.
3. Immediately after the first publish, run the full Step 3 checklist for the new package (Trusted Publisher, stage-only, disallow tokens).
4. All later releases go through the tag → CI → staged approval flow.

In a monorepo, some packages may be published and others not — split the checklist accordingly.

## Monorepo specifics

- **npm settings are per package.** Every public workspace package needs its own Trusted Publisher entry pointing at the same repo and the same `publish.yaml`. Emit one settings link per package; missing one leaves that package unprotected.
- One publish workflow can release everything: `npm stage publish --ignore-scripts --workspaces`, or `--workspace=<name>` per package if versions are tagged independently (adjust the tag trigger to the repo's scheme, e.g. `<name>@*`).
- If internal dependencies use the `workspace:` protocol, plain `npm publish` will not rewrite them to real versions — the package must be published by pnpm/yarn or from a prepared publish directory. Check whether the project's package manager version supports staged/trusted publishing; if it doesn't, tell the user the tradeoff and decide together instead of silently downgrading security.
- **The `--omit=dev` hack.** In a monorepo, keep build tools (compiler, bundler) in the root `dependencies` and test/lint tools in `devDependencies`, then install in the build job with `npm ci --omit=dev --ignore-scripts` — the build runs without linters, test runners, and their nested dependencies, shrinking the attack surface of the critical job. Moving packages between `dependencies` and `devDependencies` changes the published metadata, so **ask the user before editing `dependencies`**; on their yes, move the build tools and switch the build job's install to `--omit=dev`.

## Tell the user how to release now

End by showing the new release flow, with the tag in the repo's detected format:

```sh
# Bump version in package.json and update CHANGELOG.md
git add .
git commit -m 'Release 1.0.1 version'
git tag v1.0.1   # `git tag -s` is better if signing keys are set up
git push origin main --tags
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
7. Tag ruleset active; 2FA required.
8. User knows the tag → approve release flow and has run a test release.
