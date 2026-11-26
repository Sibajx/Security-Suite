# 🩺 security-suite

**English** · [Español](README.md)

**A security suite for Claude Code that reviews your project end to end: code, secrets, dependencies and the live
site.** It audits the code, hunts for secrets (including git history), checks dependencies, tests the running app
and runs **authorized** pentests. It ends with a diagnosis: verdict, score and the best fixes for your stack, with
ready-to-use code.

> The skill, its agents and its reports are written in Spanish. Claude answers in your language, but report
> headings and check names stay in Spanish.

```
/security-suite
 ├─ Phase 0  Intake ───────── which project, which mode, is the site yours?, test accounts
 ├─ Phase 1  Triage ───────── recon + gitleaks + .env history + semgrep + pip-audit + npm audit + live check
 ├─ Phase 2  3 auditors ───── infra-secrets · access (auth, IDOR, rate limit, spend) · inputs (SQLi, XSS, uploads…)
 ├─ Phase 3  Pentester ────── confirms live with curl / sqlmap / nuclei / ffuf, within rules of engagement
 ├─ Phase 4  Verifier ─────── tries to disprove every serious finding (zero false positives)
 └─ Phase 5  Diagnosis ────── 🔴/🟠/🟢 · X/20 checks · what's urgent · treatment with templates
```

## What it checks

The **20 checks** in [`SecurityChecks.md`](skills/security-suite/SecurityChecks.md), each with a fixed severity,
plus senior-level extras:

| Secrets | Access | Inputs | Infra | Extras |
|---|---|---|---|---|
| 1 hidden API keys · 2 env vars · 3 keys in git (history) | 4 admin route · 5 auth · 6 permissions/IDOR · 10 DB rules · 11 rate limiting · 12 spend cap | 7 validation · 8 XSS · 9 SQL injection · 13 uploads · 14 CSRF · 15 CORS · 18 cookies | 16 HTTPS · 17 headers · 19 debug · 20 production config | SSRF · deserialization/RCE · path traversal · business logic · CI/CD · logging and monitoring · subdomains · email/DNS · Cloudflare Access policies · **payment webhooks** · **chatbots and LLMs** · **ransomware-proof backups** |

## Install

**As a Claude Code plugin** (recommended):
```
/plugin marketplace add Sibajx/Security-Suite
/plugin install security-suite@security-suite
```

**As a standalone skill** (Claude Code and other compatible agents):
```bash
git clone https://github.com/Sibajx/Security-Suite.git ~/security-suite
ln -s ~/security-suite/skills/security-suite ~/.claude/skills/security-suite
```

**Tools** (Linux/macOS, no sudo, into `~/.local/bin`; binaries are verified by SHA-256; requires `uv`):
```bash
bash skills/security-suite/scripts/instalar-herramientas.sh           # install what's missing
bash skills/security-suite/scripts/instalar-herramientas.sh --revisar # check only
```
gitleaks · semgrep · pip-audit · sqlmap · nuclei · ffuf, plus `dig` and `jq`. Schemathesis and Playwright run through
`uvx` (no install; Playwright needs `uvx --with playwright playwright install chromium` once). If a tool is missing,
the suite carries on and notes it in the report.

## Usage

In Claude Code, inside your project:

- *"review the security of this project"* → code audit
- *"pentest http://localhost:8000, it's mine"* → live testing
- *"full diagnosis before deploying, staging is at …"* → everything
- *"quick review, I built the app with Lovable"* → `rapido-ia` mode: the 15 typical attacks on an AI-built app, ordered
  by damage (open Supabase/Firebase database, keys in the bundle, IDOR, editable price, fake webhook, parallel coupon,
  OTP brute force, chatbot injection…), scored X/15. See [`rapido-app-ia.md`](skills/security-suite/rapido-app-ia.md)
- *"I fixed it, check again"* → re-verification of every finding

Reports are saved **on your desktop**, outside any repo (change it with `SECURITY_SUITE_REPORTES`):
```
Desktop/Reportes-securitysuite/
├── INDICE.md                      ← traffic light for all your sites
├── VIGIA.md                       ← changes since the last weekly check
├── mydomain_com_RSS/              ← RSS = Reporte Security Suite
│   └── 2026-11-09_2255/
│       ├── DIAGNOSTICO.md
│       └── evidencia/             ← scans, live checks, nuclei, sqlmap…
└── my-project_RSS/…
```
Each run adds a new date, so you can see whether the site improved.

### Bundled pentest tools (`skills/security-suite/scripts/`)

| Script | Purpose | Level |
|---|---|---|
| `en-vivo.sh` | HTTPS, headers, cookies, exposed files; with `CF_ACCESS_CLIENT_ID/SECRET` it gets behind Cloudflare Access | 1 |
| `subdominios.sh` | Subdomains (Certificate Transparency + 92 common names), DNS wildcard, subdomain takeover | 1 |
| `correo-dns.sh` | SPF, DMARC, DKIM, CAA, DNSSEC: can someone send fake mail "from" your domain? | 1 |
| `jwt-revisar.py` | `alg=none`, weak key (offline), no `exp`, tampered token accepted | 1–2 |
| `matriz-permisos.py` | Every route × every role: IDOR/BOLA, open admin, unauthenticated routes (template generated from OpenAPI) | 2 |
| `carrera.py` | Race conditions: N simultaneous requests to a redeem/coupon/payment | 3 |
| `grabar-flujo.py` + `flujo.py` | Records a flow with Playwright and tries skipping steps, repeating the last one, starting midway | 3 |
| `fuzz-api.sh` | API fuzzing from its OpenAPI (Schemathesis); local/staging only | 3 |
| `webhook-falso.py` | Sends your payment webhook an unsigned event and one with a forged signature (Stripe, Mercado Pago, PayPal): does it mark the order paid? | 3 |
| `chatbot-inyeccion.py` | 8 harmless messages to your chatbot: system prompt leak, another user's data, raw HTML, image exfiltration | 2 |
| `revisar-access.py` | Cloudflare Access policies that actually let anyone in (Include with PIN, Everyone, gmail.com…) | 0 (reads config) |
| `reverificar.py` | After fixing: re-runs each finding's reproduction (`evidencia/repro/`) and builds a before → now table | the repro's |
| `vigia.sh` + `instalar-vigia.sh` | Passive weekly check of all your sites and a note of what changed (`VIGIA.md`) | 1 |

Every confirmed finding leaves a script in `evidencia/repro/<ID>.sh|.py` (exit 0 = fixed, 1 = still open,
2 = couldn't test; examples in [`plantillas/repro/`](skills/security-suite/plantillas/repro/)). When you say
"I fixed it", the suite runs `reverificar.py` against the new version. Runner test: `bash tests/probar-reverificar.sh`.

For a repo: [`plantillas/vigia-github-actions.yml`](skills/security-suite/plantillas/vigia-github-actions.yml)
runs gitleaks, a dependency audit and the passive check every Monday, and opens an issue if something gets worse.

## Rules of engagement and levels

Before any live test the suite shows a **level menu** and you choose:

| Level | What it does | What it leaves behind |
|---|---|---|
| 1 · Passive review | HTTPS, headers, cookies, exposed paths: the same as a browser | nothing |
| 2 · Confirmation | tests each finding with harmless payloads (SQLi without extraction, IDOR between test accounts, CORS, rate limit, nuclei) | test sessions |
| 3 · Controlled attack | + discovery with ffuf, `pentest-*` accounts, role escalation, uploading a .txt, CSRF, SSRF to the same host | `pentest-*` accounts/files (deleted afterwards) |

Your domains go in `~/.config/security-suite/autorizados.yml` with the highest level you allow (example in
[`autorizados.ejemplo.yml`](skills/security-suite/autorizados.ejemplo.yml)); that file is personal and stays out of the repo.

Pentesting is done **only** against your own sites or with the owner's written authorization. Before any live test
the suite asks and records it in the report. In production only the passive level is allowed unless you explicitly
approve more; never DoS, data extraction or shells. Details in
[`reglas-de-enfrentamiento.md`](skills/security-suite/reglas-de-enfrentamiento.md).

### Responsible use

Using the suite against systems you don't own, or without the owner's **written** permission, may be a crime where
you live. You are responsible for how you use it. It is provided "as is", without warranty (see [`LICENSE`](LICENSE)).
The authors are not liable for damage, downtime or data loss caused by live tests; that's why the default level is
passive and production requires a backup before any level that writes.

Found a vulnerability in the suite itself? See [`SECURITY.md`](SECURITY.md).

The agents **never modify** your project. Fixes are made by the main session, with your OK, and then it audits again.

## Bundled treatment

[`mejores-practicas.md`](skills/security-suite/mejores-practicas.md) and [`plantillas/`](skills/security-suite/plantillas):
- hardening module for FastAPI (argon2, slowapi with real IP behind Cloudflare, `__Host-` cookies,
  headers + CSP, strict CORS, errors without tracebacks, settings that fail without secrets);
- GitHub Actions workflow (gitleaks + semgrep + dependency audit);
- pre-commit with gitleaks, Dependabot, `.dockerignore`, non-root Dockerfile, `_headers` for Cloudflare, `security.txt`.

## Tests

Sample output: [`docs/ejemplo-diagnostico.md`](docs/ejemplo-diagnostico.md).

`tests/` generates a FastAPI app with **31 planted flaws and 6 traps** plus an answer sheet, to measure the suite
or compare models. See [`tests/README.md`](tests/README.md).

## Credits

The OWASP references in `skills/security-suite/owasp/` come from
[getsentry/skills](https://github.com/getsentry/skills) (Apache 2.0), derived from the
[OWASP Cheat Sheet Series](https://cheatsheetseries.owasp.org/). See `NOTICE`. Everything else is MIT licensed.

> ⚠️ No tool guarantees that a site is secure. The suite lowers the risk and tells you what it checked and what it
> left out; the final decisions are yours.
