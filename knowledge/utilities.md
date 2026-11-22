# Sandbox Utilities — jupyter + open-terminal lanes

What shell/file utilities exist INSIDE the two container lanes, what each is
FOR, and the hard rule both lanes obey: **no lane has internet egress — every
network move goes through the framework's Brain socket and the scope gate.**
These utilities only widen what the model can do with FILES and the
workbench bridge (172.28.0.x peers) it legitimately reaches.

## Why utilities are baked at build time

Both lanes sit on the INTERNAL workbench network with no routed egress.
`apt-get install` at runtime fails (no resolver route, verified 2026-11-22);
pip/conda fetches fail the same way. The utility sets therefore live in the
build stage, where `network: host` reaches the package mirrors exactly once:

- jupyter: `dockered/jupyter.Dockerfile` (single merged `apt-get update` line)
- open-terminal: `dockered/open-terminal.Dockerfile` (thin `FROM ghcr.io/
  open-webui/open-terminal:slim` extension; upstream tag bumps ride in via
  `docker compose build --pull open-terminal`)

Rebuild after editing either Dockerfile:

    docker compose -f dockered/docker-compose.yaml build jupyter open-terminal
    docker compose -f dockered/docker-compose.yaml up -d --force-recreate jupyter open-terminal

## open-terminal lane (`/var/lib/daharness/...`, dash/sh)

Baked base: python:3.12-slim (upstream image, ~150 packages). Added:

- `file` — magic-type any artifact: `file /var/lib/daharness/binaries/<name>`
  answers ELF/PE/script/data before reaching for `run_r2`. One-shot, zero
  side effects.
- `xxd` — hex dump: `xxd -l 128 <path> | head`. For structured dissection the
  framework's `run_r2`/`run_jadx` tools stay the path; `xxd` is quick triage
  and diff (`xxd a.bin > a.hex` then `diff`).
- `unzip` / `zip` — the `apk/` drop folder is ZIP-family (apk/jar/aab/apks).
  `unzip -l <path>` lists without extracting; `unzip -o <path> 'AndroidManifest*'
  -d /tmp/apk-slice` carves specific entries. Repack with `zip` for round-trip
  diffs.
- `tree -L 2 /var/lib/daharness/dacustoms` — directory overviews (the file
  browser UI shows one dir at a time; `tree` gives the shape).
- `vim-tiny` (call it as `vi` — Debian ships no unversioned `vim` name) /
  `nano` — edit shared-state files in place (dacustoms modules,
  notebooks as raw JSON, shell scripts) from a one-shot sh command.
- `netcat-openbsd` / `iputils-ping` / `dnsutils` (`dig`, `nslookup`) —
  diagnostics against the workbench bridge ONLY: `172.28.0.x` peers (jupyter
  `.40`, open-terminal `.45`, open-webui, jupyter-gate) and the host-side
  daharness-pg cluster via the gateway `172.28.0.1:5433`. There is still no
  default route and no internet resolve — these show the sandbox's net
  shape, they do not punch through it. Host services (Ollama :11434) are NOT
  reachable this way: framework tools that ride brain.sock are the only path.
- `procps` (`ps`, `top -bn1`) / `psmisc` (`pstree`, `killall`) — inspect the
  lane's own processes; the lane runs model-triggered sessions, so a wedged
  one-shot can be identified and killed without leaving the sandbox.

Pre-existing worth knowing: `curl` (bridge-reachable endpoints only),
`jq` (JSON shaping), `git` (dacustoms worktree ops + commits land host-side
through the shared .git), `tar`, `gzip`, `openssl`, `base64`, `less`,
`truncate`, `python3` (stdlib ONLY — no pip packages: no requests/paramiko.
Quick binary parsing with `struct`/`zlib`/`binascii` works; HTTP calls do
nothing useful — see the net rule above).

## jupyter kernel lane (`/home/jovyan/work`)

Baked base: quay.io/jupyter/base-notebook (Ubuntu 26.04, ~515 packages, conda
python 3.13 with scapy/paramiko/pyshark/requests preinstalled). Added:

- `file`, `xxd`, `tree`, `jq` — same roles as the open-terminal list; the
  kernel runs one-shot shell via `!cmd` or `subprocess` for these.
- `unzip` — APK/JAR triage straight off the `apk/` mirror (`/var/lib/daharness/apk`
  is PATH-identical in-container).
- `vim-tiny` — edit notebooks/scripts outside a cell when a cell is the wrong
  shape for the edit.
- `netcat-openbsd` / `iputils-ping` / `dnsutils` — same bridge-diagnostics
  boundary as open-terminal (workbench `172.28.0.x` only; the kernel
  container has NO egress adapter and host services stay brain-socket-only
  — `execute_code` knowledge doc, `lane boundaries` section).
- `procps` / `psmisc` — process inspection for long notebook jobs.

Python side is unchanged: the model should NOT `pip install` at runtime (no
egress — the fetch fails mid-download) — RE work belongs to host-side
`run_r2`/`run_jadx`/`dissect_packet` tools, not to pwntools/capstone attempts.

## What still goes through the framework (not these shells)

Any traffic-sending or host-service action is a framework tool call, host-side:

- scans / web requests / credentials → `nmap`, `run_ffuf`, `hydra`,
  `session_get`/`session_post`/`session_request`, `probe_web`, ...
- binary disassembly → `run_r2` (+ r2ghidra `pdg`), NOT `objdump` (not baked;
  host has r2 and it is the discoverable, cached, journaled path)
- APK analysis → `run_jadx` (+ the jadx_fleet twins)
- pcap reads → `load_pcap` / `list_pcaps` host-side (scapy), or plain
  `file`/`xxd` peek in-lane for a header check
- host databases → `db_exec` via brain.sock, never a raw socket to 5433

## Net-posture summary (both lanes)

| path | allowed | mechanism |
|---|---|---|
| workbench bridge peers (172.28.0.x) | yes | internal network, always |
| host daharness-pg (:5433) | yes | bridge gateway 172.28.0.1, repl_lane cred |
| internet | no | no default route / no egress adapter |
| host services (Ollama :11434, :5433 loopback) | framework tools only | brain.sock → scope gate |
| target hosts | framework tools only | brain.sock → scope-gated executor |

See also: `knowledge/lanes.md` (lane map), `knowledge/execute_code.md`
(kernel network semantics), `dockered/docker-compose.yaml` (mount + posture
authority).
