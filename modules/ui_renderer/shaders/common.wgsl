// Shared by every UI pipeline (silk task embed-shaders prepends it). Coordinates are device pixels,
// y down. Colors leave the fragment shaders premultiplied; the pipelines blend source-over.
struct Globals {
  // Target width and height in pixels.
  size: vec2f,
  // Text: enhanced contrast for grayscale glyphs (0 turns it off).
  contrast: f32,
  unused: f32,
  // Text: DirectWrite gamma correction ratios (all 0 turns it off).
  gamma: vec4f,
  // Image-only retained scenes: uniform scale, reserved, translation x/y.
  imageCamera: vec4f,
  // Where the target's pixel (0, 0) lies in scene pixels: an offscreen page holds only the part
  // of the scene its layers cover. `size` is the target's own size. zw unused.
  origin: vec4f,
}
@group(0) @binding(0) var<uniform> globals: Globals;

// Gradient ramps, 256 premultiplied RGBA8 words each. Only quads and paths read it.
@group(0) @binding(7) var<storage, read> ramps: array<u32>;

const CORNERS = array<vec2f, 6>(vec2f(0.0, 0.0), vec2f(1.0, 0.0), vec2f(0.0, 1.0), vec2f(0.0, 1.0), vec2f(1.0, 0.0), vec2f(1.0, 1.0));

// Clip space for corner `index` of the pixel rectangle `r` (xMin, yMin, xMax, yMax).
fn corner(r: vec4f, index: u32) -> vec4f {
  let c = CORNERS[index];
  let p = mix(r.xy, r.zw, c) - globals.origin.xy;
  return vec4f(p.x / globals.size.x * 2.0 - 1.0, 1.0 - p.y / globals.size.y * 2.0, 0.0, 1.0);
}

// The pixels a primitive drawing `bounds` under `mask` touches: their intersection rounded out to
// whole pixels and clamped to the target, in scene pixels. Empty rectangles collapse to a point.
fn cover(bounds: vec4f, mask: vec4f) -> vec4f {
  let low = globals.origin.xy;
  let high = low + globals.size;
  let lo = clamp(floor(max(bounds.xy, mask.xy)), low, high);
  let hi = clamp(ceil(min(bounds.zw, mask.zw)), low, high);
  return vec4f(lo, max(hi, lo));
}

// How much of the pixel square around `p` (a pixel center) lies in `r`, as the CPU reference clips.
fn areaIn(r: vec4f, p: vec2f) -> f32 {
  let lo = max(p - 0.5, r.xy);
  let hi = min(p + 0.5, r.zw);
  let d = clamp(hi - lo, vec2f(0.0), vec2f(1.0));
  return d.x * d.y;
}

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

// Whether any corner of `radii` is rounded.
fn isRounded(radii: Radii) -> bool {
  return max(max(radii.x.x, radii.x.y), max(radii.x.z, radii.x.w)) > 0.0;
}

// How much of the pixel centered at `p` the rounded corners `radii` of content mask `r` keep: 1
// away from the corners, so the rectangle stays `areaIn`'s. Matches ContentMask.cornerCoverage.
fn cornerCoverage(r: vec4f, radii: Radii, p: vec2f) -> f32 {
  if !isRounded(radii) { return 1.0; }
  let half = (r.zw - r.xy) * 0.5;
  let q = p - (r.xy + half);
  let e = pickRadii(q, radii);
  if e.x <= 0.0 || e.y <= 0.0 { return 1.0; }
  let d = abs(q) - half + e;
  if d.x <= 0.0 || d.y <= 0.0 { return 1.0; }
  return clamp(0.5 - ellipseDistance(d, e), 0.0, 1.0);
}

// Signed distance from `p` to rectangle `r` whose corner in `p`'s quadrant is the quarter
// ellipse with radii `e`.
fn ellipticRectSdf(p: vec2f, r: vec4f, e: vec2f) -> f32 {
  let half = (r.zw - r.xy) * 0.5;
  return foldedRectSdf(abs(p - (r.xy + half)), half, e);
}

// Coverage of the pixel at `p` from a signed distance: exact for a straight edge.
fn coverage(distance: f32) -> f32 {
  return clamp(0.5 - distance, 0.0, 1.0);
}

// A background: a solid color or a CSS gradient. `kind.x` is 0 for solid, 1 for a two-stop linear
// gradient mixed here in sRGB, 2 for one read from ramp `kind.y` of `ramps` (any other
// interpolation, sampled on the CPU with silk.color), 3 for a gradient with any number of stops
// mixed here in sRGB: `first.x` of them at word `kind.y` of `ramps`, five words each (the offset,
// then the straight color), repeating when `first.y` is 1. With any other interpolation `first.z`
// is one more than the first of their ramps, one per pair of neighbours. `kind.w` is the shape: 0 linear,
// 1 radial, 2 conic. For two stops `first` and `last` hold them, straight sRGB (`first` is the
// solid color). `line` is the center and then the direction (linear), the reciprocal radii
// (radial) or the start angle in turns (conic); `stops` holds the linear half length and the two
// stop offsets.
struct Paint {
  kind: vec4u,
  first: vec4f,
  last: vec4f,
  line: vec4f,
  stops: vec4f,
}

fn premultiply(c: vec4f) -> vec4f {
  let s = clamp(c, vec4f(0.0), vec4f(1.0));
  return vec4f(s.rgb * s.a, s.a);
}

// The premultiplied color of `paint` at pixel center `p`. Gradients take their parameter in
// 1/255 steps and mix premultiplied, as the CPU reference's 256-entry ramp does.
fn shade(paint: Paint, p: vec2f) -> vec4f {
  if paint.kind.x == 0u { return premultiply(paint.first); }
  let d = p - paint.line.xy;
  var along = dot(d, paint.line.zw) / paint.stops.x * 0.5 + 0.5;
  if paint.kind.w == 1u {
    along = length(d * paint.line.zw);
  } else if paint.kind.w == 2u {
    let a = atan2(d.x, -d.y) / 6.2831855 - paint.line.z;
    along = a - floor(a);
  }
  if paint.kind.x == 3u { return shadeStops(paint, along); }
  let span = paint.stops.z - paint.stops.y;
  var t = select(0.0, 1.0, along >= paint.stops.y);
  if span > 0.0 { t = (along - paint.stops.y) / span; }
  let step = floor(clamp(t, 0.0, 1.0) * 255.0 + 0.5);
  if paint.kind.x == 2u { return unpack4x8unorm(ramps[paint.kind.y * 256u + u32(step)]); }
  return mixPremultiplied(paint.first, paint.last, step / 255.0);
}

// Straight colors `a` and `b` mixed premultiplied at `t`.
fn mixPremultiplied(a: vec4f, b: vec4f, t: f32) -> vec4f {
  let aa = clamp(a.a, 0.0, 1.0);
  let ba = clamp(b.a, 0.0, 1.0);
  let alpha = aa + (ba - aa) * t;
  if !(alpha > 0.0) { return vec4f(0.0); }
  let c = (a.rgb * aa + (b.rgb * ba - a.rgb * aa) * t) / alpha;
  return premultiply(vec4f(c, alpha));
}

fn stopOffset(base: u32, i: u32) -> f32 {
  return bitcast<f32>(ramps[base + i * 5u]);
}

fn stopColor(base: u32, i: u32) -> vec4f {
  let w = base + i * 5u;
  return vec4f(bitcast<f32>(ramps[w + 1u]), bitcast<f32>(ramps[w + 2u]), bitcast<f32>(ramps[w + 3u]), bitcast<f32>(ramps[w + 4u]));
}

// The stops of `paint` at offset `along`, mixed in 1/255 steps between neighbours.
fn shadeStops(paint: Paint, along: f32) -> vec4f {
  let base = paint.kind.y;
  let n = u32(paint.first.x);
  if n == 0u { return vec4f(0.0); }
  let first = stopOffset(base, 0u);
  let period = stopOffset(base, n - 1u) - first;
  var a = along;
  if paint.first.y > 0.5 && period > 0.000001 {
    let k = (a - first) / period;
    a = first + (k - floor(k)) * period;
  }
  var i = 0u;
  loop {
    if i + 1u >= n || stopOffset(base, i + 1u) > a { break; }
    i = i + 1u;
  }
  if i + 1u >= n || a < first { return mixPremultiplied(stopColor(base, i), stopColor(base, i), 0.0); }
  let lo = stopOffset(base, i);
  let t = (a - lo) / (stopOffset(base, i + 1u) - lo);
  let step = floor(clamp(t, 0.0, 1.0) * 255.0 + 0.5);
  if paint.first.z > 0.5 {
    return unpack4x8unorm(ramps[(u32(paint.first.z) - 1u + i) * 256u + u32(step)]);
  }
  return mixPremultiplied(stopColor(base, i), stopColor(base, i + 1u), step / 255.0);
}
