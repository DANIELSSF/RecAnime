# RecAnime runbook

From an empty account to two people using the apps, and everything you do afterwards. Every command
runs from the repository root. Nothing here is automated: each step is something only you can do
(browser, billing, an Apple ID), and the scripts do the rest.

Preview any `infra/gcp` script before it changes anything by prefixing `DRY_RUN=1` — it prints the
exact gcloud commands and executes none of them.

---

## 1. Accounts and regions

| Thing | Value |
|---|---|
| Google account | your personal one; **never** the work account |
| gcloud configuration | `recanime` (already exists on this Mac, account set, project empty) |
| GCP region | `us-east1` (`GCP_REGION`) |
| Supabase region | **East US (North Virginia)** — must match, the API talks to the database on every request |
| iOS bundle id | `com.danielsantiago.recanime` |

Every script exports `CLOUDSDK_ACTIVE_CONFIG_NAME=recanime` and refuses to run unless that
configuration is signed in as `GCP_ACCOUNT`, so the work account cannot be used by accident.

```sh
gcloud config configurations describe recanime   # read-only, check the account
```

---

## 2. Supabase project

1. <https://supabase.com/dashboard> → **New project**, region **East US**, save the database
   password somewhere safe (you cannot read it again, only reset it).
2. Settings → API. Note:
   - `SUPABASE_PROJECT_REF` — the `<ref>` in `https://<ref>.supabase.co`
   - `SUPABASE_URL` — `https://<ref>.supabase.co`
   - the **publishable** key (`sb_publishable_…`). Never the secret/service-role key: it goes in the
     app bundle.
3. Database → **Connect** → **Session pooler** (Supavisor, port **5432**). Copy that string, put the
   password in, and append `?sslmode=require`. This is `DATABASE_URL` for Cloud Run:

   ```
   postgres://postgres.<ref>:<password>@aws-0-us-east-1.pooler.supabase.com:5432/postgres?sslmode=require
   ```

   Two reasons it must be the *session* pooler and not the direct host or port 6543:
   - the direct database host is IPv6-only on the free tier and Cloud Run has no IPv6 egress; the
     session pooler is reachable over IPv4;
   - the API sets `DB_SESSION_LOCK=true` (advisory locks around migrations), which needs session
     mode. Port 6543 is transaction mode and would break it.
4. Authentication → Sign In / Providers → **Google**: enable it, paste the **Web** client id and
   client secret from step 3 below, and add **both** the iOS and the Web client id to
   *Authorized Client IDs* (comma separated). The app signs in natively with the Google SDK, so the
   id token Supabase receives carries the iOS audience; the Web client is what Supabase itself uses.
   No redirect URLs are needed — there is no web callback.
5. Free projects **pause after 7 days without database activity**. The `keep-alive` GitHub workflow
   pings `/readyz` (which runs `SELECT 1`) every 3 days; it only works once step 6 is done.

---

## 3. Google OAuth clients

Google Cloud Console → APIs & Services, inside the RecAnime GCP project (create the project first,
step 4, or create the clients afterwards and come back).

1. **OAuth consent screen**: External, app name RecAnime, your email as support and developer
   contact. Publishing status stays *Testing* → add both users under **Test users**. In testing mode
   a refresh token expires after 7 days, which is fine: the app signs in again silently.
2. **Credentials → Create credentials → OAuth client ID → iOS**
   - Bundle ID: `com.danielsantiago.recanime`
   - Note `GOOGLE_IOS_CLIENT_ID` and the **reversed client id**
     (`com.googleusercontent.apps.<…>`) → `GOOGLE_REVERSED_CLIENT_ID`.
3. **Credentials → Create credentials → OAuth client ID → Web application**
   - Note `GOOGLE_WEB_CLIENT_ID` and its **client secret** → both go into Supabase (step 2.4);
     the client id also goes into `Secrets.xcconfig` as `GIDServerClientID`.

---

## 4. GCP project

```sh
gcloud projects create recanime-<suffix> --name RecAnime --configuration=recanime
gcloud billing accounts list                                    # copy the ACCOUNT_ID
gcloud billing projects link recanime-<suffix> --billing-account <ACCOUNT_ID>
gcloud config set project recanime-<suffix> --configuration=recanime
```

Billing must be linked before the next step: Cloud Run, Cloud Build and Artifact Registry all
require it. Usage at two users stays inside the always-free tiers (see step 9).

Then fill in the deploy environment:

```sh
cp infra/gcp/.env.deploy.example infra/gcp/.env.deploy
$EDITOR infra/gcp/.env.deploy      # GCP_ACCOUNT, GCP_PROJECT, SUPABASE_PROJECT_REF, AUTH_ALLOWED_EMAILS
```

`infra/gcp/.env.deploy` is gitignored. `GCP_ACCOUNT` has no default on purpose.

---

## 5. Bootstrap (once)

Enables the APIs, creates the runtime service account, the Artifact Registry repository with its
cleanup policy, the `recanime-database-url` secret and the two IAM bindings.

```sh
set -a; . infra/gcp/.env.deploy; set +a
DATABASE_URL='<session pooler url from step 2.3>' DRY_RUN=1 sh infra/gcp/bootstrap.sh   # preview
DATABASE_URL='<session pooler url from step 2.3>' sh infra/gcp/bootstrap.sh
```

The connection string is passed on stdin, never on a command line. The script warns (but continues)
if the URL is not a `pooler.supabase.com:5432` one or has no `sslmode=require`. It is idempotent:
re-running it adds a new secret version and leaves everything else alone.

---

## 6. Deploy

```sh
set -a; . infra/gcp/.env.deploy; set +a
DRY_RUN=1 sh infra/gcp/deploy.sh    # preview
sh infra/gcp/deploy.sh              # or: make deploy-api
```

What it does: refuses a dirty working tree (`ALLOW_DIRTY=1` overrides), builds
`services/api` through `services/api/cloudbuild.yaml` with `--build-arg VERSION=<git sha>`, pushes
`…/recanime/api:<sha>` and `:latest`, deploys the `:<sha>` tag (never `:latest`), then **verifies that
`/healthz` reports the same sha** and prints `/readyz`. A mismatch exits 1 with a rollback hint.

The first deploy applies the migrations itself (`DB_MIGRATE_ON_START=true`).

If the build step fails with a permissions error, it is the Cloud Build service account: builds run
as `<projectNumber>-compute@developer.gserviceaccount.com`, which `bootstrap.sh` grants
`roles/artifactregistry.writer` (on the repository) and `roles/logging.logWriter` (on the project;
projects created since 2024 no longer give that account `roles/editor`). Re-run `bootstrap.sh` (it is
idempotent), then check with:

```sh
gcloud projects get-iam-policy <project> --flatten bindings --filter 'bindings.members:compute@' --format 'value(bindings.role)'
```

Two follow-ups the script prints:

1. GitHub → **Settings → Secrets and variables → Actions → Variables** → New variable
   `API_BASE_URL` = the printed URL. Then Actions → `keep-alive` → **Run workflow** once to confirm
   it is green. (Your `gh` CLI is signed into the work account — do this in the browser.)
   Until the variable exists the workflow **fails** rather than silently skipping.
2. `apple/Configs/Secrets.xcconfig`: `API_BASE_URL_RELEASE = <printed value>` (the script prints it
   already escaped as `https:/$()/…`, because `//` starts a comment in an xcconfig).

---

## 7. Apps

```sh
cp apple/Configs/Secrets.xcconfig.example apple/Configs/Secrets.xcconfig
cp apple/Configs/Local.xcconfig.example  apple/Configs/Local.xcconfig
```

`Secrets.xcconfig` — all six keys: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`,
`GOOGLE_IOS_CLIENT_ID`, `GOOGLE_WEB_CLIENT_ID`, `GOOGLE_REVERSED_CLIENT_ID`,
`API_BASE_URL_RELEASE`.
`Local.xcconfig` — `DEVELOPMENT_TEAM`, the 10-character Personal Team id from
Xcode › Settings › Accounts.

```sh
make apple-gen        # or pnpm apple:gen
open apple/RecAnime.xcodeproj
```

For the sideload the build must use the **Release** configuration, which is the only one that reads
`API_BASE_URL_RELEASE`: Xcode → Product → Scheme → Edit Scheme → **Run** → Info → Build
Configuration → **Release**. Do the same for the `RecAnimeWatch` scheme.

If `API_BASE_URL_RELEASE` is missing the app opens on “Configuración incompleta” and names what is
missing, instead of falling back to `localhost` and failing with “Sin conexión”.

Then: iPhone and Watch → Settings › Privacy & Security › **Developer Mode** on; run the `RecAnime`
scheme on the iPhone over a cable, trust the developer under Settings › General › VPN & Device
Management, then run `RecAnimeWatch` on the paired Watch.

Free Apple ID limits: builds expire after **7 days** (re-run from Xcode), at most **3** sideloaded
apps per device, **10 App IDs per week** — never rename a bundle id casually. No push notifications
and no TestFlight; the app uses local notifications only.

---

## 8. Second user

```sh
set -a; . infra/gcp/.env.deploy; set +a
sh infra/gcp/allowlist.sh 'you@example.com,them@example.com'   # the full list, not just the new one
```

That updates `AUTH_ALLOWED_EMAILS` on the running service (new revision, no rebuild, a few seconds).
Also add the address as a **Test user** on the OAuth consent screen (step 3.1), otherwise Google
refuses the sign-in before Supabase ever sees it. Then sideload the app on their phone from your Mac
and they sign in with Google.

Keep `infra/gcp/.env.deploy` in sync so the next `deploy.sh` does not revert the list.

---

## 9. Day-2 operations

### Logs

Cloud Console → Logging → Logs Explorer:

```
resource.type="cloud_run_revision" AND jsonPayload.requestId!=""
```

`resource.labels.service_name="recanime-api"` narrows it further, and `severity>=ERROR` shows only
failures.

**What a Jikan rate-limit storm looks like**: responses keep coming with `X-Cache: STALE` and a
`meta.upstreamError: "rate_limited"` field — the API is serving the 12 h cache past its TTL because
upstream returned 429. Nothing to do; it recovers on its own. If it is permanent, check
`JIKAN_RPS`/`JIKAN_RPM`.

### Supabase paused

The API keeps answering `/healthz` (no database) and starts failing `/readyz`. Restore the project
from the Supabase dashboard; the API reconnects by itself, no redeploy. Then check why the
`keep-alive` workflow stopped running.

### Rotate the Supabase publishable key

Supabase → Settings → API → new publishable key → `apple/Configs/Secrets.xcconfig` → rebuild and
re-sideload both apps. Nothing server-side changes.

### Rotate the database password

```sh
set -a; . infra/gcp/.env.deploy; set +a
DATABASE_URL='<new session pooler url>' sh infra/gcp/bootstrap.sh   # adds a secret version
sh infra/gcp/deploy.sh                                             # required
```

The redeploy is not optional: `--set-secrets …:latest` resolves the version **when the revision is
created**, so a running revision keeps the old password until a new revision exists.

### Rollback

```sh
sh infra/gcp/rollback.sh                          # list revisions with the sha each one carries
sh infra/gcp/rollback.sh recanime-api-00007-abc   # 100% of traffic back to it
```

Instant, no rebuild. It does **not** undo a migration — the schema is already migrated — but the
migrations are additive, so an older revision keeps working.

### Backups

The only irreplaceable data is `recanime.app_user`, `recanime.user_settings` and
`recanime.library_entry`; everything else is a Jikan cache that rebuilds itself.

```sh
DATABASE_URL='<session pooler url>' make db-backup      # backups/recanime-<UTC>.dump
CONFIRM=yes DATABASE_URL='<url>' make db-restore FILE=backups/recanime-20260905T101500Z.dump
```

Run a backup **before every migration**. `backups/` is gitignored. The scripts use the local
`pg_dump`/`pg_restore` when they are version 17+, otherwise `postgres:17-alpine` in Docker (the
connection string is passed as an environment variable, never on a command line).

Restoring needs the schema to exist already (start the API once, or
`cd services/api && go run ./cmd/api migrate up`) and the three tables to be empty. `restore.sh`
passes `--exit-on-error`, so a partial restore fails loudly instead of pg_restore's default
"errors ignored" with exit 0.

`--disable-triggers` is on by default and is normally required: `library_entry.mal_id` references
`recanime.anime`, the Jikan cache, which is deliberately *not* in the dump — with foreign keys
enforced, every library row is rejected. Disabling triggers needs a superuser, which the local
Docker database has. If the `postgres` role on Supabase refuses it, drop the constraint around the
restore and let the app refill the cache:

```sql
ALTER TABLE recanime.library_entry DROP CONSTRAINT library_entry_mal_id_fkey;
-- DISABLE_TRIGGERS=0 CONFIRM=yes sh infra/db/restore.sh <file>
-- then open the app so it re-caches every anime, and put the constraint back:
ALTER TABLE recanime.library_entry
  ADD CONSTRAINT library_entry_mal_id_fkey FOREIGN KEY (mal_id) REFERENCES recanime.anime(mal_id);
```

### Cost

At two users everything stays inside the always-free tiers: Cloud Run scales to zero
(`--min-instances 0`, `--max-instances 1`, 256 MiB), Cloud Build has free build-minutes, and the
Artifact Registry cleanup policy (`infra/gcp/ar-cleanup-policy.json`) keeps the 5 most recent image
versions and deletes untagged ones older than 30 days, so storage does not creep. The Supabase free
tier covers the database. Set a **budget alert** on the billing account anyway.

### The 7-day rebuild

The free Apple ID signs builds for 7 days. When the app refuses to launch, plug the iPhone in and
run the Release scheme from Xcode again (and the Watch scheme for the Watch). Nothing server-side is
involved.

### Known limitations

Two accepted gaps, both harmless today but worth knowing before the repository or the sign-in flow
changes hands.

**The maintainer's personal email is in the public git history.** Every commit since the first one
is authored with it, so it is readable by anyone who clones the repository. Removing it means
rewriting the whole history (`git filter-repo --mailmap`) and force-pushing, which invalidates every
existing clone and every commit SHA — including the ones `/healthz` reports and `rollback.sh` lists.
The decision is the owner's; nothing in the app depends on it either way.

**Google sign-in runs without a nonce.** The iOS app exchanges the Google ID token for a Supabase
session without binding the token to a one-time value, so a token captured elsewhere for the same
client id could in principle be replayed. The allowlist (`AUTH_ALLOWED_EMAILS`) still limits the
blast radius to the two accounts that are allowed in at all. Adding the nonce is a four-step change,
deliberately left until there is a live Supabase project to verify it against, because GoTrue
rejects the whole sign-in when the two halves do not match:

1. Generate a random raw nonce per sign-in attempt (32 bytes, base64url).
2. Pass its SHA-256 **hex** digest to `GIDSignIn.signIn(withPresenting:hint:additionalScopes:nonce:)`.
3. Pass the **raw** nonce to `OpenIDConnectCredentials(nonce:)` alongside the id token.
4. Verify against a real project that GoTrue accepts it — sign in, and confirm a session comes back
   instead of an "invalid nonce" error — before shipping the build.

---

## 10. Checklist

- [ ] Supabase project created in East US; ref, URL and publishable key noted
- [ ] Session-pooler `DATABASE_URL` (port 5432, `sslmode=require`) copied
- [ ] Supabase Google provider enabled with the Web client id + secret and both client ids allowed
- [ ] GCP project created, billing linked, `gcloud config set project … --configuration=recanime`
- [ ] OAuth consent screen (External, Testing) with both emails as test users
- [ ] iOS and Web OAuth clients created; ids and reversed id noted
- [ ] `infra/gcp/.env.deploy` filled in
- [ ] `sh infra/gcp/bootstrap.sh` run once
- [ ] `sh infra/gcp/deploy.sh` green, `/healthz` version == git sha
- [ ] GitHub repository variable `API_BASE_URL` set; `keep-alive` run once and green
- [ ] `apple/Configs/Secrets.xcconfig` and `Local.xcconfig` filled in
- [ ] Both schemes set to the Release configuration; app running on the iPhone and the Watch
- [ ] Second user added to `AUTH_ALLOWED_EMAILS` and to the OAuth test users
- [ ] First `make db-backup` taken
