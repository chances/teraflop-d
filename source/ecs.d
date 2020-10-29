module teraflop.ecs;

import std.conv : to;
import std.string : format;
import std.traits : fullyQualifiedName;
import std.uuid : UUID;

import teraflop.traits : isStruct;

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
  void add(inout Component component) {
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

  /// Determines whether this Entity contains a given `Component` instance.
  ///
  /// Complexity: Constant
  bool contains(inout Component component) const {
    return ((key(component) in components_) !is null);
  }
  /// Determines whether this Entity contains a `NamedComponent` instance given its name.
  ///
  /// Complexity: Linear
  bool contains(string name) const {
    assert(name.length);
    import std.algorithm.iteration : filter, map;
    import std.algorithm.searching : canFind;

    auto componentNames = components.filter!(Component.isNamed)
      .map!(c => c.to!(const NamedComponent).name);
    if (componentNames.empty) return false;
    return componentNames.canFind(name);
  }
  /// Determines whether this Entity contains a Component given its type and, optionally, its name.
  ///
  /// Complexity: Linear
  bool contains(T)(string name = "") const if (isStruct!T || isComponent!T) {
    import std.algorithm.iteration : filter, map;
    import std.algorithm.searching : canFind;

    // For unnamed `Component` derivations
    static if (!isStruct!T && isComponent!T && !isNamedComponent!T) {
      static assert(name == "", "Cannot filter for named components given an unnamed Component type.");
      return !components_.filter!(c => c.classname == typeid(T)).empty;
    }

    alias FilterFunc = bool function(inout Component);
    FilterFunc isStructureOrNamed;

    static if (isStruct!T) {
      isStructureOrNamed = &Component.isStructure!T;
    } else static if (isNamedComponent!T) {
      isStructureOrNamed = &Component.isNamed;
    }

    auto namedComponents = components.filter!(isStructureOrNamed)
      .map!(c => c.to!(const NamedComponent).name);
    return name == "" ? !namedComponents.empty : namedComponents.canFind(name);
  }

  /// Get Component data given its type and optionally its name.
  immutable(T[]) get(T)(string name = "") const if (isStruct!T || isComponent!T) {
    import std.algorithm.iteration : map;
    import std.array : array;

    auto components = getMut!T(name);
    static if (isStruct!T) {
      return components.idup;
    } else {
      // Cannot implicitly convert from mutable ⇒ immutable 😢️
      // https://dlang.org/spec/const3.html#implicit_qualifier_conversions
      return cast(immutable(T[])) components;
    }
  }

  /// Get a mutable reference to Component data given its type and optionally its name.
  T[] getMut(T)(string name = "") const if (isStruct!T || isComponent!T) {
    import std.algorithm.iteration : filter, map;
    import std.algorithm.searching : canFind;
    import std.array : array;

    assert(contains!T(name), format!"Expected Component data of type %s"(typeid(T).name));

    // For unnamed `Component` derivations
    static if (!isStruct!T && !isNamedComponent!T) {
      assert(name == "", "Cannot filter for named components given an unnamed Component type.");
      return components_.filter!(c => c.classname == typeid(T)).array;
    }

    alias FilterFunc = bool function(inout Component);
    FilterFunc isStructureOrNamed;

    static if (isStruct!T) {
      isStructureOrNamed = &Component.isStructure!T;
    } else static if (isNamedComponent!T) {
      isStructureOrNamed = &Component.isNamed;
    }

    auto namedComponents = components.filter!(isStructureOrNamed)
      .map!(c => c.to!(const NamedComponent)).array;

    if (name.length) {
      namedComponents = namedComponents.filter!(c => c.name == name).array;
    }

    // Cannot implicitly convert from const ⇒ mutable
    // https://dlang.org/spec/const3.html#implicit_qualifier_conversions
    static if (isStruct!T) {
      return cast(T[]) namedComponents.map!(c => c.to!(const Structure!T).data).array;
    } else {
      return cast(T[]) namedComponents.filter!(c => c.type == typeid(T).name)
        .map!(c => c.to!(const T)).array;
    }
  }

  // TODO: Move this to the Component classes as a hash function and refactor components_ to use Component.hashOf
  private static string key(const Component component) {
    if (Component.isNamed(component)) {
      return component.type ~ ":" ~ component.to!(const NamedComponent).name;
    }
    return component.type;
  }

  unittest {
    auto entity = new Entity();
    auto seven = Number(7);
    const name = "teraflop.ecs.Number";
    const key = "teraflop.ecs.Structure!(Number).Structure:" ~ name;
    assert(entity.components.length == 0);

    entity.add(seven);
    assert(entity.components.length == 1);
    assert(entity.components_.keys[0] == key);
    assert(entity.components[0].to!(const NamedComponent).name == name);
    assert(entity.contains(name));
    assert(entity.contains!Number());
    assert(entity.contains!Number(name));
    assert(entity.contains(entity.components[0]));

    import std.conv : to;
    const structures = entity.get!Number;
    assert(structures.length == 1);
    assert(structures == [seven].idup);
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

  package static bool isStructure(T)(inout Component component) if (isStruct!T) {
    return typeid(NamedComponent).isBaseOf(component.classinfo);
  }

  package static bool isTag(inout Component component) {
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

private final class Structure(T) : NamedComponent if (isStruct!T) {
  T data;

  this(T data, const string name = fullyQualifiedName!T) pure {
    assert(name.length, "A Component constructed from a struct must be named.");
    super(name);
    this.data = data;
  }
  /// Make an immutable copy of this `Structure`.
  immutable(Structure) idup() const @property {
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
    super(name);
  }
  /// Make an immutable copy of this `Tag`.
  immutable(Tag) idup() const @property {
    return new immutable(Tag)(name);
  }
}

/// Create a new `Tag` given a name
immutable(Tag) tag(string name) {
  assert(name.length, "A Tag must be named.");
  return new Tag(name);
}

unittest {
  const foo = tag("foo");

  assert(foo.type == "teraflop.ecs.Tag");
  assert(foo.name == foo.stringof);
  assert(Component.isTag(foo));

  auto entity = new Entity();
  entity.add(foo);
  assert(entity.contains(foo.stringof));
  assert(entity.contains!Tag);
  assert(entity.contains!Tag(foo.stringof));
  assert(entity.hasTag(foo));

  const tags = entity.get!Tag;
  assert(tags.length == 1);
  assert(tags == [foo]);

  assert(entity.get!(Tag)("foo") == [foo]);
}

// TODO: Move these tag declarations to GPU-ish and teraflop.assets (Asset cache Resource) modules

/// Whether *all* of an `Entity`s GPU resources have been initialized.
static const Initialized = tag("Initialized");
/// Whether *all* of an `Entity`s `Asset` components have been loaded.
static const Loaded = tag("Loaded");

unittest {
  assert(Initialized.name == Initialized.stringof);
  assert(Loaded.name == Loaded.stringof);
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
