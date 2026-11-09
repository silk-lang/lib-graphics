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
Root `scripts/` is internal maintenance/verification tooling, never a package dependency.

GPU manifests pin `silk-lang/lib-native` by an exact Git commit, including the `modules/gpu/webgpu`
and `modules/gpu/webgpu/sys` package paths. Silk fetches that commit. Browser tools resolve the
same revision from the manifest into `$SILK_HOME/git/<revision>` (default `~/.silk/git/<revision>`).
They do not search sibling checkouts, vendor native libraries or fall back to a moving branch.

Silk permits only one physical copy of a named package in a build. Update a dependency graph
coherently: mixing these packages with older dependencies that still import the same graphics
packages from `nonstd` will fail, even when their version strings match.

## Toolchain and builds

Use Silk **0.1.0-dev.63+657e3c900f65**, an LLVM **22** installation including `clang` and `wasm-ld`,
and Git. Node **22+** runs the internal tools. `SILK_CLANG` can select an absolute LLVM 22 clang;
`SILK` can select a compiler executable for the Node runners. The compiler's standard library is
part of its release distribution. No Python is required for normal builds, tests or CI.

To install the checksum-pinned Silk release with Node and the system `tar`:

```sh
export PATH="$(node scripts/install-silk.mjs):$PATH"
export SILK_CLANG=/absolute/path/to/llvm22/bin/clang
silk check --manifest-path modules/vector/silk.toml
silk build --manifest-path modules/ui_scene/tests/silk.toml
silk build --manifest-path modules/ui_renderer/tests/silk.toml
silk build --manifest-path modules/ui_renderer/browser/silk.toml --target wasm32-unknown-unknown
```

Silk owns dependency fetching, native archives, C compilation, linking and test execution. Build
outputs are under `build/llvm/<target>/<debug|release>/`; native Windows executables have `.exe`.
A CPU-only package can be checked or tested directly without fetching or preparing a GPU runtime:

```sh
silk test --manifest-path modules/vector/silk.toml --root src/tests.silk
silk test --manifest-path modules/codec/silk.toml --root src/tests.silk
silk check --manifest-path modules/ui_scene/silk.toml --target wasm32-unknown-unknown
```

### Platform dependencies

- **macOS:** Xcode command-line tools/SDK, LLVM 22, and Metal-capable hardware for native GPU tests.
  Export `SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"` before native builds.
- **Linux:** LLVM 22, the C/C++ system toolchain and development headers, and a Vulkan driver.
  Mesa lavapipe is suitable for software GPU comparisons. Browser tests also require an installed
  Chromium, `xvfb-run` and `xauth`. The CI workflow invokes the pinned lib-native
  `scripts/setup-ci.mjs --linux-gpu` or `--browser` to prepare its reviewed dependencies.
- **Windows x64:** an x64 Visual Studio developer shell with the Windows SDK, LLVM 22 and
  PowerShell. Fetch lib-native through Silk first, then prepare its native bridge and archive
  overrides before a direct native GPU build:

  ```powershell
  $env:PATH = "$(node scripts/install-silk.mjs);$env:PATH"
  silk check --manifest-path modules/ui_renderer/browser/silk.toml --target wasm32-unknown-unknown
  node scripts/prepare-windows.mjs
  silk build --manifest-path modules/ui_renderer/tests/silk.toml
  node scripts/prepare-windows.mjs -RuntimeDirectory build/llvm/x86_64-pc-windows-msvc/debug
  ```

  This invokes PowerShell from the exact pinned lib-native checkout, not Python or a sibling tree.
  Native GPU Node runners perform preparation and runtime-DLL staging automatically. Direct Silk
  builds need the explicit preparation/staging above. The DLLs include Dawn, DXC and GLFW.

## Verification

Run from this repository root:

```sh
node scripts/check.mjs                    # six CPU test roots, goldens, all packages, wasm, native GPU comparisons
node scripts/check.mjs --skip-native      # same checks without running native GPU comparisons
node scripts/check-vector.mjs             # focused vector tests and CPU/GPU scene comparison
node scripts/test-scene.mjs               # gpu_scene exact-image comparison
node scripts/test-ui-renderer.mjs         # UI renderer fixtures against the CPU reference
node scripts/test-browser.mjs             # build wasm and compare fixtures in installed Chromium
```

`--skip-native` omits GPU execution, not dependency resolution or GPU package checks. CPU-only
users should use the direct per-package Silk commands above. The CPU golden test consumes the
committed `modules/ui_scene/tests/goldens` PNGs; codec vectors and JPEG fixtures are included.
The browser smoke uses the actual lib-native `browser/runner.ts` and host payload with
`navigator.gpu`. `PLAYWRIGHT_MODULE` may point to an already installed `playwright` or
`playwright-core` module; `PLAYWRIGHT_CHROMIUM_EXECUTABLE` selects the installed browser. The
smoke runner never downloads a browser. Linux runs Chromium under Xvfb for WebGPU presentation.

CI runs the native and browser gates on pull requests. Scheduled/manual runs additionally execute:

```sh
node scripts/bench-vector.mjs              # release vector vs locked tiny-skia (Cargo required)
node scripts/bench-filters.mjs             # release filters vs locked resvg (Cargo required)
node scripts/bench-ui-renderer.mjs         # release dense scene vs committed timing budget
```

Outputs for the CPU comparisons go to `.cache/bench`. Renderer timing budgets describe the
recorded software-renderer workload, not a promise for arbitrary machines. See each package's
README and benchmark `WORKLOADS.md` for comparison tolerances and historical measurements.

## Generated sources and optional diagnostics

Edit graphics WGSL beside its owning package and run `node scripts/embed-shaders.mjs`.
`node scripts/embed-shaders.mjs --check` detects drift. Both the canonical WGSL and generated
`src/generated_shaders.silk` modules remain here; lib-native does not generate graphics shaders.
Generated banners identify the owning package under `modules/`; shader payloads are unchanged.

The browser executable must own its callback and allocator exports: dependency modules do not
export wasm symbols. After updating the native manifest pin and fetching it with Silk, run
`node scripts/generate-browser-exports.mjs` to copy lib-native's canonical
`modules/gpu/webgpu/browser/generated_webgpu_exports.silk` template into this root wasm application.
Use `--check` to compare without writing. No Python generator is imported across repositories.

Optional Python fixture generators remain under `modules/codec/tests`; Pillow is needed for
JPEG encoding. They are maintainer-only tools, not build dependencies. The self-contained
`scripts/diagnostics/bench-jpeg.py` records JPEG decode timings (and optional Linux Callgrind
counts) from explicit input images, invoking Silk directly. Run it with `--help` for options;
it is not part of CI. ICC test vectors remain embedded in Silk, with their original generator's
source-snapshot provenance recorded in the test module.

## Provenance

Extracted from [`silk-lang/nonstd` commit
`7d6c3693a9ad1fec24127985626ab4224f9f1995`](https://github.com/silk-lang/nonstd/tree/7d6c3693a9ad1fec24127985626ab4224f9f1995).
All original `graphics/*` packages and their fixtures, tests, benchmarks and browser package are retained under `modules/`.
Implementation and package identities are preserved; extraction changes dependency locations,
internal tooling and documentation. Vector/scene gates formerly under `svg/scripts` now live in
this repository's root `scripts/`. No source library from SVG, UI or native was copied here.
The native dependency revision in the manifests, rather than this historical source snapshot,
selects the current runtime payload and native ABI.

Local extraction verification on macOS arm64 passed 408 CPU tests across all six test roots,
four CPU scene goldens, native GPU scene/UI-renderer comparisons, host and wasm package checks,
and all 18 browser renderer fixtures. Both native linking and browser runtime files came from
the manifest-pinned lib-native Git checkout, not a sibling working tree. Compiler bootstrap
and generated shader/browser-template checks also passed; no Python scripts were executed.
