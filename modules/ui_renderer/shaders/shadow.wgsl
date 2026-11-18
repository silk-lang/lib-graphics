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
  // sigma, inset (1 or 0)
  params: vec4f,
  maskRadii: Radii,
}
@group(0) @binding(1) var<storage, read> shadows: array<Shadow>;

struct Varying { @builtin(position) position: vec4f, @location(0) @interpolate(flat) index: u32 }

@vertex fn vs(@builtin(vertex_index) v: u32, @builtin(instance_index) index: u32) -> Varying {
  let s = shadows[index];
  return Varying(corner(cover(s.reach, s.mask), v), index);
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
// the side of the corner with radii `e`.
fn reachAt(y: f32, e: vec2f, half: vec2f) -> f32 {
  if e.x <= 0.0 || e.y <= 0.0 { return half.x; }
  let delta = min(half.y - e.y - abs(y), 0.0) / e.y;
  return half.x - e.x + e.x * sqrt(max(0.0, 1.0 - delta * delta));
}

// The blurred coverage of one row `y` (from the center) of the rounded box, at `x`.
// `mirrored` when the left corners match the right ones, so one reach serves both sides.
fn blurAlongX(x: f32, y: f32, sigma: f32, radii: Radii, half: vec2f, mirrored: bool) -> f32 {
  let left = reachAt(y, pickRadii(vec2f(-1.0, y), radii), half);
  var right = left;
  if !mirrored { right = reachAt(y, pickRadii(vec2f(1.0, y), radii), half); }
  let integral = 0.5 + 0.5 * erf2((x + vec2f(-right, left)) * (SQRT_HALF / sigma));
  return integral.y - integral.x;
}

@fragment fn fs(v: Varying) -> @location(0) vec4f {
  let s = shadows[v.index];
  let p = v.position.xy + globals.origin.xy;
  let clip = areaIn(s.mask, p) * cornerCoverage(s.mask, s.maskRadii, p);
  if clip <= 0.0 { discard; }
  let sigma = s.params.x;
  var alpha = 0.0;
  if s.shape.x < s.shape.z && s.shape.y < s.shape.w {
    if sigma < 0.05 {
      alpha = coverage(roundedRectSdf(p, s.shape, s.shapeRadii));
    } else {
      let half = (s.shape.zw - s.shape.xy) * 0.5;
      let q = p - (s.shape.xy + half);
      // The kernel is only non-zero over the shape's rows within 3 sigma.
      let start = clamp(-3.0 * sigma, q.y - half.y, q.y + half.y);
      let end = clamp(3.0 * sigma, q.y - half.y, q.y + half.y);
      let step = (end - start) / f32(SAMPLES);
      var y = start + step * 0.5;
      let r = s.shapeRadii;
      let mirrored = all(r.x.xw == r.x.yz) && all(r.y.xw == r.y.yz);
      for (var i = 0; i < SAMPLES; i += 1) {
        alpha += blurAlongX(q.x, q.y - y, sigma, s.shapeRadii, half, mirrored) * gaussian(y, sigma) * step;
        y += step;
      }
    }
  }
  if s.params.y != 0.0 {
    alpha = (1.0 - alpha) * coverage(roundedRectSdf(p, s.box, s.boxRadii));
  }
  return premultiply(s.color) * (clamp(alpha, 0.0, 1.0) * clip);
}
