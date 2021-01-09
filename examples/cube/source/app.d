import std.stdio;

import teraflop.components;
import teraflop.game : Game;
import teraflop.graphics;
import teraflop.math;

void main()
{
	writeln("Teraflop Cube Example");

  new Cube().run();
}

private final class Cube : Game {
  import teraflop.ecs : System, World;
  import teraflop.platform : Window;
  import teraflop.systems : FileWatcher;
  import teraflop.time : Time;

  this() {
    super("Cube");
  }

  override void initializeWorld(scope World world) {
    import std.algorithm : map;
    import std.conv : to;
    import std.array : array;
    import teraflop.graphics.primitives : cube;

    const framebufferSize = world.resources.get!Window.framebufferSize;
    auto camera = new Camera();
    camera.view = mat4f.lookAt(vec3f(8f), vec3f(0), up);
    camera.projection = mat4f.perspective(
      45.radians, framebufferSize.width / cast(float) framebufferSize.height, 0.01f, 1000.0f
    );
    world.resources.add(camera);
    this.add(new FileWatcher(world));
    this.add(System.from!aspectRatio);
    this.add(System.from!rotate);

    auto shaders = [
      Shader.watched(ShaderStage.vertex, "examples/cube/assets/shaders/cube.vs.spv"),
      Shader.watched(ShaderStage.fragment, "examples/cube/assets/shaders/cube.fs.spv")
    ];
    auto flat = new Material(shaders, FrontFace.clockwise, CullMode.front);

    auto colors = [Color.red.vec3f, Color.green.vec3f, Color.blue.vec3f, Color(1, 0, 1).vec3f];
    auto cubeData = cube();
    auto mesh = (vec3f color) => cubeData.vertices.map!(v => VertexPosNormalColor(v.position, v.normal, color)).array;

    world.spawn(
      flat,
      new Mesh!VertexPosNormalColor(Primitive.triangleList, mesh(colors[1]), cubeData.indices.to!(uint[])),
      (mat4f.translation(vec3f(1.2f, 1.50f, 0)) * mat4f.rotation(45.radians, up)).transform
    );
    world.spawn(
      flat,
      new Mesh!VertexPosNormalColor(Primitive.triangleList, mesh(colors[3]), cubeData.indices.to!(uint[])),
      mat4f.scaling(vec3f(1.2f, 0.45f, 1.2f)).transform
    );
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
