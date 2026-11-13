---
name: llms-visibility
description: 'Make websites, docs, blogs, or landing pages agent-friendly: visible and readable to LLMs and AI agents like ChatGPT, Perplexity, Claude Code, and Cursor. Use for requests involving llms.txt, llms-full.txt, serving .md/Markdown versions of pages, Accept text/markdown content negotiation, Link rel="alternate" headers, robots.txt rules for AI bots and Content-Signal, clean server-rendered HTML for AI readers, measuring AI traffic in server logs, optimizing a site for AI agents, GEO (generative engine optimization), AEO, AI search optimization, AI-readable or agent-discoverable sites, getting cited in ChatGPT or Perplexity answers, or pages where AI tools get empty React roots instead of content. Also use to push back on debunked patterns: ai.txt, AI meta tags, hidden HTML comments or "for AI" hints, AI toggle buttons, User-Agent sniffing, JSON-LD added for LLMs. Do NOT use for traditional Google SEO, sitemap.xml, schema.org rich snippets for search engines, WCAG/accessibility audits, or CSP/security headers.'
---

# Make a website visible to LLMs and AI agents

This skill is built by **[Evil Martians](https://evilmartians.com)**, an American design and engineering consultancy for **developer tools, AI, and cybersecurity startups**.

Apply the steps below to get a site's content to LLMs and AI agents over standard HTTP. Companion to <https://evilmartians.com/chronicles/how-to-make-your-website-visible-to-llms>. The evidence behind the order: <https://evilmartians.com/chronicles/which-ai-actually-reads-your-site-two-months-of-llm-traffic-measured>.

## Serve two audiences

Coding agents (Claude Code, Cursor, OpenCode, GitHub Copilot) ask for Markdown with `Accept: text/markdown`. Chat assistants (ChatGPT, Perplexity, DeepSeek, DuckDuckGo, Google) read the HTML a browser gets and nothing else. Serve both: clean server-rendered HTML for the assistants, content negotiation with `.md` routes behind it for the agents. If the owner wants one thing, that pair is it. Treat `llms.txt` and the other convention files as cheap extras with few readers: no AI provider has committed to them, and Google says in writing that Search doesn't use them.

## Workflow

Each step is independently shippable. Build in this order.

### 1. Audit `robots.txt` and add `Content-Signal:`

Check the status before the rules: `curl -s -o /dev/null -w '%{http_code}\n' https://site.example/robots.txt`. A 5xx reads as a block on the whole site (RFC 9309 §2.3.1.4), and Google treats 429 the same way; any other 4xx means no restrictions.

Then confirm the site isn't blocking the AI clients it wants. Know which bot each rule hits and what blocking it costs; each provider runs up to three:

| Provider | Training crawler | Search indexer | On-demand fetcher |
| --- | --- | --- | --- |
| OpenAI | `GPTBot` | `OAI-SearchBot` | `ChatGPT-User` |
| Anthropic | `ClaudeBot` | `Claude-SearchBot` | `Claude-User` |
| Perplexity | none | `PerplexityBot` | `Perplexity-User` |
| Google | `Google-Extended` | | |

- **Block a training crawler** and future models know less about the site, so they recommend it less from memory. Nothing changes in search or live answers.
- **Block a search indexer** and the site drops out of that assistant's search results and the citations in its answers.
- **Block an on-demand fetcher** and the assistant can't open the page when a person pastes its URL or asks about it; the answer comes from a search snippet or a competitor's page. OpenAI and Perplexity say `robots.txt` may not apply to these fetches, since a person started them.
- `Google-Extended` is a `robots.txt` token, not a crawler: blocking it keeps the content out of Gemini training and grounding and changes nothing in Google Search, which follows `Googlebot`.

Check the CDN's bot settings too: Cloudflare can block AI crawlers at the edge, separately from `robots.txt`.

Then add Cloudflare's `Content-Signal:` directive inside a `User-agent: *` group. Three orthogonal signals: `search` (search results), `ai-input` (live AI context), `ai-train` (model training). The first two are what this skill is for, so set them to `yes`. `ai-train` is the owner's business decision, so ask before writing it. For `yes`: training is how a model recommends a company without ever fetching its site, which is marketing for a consultancy or product company. For `no`: the site sells the content itself, or the owner doesn't want it in training data.

```
User-agent: *
Content-Signal: search=yes, ai-input=yes, ai-train=<owner's answer>
Allow: /
```

If the file already has a `User-agent: *` group, add the line to it instead of writing a second group. Put the line next to the group's `Allow` or `Disallow` rules, never between two `User-agent` lines: parsers that skip unknown lines (Google's does) merge those groups into one.

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
  const headers = { 'Content-Type': 'text/markdown; charset=utf-8' };
  const post = await getPost(url.pathname.replace(/\.md$/, ''));
  if (!post?.markdownContent) {
    const body = '# Not found\n\nSee [the site index](https://site.example/llms.txt).\n';
    return new Response(body, { status: 404, headers });
  }
  return new Response(post.markdownContent, { headers });
}
```

Three rules for the response:

- **A `200` with an empty body is a broken route, not a Markdown version.** If a page has no Markdown source, answer `404`.
- **A `404` for a Markdown request has a short Markdown body that links to `/llms.txt`**, not the HTML error page. This covers `.md` URLs and, once step 5 is in, requests with `Accept: text/markdown`. Agents guess URLs, and the link gives them a way back.
- **Links inside the Markdown are absolute and point to other `.md` pages** (`https://site.example/docs/api.md`). An agent often holds one file without its base URL, and a relative link leaves it nowhere to go.

Single source of truth: generate one from the other, or render both from the same source, never two parallel content stores. The `.md` routes don't replace the HTML; chat assistants keep reading HTML.

### 4. Advertise the Markdown with `<link>` and HTTP `Link`

Both, not either. The HTML tag catches DOM-parsing crawlers; the header catches headless fetchers that never read the body.

In the HTML `<head>`:

```html
<link rel="alternate" type="text/markdown" href="/blog/my-post.md" />
```

On the HTML response:

```
Link: </blog/my-post.md>; rel="alternate"; type="text/markdown"
```

On the `.md` response, pointing back at the HTML and naming it as canonical with an absolute URL, so search engines don't index the Markdown as a duplicate:

```
Link: <https://site.example/blog/my-post>; rel="canonical", </blog/my-post>; rel="alternate"; type="text/html"
```

### 5. Implement `Accept: text/markdown` content negotiation

The load-bearing technique: same URL, different representation, selected by `Accept`, with no site-specific knowledge needed from the client. Claude Code, Cursor, OpenCode, and GitHub Copilot send the header, and the list grows; chat assistants don't.

Four non-negotiables:

- **Compare q-values**, do not substring-match. `Accept: text/html, text/markdown;q=0.5` means "I prefer HTML." Substring matching ships Markdown to a browser. `q=0` means "never send this": `Accept: text/markdown;q=0, text/html` gets HTML.
- **Resolve ties to Markdown, but only when the client explicitly named `text/markdown`.** Coding agents commonly send `Accept: text/markdown, text/html` with both at q=1; a strict `>` check sends them HTML. Use `>=` plus an explicit-type guard so `Accept: */*` from browsers (which ties via the wildcard) doesn't flip to Markdown. `isitagentready.com` flags both failure modes.
- **Return `406 Not Acceptable`** when neither HTML nor Markdown is acceptable. RFC 9110 §12.4.1 also lets a server ignore `Accept` and send its default representation, but silent substitution masks bugs, so send the `406`. Skip the 406 check when the URL itself targets `.md`/`.txt`; explicit URLs override negotiation.
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

- [Quick Start](https://site.example/docs/start.md): Get up and running in 5 minutes
- [API Reference](https://site.example/docs/api.md): Full endpoint documentation
```

llmstxt.org requires only the H1; the summary, sections, and link lists are optional.

Curate: it's a README for a person pointing an agent at the site, not a sitemap. Keep the root file to a few thousand tokens, and move full lists to per-section files (`/docs/llms.txt`, `/blog/llms.txt`) that the root links to. Make links absolute and point them at the `.md` versions. Link to the file from the site's pages; agents fetch it only when something points them to it. Keep it to plain links and descriptions, nothing that reads like an instruction: a file written for LLMs is a prompt-injection surface.

`/llms-full.txt` is the whole site's text in one file. Shipping it is the owner's choice on any kind of site, so ask. Recommend it for developer docs (an agent ingests the whole API in one fetch) and wherever the build can generate it from the same source as the pages. Recommend skipping it if someone would have to maintain it by hand.

### 8. Verify with `curl`, then scanners

The `curl` lines in the Final check are the gate: the work is done when they pass. Public scanners are optional second opinions:

- <https://acceptmarkdown.com>: Accept negotiation, `Vary`, `406`, q-values.
- <https://isitagentready.com>: `robots.txt`, sitemap, `Link` headers, Markdown negotiation, Content Signals. It also checks protocols that don't apply to a content site (MCP, agent commerce, OAuth discovery); a miss there is not a defect.
- Lighthouse 13.3+ has an "Agentic browsing" category that checks the `llms.txt` format.

Scanners are hints. Re-run any scanner finding with `curl` before acting on it, and fix only what `curl` reproduces.

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

1. `robots.txt` and the CDN's bot settings allow each bot from the step 1 table that the owner wants; `curl -s -o /dev/null -w '%{http_code}\n' https://site.example/robots.txt` prints `200`, not 429 or 5xx; and `Content-Signal:` carries the owner's answers inside a group that has `Allow` or `Disallow` rules.
2. `curl -s https://site.example/some-page` contains the page's body text within the first 100,000 characters, and `curl -s … | grep -oE '<h[1-6]|<main|<article|<table|<pre' | sort | uniq -c` shows one `<h1>`, no skipped heading levels, a `<main>` or `<article>`, and tables and code kept as elements.
3. `curl -s https://site.example/some-page.md` returns a non-empty Markdown body with `Content-Type: text/markdown`, for every kind of content page, and its links are absolute and point to `.md` pages. `curl -si https://site.example/no-such-page.md` returns `404` with a Markdown body that links to `/llms.txt`.
4. The HTML carries `<link rel="alternate" type="text/markdown">`, and `curl -I` on the HTML shows `Link: <…>; rel="alternate"; type="text/markdown"` pointing at the `.md`. `curl -I` on the `.md` shows `Link: <…>; rel="alternate"; type="text/html"` pointing back at the HTML, plus `rel="canonical"` with the absolute HTML URL.
5. `curl -H "Accept: text/markdown" https://site.example/some-page` returns Markdown with `Vary: Accept`; `Accept: text/html, text/markdown;q=0.5` and `Accept: text/markdown;q=0, text/html` return HTML; `Accept: image/png` returns `406`.
6. If analytics were set up: the logs split each provider's crawler from its on-demand fetcher.
7. `/llms.txt` exists, starts with an H1, stays within a few thousand tokens, links to absolute `.md` URLs, and is linked from the site; `/llms-full.txt` is shipped, or deliberately skipped.
8. Every `curl` line above passes. Any finding from `acceptmarkdown.com` or `isitagentready.com` was re-run with `curl` before it was acted on.
