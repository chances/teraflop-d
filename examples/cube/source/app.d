import std.stdio;

import teraflop.game : Game;
import teraflop.graphics;
static import teraflop.graphics.primitives;
import teraflop.math;
import teraflop.platform : Window;
import teraflop.time : Time;

void main()
{
	writeln("Teraflop Cube Example");

  new Cube().run();
}

private final class Cube : Game {
  import teraflop.ecs : System, World;

  this() {
    super("Cube");
  }

  override void initializeWorld(scope World world) {
    import std.algorithm : map;
    import std.conv : to;
    import std.array : array;

    const framebufferSize = world.resources.get!Window.framebufferSize;
    auto camera = new Camera();
    camera.view = mat4f.lookAt(vec3f(8f), vec3f(0), up);
    camera.projection = mat4f.perspective(
      45.radians, framebufferSize.width / cast(float) framebufferSize.height, 0.01f, 1000.0f
    );
    world.resources.add(camera);

    auto shaders = [
      new Shader(ShaderStage.vertex, "examples/cube/assets/shaders/cube.vs.spv"),
      new Shader(ShaderStage.fragment, "examples/cube/assets/shaders/cube.fs.spv")
    ];

    auto colors = [Color.red.vec3f, Color.green.vec3f, Color.blue.vec3f, Color(1, 0, 1).vec3f];
    auto color = colors[3];
    auto cube = teraflop.graphics.primitives.cube();
    auto mesh = cube.vertices.map!(v => VertexPosColor(v.position, color)).array;

    world.spawn(
      new Material(shaders, FrontFace.clockwise),
      new Mesh!VertexPosColor(Primitive.triangleList, mesh, cube.indices.to!(uint[]))
    );
    this.add(System.from!aspectRatio);
    this.add(System.from!rotate);
  }

  static void aspectRatio(scope const Window window, scope Camera camera) {
    const framebufferSize = window.framebufferSize;
    camera.projection = mat4f.perspective(
      45.radians, framebufferSize.width / cast(float) framebufferSize.height, 0.01f, 1000.0f
    );
  }

  static void rotate(scope Time time, scope Camera camera) {
    import std.math : PI;

    // 6 RPM at 60 FPS
    const puls = 6 * 2*PI / 60f;
    camera.model = camera.model.rotation(puls * time.totalSeconds, up);
  }
}
