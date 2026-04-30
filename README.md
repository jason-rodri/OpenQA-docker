# OpenQA-docker

OpenQA Docker for RESF Rocky Linux testing. A single-container [openQA](https://open.qa/) instance with TAP networking support for multi-machine tests (FreeIPA, Cockpit, etc.).

## Prerequisites

- Linux host (KVM acceleration required — does not run on macOS/Windows)
- `/dev/kvm` available (`ls -la /dev/kvm`)
- `/dev/net/tun` available (`ls -la /dev/net/tun`)
- Docker + Docker Compose v2
- 8 GB RAM minimum (16 GB recommended for FreeIPA tests)
- Rocky Linux ISO (`Rocky-10.x-x86_64-dvd.iso` or similar)

## Quick Start

```bash
# 1. Build and start
docker compose up -d --build

# 2. Wait for the container to be healthy (~60s)
docker compose ps

# 3. Copy or download your Rocky ISO into the isos/ directory
mkdir -p isos
cp /path/to/Rocky-10.x-x86_64-dvd.iso isos/

# 4. Get the generated API key
docker exec openqa cat /etc/openqa/client.conf

# 5. Open the web UI
open http://localhost
```

## Submitting a Test Job

```bash
# Install openqa-cli (Fedora/Rocky: dnf install openqa-cli)
# Or use the container itself:
#
# First place your ISO in the isos/ directory next to docker-compose.yml:
#   cp Rocky-10.x-x86_64-dvd.iso isos/
#
docker exec openqa openqa-cli --host http://localhost \
    --apikey  <KEY> \
    --apisecret <SECRET> \
    api -X POST jobs \
    ISO=Rocky-10.x-x86_64-dvd.iso \
    DISTRI=rocky \
    VERSION=10 \
    FLAVOR=dvd \
    ARCH=x86_64 \
    TEST=install_default_upload
```

See [VARIABLES.md](https://github.com/rocky-linux/os-autoinst-distri-rocky/blob/main/VARIABLES.md) in the test suite for all supported job variables.

## Configuration

### Environment Variables (docker-compose.yml)

| Variable | Default | Description |
|---|---|---|
| `QEMURAM` | `4096` | MB of RAM given to the test VM |
| `QEMUCPUS` | `4` | CPU cores given to the test VM |

### Build Arguments (docker-compose.yml)

| Argument | Default | Description |
|---|---|---|
| `DISTRI_REPO` | `rocky-linux/os-autoinst-distri-rocky` | Git repo for the Rocky test suite |
| `DISTRI_BRANCH` | `main` | Branch to clone at build time |

To test a pull request, override these before building:

```yaml
# docker-compose.yml
args:
  DISTRI_BRANCH: fix-my-feature
  DISTRI_REPO: https://github.com/your-fork/os-autoinst-distri-rocky.git
```

### Runtime Test Suite Override

To iterate on needles or tests without rebuilding the image, bind-mount a local clone:

```yaml
# Add to the volumes: section in docker-compose.yml
- /path/to/your/os-autoinst-distri-rocky:/var/lib/openqa/share/tests/rocky
```

## Architecture

```
Container: openqa
├── PostgreSQL          — job database
├── Apache httpd        — web UI (port 80/443)
├── openqa-webui        — REST API + web interface
├── openqa-scheduler    — job scheduling
├── openqa-websockets   — real-time job updates
├── openqa-gru          — background tasks
└── openqa-worker #1    — QEMU test executor (KVM + TAP)
```

All services are managed by [supervisord](supervisord.conf). Startup order:

1. `tap-setup.sh` — creates `br-tap` bridge, enables NAT/IP forwarding
2. PostgreSQL
3. Apache httpd
4. openQA services (webui, scheduler, websockets, gru)
5. `bootstrap.sh` — seeds DB, generates API key, loads job templates
6. `openqa-worker` — starts after API is confirmed reachable

## TAP Networking

TAP networking enables multi-machine tests where multiple VMs communicate over a virtual network (required for FreeIPA, Cockpit, and similar tests).

**Host requirements:**
- `/dev/net/tun` must exist
- Container needs `NET_ADMIN` + `NET_RAW` capabilities (set in docker-compose.yml)

The `tap-setup.sh` script creates a `br-tap` bridge (172.16.2.0/24) inside the container and sets up NAT so test VMs can reach the network.

## Logs

```bash
# All services
docker exec openqa supervisorctl status

# Specific service
docker exec openqa tail -f /var/log/openqa/webui.log
docker exec openqa tail -f /var/log/openqa/worker-1.log
docker exec openqa tail -f /var/log/openqa/bootstrap.log
docker exec openqa tail -f /var/log/openqa/tap-setup.log
```

## Volumes

| Volume | Contents |
|---|---|
| `./isos/` | Rocky Linux ISO files (host directory, bind-mounted) |
| `test-results` | Job screenshots and results |
| `pgdata` | PostgreSQL database |

## Submitting Needles

Rocky 10.1 ships an updated Anaconda UI. If tests fail on needle matches, new needles must be contributed upstream:

1. Run the failing job and download the screenshot from the web UI
2. Create a `.json` + `.png` needle pair in `os-autoinst-distri-rocky/needles/anaconda/`
3. Open a PR to [rocky-linux/os-autoinst-distri-rocky](https://github.com/rocky-linux/os-autoinst-distri-rocky)

## Related Projects

- [os-autoinst-distri-rocky](https://github.com/rocky-linux/os-autoinst-distri-rocky) — Rocky Linux test suite
- [openQA](https://open.qa/) — upstream openQA project
- [os-autoinst](https://github.com/os-autoinst/os-autoinst) — test backend
