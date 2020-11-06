import std.stdio;

import teraflop.game : Game;
import teraflop.math;

void main()
{
	writeln("Teraflop Cube Example");

  new Cube().run();
}

private final class Cube : Game {
  import teraflop.ecs : World;
  import teraflop.graphics : Color, Material, Mesh, Shader, ShaderStage, VertexPosColor;

  this() {
    super("Cube");
  }

  override void initializeWorld(scope World world) {
    auto shaders = [
      new Shader(ShaderStage.vertex, "examples/cube/assets/shaders/cube.vs.spv"),
      new Shader(ShaderStage.fragment, "examples/cube/assets/shaders/cube.fs.spv")
    ];

    // TODO: Add a `Camera` component (resource?) with uniform buffers
    world.spawn(new Material(shaders), new Mesh!VertexPosColor([
      VertexPosColor(vec2f(0.0f, -0.5f), Color.red.vec3f),
      VertexPosColor(vec2f(0.5f, 0.5f), Color.green.vec3f),
      VertexPosColor(vec2f(-0.5f, 0.5f), Color.blue.vec3f),
    ], [0, 1, 2]));
  }
}
