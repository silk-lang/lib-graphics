// Polychrome sprites: images, color glyphs and color icons from premultiplied RGBA tiles, with
// opacity, corner radii and grayscale.
struct PolySprite {
  bounds: vec4f,
  mask: vec4f,
  tile: vec4f,
  clipBounds: vec4f,
  radii: vec4f,
  // opacity, grayscale (1 or 0), quarter turns, the transform
  params: vec4f,
  maskRadii: vec4f,
}
@group(0) @binding(1) var<storage, read> sprites: array<PolySprite>;

fn cameraSprite(source: PolySprite) -> PolySprite {
  var s = source;
  let camera = globals.imageCamera;
  let translation = vec4f(camera.zw, camera.zw);
  s.bounds = source.bounds * camera.x + translation;
  s.mask = source.mask * camera.x + translation;
  s.clipBounds = source.clipBounds * camera.x + translation;
  s.radii = source.radii * camera.x;
  return s;
}

@vertex fn vs(@builtin(vertex_index) v: u32, @builtin(instance_index) index: u32) -> Varying {
  let s = cameraSprite(sprites[index]);
  let placed = place(s.bounds, s.mask, u32(s.params.w), v);
  return Varying(placed.position, index, placed.local);
}

@fragment fn fs(v: Varying) -> @location(0) vec4f {
  let s = cameraSprite(sprites[v.index]);
  let at = spot(v.position, v.local, u32(s.params.w));
  let p = at.p;
  let radii = clamp(s.radii, vec4f(0.0), vec4f(max(min(s.clipBounds.z - s.clipBounds.x, s.clipBounds.w - s.clipBounds.y) * 0.5, 0.0)));
  let weight = roundedCoverage(p, s.clipBounds, radii, at.scale) * clamp(s.params.x, 0.0, 1.0) * areaInAt(s.mask, p, at.scale) * cornerCoverageAt(s.mask, s.maskRadii, p, at.scale) * at.keep;
  if weight <= 0.0 { discard; }
  var uv = (p - s.bounds.xy) / (s.bounds.zw - s.bounds.xy);
  let turn = u32(s.params.z);
  if turn == 1u { uv = vec2f(uv.y, 1.0 - uv.x); }
  if turn == 2u { uv = vec2f(1.0) - uv; }
  if turn == 3u { uv = vec2f(1.0 - uv.y, uv.x); }
  var c = sampleTile(s.tile, s.bounds, s.bounds.xy + uv * (s.bounds.zw - s.bounds.xy));
  if s.params.y != 0.0 {
    let l = dot(c.rgb, vec3f(0.2126, 0.7152, 0.0722));
    c = vec4f(l, l, l, c.a);
  }
  return c * weight;
}
