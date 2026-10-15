# django-template

A starter template for Django apps. It runs on Google Cloud Run in production, on
Coolify for the shared dev site, and on Docker Compose for local development.

## Tech stack

- Python 3.14
- Django 6.1
- PostgreSQL 17 (same version as the shared Cloud SQL instance)
- [uv](https://docs.astral.sh/uv/) for dependencies
- Gunicorn and WhiteNoise in production
- Ruff for linting and formatting

## Getting started

You need [Docker](https://docs.docker.com/get-docker/) installed.

1. Copy the example env file:

   ```sh
   cp .env.example .env
   ```

2. Start the app and the database:

   ```sh
   docker compose up --build
   ```

3. In a second terminal, run the migrations and make an admin user:

   ```sh
   docker compose exec web python manage.py migrate
   docker compose exec web python manage.py createsuperuser
   ```

4. Open the app:

   - Home: <http://localhost:8000/>
   - Admin: <http://localhost:8000/admin/>
   - Health check: <http://localhost:8000/health>

Your code is mounted into the container, so the dev server reloads when you
save a file.

## Common commands

All of these run inside the `web` container.

```sh
# Make migrations after you change a model
docker compose exec web python manage.py makemigrations

# Apply migrations
docker compose exec web python manage.py migrate

# Open a Django shell
docker compose exec web python manage.py shell

# Lint and format
docker compose exec web ruff check .
docker compose exec web ruff format .
```

To add a package, run `uv add <package>` and then rebuild with
`docker compose up --build`.

## Project layout

```
config/      Django settings, URLs, WSGI and ASGI entry points
accounts/    Custom User model (AUTH_USER_MODEL = accounts.User)
templates/   Project-wide templates (home.html is the placeholder home page)
scripts/     smoke-test-prod.sh: checks the prod image the way Coolify uses it
Dockerfile   Multi-stage build: "dev" for Compose, "prod" for Cloud Run and Coolify
compose.yaml Local web + Postgres services (local only, Coolify does not use it)
```

The `accounts.User` model is the same as Django's default user for now. It
exists so we can add fields later (for example for Okta or IAP login) with a
normal migration.

## Configuration

All settings come from environment variables. See `.env.example` for the full
list and notes on where each value lives on Cloud Run and on Coolify.

| Variable               | What it is                                          |
| ---------------------- | --------------------------------------------------- |
| `SECRET_KEY`           | Django secret key. Use Secret Manager on Cloud Run. |
| `DEBUG`                | `True` for local dev only. Defaults to `False`.     |
| `ALLOWED_HOSTS`        | Comma separated host names.                         |
| `CSRF_TRUSTED_ORIGINS` | Comma separated origins, with `https://`.           |
| `DB_HOST`              | Postgres host.                                      |
| `DB_PORT`              | Postgres port. Defaults to `5432`.                  |
| `DB_NAME`              | Database name.                                      |
| `DB_USER`              | Database user.                                      |
| `DB_PASSWORD`          | Database password. Local only.                      |

## Deployment

Production uses the `prod` stage of the Dockerfile and runs on Cloud Run. The
shared dev site uses the same stage on Coolify (see
[Dev on Coolify](#dev-on-coolify)).

- The image runs Gunicorn on the port Cloud Run gives it (`PORT`, which is 8080).
- Static files are collected at build time and served by WhiteNoise.
- Migrations are **not** run when the container starts. They run as a separate
  Cloud Run job. (On Coolify dev, a post-deployment command runs them.)
- `/health` is the health check. It does not touch the database and answers for any
  Host header, so Cloud Run probes are not blocked by `ALLOWED_HOSTS`.
- Database names and wiring match the shared Cloud SQL setup in
  `cru-terraform`. On Cloud Run the app is meant to log in with IAM auth
  (`DB_IAM_USER`, no password). That part is not built yet.

To build the production image locally:

```sh
docker build --target prod -t django-template .
```

## Dev on Coolify

The shared dev site runs on Coolify and redeploys on every push to `main`. This
section lists each setting and why it is set that way. Please do not change one
without reading its reason.

### Database

- A Coolify-managed **PostgreSQL 17** resource in the **same Coolify project**
  as the app. 17 matches the Postgres version used in prod.
- The app connects over the **internal hostname** with a **password**. The
  database is **not exposed to the internet**.
- Password auth is used because IAM auth is not built yet.

### Build

- Build pack: **Dockerfile**. Repo: this one. Branch: `main`.
- **Docker Build Stage Target**: `prod`. Dev then runs the same image Cloud Run
  will, so image problems show up in dev first.
- Exposed port: `8080`.
- `compose.yaml` is for local use only. Coolify does not use it.

### Health check

- Path `/health`, port `8080`.
- It does not touch the database, so a slow database cannot make Coolify restart
  the app in a loop.
- It answers for any Host header. Coolify checks the container directly, and
  `ALLOWED_HOSTS` would block that.
- Coolify runs the check by running `curl` inside the container. The `prod`
  image installs `curl` for this reason. Do not remove it. The smoke test fails
  if it goes missing.

### Migrations

- **Post-deployment command**: `python manage.py migrate --noinput`.
- It is not the pre-deployment command. That one runs in the old container,
  which cannot see the new migration files.
- The image never runs migrations when it starts. That keeps the Cloud Run
  design (migrations as a separate job) the same.

### Known tradeoff

For a few seconds after each deploy, the new code runs against the old schema,
until the post-deployment migrate finishes. This is fine for dev. **Do not copy
this setup to prod.**

### Domain

- Hostname: `django-template-dev.<your-domain>` (placeholder until the name is chosen).
- Add a DNS **A record** pointing at the Coolify server. Coolify cannot get a
  certificate until this exists.
- Coolify's proxy gets a **Let's Encrypt** certificate for it.
- `SECURE_PROXY_SSL_HEADER` is already set in the settings and works with
  Coolify's proxy, so Django knows requests came in over HTTPS. Secure cookies
  and redirects depend on this.

### Environment variables

Set these in the Coolify app's Environment Variables page.

| Variable               | Value on Coolify                                            | Why                                                       |
| ---------------------- | ----------------------------------------------------------- | --------------------------------------------------------- |
| `SECRET_KEY`           | New random value. Mark it as secret.                        | Sessions can't be forged. Don't reuse local or prod keys. |
| `DEBUG`                | `False`                                                     | The site is public. No stack traces for visitors.         |
| `ALLOWED_HOSTS`        | `django-template-dev.<your-domain>`                         | Pages load without a 400 error.                           |
| `CSRF_TRUSTED_ORIGINS` | `https://django-template-dev.<your-domain>`                 | Admin login works without a 403 error.                    |
| `DB_HOST`              | Internal hostname from the Postgres resource                | Keeps database traffic on the internal network.           |
| `DB_PORT`              | From the Postgres resource (usually `5432`)                 | Copied, not guessed.                                      |
| `DB_NAME`              | From the Postgres resource                                  | Copied, not guessed.                                      |
| `DB_USER`              | From the Postgres resource                                  | Copied, not guessed.                                      |
| `DB_PASSWORD`          | From the Postgres resource. Mark it as secret.              | Password auth for dev.                                    |

### First admin user

After the first deploy, open the app's **Terminal** in Coolify and run this once:

```sh
python manage.py createsuperuser
```

### Access rule

The dev site is public and protected only by the Django login. So **dev holds
fake data only**. If real data might ever go in, first put HTTP basic auth in
front of the site with Coolify's proxy.

### Warning for IAM auth work

When IAM database auth is built for Cloud Run, **password auth must keep
working**. If it stops, Coolify dev breaks.

### Smoke test

Run this from the repo root before you push. You need Docker running.

```sh
scripts/smoke-test-prod.sh
```

It builds the `prod` image, starts a throwaway Postgres 17, runs the same
migrate command as the post-deployment command, and runs `curl` on `/health`
inside the container, like Coolify does. It cleans up after itself and exits
non-zero with the failed step if anything breaks.

### Manual checks after the first deploy

The smoke test can't check Coolify settings, DNS or certificates. Check these by
hand:

- [ ] `https://django-template-dev.<your-domain>/` loads over HTTPS with a valid cert
- [ ] The admin page at `/admin/` shows its CSS (static files work)
- [ ] You can log in to the admin with the superuser you made
- [ ] `/health` returns `ok`, and Coolify shows the app as healthy
- [ ] A push to `main` redeploys the app and runs the migrations
