# graphics-ui-renderer

Draws a finished [`modules/ui_scene`](../ui_scene) `Scene` with WebGPU, natively through Dawn
and in the browser through `navigator.gpu` ([gpu-webgpu](https://github.com/silk-lang/lib-native/tree/main/modules/gpu/webgpu)). This is phase 3 of
the UI drawing layer: the GPU counterpart of `ui_scene.cpu.CpuRenderer`.

## Use

```silk
import ui_renderer.atlas_textures { GpuAtlas }
import ui_renderer.renderer { UiRenderer }
import ui_scene.color { Color }
import webgpu_sys.generated_webgpu as flags

// Once per window, for the surface's format (RGBA8Unorm or BGRA8Unorm):
let mut renderer = run UiRenderer.make(&device, flags.WGPUTextureFormat_BGRA8Unorm)
let mut textures = GpuAtlas.make()

// Each frame, after painting and `scene.finish()`:
run textures.sync(&device, &atlas)          // new atlas textures
textures.write(&queue, tile, pixels)          // each new tile's pixels
run renderer.draw(&device, &queue, &scene, &textures, &surfaceView, width, height, Color.white())
```

`draw` records and submits one command buffer. `encode` records into a caller's encoder instead,
for callers that also present or read back.

## How it draws

Every batch of the scene is one instanced draw of six vertices per instance, as in GPUI:

| Kind | Shader | How |
| --- | --- | --- |
| Quad | `shaders/quad.wgsl` | Rounded-rectangle SDF per corner radius, analytic antialiasing. The border is the band between the outline and the inner outline with elliptical corners (`r - left`, `r - top`), drawn over the background in the same fragment. Dashes (`2w` on, `w` off, from the top-left corner, clockwise) follow the arc length of the band's center line. |
| Shadow | `shaders/shadow.wgsl` | Closed-form Gaussian along x (erf), integrated along y with 8 samples (Evan Wallace's method). `sigma = blurRadius / 2`, as CSS. Inset shadows are the complement, clipped to the box. |
| Underline | `shaders/underline.wgsl` | Straight: exact area of the top `thickness` rows. Wavy: distance to the sine wave to first order. |
| Glyph | `shaders/mono.wgsl` | A8 atlas tile, bilinear at pixel centers clamped to the tile, with DirectWrite's contrast and gamma correction for text (see below). |
| Image | `shaders/poly.wgsl` | Premultiplied RGBA tile, bilinear, with corner radii, opacity and grayscale. |
| Path | `shaders/path.wgsl` | `vector` coverage strips in gpu_scene's run layout (4-row bands, a word of coverage per column), placed at the sprite's integer origin; bands start at the sprite's own `y`. |
| Layer | `shaders/layer.wgsl` | Plain isolated layers (opacity, a transform, a mask layer) are drawn into shared textures and blitted inside their parent's pass. Every other layer is drawn into a pooled RGBA8 texture and composited with gpu_scene's `blend.wgsl` (all `vector.layer` blend modes) and the group opacity, with optional layer/backdrop blur and color filters. See [Isolated layers](#isolated-layers). |

Two-stop linear gradients take any `silk.color` interpolation. sRGB gradients are mixed in the
shader; every other interpolation (linear sRGB, Oklab, Oklch and the other polar spaces with their
hue arcs, wide gamut spaces) gets a 256-entry ramp of premultiplied RGBA8 words, sampled on the
CPU with the same `color.mix` the CPU reference uses, in a storage buffer the quad and path
shaders read. Either way the parameter steps in 1/255, as the CPU reference's ramp does. `Stops` gradients
(linear, radial, conic, any number of stops, repeating or not) put their stops in the same
storage buffer, five words each, and the parameter steps in 1/255 between neighbouring stops. In
sRGB the shader mixes them; in any other interpolation each pair of neighbours gets its own ramp.
Ramps clip to sRGB channel by channel instead of gamut mapping, as Chromium paints gradients, and
stops may hold extended sRGB so a wide gamut CSS color keeps its chroma until the mix.
Content masks clip by pixel area. `shaders/common.wgsl` holds what the pipelines share; edit the
`.wgsl` files and run `silk task embed-shaders`, never the generated module.

All instances of a frame go into one storage buffer per kind (every layer's sorted list, in layer
order), uploaded with `queue.writeBuffer`. The buffers persist across frames and are replaced
only when a frame outgrows them. A scene without isolated layers draws straight onto the target.

Paths do not go through `gpu_scene.SceneRenderer` itself: UI paths need content masks and gradient
ramps, which its paint records lack. They reuse its band layout, its buffer helpers and its
blend modes.

### Isolated layers

A layer that needs only its pixels, an opacity, a transform and a mask layer is **plain**. It
costs no pass of its own:

- Plain layers of one nesting depth that do not overlap share a texture, a **page**. A page is
  one pass, drawn before the layers that hold its layers, deepest first. Each layer draws within
  its own pixels of the page (a scissor).
- A page's texture spans only the bounds of its layers (rounded up to 128 pixels), and a layer
  far from a page's others starts a page of its own, so pages cost memory for what they hold,
  not for the window. A page that holds a layer composited the slow way, or a backdrop blur, is
  target-sized.
- The parent's pass then blits each layer where it comes in the parent's batches, blended
  source-over by the pipeline. A mask layer is one more layer on another page; the blit keeps
  the layer inside its alpha.
- Layers that overlap take a page each, up to 12 pages a frame.

So a page of 50 animated tiles is two passes: one page, then the frame. `layers-frame` in the
benchmark is that frame, 128 ms before pages and 37 ms with them on lavapipe.

Every other layer (a blend mode, blur, a color filter, a drop shadow, backdrop blur, or one past
the page limit) is composited the slow way: its content into a pooled texture, then a blend pass
that reads a copy of what is under it. That pass interrupts the parent's pass, and each of these
passes loads and stores a target-sized texture, so keep such layers few. When the root holds
one, the frame is drawn into an RGBA8 texture and copied to the target at the end. A plain layer
that holds a backdrop blur takes a page alone, so the blur reads only that layer.

### Layer effects and atlas uploads

`Scene.pushEffectLayer` carries the shared [`LayerEffects`](../ui_scene/src/effects.silk)
settings into the renderer. Gaussian blur and color matrices reuse `gpu_scene.FilterRenderer`;
filter scratch textures and uniforms are pooled between frames. A scene without isolated layers
keeps the direct rendering path. Backdrop blur currently copies and filters the full viewport.
Filter surfaces are viewport sized, so source pixels beyond their edges cannot contribute to
blur. Cost scales with filtered area and layer count; these changes do not make large stacks of
blurred layers free.

`GpuAtlas.texture(index)` exposes a borrowed texture for external uploads. Call `sync` first,
write only the allocated tile, and provide premultiplied pixels for color tiles. Color atlas
textures now include render-attachment usage, which browser canvas-to-texture copies require;
monochrome textures keep their previous usage. Instance packing writes whole little-endian
vectors in bulk rather than appending each byte separately.

### Text correction

Unhinted coverage blended plainly looks thin. `TextSettings` applies Windows Terminal's DirectWrite
correction (MIT), as GPUI does: an enhanced-contrast curve weighted by how dark the text is, then
DirectWrite's gamma ratios. The default is gamma 1.8, contrast 1.0 (GPUI's Linux and web
defaults); `TextSettings.none()` turns it off. `TextSettings.correct` computes the same curve on
the CPU.

## Accuracy

The GPU output is compared with `CpuRenderer`, within a tolerance rather than byte for byte. Most
of the difference is on the CPU side: `vector` flattens arcs to within 0.25 px, so pixels where a
rounded corner runs nearly parallel to a pixel row can differ by up to a quarter of their coverage
(the largest deltas, around 35 levels). The erf blur and the dash arc length are approximations
too. Flat areas match exactly.

| Fixture | Max channel delta | Channels over 8 | Mean delta |
| --- | --- | --- | --- |
| cards | 36 | 0.17% | 0.18 |
| borders | 32 | 0.39% | 0.12 |
| shadows | 13 | 0.05% | 0.35 |
| layers | 25 | 0.20% | 0.06 |
| nested | 24 | 0.10% | 0.04 |
| gradients | 28 | 0.37% | 0.13 |
| pages | 23 | 0.23% | 0.08 |
| text ramp | 0 | 0 | 0 |

These are lavapipe's numbers. Chromium's WebGPU (SwiftShader) gives the same within a level.
The test allows 48, 0.6% and 0.5 (exact for the text ramp).

## Packages

| Path | Package | What it is |
| --- | --- | --- |
| `modules/ui_renderer` | `graphics-ui-renderer` | The renderer (`renderer`, `atlas_textures`, `instances`, `text`) |
| `modules/ui_renderer/fixtures` | `graphics-ui-renderer-fixtures` | Fixture scenes and their CPU references |
| `modules/ui_renderer/tests` | `graphics-ui-renderer-tests` | Native GPU against CPU comparison |
| `modules/ui_renderer/browser` | `graphics-ui-renderer-browser` | The same comparison as a wasm module for Chromium |
| `modules/ui_renderer/bench` | `graphics-ui-renderer-bench` | Frame time of a dense scene and of a page of 50 layers |

## Tests

From the repository root, with a Vulkan, Metal or D3D driver (CI uses lavapipe):

```sh
silk task check                        # shaders, packages, CPU tests, wasm32, GPU comparisons
silk task test-browser                 # the comparison in installed Chromium
silk task bench ui-renderer            # dense scene against bench/budget.json
```

The browser task currently runs on macOS/Linux; the root README documents the
Windows managed-process compiler blocker. Native GPU tasks also prepare Windows.

The comparison renders eight fixtures (the four `ui_scene` golden scenes, nested isolated layers
with clipped sprites and paths, gradients in eight interpolations on quads and paths, layer/backdrop
blur with color adjustments and blending, and a text coverage ramp) into RGBA8 and BGRA8 targets.
It checks text correction against `TextSettings.correct` within one level and redraws the layered,
gradient, and effects scenes after another scene to check that pooled resources carry nothing over.

The benchmark draws 320 cards (shadow, bordered rounded quad, a line of glyphs; 3,521 primitives)
at 1280 x 800 and reports the median build, encode and frame times. On lavapipe in a 4-core
container: build 3.9 to 5.1 ms, encode 1.2 to 1.5 ms, frame about 70 ms (software rasterization).
The `graphics` workflow runs the check and the browser test on every pull request and
the benchmark weekly. See the [root README](../../README.md) for toolchain and runtime setup.

Dependents import the package as `ui_renderer`.
