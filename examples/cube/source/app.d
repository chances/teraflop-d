import std.stdio;

import teraflop.game : Game;
import teraflop.math;
import teraflop.platform : Window;

void main()
{
	writeln("Teraflop Cube Example");

  new Cube().run();
}

private final class Cube : Game {
  import teraflop.ecs : System, World;
  import teraflop.graphics : Camera, Color, FrontFace, Material, Mesh, Shader, ShaderStage, VertexPosColor;

  this() {
    super("Cube");
  }

  override void initializeWorld(scope World world) {
    const framebufferSize = world.resources.get!Window.framebufferSize;
    auto camera = new Camera();
    camera.view = mat4f.lookAt(vec3f(2f), vec3f(0), up);
    camera.projection = mat4f.perspective(
      45.radians, framebufferSize.width / cast(float) framebufferSize.height, 0.05f, 10.0f
    );
    world.resources.add(camera);

    auto shaders = [
      new Shader(ShaderStage.vertex, "examples/cube/assets/shaders/cube.vs.spv"),
      new Shader(ShaderStage.fragment, "examples/cube/assets/shaders/cube.fs.spv")
    ];

    world.spawn(new Material(shaders, FrontFace.counterClockwise), new Mesh!VertexPosColor([
      VertexPosColor(vec2f(0.0f, -0.5f), Color.red.vec3f),
      VertexPosColor(vec2f(0.5f, 0.5f), Color.green.vec3f),
      VertexPosColor(vec2f(-0.5f, 0.5f), Color.blue.vec3f),
    ], [0, 1, 2]));

    this.add(System.from!aspectRatio);
  }

  static void aspectRatio(scope const Window window, scope Camera camera) {
    const framebufferSize = window.framebufferSize;
    camera.projection = mat4f.perspective(
      45.radians, framebufferSize.width / cast(float) framebufferSize.height, 0.05f, 10.0f
    );
  }
}
