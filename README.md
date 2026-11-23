[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/gitdiagram?utm_medium=integration&utm_source=button&utm_campaign=gitdiagram)

# GitDiagram on Railway

One-click Railway template for [GitDiagram](https://github.com/ahmedkhaleel2004/gitdiagram) (MIT), built from upstream commit [`39847f5`](https://github.com/ahmedkhaleel2004/gitdiagram/commit/39847f550220c5b547696277fdea89b9ba9eaff5) (2026-11-21). Upstream publishes no image or release tags, so the `Dockerfile` downloads that exact commit and checks its SHA-256.

## What's in this repo

* `Dockerfile`: builds GitDiagram's Next.js standalone server (the explainer-video Chromium is left out) on `node:22.23.5-bookworm-slim` pinned by digest, plus Caddy 2.11.9 and the Redis bridge.
* `wrapper/patch.mjs`: four checked one-line source patches: S3 endpoint and region from the Railway Bucket (upstream hard-codes Cloudflare R2), the site URL from the Railway domain, and an empty browse index on a fresh bucket. The build fails if upstream code changes under a patch.
* `wrapper/redis-rest-shim.mjs`: a small Upstash-REST-compatible bridge on `127.0.0.1` so the app can use Railway Redis instead of an Upstash account.
* `wrapper/Caddyfile`, `wrapper/start.sh`: the login front on `$PORT`, the open `/healthz`, and a supervisor that exits 1 when any process dies so Railway restarts the service.

## Variables

| Variable | Default | Notes |
|---|---|---|
| `OPENAI_API_KEY` | (you enter it) | The only prompt. https://platform.openai.com/api-keys |
| `OPENAI_MODEL` | `gpt-6-luna` | Any OpenAI model upstream prices |
| `OPENAI_BASE_URL` | empty | Only for an OpenAI-compatible proxy with the Responses API |
| `GITHUB_PAT` | empty | Optional GitHub token for higher API limits |
| `GITDIAGRAM_USERNAME` / `GITDIAGRAM_PASSWORD` | `admin` / generated | Site login |
| `CACHE_KEY_SECRET` | generated | Signs private-repo storage keys |
| `REDIS_URL`, `S3_*` | references | Wired to the Redis service and the Bucket |

## Updates

A merge to `main` makes Railway show "update available" to everyone who deployed the template; they choose when to apply it. Every version has a `CHANGELOG.md` entry, breaking changes first.


GitDiagram turns any GitHub repository into an interactive architecture diagram. Paste a repository URL (or replace `github.com` with your domain in the address bar) and it reads the file tree, README and key source files, asks an AI model to explain the structure, and draws a clickable Mermaid diagram that links each component to its code.

## About Hosting GitDiagram

This template builds GitDiagram from a pinned upstream commit in our GitHub repo, so Railway shows you an update notice when we bump the version. You get three pieces: the GitDiagram web app, Railway Redis (rate limits, locks, generation state) and a Railway Bucket (stored diagrams). They are wired together over reference variables and come up healthy on the first deploy. The only thing you supply is an OpenAI API key, because every new diagram is one AI request billed to your key. The site sits behind a generated login so strangers can't spend it, and a crash exits non-zero so Railway restarts the service.

## Common Use Cases

* Get a quick map of an unfamiliar codebase before onboarding, a code review or a contribution
* Share architecture diagrams of your own projects with your team, with links straight to the code
* Diagram private repositories with your own GitHub token, without sending them to a public site

## Dependencies for GitDiagram Hosting

* An OpenAI API key (create one at https://platform.openai.com/api-keys); the default model is `gpt-6-luna`, the cheapest one upstream supports
* Optional: a GitHub personal access token in `GITHUB_PAT`, for higher GitHub API limits

### Deployment Dependencies

* **GitDiagram**: the Next.js web app, built from https://github.com/aalfath/gitdiagram-railway-template (upstream https://github.com/ahmedkhaleel2004/gitdiagram, MIT). A small Caddy front adds the login and an open `/healthz`, and a tiny bridge lets the app's Upstash-style Redis calls reach Railway Redis.
* **Redis**: Railway's Redis, for rate limits, locks and generation state.
* **Bucket**: a Railway Bucket (S3-compatible) that stores every generated diagram, so they survive redeploys.

### Implementation Details

**After deploy.** Open the GitDiagram service's public URL. Sign in with user `admin` and the password in the service's `GITDIAGRAM_PASSWORD` variable (Variables tab). Paste a repository such as `https://github.com/fastapi/fastapi` and press Diagram. A first diagram takes about 10 to 60 seconds and usually costs well under one cent on the default model. Finished diagrams are saved in the bucket and open again instantly.

**Variables you might change**

* `OPENAI_MODEL`: one of the OpenAI models upstream prices (default `gpt-6-luna`; for example `gpt-5.6-terra` or `gpt-6.2-sol` for more detailed diagrams at a higher cost).
* `OPENAI_BASE_URL`: only for an OpenAI-compatible proxy that supports the Responses API and the same model names. Leave it empty for OpenAI.
* `GITHUB_PAT`: a GitHub token (no scopes needed for public repositories) to avoid GitHub's 60 requests an hour limit for anonymous calls.
* OpenRouter instead of OpenAI: set `AI_PROVIDER=openrouter`, `OPENROUTER_API_KEY` and optionally `OPENROUTER_MODEL`, and leave `OPENAI_API_KEY` empty.

**Private repositories.** In the app, open "Private Repos" and paste a GitHub token with read access; it stays in your browser and diagrams of private repositories are stored apart from public ones.

**MCP server.** GitDiagram also serves a read-only MCP endpoint at `https://YOUR-DOMAIN/mcp` behind the same login, for example `claude mcp add --transport http gitdiagram https://YOUR-DOMAIN/mcp --header "Authorization: Basic BASE64-OF-admin:PASSWORD"`.

**Left out on purpose.** Explainer videos (they need Anthropic and OpenRouter keys plus headless Chromium and far more memory), PostHog analytics, sponsor slots, the GitHub App sign-in and the operator dashboard are off.

**Resources.** It runs in 0.5 GB of RAM (about 130 MB in use while generating). The first build takes about 5 minutes.

**Updates.** Railway shows "update available" when we merge a new upstream commit into the template repo. Read `CHANGELOG.md` there before you apply it. Your diagrams stay in the bucket.

## Why Deploy GitDiagram on Railway?

<!-- Recommended: Keep this section as shown below -->
Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying GitDiagram on Railway, you are one step closer to supporting a complete full-stack application with minimal burden. Host your servers, databases, AI agents, and more on Railway.
<!-- End recommended section -->
