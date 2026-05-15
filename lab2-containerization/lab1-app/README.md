# Practical part — running the Lab 1 system with Docker Compose

This folder contains the **practical part** of Lab 2: a Docker Compose setup
that runs all three services of the Lab 1 system (web application, nginx
reverse proxy, PostgreSQL database) in containers.

> **Repository note.** The Lab 2 assignment states that `docker-compose.yml`
> should live in the **Lab 1 repository**, which should also be extended
> with Docker Compose run instructions. This folder is intentionally
> self-contained so it can be copied into the Lab 1 repository as-is. It is
> kept here as well so this Lab 2 repository is complete on its own.

## Contents

| File | Purpose |
|---|---|
| `docker-compose.yml` | Orchestrates the `db`, `app`, `nginx` services |
| `Dockerfile` | Builds the FastAPI application image |
| `entrypoint.sh` | Runs the DB migration, then starts the app |
| `config.toml` | Application config (DB host = `db`), mounted into the app |
| `nginx-mywebapp.conf` | Reverse proxy config, mounted into nginx |
| `.dockerignore` | Keeps the build context small |
| `app/`, `requirements.txt` | Copy of the Lab 1 application source |

## How it maps to the assignment requirements

* **Three services** — `db` (PostgreSQL), `app` (FastAPI), `nginx`.
* **Dedicated network** — all services join `mywebapp_net`, a custom bridge
  network; the default network is not used.
* **Persistent database** — PostgreSQL stores its data in the named volume
  `db_data`, which lives on disk independently of the containers.
* **Only the proxy is exposed** — only `nginx` publishes a port (`80`);
  `app` and `db` are reachable only from inside `mywebapp_net`, mirroring
  the Lab 1 rules (clients go through the reverse proxy; the database is not
  exposed outside the host).

## Run it

```bash
# from this folder
docker compose up --build -d

# watch it come up
docker compose ps
docker compose logs -f app
```

The system is then available through nginx:

```bash
curl -i -H "Accept: text/html" http://localhost/
curl -X POST -H "Content-Type: application/json" \
     -d '{"name":"Drill","quantity":5}' http://localhost/items
curl http://localhost/items
curl http://localhost/items/1

# /health/* is hidden by nginx, as in Lab 1
curl -o /dev/null -w "%{http_code}\n" http://localhost/health/alive   # 404
```

Stop it:

```bash
docker compose down            # stops & removes containers, KEEPS db_data
docker compose down -v         # also removes the db_data volume (wipes the DB)
```

## Verifying database persistence

The assignment requires the database to survive container restarts,
`docker` removal, and host reboots. To check:

```bash
# 1. create some data
curl -X POST -H "Content-Type: application/json" \
     -d '{"name":"Hammer","quantity":3}' http://localhost/items

# 2. fully stop and remove the containers (the volume stays)
docker compose down

# 3. bring the system back up
docker compose up -d

# 4. the data is still there
curl http://localhost/items
```

The data is stored in the named volume `db_data` (`docker volume ls`), which
is only deleted by an explicit `docker compose down -v` or
`docker volume rm`. Container restarts and host reboots do not touch it.

## Viewing the nginx request log

nginx writes the access log inside its container:

```bash
docker compose exec nginx tail -f /var/log/nginx/mywebapp_access.log
```

## Notes

* `entrypoint.sh` runs the database migration before starting the app — the
  same ordering as the Lab 1 systemd unit's `ExecStartPre`. `app` also waits
  for the `db` healthcheck to pass before it starts.
* The database password is kept in plain text in `config.toml` and, matching,
  in the `db` service environment. For a lab this is fine; in production use
  Docker secrets or an `.env` file.
