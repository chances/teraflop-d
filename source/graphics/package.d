/// Graphics pipeline primitives.
///
/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.graphics;

import erupted;

/// A programmable stage in the graphics `Pipeline`.
enum ShaderStage {
  /// For every vertex, generally applies transformations to turn vertex positions from model space to screen space.
  vertex,
  /// Subdivide geometry to increase the mesh quality.
  tesselation,
  /// For every primitive (triangle, line, point) either discard it or output more primitives than came in. Similar to
  /// the tessellation shader, but much more flexible.
  geometry,
  /// For every fragment that survives and determines which framebuffer(s) the fragments are written to and with which
  /// color and depth values. It can do this using the interpolated data from the vertex shader, which can include
  /// things like texture coordinates and normals for lighting.
  fragment
}

/// A SPIR-V program for one programmable stage in the graphics `Pipeline`.
struct Shader {
  package (teraflop) VkShaderModule modules;
  /// The stage in the graphics pipeline in which this Shader performs.
  const ShaderStage stage;

  /// Initialize a new Shader.
  ///
  /// Params:
  /// stage = The stage in the graphics pipeline in which this Shader performs.
  /// spv = SPIR-V source bytecode.
  this(ShaderStage stage, ubyte[] spv) {
    this.stage = stage;
  }
}

/// A graphics pipeline transforming input vertex/index buffers and outputting rasterized, tesselated, shaded, and
/// blended output.
class Pipeline {
  package (teraflop) VkShaderModule[ShaderStage] modules;
}
