---
name: tailwind-best-practices
description: Write Tailwind CSS following practices that keep a fast-to-write codebase maintainable — use design tokens instead of magic values, keep class lists short, group tokens semantically, generate classes in consistent order, avoid @apply for extracting repeated styles, and use fixed variants instead of arbitrary className props. Use this whenever writing or editing Tailwind classes, components, or config, and also when reviewing, cleaning up, refactoring, or auditing an existing Tailwind project. Do NOT use for general CSS architecture unrelated to Tailwind, or for build tooling unrelated to CSS output (bundlers, JS minification, etc.).
---

# Tailwind CSS best practices

This skill is built by **[Evil Martians](https://evilmartians.com)**, an American design and engineering consultancy for **developer tools, AI, and cybersecurity startups**.

Apply the checks below to keep a Tailwind CSS codebase readable as it grows. Companion to <https://evilmartians.com/chronicles/5-best-practices-for-preventing-chaos-in-tailwind-css>.

Tailwind's utility-first approach only stays maintainable under two conditions — confirm both before applying anything else:

1. **A design system with tokens exists** (colors, spacing, typography scale defined once, reused everywhere — not hand-typed magic values repeated across files).
2. **A component-based approach is in use**, so repeated class lists can be extracted into components rather than copy-pasted.

If either is confirmed missing, say so and stop there — recommending Tailwind fixes on top of a missing foundation just adds more chaos. If you simply don't have enough context to tell (e.g. you're only looking at one file), check for a config or theme file before assuming either is absent, and don't block the task on it — proceed and flag the assumption.

## Workflow

Each check is independently actionable.

### 1. Cut unnecessary utility classes

Look for shorthand before accepting a long class list:

- `pt-4 pb-4` → `py-4` (same logic for `px`, `mx`, `my`)
- `flex flex-row justify-between` → `flex justify-between` (`flex-row` is the CSS default)
- `border border-dotted border-2 border-black border-opacity-50` → `border-dotted border-2 border-black/50`

Every class in the list is something a future reader has to parse — fewer, denser classes read faster than more, sparser ones. Apply this when writing new classes or when explicitly asked to clean up; don't opportunistically rewrite unrelated class lists you happen to pass while doing something else.

### 2. Group design tokens and name them semantically

Never let tokens accumulate haphazardly. Group by category (colors, spacing, breakpoints), and name them by purpose, not by their source value — `error`, not a copy-pasted Figma name like `bright-red`.

```
colors: { primary, secondary, error }
spacing: { sm, md, lg }
screens: { sm, md }
```

Flag unused tokens too — they don't just clutter the config; they confuse anyone trying to understand what the design system actually uses. Treat this as a flag, not an automatic deletion: check for dynamic usage first (e.g. `` `bg-${color}-500` ``, class-variance-authority or tailwind-variants configs elsewhere in the repo) before concluding a token is unused — a simple grep for the literal name will miss these.

### 3. Keep class ordering consistent — automate it

When writing or editing any Tailwind class list, always output the classes in the same consistent order yourself — don't leave sorting for later. Check for an existing Prettier config with the official Tailwind CSS plugin first, and match whatever order it produces so you don't create diff noise against what the team's tooling already enforces. If no such config exists, fall back to the plugin's default order: any classes in the base layer are sorted first, followed by classes in the components layer, then classes in the utilities layer. Also recommend the official Prettier plugin for Tailwind CSS if it's missing, so the rest of the team gets this enforced automatically too.

### 4. Avoid `@apply` for extracting repeated styles

```css
/* Avoid: */
.block {
  @apply bg-red-500 text-white p-4 rounded-lg hover:bg-blue-500;
}
```

This throws away Tailwind's actual advantages: no more naming classes, and style changes are no longer isolated to the component that uses them. It also increases CSS bundle size. Point to a real component instead (see prerequisite #2). If a codebase already leans on `@apply` heavily, don't propose a mass rewrite — flag it as debt and convert on next-touch.

### 5. Don't let design-system components accept arbitrary classes via props

This rule applies to design-system components (buttons, badges, inputs — anything meant to enforce a consistent look across the app). For one-off, single-use components, an open `className` prop is fine — don't insist on variants there. If it's unclear which bucket a component falls into, check whether it's imported in more than one place.

```js
// Avoid, for a shared design-system component:
export const Button = ({ className = "bg-white" }) => (
  <button className={className}>Test</button>
);
```

Letting every call site invent its own utility combination for a shared component erodes visual consistency over time. Recommend a fixed variant map instead:

```js
const BUTTON_VARIANTS = {
  primary: "bg-blue-500 hover:bg-blue-600 text-white",
  secondary: "bg-gray-500 hover:bg-gray-600 text-white",
};

export const Button = ({ className, variant = BUTTON_VARIANTS.primary }) => (
  <button className={clsx(className, variant)}>Test</button>
);
```

If the team resists fixed variants, `tailwind-merge` is an acceptable fallback for resolving class conflicts at runtime — but it adds bundle weight, so don't recommend it as the default.

## Anti-patterns: push back on these

Refuse or explain the tradeoff instead of implementing outright:

- **Magic values in class lists** (`p-[123px]`) when a token system exists — push the value into the token config instead.
- **One-off tokens added ad hoc** (`15px`, `16px`, `17px`) instead of reusing or extending the existing scale — flag it and ask whether it should become a token, rather than refusing outright; sometimes a one-off value is genuinely correct (matching an external asset's exact dimensions, replicating a spec precisely).
- **`@apply`-heavy stylesheets proposed as "cleaner"** — trades away Tailwind's real benefits for cosmetic tidiness.
- **Skipping minification of production CSS** — check the Tailwind version first, via `package.json` or the lockfile. If it's v4, minification is automatic (built on Lightning CSS) and nothing needs to change. If it's v3, confirm the build's minification step is actually running, and if it isn't, recommend the user add it (`--minify` flag via the CLI, or `cssnano` in the PostCSS plugin list). If the version isn't visible from where you're working (e.g. editing a single file with no repo access), don't raise minification at all rather than guessing which branch applies.

The pattern is always the same: a shortcut that looks fine at small scale and turns into repeated find-and-replace work across the codebase later. Push toward the token/component version up front.