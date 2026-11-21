# Execute Code Lane — Jupyter Kernel

## what it is

OpenWebUI is configured with Jupyter as the code interpreter and execution
engine. The `execute_code` lane runs in the same daharness Jupyter kernel
the REPL (`tool_repl.py`) uses — the framework namespace (bare tool names,
async wrappers, envelope helpers) and the scope gate are wired in
identically. This is a DIRECT EXECUTION lane: the model can run multi-step
tool chains programmatically without handing off to the User for REPL entry.

Kernel connectivity: The Jupyter kernel is a separate process connected via WebSocket. If execute_code returns Error: timed out during opening handshake, the kernel is unresponsive (crashed, overwhelmed, or disconnected). This is a kernel-level issue, not a tool failure — report it to the User and wait; do not retry repeatedly. The User can restart the kernel from the OpenWebUI interface. Bridge tools (framework_run_tool) remain functional during kernel downtime — use them as a fallback for critical operations

## execution scope — one call = one fresh context

Each `execute_code` invocation is a self-contained script. Variables,
imports, and state created inside one call do NOT persist to the next
`execute_code` call. There is no global variable state across calls. Write
each block as a complete, self-contained script: declare imports, define
helpers, run the chain, and bank results to stores all within the same
block. If a later call needs a value from an earlier call, retrieve it from
stores (findings, memory, scratch) — never assume a variable survived.

## lane boundaries — network and filesystem (verified 2026-11-20)

The kernel container sits on the INTERNAL workbench bridge (no egress
adapter): `127.0.0.1` inside execute_code is the CONTAINER's loopback, not
the host's. Host services (Ollama on :11434, the :5433 postgres cluster)
are NOT reachable from raw kernel sockets regardless of how they're bound
on the host — probing `http://127.0.0.1:11434/api/embed` from
`execute_code` returns `[Errno 111] Connection refused` even when the
embedding lane is healthy (a `urllib` probe looks identical to a real
outage). Only the framework tool path can reach them: kernel tool calls
ride the Brain UDS socket (`/run/daharness/brain.sock`, a filesystem path,
unaffected by network namespace) and execute HOST-side through the scope
gate.

Practical rules:
- Never debug `EMBED_URL`/embedding health from the kernel. Use
  `framework_health` or a `tools_search` probe instead — they run
  host-side and report the truth.
- Any direct socket/HTTP experiment in execute_code can only reach things
  ON the workbench bridge (jupyter:8888, 172.28.0.x peers), not host
  services. Raw `socket`/`urllib` refusal ≠ service down.

Filesystem: the kernel runs as `jovyan`; host-side state dirs written by
the daemon (`scratch.db`, `run/jobs`, `run/worker_queue`, `.cache`) are
root/daharness-owned → kernel reads fail with `Permission denied`. Scratch
and job forensics MUST go through the framework tools
(`scratch_search`, and the various `*_status` tools), not filesystem
access. Only PATH-identical mounts (`/var/lib/daharness` via group_add
GID 125, `/run/daharness`, `/home/jovyan/framework`) are readable.

## within a single call

Multiple `await` lines in one execute_code block run sequentially and
variables carry forward line-to-line:

```python
result = await nmap(target="10.10.10.50", options="-Pn -p 22,445")
ports = pluck(result, "open_ports")
if 445 in ports:
    await smb_recon(target="10.10.10.50")
```

That entire block is ONE execute_code call. The next execute_code call
starts clean — `result`, `ports`, and any imports are gone.

## tool names

Tool names in execute_code use BASE NAMES (bare tool names the kernel
resolves, not dotted tool_ids): `nmap`, `masscan`, `ffuf_payload`,
`null_session`, `smb_recon`, `ftp_banner`, `ftp_anon_check`, `ftp_list`,
`ftp_get`, `ftp_put`, `sftp_list`, `sftp_get`, `sftp_put`, `resolve_host`,
`ptr_lookup`, `tls_info`, `cors`, `security_headers`, `ssh_exec`,
`probe_web`, `db_connect`, `db_exec`, `db_exec_batch`, `db_schema_farm`,
`db_close`, `hydra`, `sqlmap`, `john`, `hashcat`, `searchsploit`,
`msfvenom`, `msf_dispatch`, `msf_index`, `msf_options`, `msf_interact`,
`session_get`, `session_post`, `session_upload`. The full alias set is in
`tool_repl.py:_TOOL_ALIASES` + auto-derived from module_id. When unsure
of a base name, use `framework_search_tools` to confirm.

## await is required

Every framework tool call in execute_code is `await`ed. The kernel injects
async wrappers (not the raw functions) and autoawait is on. Without `await`
you get a coroutine object, not the result, and the tool never executes.

## transport envelope

Results come back in a transport envelope:
`{"status": ..., "result": <tool dict>, "_elapsed_s": N}`. The tool's own
fields are under `result`, not at the top level. The kernel namespace ships
envelope helpers that auto-unwrap: `keys(r)` (every key at any depth),
`pluck(r, K)` (flat list of every value for key K), `find(r, K)` (values +
paths), `grep(r, RX)` (string search across all values). Use these instead
of guessing the nesting.

## scope gate

The scope gate fires on every traffic-sending call inside the kernel — it
enforces identically to the bridge. The kernel does not bypass the scope
gate. No manual [GATED] markers needed: the gate is automatic.

## budget

The per-turn tool budget (`TOOL_BUDGET_PER_TURN`) is enforced on the bridge
wrapper (`framework_run_tool` / OWUI tool calls), NOT on execute_code. The
kernel talks to the framework directly, so chains run unbounded. This is
deliberate: scripting loops and multi-step chains through execute_code is
the expected workflow, and a per-call cap would make that impossible.
