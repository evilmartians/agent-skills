#!/usr/bin/env node
// Checks each skill against the Agent Skills spec <https://agentskills.io/specification>
// and against the marketplace manifest:
//
//   - SKILL.md exists and its front matter parses
//   - `name` is 1-64 chars, kebab-case, and matches its directory
//   - `description` is present and at most 1024 chars
//   - skills/ and the manifest's plugin list are 1:1
//   - each plugin entry's `skills` path points at its own slug

import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const MANIFEST = '.claude-plugin/marketplace.json';

const NAME_MAX = 64;
const DESCRIPTION_MAX = 1024;
// Lowercase alphanumerics in hyphen-separated groups: no leading, trailing or
// doubled hyphen, which is every rule the spec puts on `name` bar its length.
const NAME_PATTERN = /^[a-z0-9]+(-[a-z0-9]+)*$/;

const errors = [];
const fail = (where, message) => errors.push(`${where}: ${message}`);

// Enough YAML for two quoted-or-plain scalars, which saves a dependency.
const frontmatterOf = (source) => {
  const match = /^---\n(.*?)\n---(?:\n|$)/s.exec(source);
  if (!match) return null;

  const fields = {};
  for (const line of match[1].split('\n')) {
    const field = /^([A-Za-z][\w-]*):[ \t]*(.*)$/.exec(line);
    if (!field) continue;
    const value = field[2].trim();
    const quoted = /^'(.*)'$|^"(.*)"$/s.exec(value);
    fields[field[1]] = quoted ? (quoted[1] ?? quoted[2]) : value;
  }
  return fields;
};

const slugs = readdirSync('skills', { withFileTypes: true })
  .filter((entry) => entry.isDirectory() && !entry.name.startsWith('.'))
  .map((entry) => entry.name)
  .sort();

for (const slug of slugs) {
  const path = join('skills', slug, 'SKILL.md');
  if (!existsSync(path)) {
    fail(path, 'missing SKILL.md');
    continue;
  }

  const frontmatter = frontmatterOf(readFileSync(path, 'utf8'));
  if (!frontmatter) {
    fail(path, 'missing YAML front matter (--- name / description ---)');
    continue;
  }

  const { name = '', description = '' } = frontmatter;

  if (name !== slug)
    fail(path, `\`name: ${name}\` must match its directory (${slug})`);
  else if (!NAME_PATTERN.test(name))
    fail(
      path,
      `\`name: ${name}\` must be lowercase a–z, 0–9 and single hyphens, ` +
      'not leading, trailing or doubled',
    );
  else if (name.length > NAME_MAX)
    fail(path, `\`name\` is ${name.length} characters (max ${NAME_MAX})`);

  // An agent reads the description to decide whether the skill is relevant, so
  // without one the skill never fires.
  if (!description) fail(path, 'front matter is missing `description`');
  else if (description.length > DESCRIPTION_MAX)
    fail(
      path,
      `\`description\` is ${description.length} characters (max ${DESCRIPTION_MAX})`,
    );
}

let manifest;
try {
  manifest = JSON.parse(readFileSync(MANIFEST, 'utf8'));
} catch (error) {
  fail(MANIFEST, `unreadable or invalid JSON — ${error.message}`);
}

if (manifest) {
  const plugins = manifest.plugins ?? [];
  const listed = plugins.map((plugin) => plugin.name);

  // A skill with no entry can't be installed; an entry with no skill installs empty.
  for (const slug of slugs)
    if (!listed.includes(slug)) fail(MANIFEST, `skills/${slug} has no plugin entry`);
  for (const name of listed)
    if (!slugs.includes(name)) fail(MANIFEST, `plugin \`${name}\` has no skills/${name}`);

  // The next skill will be added by copying this entry and editing `name`. Leave the
  // path behind and it installs cleanly, serving the wrong skill under the new name.
  for (const plugin of plugins) {
    const expected = `./skills/${plugin.name}`;
    const paths = [plugin.skills ?? []].flat();
    if (paths.length !== 1 || paths[0] !== expected)
      fail(`${MANIFEST} → ${plugin.name}`, `\`skills\` must be exactly ["${expected}"]`);
  }
}

if (errors.length > 0) {
  console.error(`✗ ${errors.length} problem(s):\n`);
  for (const error of errors) console.error(`  ${error}`);
  process.exit(1);
}

console.log(`✓ ${slugs.length} skill(s) valid: ${slugs.join(', ')}`);
