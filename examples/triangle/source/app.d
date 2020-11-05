import std.stdio;

import teraflop.game : Game;

void main()
{
	writeln("Teraflop Trianlge Example");

  new Triangle().run();
}

private final class Triangle : Game {
  import teraflop.graphics : Shader, ShaderStage;

  this() {
    super("Triangle");
  }

  override void initializeWorld() {
    auto shaders = [
      new Shader(ShaderStage.vertex, "examples/triangle/assets/shaders/triangle.vs.spv"),
      new Shader(ShaderStage.fragment, "examples/triangle/assets/shaders/triangle.fs.spv")
    ];

    // TODO: Add a triangle Entity
  }
}
