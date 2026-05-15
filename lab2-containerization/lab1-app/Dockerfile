# Dockerfile for the Lab 1 web application (mywebapp — Simple Inventory).
#
# Built and orchestrated by docker-compose.yml together with PostgreSQL and
# an nginx reverse proxy.
#
# Layers are ordered by change frequency (base -> dependencies -> code) so
# that editing application code does not invalidate the dependency layer.
# `psycopg[binary]` ships a prebuilt wheel, so no C toolchain or libpq-dev
# is needed and the slim base is enough.

FROM python:3.13-slim

WORKDIR /opt/mywebapp

# --- Rarely changes: dependencies -----------------------------------------
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# --- Often changes: application code --------------------------------------
COPY app/ app/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Run as an unprivileged system user (mirrors the "app" user from Lab 1).
RUN useradd --system --no-create-home --shell /usr/sbin/nologin appuser
USER appuser

EXPOSE 5200

ENTRYPOINT ["/entrypoint.sh"]
