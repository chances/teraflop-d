/// Static and generative mesh primitives.
///
/// Authors: Chance Snow
/// Copyright: Copyright © 2022 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.graphics.primitives;

import teraflop.math;

///
struct VertexPosNormal {
  ///
  vec3f position;
  ///
  vec3f normal;
}

///
struct VertexPosColor {
  ///
  vec3f position;
  ///
  vec4f color;
}
