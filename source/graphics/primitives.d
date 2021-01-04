/// Generative mesh primitives.
///
/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: MIT License
module teraflop.graphics.primitives;

import gfx.genmesh.algorithm : indexCollectMesh, triangulate, vertices;
import teraflop.math;

struct Vertex {
  vec3f position;
  vec3f normal;
}

/// Generate a cube of a normalized size, i.e. all axes bounded by `[-1, 1]`.
auto cube() {
  import gfx.genmesh.cube : genCube;
  import gfx.genmesh.poly : quad;
  import std.algorithm : map;

  return genCube()
    .map!(f => quad(
        Vertex( vec3f(f[0].p), vec3f(f[0].n) ),
        Vertex( vec3f(f[1].p), vec3f(f[1].n) ),
        Vertex( vec3f(f[2].p), vec3f(f[2].n) ),
        Vertex( vec3f(f[3].p), vec3f(f[3].n) ),
    ))
    .triangulate()
    .vertices()
    .indexCollectMesh();
}
