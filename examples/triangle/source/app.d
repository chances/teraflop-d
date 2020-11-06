import std.stdio;

import teraflop.game : Game;

void main()
{
	writeln("Teraflop Trianlge Example");

  new Triangle().run();
}

private final class Triangle : Game {
  import teraflop.ecs : World;
  import teraflop.graphics : Material, Shader, ShaderStage;

  this() {
    super("Triangle");
  }

  override void initializeWorld(scope World world) {
    auto shaders = [
      new Shader(ShaderStage.vertex, "examples/triangle/assets/shaders/triangle.vs.spv"),
      new Shader(ShaderStage.fragment, "examples/triangle/assets/shaders/triangle.fs.spv")
    ];

    // TODO: Add a triangle Entity
    // TODO: Add a `Mesh` component with vertex layouts/buffers and uniform buffers
    world.spawn(new Material(shaders));
  }
}
