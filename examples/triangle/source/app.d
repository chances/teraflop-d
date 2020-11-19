import std.stdio;

import teraflop.game : Game;
import teraflop.math;

void main()
{
	writeln("Teraflop Triangle Example");

  new Triangle().run();
}

private final class Triangle : Game {
  import teraflop.ecs : World;
  import teraflop.graphics : Color, Material, Mesh, Shader, ShaderStage, VertexPosColor;

  this() {
    super("Triangle");
  }

  override void initializeWorld(scope World world) {
    auto shaders = [
      new Shader(ShaderStage.vertex, "examples/triangle/assets/shaders/triangle.vs.spv"),
      new Shader(ShaderStage.fragment, "examples/triangle/assets/shaders/triangle.fs.spv")
    ];

    world.spawn(new Material(shaders), new Mesh!VertexPosColor([
      VertexPosColor(vec3f(0.0f, -0.5f, 0), Color.red.vec3f),
      VertexPosColor(vec3f(0.5f, 0.5f, 0), Color.green.vec3f),
      VertexPosColor(vec3f(-0.5f, 0.5f, 0), Color.blue.vec3f),
    ], [0, 1, 2]));
  }
}
