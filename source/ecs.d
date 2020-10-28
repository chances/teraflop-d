module teraflop.ecs;

import std.traits : fullyQualifiedName;
import std.uuid : UUID;

/// A collection of Entities, their `Component`s, `Resource`s, and the `System`s that operate on
/// those components and mutate the world
final class World {
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
final class Entity {
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
  void add(const Component component) {
    components_[key(component)] = cast(Component) component;
  }
  /// Add a new Component given its type and, optionally, a default value and its name
  void add(T)(T data = T.init, string name = fullyQualifiedName!T) if (isStruct!T) {
    add(new Structure!T(data, name));
  }

  /// Detect whether this Entity has the given `Tag`.
  bool hasTag(const Tag tag) {
    return (key(tag) in components_) !is null;
  }

  private static string key(const Component component) {
    if (Component.isNamed(component)) {
      import std.conv : to;
      return component.type ~ ":" ~ component.to!(const NamedComponent).name;
    }
    return component.type;
  }

  unittest {
    auto entity = new Entity();
    auto seven = Number(7);
    const key = "teraflop.ecs.Structure!(Number).Structure:teraflop.ecs.Number";
    assert(entity.components.length == 0);

    entity.add(seven);
    assert(entity.components.length == 1);
    import std.conv : to;
    assert(entity.components[0].to!(const(Structure!Number)).data == seven);
    assert(entity.components_.keys[0] == key);
  }
}

import teraflop.traits : inheritsFrom;
/// Detect whether `T` inherits from `Component`.
enum bool isComponent(T) = inheritsFrom!(T, Component);

/// A container for specialized `Entity` data.
abstract class Component {
  private string type_;

  package string type() const @property {
    return this.classinfo.name;
  }

  package static bool isNamed(inout Component component) {
    return typeid(NamedComponent).isBaseOf(component.classinfo);
  }

  package static bool isTag(Component component) {
    return typeid(Tag).isBaseOf(component.classinfo);
  }
}

/// Detect whether `T` inherits from `NamedComponent`.
enum bool isNamedComponent(T) = inheritsFrom!(T, NamedComponent);

/// A named container for specialized `Entity` data.
abstract class NamedComponent : Component {
  private string name_;

  /// Initialize a new NamedComponent.
  this(string name) pure {
    assert(name.length, "A named Component must have a non-empty name.");
    this.name_ = name;
  }

  string name() const @property {
    return name_;
  }
}

import teraflop.traits : isStruct;
private final class Structure(T) : NamedComponent if (isStruct!T) {
  T data;

  this(T data, string name = fullyQualifiedName!T) {
    assert(name.length, "A Component constructed from a struct must be named.");
    super(name);
    this.data = data;
  }
  /// Make an immutable copy of this `Structure`.
  immutable(Structure) idup() {
    return new immutable(Structure!T)(data, name);
  }
}

unittest {
  auto one = Number(1);
  auto component = new Structure!Number(one);
  assert(component.type == "teraflop.ecs.Structure!(Number).Structure");
  assert(component.name == "teraflop.ecs.Number");
}

/// A named, dataless Component used to flag Entities.
final class Tag : NamedComponent {
  /// Initialize a new Tag
  this(string name) pure {
    assert(name.length, "A Tag must be named.");
    super(name);
  }
  /// Make an immutable copy of this `Tag`.
  immutable(Tag) idup() {
    return new immutable(Tag)(name);
  }
}

/// Create a new `Tag` given a name
immutable(Tag) tag(string name) {
  return new Tag(name).idup;
}

// TODO: Move these tag declarations to GPU-ish and teraflop.assets (Asset cache Resource) modules

/// Whether *all* of an `Entity`s GPU resources have been initialized.
static immutable Initialized = tag("Initialized");
/// Whether *all* of an `Entity`s `Asset` components have been loaded.
static immutable Loaded = tag("Loaded");

unittest {
  assert(Initialized.name == Initialized.stringof);

  const foo = tag("foo");
  assert(foo.type == "teraflop.ecs.Tag");
  assert(foo.name == foo.stringof);

  auto entity = new Entity();
  entity.add(foo);
  assert(entity.hasTag(foo));
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
  struct Number {
    int value;
  }
}
