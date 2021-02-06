/// Generative mesh primitives.
///
/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.graphics.primitives;

import gfx.genmesh.algorithm : indexCollectMesh, triangulate, vertices;
static import gfx.genmesh.poly;
import std.typecons : Flag, Yes;
import teraflop.math;

/// A generated vertex.
struct Vertex {
  ///
  vec3f position;
  ///
  vec3f normal;
}

/// Generate a quadrilateral of a normalized size, i.e. all axes bounded by `[-1, 1]`.
///
/// Examples:
/// <h3>Generate a square quadrilateral <a href="../Mesh.html">`Mesh`</a></h3>
/// ---
/// import std.algorithm : map;
/// import std.array : array;
/// import std.conv : to;
/// import std.typecons : No;
/// import teraflop.graphics : Color, Mesh, Primitive, VertexPosColor;
///
/// auto quadData = quad!No.normals;
/// auto vertices = quadData.vertices.map!(v => VertexPosColor(v.position, Color.blue)).array;
/// auto mesh = new Mesh!VertexPosColor(Primitive.triangleList, vertices, quadData.indices.to!(uint[]));
/// ---
auto @property quad(Flag!"normals" normals = Yes.normals)() {
  import std.range : only;

  // static if (normals == Yes.normals) {
  //   immutable float[3] n = [ 0,  0,  1 ];    // Z+
  //   immutable float[3] n = [ 0,  0, -1 ];    // Z-
  // }

  auto face = gfx.genmesh.poly.quad(
    Vertex( vec3f([-1, -1, 1]) /* Z+ */, vec3f([0,  0,  normals == Yes.normals ? 1 : 0]) /* Z+ */ ),
    Vertex( vec3f([1, -1, 1]) /* Z+ */, vec3f([0,  0,  normals == Yes.normals ? 1 : 0]) /* Z+ */ ),
    Vertex( vec3f([1, 1, 1]) /* Z+ */, vec3f([0,  0,  normals == Yes.normals ? 1 : 0]) /* Z+ */ ),
    Vertex( vec3f([-1, 1, 1]) /* Z+ */, vec3f([0,  0,  normals == Yes.normals ? 1 : 0]) /* Z+ */ ),
  );

  return only(face)
    .triangulate()
    .vertices()
    .indexCollectMesh();
}

unittest {
  import std.algorithm : equal;

  foreach (f; 0 .. 6) {
    immutable f6 = f*6;
    immutable f4 = f*4;
    assert(quad.indices[f6 .. f6+6].equal([f4, f4+1, f4+2, f4, f4+2, f4+3]));
  }
}

/// Generate a cube of a normalized size, i.e. all axes bounded by `[-1, 1]`.
///
/// Examples:
/// <h3>Generate a Cube <a href="../Mesh.html">`Mesh`</a></h3>
/// ---
/// import std.algorithm : map;
/// import std.array : array;
/// import std.conv : to;
/// import teraflop.graphics : Color, Mesh, Primitive, VertexPosColor;
///
/// auto cubeData = cube();
/// auto vertices = cubeData.vertices.map!(v => VertexPosColor(v.position, Color.blue)).array;
/// auto mesh = new Mesh!VertexPosColor(Primitive.triangleList, vertices, cubeData.indices.to!(uint[]));
/// ---
auto @property cube() {
  import gfx.genmesh.cube : genCube;
  import std.algorithm : map;

  return genCube()
    .map!(f => gfx.genmesh.poly.quad(
        Vertex( vec3f(f[0].p), vec3f(f[0].n) ),
        Vertex( vec3f(f[1].p), vec3f(f[1].n) ),
        Vertex( vec3f(f[2].p), vec3f(f[2].n) ),
        Vertex( vec3f(f[3].p), vec3f(f[3].n) ),
    ))
    .triangulate()
    .vertices()
    .indexCollectMesh();
}

unittest {
  import std.algorithm : equal;

  foreach (f; 0 .. 6) {
    immutable f6 = f*6;
    immutable f4 = f*4;
    assert(cube.indices[f6 .. f6+6].equal([f4, f4+1, f4+2, f4, f4+2, f4+3]));
  }
}
