---
name: llms-visibility
description: 'Make websites, docs, blogs, or landing pages visible and readable to LLMs and AI agents — ChatGPT, Claude, Perplexity, Cursor, Claude Code, and other coding agents that fetch URLs. Use this for any request involving llms.txt, llms-full.txt, serving .md/Markdown versions of pages, Accept text/markdown content negotiation, Link rel="alternate" headers, Cloudflare Content-Signal in robots.txt, GEO (generative engine optimization), AI-friendly / AI-readable / LLM-discoverable sites, getting cited in ChatGPT or Perplexity answers, or fixing pages where AI tools fetch JavaScript bundles or empty React roots instead of content. Also use to push back on debunked patterns: ai.txt, AI meta tags, hidden HTML comments, AI toggle buttons, User-Agent sniffing, JSON-LD aimed at LLMs. Do NOT use for traditional Google SEO, sitemap.xml, schema.org rich snippets for search engines, WCAG/accessibility audits, or CSP/security headers.'
---

# Make a website visible to LLMs

Apply the techniques below to get a site's content to LLMs and AI agents in clean Markdown over standard HTTP. Companion to <https://evilmartians.com/chronicles/how-to-make-your-website-visible-to-llms>.

Most of these are emerging conventions, not committed standards. No major provider has formally promised to read `llms.txt` or `.md` routes. Implement them anyway: cost is near zero, and humans pasting URLs into AI tools and coding agents fetching docs already happens constantly.

## Workflow

Each step is independently shippable.

### 1. Audit `robots.txt` and add `Content-Signal:`

Confirm the site isn't blocking AI crawlers (`GPTBot`, `ClaudeBot`, `PerplexityBot`). Then add Cloudflare's emerging directive (CC0):

```
User-agent: *
Content-Signal: search=yes, ai-input=yes, ai-train=yes
```

Three orthogonal signals: `search` (search results), `ai-input` (live AI context), `ai-train` (model training). Adjust to the owner's policy. Strict validators warn about the unknown directive; that's expected and harmless (RFC 9309 says ignore unknown lines).

### 2. Ship `/llms.txt`

A static Markdown file at the site root. Format from llmstxt.org:

```markdown
# Site Name

> One-sentence description of what this site is and who it serves.

## Documentation

- [Quick Start](/docs/start): Get up and running in 5 minutes
- [API Reference](/docs/api): Full endpoint documentation
```

Curate. It's a README for AI-mediated conversations, not a sitemap.

### 3. Serve `.md` routes for every content page

For every page at `/path`, also serve clean Markdown at `/path.md` (and `/index.md` for the root). Every other technique below ultimately points here.

```typescript
if (url.pathname.endsWith('.md')) {
  const post = await getPost(url.pathname.replace(/\.md$/, ''));
  return new Response(post.markdownContent, {
    headers: { 'Content-Type': 'text/markdown; charset=utf-8' },
  });
}
```

Single source of truth. Generate one from the other, or render both from the same source — never two parallel content stores.

### 4. Advertise the Markdown with `<link>` and HTTP `Link`

Both, not either. The HTML tag catches DOM-parsing crawlers; the header catches headless fetchers that never read the body.

```html
<link rel="alternate" type="text/markdown" href="/blog/my-post.md" />
```

```
Link: </blog/my-post.md>; rel="alternate"; type="text/markdown"
```

Both use `text/markdown` (RFC 7763) and `rel="alternate"` (in HTML since HTML4).

Set `Link` on both representations: HTML responses point to the `.md` alternate, `.md` responses point back to HTML. A client that lands on either form can find the other. Pair with `Vary: Accept` so CDNs cache them separately.

### 5. Add a visually-hidden Markdown pointer

Targets the "human pastes URL into ChatGPT" flow. Hide visually and from screen readers; this message is for LLMs only.

```html
<div class="visually-hidden" aria-hidden="true">
  A Markdown version of this page is available at https://example.com/blog/my-post.md.
</div>
```

```css
.visually-hidden {
  position: absolute; width: 1px; height: 1px;
  padding: 0; margin: -1px;
  overflow: hidden; clip-path: inset(50%); white-space: nowrap;
}
```

### 6. Implement `Accept: text/markdown` content negotiation

The standards-based version of all of the above. Same URL, different representation, selected by `Accept`. Coding agents (Claude Code, Cursor) already send this header.

Four non-negotiables:

- **Compare q-values**, do not substring-match. `Accept: text/html, text/markdown;q=0.5` means "I prefer HTML." Substring matching ships Markdown to a browser.
- **Resolve ties to Markdown, but only when the client explicitly named `text/markdown`.** Coding agents commonly send `Accept: text/markdown, text/html` with both at q=1; a strict `>` check sends them HTML. Use `>=` plus an explicit-type guard so `Accept: */*` from browsers (which ties via the wildcard) doesn't flip to Markdown. `isitagentready.com` flags both failure modes.
- **Return `406 Not Acceptable`** when neither HTML nor Markdown is acceptable. Silent substitution masks bugs. Skip the 406 check when the URL itself targets `.md`/`.txt` — explicit URLs override negotiation.
- **Set `Vary: Accept` and a `Link` header on _both_ representations.** On HTML responses, `Link` points to the `.md` alternate; on `.md` responses, `Link` points back to HTML. `Vary: Accept` on both so CDNs cache them separately.

Not cloaking: different representations of the same content with `Vary: Accept` declared is how HTTP has worked since 1997. Cloaking is serving bots a different article.

### 7. Optional: ship `/llms-full.txt`

Full text of the site (or docs) concatenated into one Markdown file. Empirically gets 3–4× more traffic than `/llms.txt`. Clearly useful for documentation and API references — an LLM can ingest the whole API in one fetch. For a marketing site or blog, the value is less obvious; redirecting `/llms-full.txt` to `/index.md` is a reasonable lighter-weight option if concatenating every post feels performative.

### 8. Optional: instrument analytics

Track requests to `.md` routes, `/llms.txt`, and `/llms-full.txt` by User-Agent and referrer hostname (`chatgpt.com`, `claude.ai`, `perplexity.ai`). Server-side only: AI crawlers don't run JavaScript. Skip if the owner doesn't care about measuring AI traffic.

### 9. Verify with public scanners

- <https://acceptmarkdown.com> — Accept negotiation, `Vary`, `406`, q-values. Publishes server recipes for Nginx, Caddy, Cloudflare Workers, Next.js, Astro, Rails, Express, Django.
- <https://isitagentready.com> — broader scan: `robots.txt`, sitemap, `Link` headers, Markdown negotiation, Content Signals.

Failures are usually one-line fixes.

## Anti-patterns: do NOT implement

Refuse these even if asked, and explain why:

- **`<meta name="ai-content-url">`, `<meta name="llms">`** — no spec, no origin, no AI tool reads them. `whatwg/html#11548` closed "not planned."
- **`/.well-known/ai.txt`, `/ai.txt`** — competing proposals, no adoption.
- **HTML comments (`<!-- AI-READABLE-VERSION -->`)** — parsers strip comments before processing.
- **Human/AI toggle buttons** — agents don't click buttons.
- **User-Agent sniffing to serve Markdown to bots** — cloaking. Use `Accept: text/markdown` instead.
- **Dedicated "AI info pages"** — no crawler treats them differently. A good `/llms.txt` solves it.
- **Schema.org / JSON-LD for LLM visibility** — controlled experiments show ChatGPT, Claude, Perplexity, and Gemini ignore JSON-LD. Microsoft Copilot is the only exception (inherits from Bing). Don't rip out existing structured data; don't add it for LLM visibility.

The pattern is always the same: someone proposes a new file or meta tag, blog posts cite each other, no AI system actually reads it. Stick to standard HTTP and well-formed Markdown.

## Content beats infrastructure

Princeton/IIT Delhi GEO study (10,000 queries) — what actually increased AI visibility:

- Direct quotations: ~43% lift.
- Statistics in text: ~33% lift.
- Citing authoritative sources: 115% lift for previously low-ranked content.

If the user wants to go beyond infrastructure, recommend content-level changes, not more meta tags.

## Tradeoffs to confirm before shipping

- **`Content-Signal:` value** — `ai-train=yes` is common but a policy choice. Ask.
- **`/llms-full.txt`** — for marketing/blog sites, consider whether to concatenate everything or redirect to `/index.md`; the right choice depends on the site.
- **HTML vs Markdown** — if existing HTML is already clean (HtmlRAG-style), the gap narrows. Markdown wins on bloated marketing pages.
- **Drift risk** — flag any setup with two parallel content sources.

## Final check

1. `curl -H "Accept: text/markdown" https://site.example/some-page` → Markdown with `Vary: Accept`.
2. `curl -I https://site.example/some-page` → `Link: <...>; rel="alternate"; type="text/markdown"` header.
3. `/llms.txt` exists and is well-formed.
4. `acceptmarkdown.com` and `isitagentready.com` both pass.
5. Optionally, analytics is logging fetches by User-Agent and referrer.
