import std.stdio;

import teraflop.game : Game;
import teraflop.input;
import teraflop.math;

void main()
{
	writeln("Teraflop Triangle Example");

  new Triangle().run();
}

private final class Triangle : Game {
  import std.typecons : Flag, No, Yes;
  import teraflop.async : Event;
  import teraflop.ecs : ClassOf, System, World;
  import teraflop.graphics : Color, Material, Mesh, Shader, ShaderStage, VertexPosColor;

  alias ExitEvent = Event!(Flag!"force");
  ExitEvent onExit;

  this() {
    super("Triangle");

    onExit ~= (Flag!"force" force) {
      if (active && force) exit();
    };
  }

  override void initializeWorld(scope World world) {
    // Exit the app with the escape key
    world.resources.add(onExit);
    auto input = world.resources.get!Input;
    input.map.bind("exit").keyboardPressed(KeyboardKey.escape);
    this.add(System.from!exitOnEscape);

    auto shaders = [
      new Shader(ShaderStage.vertex, "examples/triangle/assets/shaders/triangle.vs.spv"),
      new Shader(ShaderStage.fragment, "examples/triangle/assets/shaders/triangle.fs.spv")
    ];

    world.spawn(Material(shaders, No.depthTest), Mesh!VertexPosColor([
      VertexPosColor(vec3f(0.0f, -0.5f, 0), Color.red.vec4f),
      VertexPosColor(vec3f(0.5f, 0.5f, 0), Color.green.vec4f),
      VertexPosColor(vec3f(-0.5f, 0.5f, 0), Color.blue.vec4f),
    ], [0, 1, 2]));
  }

  static void exitOnEscape(scope const ClassOf!InputEventAction event, scope ExitEvent exit) {
    if (event.action == "exit") exit(Yes.force);
  }
}
