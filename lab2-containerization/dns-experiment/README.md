# musl (Alpine) vs glibc (Debian/Ubuntu) — DNS resolution experiment

This experiment compares how the C library's resolver behaves when a
**search domain** is involved: glibc (used by Ubuntu/Debian) versus musl
(used by Alpine). The empirical core is the DNS server log — it shows
exactly which queries each container actually sent.

## Reproduce

> The commands below are a cleaned-up version of the ones in the assignment
> (the assignment text contains copy-paste artefacts — en-dashes instead of
> `--`). Run each numbered block in its own terminal.

**1. Create an isolated Docker network:**

```bash
docker network create dns-lab
```

**2. Start a DNS server that resolves one custom domain:**

```bash
docker run --rm -it --name dns-server --network dns-lab \
  alpine sh -c "apk add dnsmasq && \
  echo 'address=/myservice.internal.corp/10.0.0.50' > /etc/dnsmasq.conf && \
  dnsmasq -k --log-queries --log-facility=-"
```

Leave this running — its stdout is the query log you will analyse.
Note the configured record: the FQDN `myservice.internal.corp` → `10.0.0.50`.

**3. From a glibc container (Ubuntu), resolve the short name:**

```bash
docker run --rm --network dns-lab \
  --dns=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' dns-server) \
  --dns-search="corp" \
  ubuntu:latest getent hosts myservice.internal
```

**4. From a musl container (Alpine), the same lookup:**

```bash
docker run --rm --network dns-lab \
  --dns=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' dns-server) \
  --dns-search="corp" \
  alpine:latest getent hosts myservice.internal
```

The short name `myservice.internal` only matches the configured record
**if** the resolver appends the `corp` search domain →
`myservice.internal.corp`.

## What to record for the report

For steps 3 and 4 capture:

* the **stdout** of `getent hosts` (an address line, or empty),
* the process **exit code** (`echo $?` right after — `0` = found, `2` = not found),
* the corresponding lines in the **dns-server log** from step 2 — i.e. which
  exact query name(s) each container sent (`myservice.internal`,
  `myservice.internal.corp`, both, or neither).

## Cleanup

```bash
docker network rm dns-lab
```

## Background for the analysis

glibc and musl implement the stub resolver independently, and they differ
in several behaviours relevant here:

* **Search-domain handling.** glibc reads `search`/`domain` from
  `resolv.conf` and, governed by the `ndots` option (default `1`), decides
  whether to try the name as-is, with the search domains appended, or both —
  and in which order. musl's resolver handles the search list differently
  and does **not** honour the `ndots` option the way glibc does.
* **Querying multiple nameservers.** glibc queries the nameservers
  sequentially; musl queries them in parallel and takes the first answer.
* **NSS configurability.** glibc routes `getent hosts` through
  `/etc/nsswitch.conf` (the `hosts:` line), so the lookup path is
  configurable. musl has no `nsswitch.conf` — it uses a fixed
  files-then-dns order.
* **TCP fallback for large responses.** older musl versions had limited
  fallback to TCP for responses that do not fit in a UDP packet.

The point of the experiment is to *observe* which queries each libc emits
(from the DNS server log), match that to the behaviours above, explain why
the two containers do or do not resolve the name, and — as the assignment
asks — note in the conclusions what this difference can lead to in a real
system that mixes Alpine- and Debian-based images.
