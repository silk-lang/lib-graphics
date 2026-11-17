// Isolated layers: composite a layer onto a copy of what is under it with a vector.layer blend
// mode and a group opacity (prepended with gpu_scene's blend.wgsl), and copy a finished frame out
// to a target of any format. A plain layer (normal blend, no filters, no mask) is instead blitted
// inside its parent's pass, where the pipeline blends it source-over. A blit that is `masked` keeps
// the layer inside the alpha of its mask layer, bound in place of the filtered backdrop.
// A transformed layer (`mapped` set) is sampled bilinearly through `inverse` (rows), which maps a
// target pixel back to a layer pixel, within the layer pixels `source` (x0, y0, x1, y1).
struct Params {
  op: u32, mode: u32, opacity: u32, backdropEnabled: u32, clip: vec4f, radius: f32, shape: u32, unused: vec2u,
  inverse0: vec4f, inverse1: vec4f, inverse2: vec4f, source: vec4f, mapped: u32, masked: u32, pad1: u32, pad2: u32,
  // The content mask the layer lands in; its rounded corners clip the layer (radii tl, tr, br, bl).
  maskBounds: vec4f, maskRadii: vec4f,
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

// `s` inside the mask layer's alpha at `pixel`, as vector.filter's COMPOSITE_IN.
fn inMask(s: vec4u, pixel: vec2u) -> vec4u {
  let a = bytes(filteredBackdrop, pixel).w;
  return vec4u(div255(s.x * a), div255(s.y * a), div255(s.z * a), div255(s.w * a));
}

fn texel(x: f32, y: f32) -> vec4f {
  let size = vec2f(textureDimensions(layer));
  let low = max(params.source.xy, vec2f(0.0));
  let high = min(params.source.zw, size) - 1.0;
  if x < low.x || y < low.y || x > high.x || y > high.y { return vec4f(0.0); }
  let at = vec2u(u32(x), u32(y));
  if params.masked != 0u { return vec4f(inMask(bytes(layer, at), at)); }
  return textureLoad(layer, at, 0) * 255.0;
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

// How much of the pixel at `p` the mask's rounded corners keep (common.wgsl's cornerCoverage).
fn corner(p: vec2f) -> f32 {
  let radii = params.maskRadii;
  if max(max(radii.x, radii.y), max(radii.z, radii.w)) <= 0.0 { return 1.0; }
  let r = params.maskBounds;
  let half = (r.zw - r.xy) * 0.5;
  let q = p - (r.xy + half);
  var picked = select(radii.z, radii.y, q.y < 0.0);
  if q.x < 0.0 { picked = select(radii.w, radii.x, q.y < 0.0); }
  let radius = clamp(picked, 0.0, max(min(half.x, half.y), 0.0));
  if radius <= 0.0 { return 1.0; }
  let d = abs(q) - half + radius;
  if d.x <= 0.0 || d.y <= 0.0 { return 1.0; }
  return clamp(0.5 - (length(d) - radius), 0.0, 1.0);
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

@fragment fn fs(@builtin(position) position: vec4f) -> @location(0) vec4f {
  let pixel = vec2u(position.xy);
  var content = bytes(layer, pixel);
  if params.mapped != 0u {
    content = mappedBytes(position.xy);
  } else if params.masked != 0u {
    content = inMask(content, pixel);
  }
  if params.op == OP_COPY { return vec4f(content) / 255.0; }
  content = scaled(content, corner(position.xy));
  if params.op == OP_BLIT {
    if params.opacity == 255u { return vec4f(content) / 255.0; }
    return vec4f(faded(content)) / 255.0;
  }
  var b = bytes(backdrop, pixel);
  if params.backdropEnabled != 0u {
    let halfSize = (params.clip.zw - params.clip.xy) * 0.5;
    let p = position.xy - (params.clip.xy + halfSize);
    let radius = min(params.radius, min(halfSize.x, halfSize.y));
    let q = abs(p) - halfSize + radius;
    var distance = length(max(q, vec2f(0.0))) + min(max(q.x, q.y), 0.0) - radius;
    if params.shape == 1u {
      let normalized = p / max(halfSize, vec2f(0.001));
      distance = (length(normalized) - 1.0) * min(halfSize.x, halfSize.y);
    }
    let coverage = clamp(0.5 - distance, 0.0, 1.0) * f32(params.opacity) / 255.0;
    b = vec4u(round(mix(vec4f(b), vec4f(bytes(filteredBackdrop, pixel)), coverage)));
  }
  if params.opacity == 0u || content.w == 0u { return vec4f(b) / 255.0; }
  var s = content;
  if params.opacity != 255u { s = faded(s); }
  return vec4f(blend(b, s, params.mode)) / 255.0;
}
