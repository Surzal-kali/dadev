# =============================================================================
# open-terminal + agent-QoL utilities
#
# Thin extension of ghcr.io/open-webui/open-terminal:slim — the ONE apt layer
# this stack's editor lane was missing (2026-11-22, knowledge/utilities.md).
# The runtime lane has no egress (workbench-internal by design; apt fails
# live-verified), so utilities must be baked at BUILD time, where --network=host
# reaches the host resolver exactly like jupyter.Dockerfile's build (the same
# 2026-10-21 BuildKit-DNS workaround).
#
# Everything else stays stock: the upstream image's entrypoint machinery
# (_FILE secret resolution, fix_home seeding, gosu drop, iptables/DOMAINS
# egress gate) is inherited untouched — compose still carries its inline
# entrypoint override for the /etc/passwd GID surgery and tini exec. Upstream
# updates ride in by bumping the FROM tag (docker compose build --pull).
# =============================================================================
FROM ghcr.io/open-webui/open-terminal:slim

USER root
# Utility additions (knowledge/utilities.md has the usage map):
#   file   — magic-type ID for binaries/ and apk/ artifacts the model reads
#   xxd    — hex dump (open-terminal has no strings/objdump; the framework's
#            run_r2 tools stay the RE path — this is quick triage only)
#   unzip  — the apk/ drop folder is ZIP-family (apk/jar/aab); the model can
#            carve APK contents without shipping them host-side first
#   zip    — round-trip repack (craft modified archives, diff-able drops)
#   tree   — directory overviews of dacustoms/ binaries/ notebooks
#   vim-tiny (via its `vi` link — there is no unversioned `vim` name),
#            nano — in-editor file edits over the shared state root
#   netcat-openbsd, iputils-ping, dnsutils — workbench-bridge diagnostics only
#            (172.28.0.x peers, host-native daharness-pg on 172.28.0.1:5433);
#            the lane's no-egress posture is unchanged — these give visibility
#            INTO the sandbox net shape, not a route OUT of it
#   procps, psmisc — ps/pstree/killall for the lane's own session processes
RUN apt-get update && apt-get install -y --no-install-recommends \
        file xxd unzip zip tree vim-tiny nano \
        netcat-openbsd iputils-ping dnsutils procps psmisc \
    && rm -rf /var/lib/apt/lists/*
# NOTE: deliberately NO trailing `USER user` — the upstream slim image boots as
# ROOT (Config.User is empty) because entrypoint-slim.sh must run as root to
# perform /etc/passwd GID surgery, iptables egress setup, and the gosu drop.
# compose's inline entrypoint override carries that contract; ending this
# Dockerfile with USER user flipped the boot user and crashed the entrypoint
# (sed -i /etc/passwd -> "Permission denied" loop, "failed switching to user").
# git safe.directory: the shared dacustoms worktree is owned by the HOST
# daharness user (uid 120); the container's uid 1000 `user` (and root) trip
# git's dubious-ownership check — stock-image behavior, panel detector aside
# (compose comment: ".git usable in shell" needed this caveat too). A system
# gitconfig blessing the PATH-IDENTICAL state root fixes git for every shell
# identity this lane runs as, without touching the operator's repo config.
RUN git config --system --add safe.directory /var/lib/daharness/dacustoms \
    && git config --system --add safe.directory /home/jovyan/work
