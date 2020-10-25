module teraflop.ecs;

import std.uuid : UUID;

/// A collection of Entities, their `Component`s, `Resource`s, and the `System`s that operate on
/// those components and mutate the world
class World {
  private Entity[UUID] entities_;
  private ResourceCollection resources_;
  private ResourceTracker resourceChanged;

  const(Entity[]) entities() const @property {
    return entities_.values;
  }

  /// A collection of resource instances identified by their type.
  Resources resources() const @property {
    return Resources(
      cast(ResourceCollection*) &resources_,
      cast(ResourceTracker*) &resourceChanged
    );
  }

  /// Spawn a new entity given a set of `Component` instances.
  void spawn(T...)(T components) if (components.length > 0) {
    auto entity = new Entity();
    foreach (component; components) entity.add(component);
    entities_[entity.id] = entity;
  }
}

import std.variant : Variant;
alias ResourceId = size_t;
private alias ResourceCollection = Variant[ResourceId];
private alias ResourceTracker = bool[ResourceId];
/// A collection of resource instances identified by their type.
struct Resources {
  private ResourceCollection* resources;
  private ResourceTracker* resourceChanged;

  /// Add a resource to the collection.
  void add(T)(T resource) {
    Variant resourceVariant = resource;
    (*resources)[resourceVariant.type.toHash] = resourceVariant;
  }

  /// Returns `true` if and only if the given resource type can be found in the collection.
  bool contains(T)() const {
    import std.algorithm.searching : canFind;
    return resources.keys.canFind(typeid(T).toHash);
  }

  /// Returns a resource from the collection given its resource type.
  immutable(T) get(T)() {
    assert(contains!T(), "Could not find resource!");
    auto variant = (*resources)[typeid(T).toHash];
    assert(variant.peek!T !is null);
    return variant.get!T;
  }

  /// Replace a resource.
  void replace(T)(T resource) {
    assert(contains!T(), "A resource must first be added before replacement.");
    const Variant resourceVariant = resource;
    auto key = resourceVariant.type.toHash;
    (*resources)[key] = resource;
    (*resourceChanged)[key] = true;
  }

  /// Clear each resource's change detection tracking state.
  void clearTrackers() {
    foreach (key; resourceChanged.keys) {
      (*resourceChanged)[key] = false;
    }
  }
}

unittest {
  auto world = new World();
  world.resources.add(7);
  assert(world.resources.get!int == 7);
  world.resources.replace(3);
  assert(world.resources.get!int == 3);

  struct Foo {
    auto bar = "hello";
  }
  world.resources.add(Foo());
  assert(world.resources.get!Foo.bar == "hello");
}

/// A world entity consisting of a unique ID and a collection of associated components.
class Entity {
  private Component[string] components_;
  import std.uuid : randomUUID;
  /// Unique ID of this entity
  UUID id;

  /// Initialize a new empty entity.
  this() {
    id = randomUUID();
  }

  const(Component[]) components() const @property {
    return components_.values;
  }

  /// Add a `Component` instance to this entity.
  void add(Component component) {
    auto name = component.classinfo.name ~ ":" ~ component.name;
    components_[name] = component;
  }

  unittest {
    auto entity = new Entity();
    assert(entity.components.length == 0);
    auto seven = new Number(7, "seven");
    entity.add(seven);
    assert(entity.components.length == 1);
    assert(entity.components[0] == seven);
    assert(entity.components_.keys[0] == "teraflop.ecs.Number:seven");
  }
}

/// Derive this class to contain specialized `Entity` data.
abstract class Component {
  private string name_;

  /// Initialize a component given its name.
  this(string name = "") {
    this.name_ = name;
    if (name == "") {
      this.name_ = this.classinfo.name;
    }
  }

  string name() const @property {
    return name_;
  }

  unittest {
    assert(new Number(1).name == "teraflop.ecs.Number");

    auto seven = new Number(7, "seven");
    assert(seven.name == "seven");
  }
}

// TODO: Move these tag declarations to GPU-ish and teraflop.assets (Asset cache Resource) modules

/// Whether *all* of an `Entity`s GPU resources have been initialized.
mixin Tag!"Initialized";
/// Whether *all* of an `Entity`s `Asset` components have been loaded.
mixin Tag!"Loaded";

/// Create a dataless `Component` derivation given a name
mixin template Tag(string name) {
  mixin("class " ~ name ~ " : Component {}");
}

unittest {
  auto initTag = new Initialized();
  assert(initTag.name_ == "teraflop.ecs.Tag!\"Initialized\".Initialized");
}

/// Derive this class to encapsulate a game system that operates on `Component`s in the world.
abstract class System {
  private World world;

  /// Initialize a system given the ECS `World`.
  this(World world) {
    this.world = world;
  }

  /// Query the world for entities containing a component of the given type.
  Entity[] query(ComponentT...)() {
    static if (ComponentT.length == 0) return world.entities;
  }
}

version(unittest) {
  class Number : Component {
    int number;

    this(int number, string name = "") {
      super(name);
      this.number = number;
    }
  }
}
