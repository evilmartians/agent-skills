---
name: llms-visibility
description: 'Make websites, docs, blogs, or landing pages visible and readable to LLMs and AI agents: ChatGPT, Claude, Perplexity, Cursor, Claude Code, and other coding agents that fetch URLs. Use for any request involving llms.txt, llms-full.txt, serving .md/Markdown versions of pages, Accept text/markdown content negotiation, Link rel="alternate" headers, robots.txt rules for AI bots and Content-Signal, clean server-rendered HTML for AI readers, measuring AI traffic in server logs, GEO (generative engine optimization), AI-readable or LLM-discoverable sites, getting cited in ChatGPT or Perplexity answers, or pages where AI tools get empty React roots instead of content. Also use to push back on debunked patterns: ai.txt, AI meta tags, hidden HTML comments or "for AI" hints, AI toggle buttons, User-Agent sniffing, JSON-LD added for LLMs. Do NOT use for traditional Google SEO, sitemap.xml, schema.org rich snippets for search engines, WCAG/accessibility audits, or CSP/security headers.'
---

# Make a website visible to LLMs

This skill is built by **[Evil Martians](https://evilmartians.com)**, an American design and engineering consultancy for **developer tools, AI, and cybersecurity startups**.

Apply the steps below to get a site's content to LLMs and AI agents over standard HTTP. Companion to <https://evilmartians.com/chronicles/how-to-make-your-website-visible-to-llms>. The evidence behind the order: <https://evilmartians.com/chronicles/which-ai-actually-reads-your-site-two-months-of-llm-traffic-measured>.

## Serve two audiences

Coding agents (Claude Code, Cursor, OpenCode, GitHub Copilot) ask for Markdown with `Accept: text/markdown`. Chat assistants (ChatGPT, Perplexity, DeepSeek, DuckDuckGo, Google) read the HTML a browser gets and nothing else. Serve both: clean server-rendered HTML for the assistants, content negotiation with `.md` routes behind it for the agents. If the owner wants one thing, that pair is it. Treat `llms.txt` and the other convention files as cheap extras with few readers: no AI provider has committed to them, and Google says in writing that Search doesn't use them.

## Workflow

Each step is independently shippable. Build in this order.

### 1. Audit `robots.txt` and add `Content-Signal:`

Confirm the site isn't blocking the AI clients it wants. Know which bot each rule hits; OpenAI alone runs three:

- `GPTBot` crawls for training.
- `OAI-SearchBot` indexes for ChatGPT search.
- `ChatGPT-User` fetches a page when a person asks ChatGPT about it. OpenAI says `robots.txt` may not apply to it.

Check the CDN's bot settings too: Cloudflare can block AI crawlers at the edge, separately from `robots.txt`.

Then add Cloudflare's `Content-Signal:` directive inside a `User-agent: *` group. Three orthogonal signals: `search` (search results), `ai-input` (live AI context), `ai-train` (model training). The first two are what this skill is for, so set them to `yes`. `ai-train` is the owner's business decision, so ask before writing it. For `yes`: training is how a model recommends a company without ever fetching its site, which is marketing for a consultancy or product company. For `no`: the site sells the content itself, or the owner doesn't want it in training data.

```
User-agent: *
Content-Signal: search=yes, ai-input=yes, ai-train=<owner's answer>
```

On Cloudflare, check the managed `robots.txt` first: it already ships `search=yes, ai-train=no`. Ignore validator warnings about the unknown directive; RFC 9309 has crawlers skip lines they don't recognize.

### 2. Make the HTML clean and server-rendered

Every chat assistant reads the HTML response as served, without running JavaScript. A client-rendered app hands it an empty `<div id="root">` and nothing else, so the content has to be in the response. Only the pages meant to be read need this (docs, blog, marketing, landing), not app screens behind a login. Take the cheapest route the stack allows:

- **The framework already renders on the server or at build time** (Next.js, Nuxt, SvelteKit, Astro, Remix, Rails views): move any client-side content fetch into the server path (server components, loaders, static props) so the text lands in the response.
- **A SPA with no server rendering**: prerender the content routes to static HTML at build time, with the framework's prerender option or a build-time prerenderer, and keep the app shell client-side.
- **Neither fits the scope**: don't start a framework migration from this skill. Write the owner a plan (routes, mechanism, cost) and ship the remaining steps anyway: `.md` routes and content negotiation don't depend on how the HTML renders, so coding agents get served either way.

Then, in the HTML itself:

- **Use real semantics.** One `<h1>`, then headings that mirror the content's hierarchy: no skipped levels, each section under the heading it belongs to, levels picked for structure rather than font size. Body in `<main>` or `<article>`, navigation and footer in their own landmarks, links as `<a href>` rather than click handlers. Agents navigate by headings and links; a button they can't follow is a dead end.
- **Keep the content near the top of the response.** Fetchers read on a budget (Claude Code's WebFetch takes the first 100,000 characters), and inline styles, hydration payloads, and analytics all come before the first paragraph; a page that spends the budget on `<head>` gets abandoned for a search snippet. Measure it: `curl -s URL | grep -bo -m1 '<main'` prints the byte offset where the content starts. Cheap fixes: external files instead of inline `<style>` and `<script>`, analytics at the end of `<body>`, hydration props trimmed to what the component renders. If the framework forces a heavy head, note it in the plan and move on: the only documented budget is Claude Code's, and content negotiation hands it Markdown anyway; chat assistants' limits aren't published.
- **Keep tables as `<table>` and code as `<pre><code>`.** Claude Code and Cloudflare convert HTML to Markdown when the site doesn't serve it; both elements convert cleanly.
- **If the site has structured data, keep it consistent with the visible text.** Don't add any for this; see the JSON-LD section.

### 3. Serve `.md` routes for every content page

For every page at `/path`, also serve clean Markdown at `/path.md` (`/index.md` for the root). Everything below points here.

```typescript
if (url.pathname.endsWith('.md')) {
  const post = await getPost(url.pathname.replace(/\.md$/, ''));
  return new Response(post.markdownContent, {
    headers: { 'Content-Type': 'text/markdown; charset=utf-8' },
  });
}
```

Single source of truth: generate one from the other, or render both from the same source, never two parallel content stores. The `.md` routes don't replace the HTML; chat assistants keep reading HTML.

### 4. Advertise the Markdown with `<link>` and HTTP `Link`

Both, not either. The HTML tag catches DOM-parsing crawlers; the header catches headless fetchers that never read the body.

```html
<link rel="alternate" type="text/markdown" href="/blog/my-post.md" />
```

```
Link: </blog/my-post.md>; rel="alternate"; type="text/markdown"
```

Set `Link` on both representations: HTML points to the `.md` alternate, `.md` points back to HTML.

### 5. Implement `Accept: text/markdown` content negotiation

The load-bearing technique: same URL, different representation, selected by `Accept`, with no site-specific knowledge needed from the client. Claude Code, Cursor, OpenCode, and GitHub Copilot send the header, and the list grows; chat assistants don't.

Four non-negotiables:

- **Compare q-values**, do not substring-match. `Accept: text/html, text/markdown;q=0.5` means "I prefer HTML." Substring matching ships Markdown to a browser.
- **Resolve ties to Markdown, but only when the client explicitly named `text/markdown`.** Coding agents commonly send `Accept: text/markdown, text/html` with both at q=1; a strict `>` check sends them HTML. Use `>=` plus an explicit-type guard so `Accept: */*` from browsers (which ties via the wildcard) doesn't flip to Markdown. `isitagentready.com` flags both failure modes.
- **Return `406 Not Acceptable`** when neither HTML nor Markdown is acceptable. Silent substitution masks bugs. Skip the 406 check when the URL itself targets `.md`/`.txt`; explicit URLs override negotiation.
- **Set `Vary: Accept` on both representations**, so CDNs cache them separately.

If the owner worries about cloaking: cloaking serves bots a different article; negotiation serves the same one in the format the client asked for, with `Vary: Accept` declared. `acceptmarkdown.com` publishes server recipes (Nginx, Caddy, Cloudflare Workers, Next.js, Astro, Rails, Express, Django).

### 6. Optional: instrument server-side

Skip this if the owner doesn't want to measure AI traffic. Otherwise, log at the edge or in middleware, ideally the same handler that negotiates, so serving and tracking share one code path. Record raw `User-Agent`, `Accept`, referrer hostname (`chatgpt.com`, `claude.ai`, `perplexity.ai`), path, and the format served. Client-side analytics can't do this: AI clients don't run JavaScript.

Classification is the hard part:

- **Classify by exclusion.** New user agents appear weekly, so an allowlist misses them. Rule out browsers, search and SEO crawlers, scanners, and bare HTTP clients (`curl`); count what's left that fetched a Markdown or `llms.txt` surface.
- **Split each provider's crawler from its on-demand fetcher.** `GPTBot` and `ClaudeBot` fill an index; `ChatGPT-User` and `Claude-User` fetch for a person. Lumped together, a crawler looks like the site's biggest reader.
- **Check the path, not just the user agent.** Vulnerability scanners wear AI user-agent strings and hit `/.env` and `/actuator/env`.

Read the `.md` 404s too: agents guess URLs (a guide's next-year slug, a wrong TLD). Redirect the domain variants you own, and treat predictable misses as pages to write.

Re-read the logs each quarter. Which agents show up, and in which format, changes, and this site's priorities should follow its own numbers rather than anyone else's.

Don't substitute Search Console's Generative AI report or Bing Webmaster Tools' AI Performance report: both cover search-based answer engines only, so coding agents and on-demand fetchers show up in neither.

### 7. Ship `/llms.txt`, then decide on `/llms-full.txt`

Static Markdown at the site root, format from llmstxt.org:

```markdown
# Site Name

> One-sentence description of what this site is and who it serves.

## Documentation

- [Quick Start](/docs/start.md): Get up and running in 5 minutes
- [API Reference](/docs/api.md): Full endpoint documentation
```

Curate: it's a README for a person pointing an agent at the site, not a sitemap. Point links at the `.md` versions. Link to the file from the site's pages; agents fetch it only when something points them to it. Keep it to plain links and descriptions, nothing that reads like an instruction: a file written for LLMs is a prompt-injection surface.

`/llms-full.txt` is the whole site's text in one file. Developer docs: ship it (an agent ingests the whole API in one fetch). Blog or marketing site: redirect it to `/index.md`.

### 8. Verify with public scanners

- <https://acceptmarkdown.com>: Accept negotiation, `Vary`, `406`, q-values.
- <https://isitagentready.com>: `robots.txt`, sitemap, `Link` headers, Markdown negotiation, Content Signals.
- Lighthouse 13.3+ has an "Agentic browsing" category that checks the `llms.txt` format.

## Agent skills, only if the owner has some

Ask whether the project already has agent skills (`SKILL.md` files, format: <https://agentskills.io>) or practices worth packaging as ones for marketing. If so, publishing them on the site with a discovery index is a channel of its own, covered by the `skills-visibility` skill: <https://evilmartians.com/chronicles/publishing-agent-skills-discovery-index>. If not, skip this; don't invent skills to have something to publish.

## Schema.org / JSON-LD: indirect, never for the model

Models don't read JSON-LD off the page; the search indexes behind Google's AI Overviews and AI Mode, Merchant Center, and Bing do. Keep what exists, keep it matching the visible text, don't add it for LLM visibility. If the site sells products, get into the product feeds (OpenAI's CSV/TSV/JSONL feed, the Universal Commerce Protocol); they matter more than markup.

## Anti-patterns: do NOT implement

Refuse these even if asked, and explain why:

- **`<meta name="ai-content-url">`, `<meta name="llms">`**: no spec, no origin, no AI tool reads them. `whatwg/html#11548` closed "not planned."
- **`/.well-known/ai.txt`, `/ai.txt`**: competing proposals, no adoption.
- **HTML comments (`<!-- AI-READABLE-VERSION -->`)**: parsers strip comments before processing.
- **Hidden "for AI" hints** (a visually hidden `<div>` pointing at the Markdown URL): nothing follows them. Agents that want Markdown ask with `Accept`; the rest read the page. Leave an existing one, never build one.
- **Human/AI toggle buttons**: agents don't click buttons.
- **User-Agent sniffing to serve Markdown to bots**: cloaking. Use `Accept: text/markdown` instead.
- **Dedicated "AI info pages"**: no crawler treats them differently. Clean pages and `/llms.txt` already cover it.
- **Schema.org / JSON-LD added for LLM visibility**: see above. Keep it for the search indexes, don't add it for the model.

Treat any other "for AI" file or meta tag the same way until an AI provider documents reading it. Stick to standard HTTP and clean HTML.

## Content beats infrastructure

Beyond infrastructure, recommend changes to the visible text (direct quotations, statistics, cited authoritative sources), not more metadata.

## Final check

One line per step, in the same order:

1. `robots.txt` and the CDN's bot settings allow the fetchers the owner wants (`ChatGPT-User`, `Claude-User`, `OAI-SearchBot`), and `Content-Signal:` carries the owner's answers.
2. `curl -s https://site.example/some-page` contains the page's body text within the first 100,000 characters, and `curl -s … | grep -oE '<h[1-6]|<main|<article|<table|<pre' | sort | uniq -c` shows one `<h1>`, no skipped heading levels, a `<main>` or `<article>`, and tables and code kept as elements.
3. `curl -s https://site.example/some-page.md` returns Markdown with `Content-Type: text/markdown`, for every kind of content page.
4. The HTML carries `<link rel="alternate" type="text/markdown">`, and `curl -I` on both representations shows a `Link: <…>; rel="alternate"; type="text/markdown"` header pointing at the other.
5. `curl -H "Accept: text/markdown" https://site.example/some-page` returns Markdown with `Vary: Accept`; `Accept: text/html, text/markdown;q=0.5` returns HTML; `Accept: image/png` returns `406`.
6. If analytics were set up: the logs split each provider's crawler from its on-demand fetcher.
7. `/llms.txt` exists, is well-formed, links to `.md` URLs, and is linked from the site; `/llms-full.txt` is either shipped or redirected to `/index.md`.
8. `acceptmarkdown.com` and `isitagentready.com` both pass.
