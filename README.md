# lib-graphics

Standalone Silk graphics libraries: CPU geometry, codecs and rasterization, retained drawing
scenes, and WebGPU renderers. Package names and import aliases are unchanged by extraction.
This repository does not contain SVG, UI widgets, CSS, fonts, XML, Studio or graphics-demo.

## Package boundaries

| Package directory | Responsibility | Dependencies beyond the Silk standard library |
| --- | --- | --- |
| `modules/geometry` | Shared geometry | None |
| `modules/codec` | PNG/JPEG decoding, PNG encoding, image and color-profile handling | None |
| `modules/vector` | CPU paths, coverage strips, paints, layers and filters | None |
| `modules/atlas` | Texture atlas allocation and eviction | None |
| `modules/ui_scene` | Ordered drawing primitives and CPU reference renderer | vector, atlas |
| `modules/editor` | Retained shape/image documents, hit tests and viewport painting | ui_scene, vector, atlas |
| `modules/gpu_scene` | WebGPU rendering of vector scenes | vector; lib-native WebGPU |
| `modules/ui_renderer` | WebGPU rendering of finished UI drawing scenes | ui_scene, vector, atlas, gpu_scene; lib-native WebGPU |

The six CPU libraries have no native-package dependency. `ui_scene` is a graphics scene model,
not a widget/UI framework. Test executables, renderer fixtures, browser wasm tests and benchmarks
remain separate packages in the workspace. Rust benchmark comparators are development-only.
Root `tasks/` is internal Silk maintenance/verification tooling, never a package dependency.

GPU manifests pin `silk-lang/lib-native` by an exact Git commit, including the `modules/gpu/webgpu`
and `modules/gpu/webgpu/sys` package paths. Silk fetches that commit. Browser tools resolve the
same revision from the manifest into `$SILK_HOME/git/<revision>` (default `~/.silk/git/<revision>`).
They do not search sibling checkouts, vendor native libraries or fall back to a moving branch.

Silk permits only one physical copy of a named package in a build. Update a dependency graph
coherently: mixing these packages with older dependencies that still import the same graphics
packages from `nonstd` will fail, even when their version strings match.

## Toolchain and builds

Use Silk **0.1.0-dev.72+9c780a04d6ef**, LLVM **22** including `clang` and `wasm-ld`,
and Git. `SILK_CLANG` selects an absolute LLVM 22 clang. The standard library ships
with the compiler. Bootstrap Silk with its official installer before running tasks:

```sh
curl -fsSL https://raw.githubusercontent.com/silk-lang/silk/8214c402307b2eda053d71d353f8649f40c03074/install.sh | SILK_RELEASE='v0.1.0-dev.72+9c780a04d6ef' sh
export PATH="$HOME/.silk/bin:$PATH"
export SILK_CLANG=/absolute/path/to/llvm22/bin/clang
silk task
silk check --manifest-path modules/vector/silk.toml
silk build --manifest-path modules/ui_scene/tests/silk.toml
silk build --manifest-path modules/ui_renderer/tests/silk.toml
silk build --manifest-path modules/ui_renderer/browser/silk.toml --target wasm32-unknown-unknown
```

Silk owns dependency fetching, native archives, C compilation, linking and tests.
Build outputs are under `build/llvm/<target>/<debug|release>/`; Windows native
executables have `.exe`. CPU-only work needs no GPU runtime:

```sh
silk test --manifest-path modules/vector/silk.toml --root src/tests.silk
silk test --manifest-path modules/codec/silk.toml --root src/tests.silk
silk check --manifest-path modules/ui_scene/silk.toml --target wasm32-unknown-unknown
```

### Platform dependencies

Task subprocesses retain a ten-minute deadline. Install native GNU coreutils
`timeout` on Linux, `gtimeout` on macOS, or busybox-w32 `busybox.exe` on Windows.
These are native executables, not script interpreters. JPEG diagnostics use
shorter 300-second build/Callgrind and 120-second sample deadlines.

- **macOS:** Xcode command-line tools/SDK, LLVM 22 and Metal-capable hardware for
  native GPU tests. Export `SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"`.
- **Linux:** LLVM 22, the C/C++ system toolchain and development headers, and a
  Vulkan driver (Mesa lavapipe works). Browser tests use installed Chromium,
  `Xvfb`, `xauth` and `openssl`; Silk starts and reaps its private Xvfb directly.
- **Windows x64:** an x64 Visual Studio developer shell with Windows SDK, LLVM 22
  and PowerShell. Install Silk with the official installer:

  ```powershell
  $env:SILK_RELEASE = 'v0.1.0-dev.72+9c780a04d6ef'
  irm https://raw.githubusercontent.com/silk-lang/silk/8214c402307b2eda053d71d353f8649f40c03074/install.ps1 | iex
  silk check --manifest-path modules/ui_renderer/browser/silk.toml --target wasm32-unknown-unknown
  silk task prepare-windows
  silk build --manifest-path modules/ui_renderer/tests/silk.toml
  silk task prepare-windows --runtime-directory build/llvm/x86_64-pc-windows-msvc/debug
  ```

`silk task setup-ci --linux-gpu` and `silk task setup-ci --browser` delegate to
the exact manifest-pinned lib-native task program. Native GPU tasks automatically
prepare Windows bridges and stage runtime DLLs beside the executable. No sibling
checkout, moving branch, interpreter wrapper or legacy runner is selected.

Windows managed Chromium remains unsupported pending
[Silk issue #3034](https://github.com/silk-lang/silk/issues/3034): the managed
subprocess/extra-pipe API is unavailable on Windows. `silk task test-browser`
reports that blocker there; no parallel JavaScript automation is retained.

## Verification

Run from this repository root:

```sh
silk task check                        # CPU roots, goldens, packages, wasm, native GPU
silk task check --skip-native          # no native GPU execution; all package checks remain
silk task check-vector                 # vector tests and CPU/GPU scene comparison
silk task test-scene                   # gpu_scene exact-image comparison
silk task test-ui-renderer             # UI fixtures against CPU references
silk task test-browser                 # eighteen Chromium WebGPU fixtures (macOS/Linux)
```

`--skip-native` omits GPU execution, not dependency resolution or GPU package
checks. CPU goldens consume committed `modules/ui_scene/tests/goldens` PNGs.
Browser tasks use the manifest-pinned lib-native `browser/runner.ts`, host and
schema as actual browser runtime modules. Silk manages Chromium through its
DevTools pipe and compares CPU/GPU pixels itself. It needs no Playwright and never
downloads a browser. `CHROMIUM_EXECUTABLE` selects an installed browser; Linux
uses a private X display.

Scheduled/manual CI additionally runs:

```sh
silk task bench vector                 # release vector vs locked tiny-skia; Cargo
silk task bench filters                # release filters vs locked resvg; Cargo
silk task bench ui-renderer            # dense scene vs committed budget
```

CPU comparisons write `.cache/bench`. Timing budgets describe the recorded
software-renderer workload, not arbitrary machines. See package READMEs and
benchmark `WORKLOADS.md` for tolerances and historical measurements.

## Generated sources and optional diagnostics

```sh
silk task embed-shaders
silk task embed-shaders --check
silk task generate-browser-exports
silk task generate-browser-exports --check
```

Canonical WGSL and generated `src/generated_shaders.silk` stay with their graphics
packages. The shader generator preserves the byte-literal format and identifies
the generating task in its banner. Browser roots own their callback/allocator wasm exports;
after fetching a new native pin, regenerate from its canonical
`modules/gpu/webgpu/browser/generated_webgpu_exports.silk` template.

Fixture generation is also Silk, with native `gzip` for independent PNG
compression and `cjpeg` (libjpeg-turbo) for independent JPEG encoding:

```sh
silk task fixtures png
silk task fixtures jpeg
silk task fixtures jpeg-progressive
silk task fixtures jpeg-metadata
silk task fixtures jpeg-benchmark .cache/jpeg-inputs
silk task bench jpeg .cache/jpeg-inputs/RGB-baseline.jpg --output .cache/jpeg-report.json
```

Regeneration is intentional, not part of normal CI: native encoder versions may
change compressed bytes. JPEG diagnostics keep sample/iteration/warmup validation,
output checksum checks, SHA-256 provenance, median decode timings and optional
Linux `--callgrind` whole-process instruction counts. They build the codec's
`jpeg-bench` executable profile without copying its sources. Callgrind additionally
requires Valgrind; the native deadline utilities are listed under platform dependencies.
ICC vectors retain their original source-snapshot provenance.

## Provenance

Extracted from [`silk-lang/nonstd` commit
`7d6c3693a9ad1fec24127985626ab4224f9f1995`](https://github.com/silk-lang/nonstd/tree/7d6c3693a9ad1fec24127985626ab4224f9f1995).
All original `graphics/*` packages and their fixtures, tests, benchmarks and browser package are retained under `modules/`.
Implementation and package identities are preserved; extraction changes dependency locations,
internal tooling and documentation. Vector/scene gates formerly under `svg/scripts` now live in
this repository's root `tasks/`.
The native dependency revision in the manifests, rather than this historical source snapshot,
selects the current runtime payload and native ABI.

Local extraction verification on macOS arm64 passed 408 CPU tests across all six test roots,
four CPU scene goldens, native GPU scene/UI-renderer comparisons, host and wasm package checks,
and all 18 browser renderer fixtures. Both native linking and browser runtime files came from
the manifest-pinned lib-native Git checkout, not a sibling working tree. Compiler bootstrap
and generated shader/browser-template checks also passed; no Python scripts were executed.
