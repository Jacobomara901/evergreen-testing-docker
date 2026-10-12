# evergreen-testing-docker (etd)

This project runs an Evergreen ILS development server in Docker. It builds
Evergreen and OpenSRF from source on Debian bookworm, loads the concerto
sample data into PostgreSQL and writes an Aspen Discovery export on every
start. It is the Evergreen counterpart of koha-testing-docker. Aspen dev
boxes and sandboxes connect to it over a Docker network.

## Requirements

- Docker Engine and Docker Compose v2
- About 6 GB of free disk for the images
- About 1.5 GB of free RAM for a running stack
- A lot more disk and RAM if you build the images yourself

## Quick start

```shell
git clone <this repository> evergreen-testing-docker
cd evergreen-testing-docker
cp .env.example .env
bin/etd up -d
bin/etd logs -f
```

The first start creates the database and loads the sample data. That takes
10 to 20 minutes. Wait for this line:

```
etd: evergreen is ready
```

Then open:

- OPAC: http://localhost:8086/eg/opac/home
- Staff client: http://localhost:8086/eg2/en-US/staff/
- Gateway: http://localhost:8086/osrf-gateway-v1
- HTTPS: https://localhost:8446/eg/opac/home (self signed certificate)

The database volume survives `bin/etd down`. The second start skips the
load and is ready in about a minute.

## Logins

| What | User | Password |
|---|---|---|
| Evergreen staff | `admin` | `demo123` |
| Evergreen patron | barcode `PATRON_BARCODE` | `demo123` |
| PostgreSQL | `evergreen` | `evergreen` |

Every sample user has the password `demo123`. To find more patron
barcodes:

```shell
bin/etd psql -c "SELECT c.barcode FROM actor.usr u JOIN actor.card c ON c.id = u.card WHERE u.expire_date > now() AND NOT u.deleted AND u.active LIMIT 10"
```

## Sample data

`EG_SAMPLE_DATA` picks the dataset. It is only read when the database is
first created, so change it before the first `bin/etd up` or run
`bin/etd down -v` first.

| Value | What you get |
|---|---|
| `concerto_enhanced` | The enhanced concerto set, the default |
| `concerto` | The plain concerto set |
| `none` | An empty Evergreen database |

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
| `EG_SAMPLE_DATA` | `concerto_enhanced` | Sample data loaded on first boot |
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

The container only writes `/eg_ready` once the database is loaded, the
OpenSRF services are up, autogen has run, Apache answers and the Aspen
export is written. If `/eg_ready` is missing, read the container logs to
see which step is still running.

To start over from an empty database:

```shell
bin/etd down -v
bin/etd up -d
```
