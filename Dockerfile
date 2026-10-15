# syntax=docker/dockerfile:1

# ---- base: Python + uv + project dependencies ----
FROM python:3.14-slim AS base

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PROJECT_ENVIRONMENT=/opt/venv \
    PATH="/opt/venv/bin:$PATH"

WORKDIR /app

# ---- dev: used by compose.yaml, code is mounted in ----
FROM base AS dev

RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --locked

CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]

# ---- prod: what runs on Cloud Run ----
FROM base AS prod

RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --locked --no-dev

COPY . .

# collectstatic needs settings to load, but not real values.
RUN SECRET_KEY=build DB_HOST=x DB_NAME=x DB_USER=x \
    python manage.py collectstatic --noinput

# Coolify runs its health check with curl inside the container.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --system --create-home app
USER app

# Cloud Run sets PORT (8080). Migrations run as a separate Cloud Run job, not here.
ENV PORT=8080
CMD ["sh", "-c", "exec gunicorn config.wsgi:application --bind 0.0.0.0:${PORT} --workers 2 --access-logfile -"]
