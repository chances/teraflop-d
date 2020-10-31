import std.stdio;

import teraflop.game : Game;

void main()
{
	writeln("Teraflop Trianlge Example");

  new Triangle().run();
}

private final class Triangle : Game {
  this() {
    super("Triangle");
  }

  override void initializeWorld() {
    // TODO: Add a triangle Entity
  }
}
