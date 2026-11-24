// Shadows: a rounded rectangle blurred by a Gaussian, evaluated in closed form along x with an
// erf approximation and integrated numerically along y (Evan Wallace's method, as GPUI does).
struct Shadow {
  // The blurred shape: the box moved by the offset and grown (or, inset, shrunk) by the spread.
  shape: vec4f,
  mask: vec4f,
  shapeRadii: Radii,
  // straight alpha
  color: vec4f,
  // The box casting the shadow; an inset shadow draws only inside it.
  box: vec4f,
  boxRadii: Radii,
  // Everything the shadow can touch.
  reach: vec4f,
  // sigma, inset (1 or 0), the transform
  params: vec4f,
  maskRadii: Radii,
}
@group(0) @binding(1) var<storage, read> shadows: array<Shadow>;

struct Varying { @builtin(position) position: vec4f, @location(0) @interpolate(flat) index: u32, @location(1) local: vec2f }

@vertex fn vs(@builtin(vertex_index) v: u32, @builtin(instance_index) index: u32) -> Varying {
  let s = shadows[index];
  let placed = place(s.reach, s.mask, u32(s.params.z), v);
  return Varying(placed.position, index, placed.local);
}

const SQRT_HALF: f32 = 0.7071067811865476;
const SQRT_TAU: f32 = 2.5066282746310002;
const SAMPLES: i32 = 8;

fn gaussian(x: f32, sigma: f32) -> f32 {
  return exp(-(x * x) / (2.0 * sigma * sigma)) / (SQRT_TAU * sigma);
}

// Abramowitz and Stegun 7.1.27, |error| < 5e-4.
fn erf2(v: vec2f) -> vec2f {
  let s = sign(v);
  let a = abs(v);
  let r1 = 1.0 + (0.278393 + (0.230389 + (0.000972 + 0.078108 * a) * a) * a) * a;
  let r2 = r1 * r1;
  return s - s / (r2 * r2);
}

// How far row `y` (from the center) of a box of half size `half` reaches out from the center on
// the side of the corner with radii `e`; `inverse` is 1 / e.y, or 0 for a square corner.
fn reachAt(y: f32, e: vec2f, inverse: f32, half: vec2f) -> f32 {
  let delta = min(half.y - e.y - abs(y), 0.0) * inverse;
  return half.x - e.x + e.x * sqrt(max(0.0, 1.0 - delta * delta));
}

// 1 / e.y for a rounded corner with radii `e`, 0 for a square one.
fn inverseOf(e: vec2f) -> f32 {
  return select(0.0, 1.0 / e.y, e.x > 0.0 && e.y > 0.0);
}

@fragment fn fs(v: Varying) -> @location(0) vec4f {
  let s = shadows[v.index];
  let at = spot(v.position, v.local, u32(s.params.z));
  let p = at.p;
  let clip = areaInAt(s.mask, p, at.scale) * cornerCoverageAt(s.mask, s.maskRadii, p, at.scale) * at.keep;
  if clip <= 0.0 { discard; }
  let sigma = s.params.x;
  var alpha = 0.0;
  if s.shape.x < s.shape.z && s.shape.y < s.shape.w {
    if sigma < 0.05 {
      alpha = roundedCoverage(p, s.shape, s.shapeRadii, at.scale);
    } else {
      let half = (s.shape.zw - s.shape.xy) * 0.5;
      let q = p - (s.shape.xy + half);
      // The kernel is only non-zero over the shape's rows within 3 sigma.
      let start = clamp(-3.0 * sigma, q.y - half.y, q.y + half.y);
      let end = clamp(3.0 * sigma, q.y - half.y, q.y + half.y);
      let step = (end - start) / f32(SAMPLES);
      var y = start + step * 0.5;
      // The corners on each side, above and below the center: a row reaches out to the corner
      // on its side, so each sample takes one reach per side (one when the sides match).
      let r = s.shapeRadii;
      let mirrored = all(r.x.xw == r.x.yz) && all(r.y.xw == r.y.yz);
      let leftTop = vec2f(r.x.x, r.y.x);
      let leftBottom = vec2f(r.x.w, r.y.w);
      let rightTop = vec2f(r.x.y, r.y.y);
      let rightBottom = vec2f(r.x.z, r.y.z);
      let inverses = vec4f(inverseOf(leftTop), inverseOf(leftBottom), inverseOf(rightTop), inverseOf(rightBottom));
      let scale = SQRT_HALF / sigma;
      for (var i = 0; i < SAMPLES; i += 1) {
        let row = q.y - y;
        let top = row < 0.0;
        let left = reachAt(row, select(leftBottom, leftTop, top), select(inverses.y, inverses.x, top), half);
        var right = left;
        if !mirrored {
          right = reachAt(row, select(rightBottom, rightTop, top), select(inverses.w, inverses.z, top), half);
        }
        let integral = 0.5 + 0.5 * erf2((q.x + vec2f(-right, left)) * scale);
        alpha += (integral.y - integral.x) * gaussian(y, sigma) * step;
        y += step;
      }
    }
  }
  if s.params.y != 0.0 {
    alpha = (1.0 - alpha) * roundedCoverage(p, s.box, s.boxRadii, at.scale);
  } else if s.params.w != 0.0 {
    alpha = alpha * (1.0 - roundedCoverage(p, s.box, s.boxRadii, at.scale));
  }
  return premultiply(s.color) * (clamp(alpha, 0.0, 1.0) * clip);
}
