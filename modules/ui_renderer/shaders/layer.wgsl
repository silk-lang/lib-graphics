// Isolated layers: composite a layer onto a copy of what is under it with a vector.layer blend
// mode and a group opacity (prepended with gpu_scene's blend.wgsl), and copy a finished frame out
// to a target of any format. A plain layer (normal blend, no filters, no mask) is instead blitted
// inside its parent's pass, where the pipeline blends it source-over. A blit that is `masked` keeps
// the layer inside the alpha of its mask layer, bound in place of the filtered backdrop.
// A transformed layer (`mapped` set) is sampled bilinearly through `inverse` (rows), which maps a
// target pixel back to a layer pixel, within the layer pixels `source` (x0, y0, x1, y1).
// Positions are scene pixels; a page holds only part of the scene, so `origins` gives where pixel
// (0, 0) of the output (xy) and of the layer's page or texture (zw) lie, `maskOrigin` of the
// mask's page, and `backdropOrigin` of a composite's backdrop copy and its blur. A backdrop blurred
// by `blur.wgsl` is `blurSize` pixels that each span `blurScale` pixels of the backdrop copy, and
// is scaled back up here as that shader's GROW does; `blurScale` 0 is a blur at full size.
struct Params {
  op: u32, mode: u32, opacity: u32, backdropEnabled: u32, clip: vec4f, pad0: u32, pad1: u32, maskOrigin: vec2i,
  inverse0: vec4f, inverse1: vec4f, inverse2: vec4f, source: vec4f, mapped: u32, masked: u32, rounded: u32, blurScale: u32,
  // The content mask the layer lands in; its rounded corners clip the layer.
  maskBounds: vec4f, maskRadii: Radii,
  origins: vec4i,
  backdropOrigin: vec2i, blurSize: vec2u,
  // The corners of the backdrop's `clip`.
  clipRadii: Radii,
}
// A copy of common.wgsl's corner functions, which this shader is not prepended with.
// Corner radii, fitted on the CPU (Radii.fitted): horizontal `x` and vertical `y` of the
// top-left, top-right, bottom-right and bottom-left corners. A corner with a zero radius is square.
struct Radii { x: vec4f, y: vec4f }

// The radii (horizontal, vertical) of the corner of quadrant `q` (from the center).
fn pickRadii(q: vec2f, r: Radii) -> vec2f {
  if q.x < 0.0 {
    return select(vec2f(r.x.w, r.y.w), vec2f(r.x.x, r.y.x), q.y < 0.0);
  }
  return select(vec2f(r.x.z, r.y.z), vec2f(r.x.y, r.y.y), q.y < 0.0);
}

// Signed distance to the ellipse with radii `e` from `d`, a point measured from its center: the
// implicit function over its gradient, exact for a circle. Matches radii.ellipseDistance.
fn ellipseDistance(d: vec2f, e: vec2f) -> f32 {
  let k1 = length(d / (e * e));
  if k1 <= 0.0 { return -min(e.x, e.y); }
  let k0 = length(d / e);
  return k0 * (k0 - 1.0) / k1;
}

// Signed distance from `a`, a point folded into the positive quadrant of a rectangle of half size
// `half`, to that rectangle with the corner there the quarter ellipse with radii `e`.
fn foldedRectSdf(a: vec2f, half: vec2f, e: vec2f) -> f32 {
  let d = a - (half - e);
  // Circular and square corners, the common case, take the branch-free circle distance.
  if e.x == e.y { return min(max(d.x, d.y), 0.0) + length(max(d, vec2f(0.0))) - e.x; }
  if d.x > 0.0 && d.y > 0.0 && e.x > 0.0 && e.y > 0.0 {
    return ellipseDistance(d, e);
  }
  let b = a - half;
  return min(max(b.x, b.y), 0.0) + length(max(b, vec2f(0.0)));
}

// Signed distance from `p` to rectangle `r` with corners `radii`; negative inside.
fn roundedRectSdf(p: vec2f, r: vec4f, radii: Radii) -> f32 {
  let half = (r.zw - r.xy) * 0.5;
  let q = p - (r.xy + half);
  return foldedRectSdf(abs(q), half, max(pickRadii(q, radii), vec2f(0.0)));
}

@group(0) @binding(0) var<uniform> params: Params;
@group(0) @binding(1) var backdrop: texture_2d<f32>;
@group(0) @binding(2) var layer: texture_2d<f32>;
@group(0) @binding(3) var filteredBackdrop: texture_2d<f32>;

const OP_COMPOSITE: u32 = 0u;
const OP_COPY: u32 = 1u;
const OP_BLIT: u32 = 2u;

@vertex fn vs(@builtin(vertex_index) index: u32) -> @builtin(position) vec4f {
  let p = vec2f(f32((index << 1u) & 2u), f32(index & 2u));
  return vec4f(p * 2.0 - 1.0, 0.0, 1.0);
}

// `s` inside the mask layer's alpha at scene pixel `pixel`, as vector.filter's COMPOSITE_IN.
fn inMask(s: vec4u, pixel: vec2i) -> vec4u {
  let a = bytes(filteredBackdrop, vec2u(pixel - params.maskOrigin)).w;
  return vec4u(div255(s.x * a), div255(s.y * a), div255(s.z * a), div255(s.w * a));
}

fn texel(x: f32, y: f32) -> vec4f {
  let start = vec2f(params.origins.zw);
  let size = vec2f(textureDimensions(layer));
  let low = max(params.source.xy, start);
  let high = min(params.source.zw, start + size) - 1.0;
  if x < low.x || y < low.y || x > high.x || y > high.y { return vec4f(0.0); }
  let at = vec2i(i32(floor(x)), i32(floor(y)));
  let local = vec2u(at - params.origins.zw);
  if params.masked != 0u { return vec4f(inMask(bytes(layer, local), at)); }
  return textureLoad(layer, local, 0) * 255.0;
}

fn mappedBytes(position: vec2f) -> vec4u {
  let p = vec3f(position, 1.0);
  let w = dot(params.inverse2.xyz, p);
  if w <= 0.000001 { return vec4u(0u); }
  let s = vec2f(dot(params.inverse0.xyz, p), dot(params.inverse1.xyz, p)) / w - 0.5;
  let f = floor(s);
  let t = s - f;
  let top = mix(texel(f.x, f.y), texel(f.x + 1.0, f.y), t.x);
  let bottom = mix(texel(f.x, f.y + 1.0), texel(f.x + 1.0, f.y + 1.0), t.x);
  return vec4u(round(clamp(mix(top, bottom, t.y), vec4f(0.0), vec4f(255.0))));
}

// The layer's bytes at scene pixel `pixel`; transparent outside its page.
fn layerBytes(pixel: vec2i) -> vec4u {
  let start = params.origins.zw;
  let size = vec2i(textureDimensions(layer));
  let local = pixel - start;
  if any(local < vec2i(0)) || any(local >= size) { return vec4u(0u); }
  return bytes(layer, vec2u(local));
}

fn blurredTexel(p: vec2i) -> vec4f {
  return textureLoad(filteredBackdrop, vec2u(clamp(p, vec2i(0), vec2i(params.blurSize) - 1)), 0);
}

// The blurred backdrop at pixel `under` of the backdrop copy, as bytes.
fn blurred(under: vec2u) -> vec4f {
  if params.blurScale == 0u { return vec4f(bytes(filteredBackdrop, under)); }
  let c = (vec2f(under) + 0.5) / f32(params.blurScale) - 0.5;
  let f = floor(c);
  let t = c - f;
  let q = vec2i(f);
  let top = mix(blurredTexel(q), blurredTexel(q + vec2i(1, 0)), t.x);
  let bottom = mix(blurredTexel(q + vec2i(0, 1)), blurredTexel(q + vec2i(1, 1)), t.x);
  return mix(top, bottom, t.y) * 255.0;
}

// How much of the pixel at `p` the mask's rounded corners keep (common.wgsl's cornerCoverage).
fn corner(p: vec2f) -> f32 {
  let r = params.maskBounds;
  let half = (r.zw - r.xy) * 0.5;
  let q = p - (r.xy + half);
  let e = pickRadii(q, params.maskRadii);
  if e.x <= 0.0 || e.y <= 0.0 { return 1.0; }
  let d = abs(q) - half + e;
  if d.x <= 0.0 || d.y <= 0.0 { return 1.0; }
  if e.x == e.y { return clamp(0.5 - (length(d) - e.x), 0.0, 1.0); }
  return clamp(0.5 - ellipseDistance(d, e), 0.0, 1.0);
}

// `s` scaled by `k` (0 to 1).
fn scaled(s: vec4u, k: f32) -> vec4u {
  if k >= 1.0 { return s; }
  return vec4u(round(vec4f(s) * k));
}

// `s` times the group opacity.
fn faded(s: vec4u) -> vec4u {
  return vec4u(div255(s.x * params.opacity), div255(s.y * params.opacity), div255(s.z * params.opacity), div255(s.w * params.opacity));
}

@fragment fn fs(@builtin(position) output: vec4f) -> @location(0) vec4f {
  let position = vec4f(output.xy + vec2f(params.origins.xy), output.zw);
  let pixel = vec2i(floor(position.xy));
  var content = vec4u(0u);
  if params.mapped != 0u {
    content = mappedBytes(position.xy);
  } else {
    content = layerBytes(pixel);
    if params.masked != 0u { content = inMask(content, pixel); }
  }
  if params.op == OP_COPY { return vec4f(content) / 255.0; }
  if params.rounded != 0u { content = scaled(content, corner(position.xy)); }
  if params.op == OP_BLIT {
    if params.opacity == 255u { return vec4f(content) / 255.0; }
    return vec4f(faded(content)) / 255.0;
  }
  let under = vec2u(pixel - params.backdropOrigin);
  var b = bytes(backdrop, under);
  if params.backdropEnabled != 0u {
    let distance = roundedRectSdf(position.xy, params.clip, params.clipRadii);
    let coverage = clamp(0.5 - distance, 0.0, 1.0) * f32(params.opacity) / 255.0;
    b = vec4u(round(mix(vec4f(b), blurred(under), coverage)));
  }
  if (params.opacity == 0u || content.w == 0u) && !clearsUnder(params.mode) { return vec4f(b) / 255.0; }
  var s = content;
  if params.opacity != 255u { s = faded(s); }
  return vec4f(blend(b, s, params.mode)) / 255.0;
}
