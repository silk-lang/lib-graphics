// A fast Gaussian blur for layer effects, as Skia draws large blurs: halve the image until the
// blur is a few pixels wide (HALVE), blur that with a separable kernel (ROWS, then COLUMNS), and
// scale the result back up bilinearly (GROW; layer.wgsl scales a blurred backdrop up itself, where
// it reads it). Its cost follows the image's pixels, not the blur's radius. Images are
// premultiplied RGBA8.
struct Params {
  op: u32,
  // The kernel's radius (ROWS, COLUMNS) or how many source pixels one image pixel spans (GROW).
  count: u32,
  // 1 repeats the image's edge pixels past its edges; 0 reads transparent there.
  clamped: u32,
  pad0: u32,
  // The image's pixels in its texture: x0, y0, x1, y1.
  image: vec4u,
  // The output pixel the image's first pixel lands on.
  origin: vec2u,
  pad1: vec2u,
  // `weights[i / 4][i % 4]` weighs the pixels `i` places from the center.
  weights: array<vec4f, 4>,
}
@group(0) @binding(0) var<uniform> params: Params;
@group(0) @binding(1) var image: texture_2d<f32>;

const OP_HALVE: u32 = 0u;
const OP_ROWS: u32 = 1u;
const OP_COLUMNS: u32 = 2u;
const OP_GROW: u32 = 3u;

@vertex fn vs(@builtin(vertex_index) index: u32) -> @builtin(position) vec4f {
  // One triangle covering the target.
  let p = vec2f(f32((index << 1u) & 2u), f32(index & 2u));
  return vec4f(p * 2.0 - 1.0, 0.0, 1.0);
}

fn size() -> vec2i { return vec2i(params.image.zw - params.image.xy); }

fn held(p: vec2i) -> vec4f {
  return textureLoad(image, vec2u(clamp(p, vec2i(0), size() - 1)) + params.image.xy, 0);
}

// The image's pixel `p`, counted from its first.
fn read(p: vec2i) -> vec4f {
  if params.clamped == 0u && (any(p < vec2i(0)) || any(p >= size())) { return vec4f(0.0); }
  return held(p);
}

fn weight(i: u32) -> f32 { return params.weights[i >> 2u][i & 3u]; }

@fragment fn fs(@builtin(position) position: vec4f) -> @location(0) vec4f {
  let p = vec2i(position.xy) - vec2i(params.origin);
  if params.op == OP_HALVE {
    let q = p * 2;
    return (read(q) + read(q + vec2i(1, 0)) + read(q + vec2i(0, 1)) + read(q + vec2i(1, 1))) * 0.25;
  }
  if params.op == OP_GROW {
    // Output pixel centers in image pixels; the image's edge pixels reach to the output's edge.
    let c = (vec2f(p) + 0.5) / f32(params.count) - 0.5;
    let f = floor(c);
    let t = c - f;
    let q = vec2i(f);
    let top = mix(held(q), held(q + vec2i(1, 0)), t.x);
    let bottom = mix(held(q + vec2i(0, 1)), held(q + vec2i(1, 1)), t.x);
    return mix(top, bottom, t.y);
  }
  var step = vec2i(1, 0);
  if params.op == OP_COLUMNS { step = vec2i(0, 1); }
  var sum = read(p) * weight(0u);
  for (var i = 1u; i <= params.count; i++) {
    let offset = step * i32(i);
    sum += (read(p + offset) + read(p - offset)) * weight(i);
  }
  return sum;
}
