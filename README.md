# evergreen-testing-docker (etd)

This project runs an Evergreen ILS development server in Docker. It builds
Evergreen and OpenSRF from source on Debian bookworm, ships the concerto
sample data inside the database image and writes an Aspen Discovery export
on every start. It is the Evergreen counterpart of koha-testing-docker.
Aspen dev boxes and sandboxes connect to it over a Docker network.

## Requirements

- Docker Engine and Docker Compose v2
- About 8 GB of free disk for the images
- About 2.5 GB of free RAM for a running stack, or 1 GB with `EG_SERVICES=minimal`
- A lot more disk and RAM if you build the images yourself

## Quick start

```shell
git clone <this repository> evergreen-testing-docker
cd evergreen-testing-docker
cp .env.example .env
bin/etd up -d
bin/etd logs -f
```

The database image already holds the sample data, so the stack is ready in
about a minute. Wait for this line:

```
etd: evergreen is ready
```

Then open:

- OPAC: http://localhost:8086/eg/opac/home
- Staff client: http://localhost:8086/eg2/en-US/staff/
- Gateway: http://localhost:8086/osrf-gateway-v1
- HTTPS: https://localhost:8446/eg/opac/home (self signed certificate)

The `db-data` volume survives `bin/etd down`, so anything you change in
the database is still there on the next start.

## Logins

| What | User | Password |
|---|---|---|
| Evergreen staff | `admin` | `demo123` |
| Evergreen patron | barcode `99999373998` | `demo123` |
| PostgreSQL | `evergreen` | `evergreen` |

Every sample user has the password `demo123`. To find more patron
barcodes:

```shell
bin/etd psql -c "SELECT c.barcode FROM actor.usr u JOIN actor.card c ON c.id = u.card WHERE u.expire_date > now() AND NOT u.deleted AND u.active LIMIT 10"
```

## Sample data

The sample data is loaded into the database image when the image is built.
Nothing is loaded at start time.

`EG_SAMPLE_DATA` picks the dataset. It is a build argument, so set it and
run `bin/etd build` to get a different one. The published image carries the
default.

| Value | What you get |
|---|---|
| `concerto_enhanced` | The enhanced concerto set, the default |
| `concerto` | The plain concerto set |
| `none` | An empty Evergreen database |

The `db-data` volume holds the live database. Docker fills an empty volume
from the image the first time the stack runs. To throw your changes away
and go back to the data in the image:

```shell
bin/etd down -v
bin/etd up -d
```

That takes about a minute.

## Services

Evergreen starts 33 OpenSRF services by default. Most of them are only used
by the staff client, and each one costs about 110 MB. `EG_SERVICES` picks how
many run. It is read at start time, so a `bin/etd stop` and `bin/etd start`
is enough to change it.

| Value | Services | Idle memory |
|---|---|---|
| `full` | 33, the default | about 2.1 GB |
| `minimal` | 14 | about 1.2 GB |

```shell
EG_SERVICES=minimal bin/etd up -d
```

`minimal` keeps everything the OPAC, the gateway and the Aspen export use:
`opensrf.settings`, `open-ils.actor`, `circ`, `search`, `supercat`, `cstore`,
`pcrud`, `storage`, `fielder`, `trigger`, `hold-targeter`, `auth`,
`auth_internal` and `auth_mfa`.

It drops acquisitions, serials, booking, reports, vandelay, SIP2, course
reserves, curbside, the link checker and the collections agency, so those
parts of the staff client stop working. The OPAC also loses its SMS
call-number feature, the reservations page, geographic sorting and compressed
serial holdings.

## Connecting Aspen

An Aspen dev box joins the `egdev_egnet` network with
`adb up --ils evergreen` and copies the export out of the Evergreen
container from `/exports/aspen`. The export holds `marc/all_bibs.mrc`,
`marc/large_bibs.xml`, `marc_delta/all_bib.ids` and the three files under
`supplemental/`. See the adb docs for the Aspen side.

## Commands

| Command | What it does |
|---|---|
| `bin/etd up [-d]` | Start the stack |
| `bin/etd down [-v]` | Remove the stack, `-v` also drops the database |
| `bin/etd stop` | Stop the containers |
| `bin/etd start` | Start stopped containers |
| `bin/etd logs [-f]` | Show the Evergreen container logs |
| `bin/etd shell` | Bash in the Evergreen container as `opensrf` |
| `bin/etd psql` | psql in the database container |
| `bin/etd export` | Regenerate the Aspen export |
| `bin/etd build` | Build the images from this repository |
| `bin/etd pull` | Pull the published images |
| `bin/etd push` | Push the built images |
| `bin/etd status` | Show the container status |

## Environment variables

Copy `.env.example` to `.env` and edit it. `.env` is not tracked.

| Variable | Default | What it does |
|---|---|---|
| `COMPOSE_PROJECT_NAME` | `egdev` | Compose project, so containers are `egdev-evergreen-1` and `egdev-db-1` |
| `ETD_IMAGE` | `git.homeserv.uk/jacobomara901/evergreen-testing` | Evergreen image |
| `ETD_DB_IMAGE` | `git.homeserv.uk/jacobomara901/evergreen-testing-db` | Database image |
| `ETD_TAG` | `latest` | Tag for both images |
| `EG_HTTP_PORT` | `8086` | Host port for Apache on 80 |
| `EG_HTTPS_PORT` | `8446` | Host port for Apache on 443 |
| `EG_PSQL_PORT` | `5433` | Host port for PostgreSQL on 5432 |
| `EG_SAMPLE_DATA` | `concerto_enhanced` | Sample data baked into the database image |
| `EG_SERVICES` | `full` | `full` starts 33 OpenSRF services, `minimal` starts 14 |
| `EG_REPO` | Evergreen on GitHub | Evergreen git remote |
| `EG_REF` | `rel_3_17` | Evergreen branch or tag |
| `OSRF_REPO` | OpenSRF on GitHub | OpenSRF git remote |
| `OSRF_REF` | `main` | OpenSRF branch or tag |
| `EG_STAFF_CLIENT` | `1` | Build the web staff client, `0` skips it |

## Building and publishing

```shell
bin/etd build
bin/etd push
```

One `Dockerfile` builds both images. The `base` stage holds Debian,
OpenSRF, Evergreen and their dependencies. The `app` stage adds the Apache
and OpenSRF configuration and the scripts. The `loader` stage loads the
sample data into a PostgreSQL cluster and the `db` stage copies that
cluster into the published database image. The data load only runs again
when the Evergreen source or its dependencies change, so editing the
entrypoint or the Apache settings rebuilds the app image in seconds and
leaves the database image cached. A full load takes about 4 minutes.

`EG_REF` and `OSRF_REF` pick the source. Evergreen 3.17 talks to OpenSRF
over Redis, and only OpenSRF `main` carries the Redis transport, so that
is the default. The GitHub mirror has no release tags on the Evergreen
maintenance branches, so `EG_REF` names a branch.

`EG_STAFF_CLIENT=1` builds the AngularJS staff client under
`Open-ILS/web/js/ui/default/staff` and the Angular staff client under
`Open-ILS/src/eg2`. The Angular build needs about 3 GB of RAM. Set
`EG_STAFF_CLIENT=0` on a small machine. Without it the OPAC, the gateway
and the Aspen export still work, but `/eg2/en-US/staff/` does not.

## Troubleshooting

OpenSRF logs are in `/openils/var/log` inside the Evergreen container.
Apache writes to the container logs, so `bin/etd logs` shows them.

```shell
bin/etd shell
osrf_control --localhost --diagnostic
tail -f /openils/var/log/osrfsys.log
```

The container only writes `/eg_ready` once the OpenSRF services are up,
autogen has run, Apache answers and the Aspen export is written. If
`/eg_ready` is missing, read the container logs to see which step is still
running.

To start over from the data in the image:

```shell
bin/etd down -v
bin/etd up -d
```
