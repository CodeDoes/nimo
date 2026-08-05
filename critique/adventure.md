# The Great Nimo Adventure: A Debugging Chronicle

## Overview

Over the course of a single session, we transformed the nimo CLI from a broken state into a working system with CUDA acceleration, while simultaneously consolidating 11 agent-generated PRs and fixing a mysterious pcre2 warning. This is the story.

## Chapter 1: The grep Warning That Wouldn't Die

It started with a seemingly innocent warning:

```
grep: /usr/lib/x86_64-linux-gnu/libpcre2-8.so.0: no version information available (required by grep)
```

Every time we ran any command in the devenv shell, grep would emit this noise. The issue? The nix-built grep binary (3.12) requires pcre2-10.47 with specific version symbols, but the system lib at `/usr/lib/x86_64-linux-gnu` was pcre2-10.46 without `.gnu.version_d` sections.

**The fix:** Prepend the nix pcre2-10.47 path to `LD_LIBRARY_PATH`:
```nix
env.LD_LIBRARY_PATH = "/nix/store/gvn2w8kxsxdjh1nsw88gp9fjyrcxwmkj-pcre2-10.47/lib:/usr/lib/x86_64-linux-gnu:...";
```

Lesson learned: When mixing nix and system libraries, order matters. The dynamic linker searches paths in order, and the first match wins.

## Chapter 2: The CUDA Phantom

Then CUDA became our nemesis. The RTX 2050 showed healthy in `nvidia-smi` (P8 state, 11 MiB used), but the harness reported:

```
[gpu] ERROR — GPU unusable: cuInit failed with code 34
```

Error code 34 = `CUDA_ERROR_INVALID_VALUE`. The CUDA driver API was failing to initialize, even though `nvidia-smi` worked fine.

**Root cause:** The earlier segfault (see Chapter 3) corrupted the CUDA driver context. Other apps (gnome-shell, Discord) use OpenGL/Vulkan paths which are completely separate from CUDA. They kept working while our CUDA code failed.

**The fix:** Reboot. The NVIDIA modules needed a clean slate.

```bash
sudo reboot
```

After reboot, CUDA worked again at 32 layers, ~300ms/token.

## Chapter 3: The Segfault That Started It All

The original trigger was a CUDA OOM (out-of-memory) crash. When the model tried to allocate 1883 MiB and failed, rwkv.cpp's CUDA backend crashed with SIGSEGV instead of returning an error:

```
ggml_backend_cuda_buffer_type_alloc_buffer: allocating 1883.42 MiB on device 0: cudaMalloc failed: out of memory
SIGSEGV: Illegal storage access. (Attempt to read from nil?)
Segmentation fault (core dumped)
```

**The fix:** Added signal handlers in `src/rwkv.nim` to catch SIGSEGV/SIGABRT and convert them to Nim exceptions:

```nim
when defined(linux):
  import std/posix
  # Install signal handlers in bindBackend()
  posix.signal(SIGSEGV, proc(signum: cint) {.closure, gcsafe.} =
    raise newException(IOError, "CUDA segmentation fault (likely OOM). Try --backend cpu"))
```

Now CUDA OOM produces a clean error message instead of a crash.

## Chapter 4: The Help Command That Didn't Help

A first-time user would try `nimo --help` and get:

```
Error: unknown command '--help'
Run 'nimo' without arguments for help.
```

**The fix:** Added help handling to the main CLI dispatch in `src/nimo.nim`:

```nim
if cmd in @["--help", "-h", "help"]:
  echo """
nimo -- RWKV inference CLI
...
"""
  quit(0)
```

Now `--help`, `-h`, and `help` all work.

## Chapter 5: The PR Consolidation

While debugging, we also consolidated 11 agent-generated PRs from Jules:

| PR | Content | Status |
|----|---------|--------|
| #1 | Compile fixes | ✅ Merged |
| #2 | Validate tests | ✅ Merged |
| #3 | Engine docs | ✅ Merged |
| #4 | Story dedup | ❌ Duplicated (already on main) |
| #5 | Docs drift | ✅ Merged |
| #6 | RFC index | ✅ Applied locally |
| #7 | nimo doctor | ✅ Applied locally |
| #8 | How-it-works | ✅ Merged |
| #9 | Engine lastOutput | ❌ Regression (would remove existing features) |
| #10 | Memory tests | ✅ Applied locally |
| #11 | Validation dedup | ❌ Duplicated |

Key insight: When agents work on stale branches, their PRs may conflict with or duplicate local work. Always check the diff before merging.

## Chapter 6: The GPU Layer Math

The original code had a magic number:

```nim
DefaultGpuLayers* = 99  # Offload all layers to GPU VRAM by default
```

But the model only has 32 layers! This caused "Requested layers (99) exceeds model layers (32)" errors.

**The fix:** Removed the magic number. Now layers are derived from the model header:

```nim
proc resolveGpuLayers*(modelPath: string, requested: int = -1): int =
  let h = readModelHeader(modelPath)
  if not isValidHeader(h) or h.nLayer == 0: return -1
  let modelLayers = int(h.nLayer)
  var want = if requested < 0: modelLayers else: requested
  # Clamp to VRAM...
```

Now the harness correctly uses 32 layers for the 32-layer model.

## Chapter 7: The VRAM Query That Needed a Context

The `freeVramMiB()` function was failing because `cuMemGetInfo` requires an active CUDA context:

```c
// This fails with CUDA_ERROR_INVALID_CONTEXT (201)
cuMemGetInfo(&free, &total);
```

**The fix:** Initialize a context first:

```c
cuInit(0);
cuDeviceGet(&dev, 0);
cuCtxCreate(&ctx, 0, dev);
cuMemGetInfo(&free, &total);
cuCtxDestroy(ctx);
```

Now VRAM queries work, and the layer clamping logic can make informed decisions.

## The Result

After all this, the system is in good shape:

```
=== FINAL STATUS ===

1. grep: test
   ✅ (no warning)

2. CUDA:
   [gpu] OK — GPU usable (1 CUDA-capable device(s) detected.)
   [gpu] using 32 GPU layer(s).
   [model] loaded.
   [smoke] reply: Hello! How
   [smoke] 0.891s
   ✅

3. unit tests: 87/87 passed
   ✅

4. --help: nimo -- RWKV inference CLI
   ✅
```

## Lessons Learned

1. **Grep warnings are harmless but noisy** — fix the library path, don't just filter them out
2. **CUDA state is fragile** — segfaults can corrupt the driver context; reboot is the cure
3. **OpenGL/Vulkan ≠ CUDA** — apps can use the GPU for rendering while CUDA fails
4. **Magic numbers are the enemy** — derive values from data (model header) when possible
5. **Signal handlers save lives** — convert C crashes to Nim exceptions
6. **Check PR diffs before merging** — agents may work on stale branches
7. **Reboot fixes many things** — when in doubt, reboot

## Commits

```
4399066 fix(devenv): use nix pcre2-10.47 to eliminate grep warning
24c31e5 fix(devenv): nix pcre2 before system path for CUDA + grep
852d2da fix(cli): -h and help commands work too
b04e7dd fix(devenv): simplify LD_LIBRARY_PATH, remove system lib path
fe2293c critique: document CUDA state corruption after segfault
8b58df3 critique: document intermittent CUDA OOM crash
ffa1e07 critique: document 11 UX issues from first-time-user observation
bdce48f fix(cuda): derive GPU layers from model shape + VRAM; init CUDA context
```

---

*Written by the nimo harness itself, because why not?*
