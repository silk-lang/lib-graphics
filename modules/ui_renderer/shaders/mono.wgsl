// Monochrome sprites: glyphs and icons, a coverage tile tinted with one color, with the
// DirectWrite contrast and gamma correction for text (from Windows Terminal's dwrite.hlsl, MIT,
// as GPUI uses it).
struct MonoSprite {
  bounds: vec4f,
  mask: vec4f,
  // straight alpha
  color: vec4f,
  tile: vec4f,
  maskRadii: Radii,
  // x is the transform, y the scroll group (a `Placement`).
  extra: vec4f,
}
@group(0) @binding(1) var<storage, read> sprites: array<MonoSprite>;

// Where a scroll group draws: what it holds is moved by `offset.xy` and cut to `clip` with
// corners `clipRadii`. Sprites keep the bounds and mask they were painted with and name their
// group, so a scroll writes these and no sprite. Entry 0, outside every group, moves nothing.
struct Placement {
  offset: vec4f,
  clip: vec4f,
  clipRadii: Radii,
}
@group(0) @binding(9) var<storage, read> placements: array<Placement>;

@vertex fn vs(@builtin(vertex_index) v: u32, @builtin(instance_index) index: u32) -> Varying {
  let s = sprites[index];
  let g = placements[u32(s.extra.y)];
  let own = s.mask + g.offset.xyxy;
  let mask = vec4f(max(own.xy, g.clip.xy), min(own.zw, g.clip.zw));
  let placed = place(s.bounds + g.offset.xyxy, mask, u32(s.extra.x), v);
  return Varying(placed.position, index, placed.local);
}

fn brightness(color: vec3f) -> f32 {
  return dot(color, vec3f(0.30, 0.59, 0.11));
}

// The correction of glyph coverage `alpha` for text of `color`.
fn correctText(alpha: f32, color: vec3f) -> f32 {
  let b = brightness(color);
  let k = globals.contrast * clamp(4.0 * (0.75 - b), 0.0, 1.0);
  let a = alpha * (k + 1.0) / (alpha * k + 1.0);
  let g = globals.gamma;
  let correction = (g.x * b + g.y) * a + (g.z * b + g.w);
  return a + a * (1.0 - a) * correction;
}

@fragment fn fs(v: Varying) -> @location(0) vec4f {
  let s = sprites[v.index];
  let at = spot(v.position, v.local, u32(s.extra.x));
  let p = at.p;
  let g = placements[u32(s.extra.y)];
  let bounds = s.bounds + g.offset.xyxy;
  let own = s.mask + g.offset.xyxy;
  let clipped = vec4f(max(max(own.xy, g.clip.xy), bounds.xy), min(min(own.zw, g.clip.zw), bounds.zw));
  let clip = areaInAt(clipped, p, at.scale) * cornerCoverageAt(own, s.maskRadii, p, at.scale)
    * cornerCoverageAt(g.clip, g.clipRadii, p, at.scale) * at.keep;
  if clip <= 0.0 { discard; }
  let sample = sampleTile(s.tile, bounds, p).r;
  let alpha = clamp(correctText(sample, clamp(s.color.rgb, vec3f(0.0), vec3f(1.0))), 0.0, 1.0);
  return premultiply(s.color) * (alpha * clip);
}
