module teraflop.ecs;

import std.conv : to;
import std.string : format;
import std.meta : templateOr;
import std.traits : fullyQualifiedName, Unqual;
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

  /// Get an Entity given its unique ID.
  const(Entity) get(UUID id) const {
    assert((id in entities_) !is null, "Could not find Entity!");
    return entities_[id];
  }

  /// A collection of resource instances identified by their type.
  Resources resources() const @property {
    return Resources(
      cast(ResourceCollection*) &resources_,
      cast(ResourceTracker*) &resourceChanged
    );
  }

  import std.meta : allSatisfy;
  /// Spawn a new entity given a set of `Component` instances.
  void spawn(T...)(T components) if (components.length && allSatisfy!(storableAsComponent, T)) {
    auto entity = new Entity();
    foreach (component; components) entity.add(component);
    entities_[entity.id] = entity;
  }
}

import std.variant : Variant;
alias ResourceId = size_t;
private alias ResourceCollection = Variant[ResourceId];
private alias ResourceTracker = bool[ResourceId];
/// A collection of Resource instances identified by their type.
struct Resources {
  private ResourceCollection* resources;
  private ResourceTracker* resourceChanged;

  /// Add a Resource to the collection.
  void add(T)(T resource) {
    Variant resourceVariant = resource;
    (*resources)[resourceVariant.type.toHash] = resourceVariant;
  }

  /// Returns `true` if and only if the given Resource type can be found in the collection.
  bool contains(T)() const {
    import std.algorithm.searching : canFind;
    return resources.keys.canFind(typeid(T).toHash);
  }

  /// Returns a Resource from the collection given its type.
  immutable(T) get(T)() {
    assert(contains!T(), "Could not find Resource!");
    auto variant = (*resources)[typeid(T).toHash];
    assert(variant.peek!T !is null);
    return variant.get!T;
  }

  /// Replace a Resource.
  void replace(T)(T resource) {
    assert(contains!T(), "A Resource must first be added before replacement.");
    const Variant resourceVariant = resource;
    auto key = resourceVariant.type.toHash;
    (*resources)[key] = resource;
    (*resourceChanged)[key] = true;
  }

  /// Clear each Resource's change detection tracking state.
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

/// Detect whether `T` is the `Entity` class.
enum bool isEntity(T) = __traits(isSame, Unqual!T, Entity);

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
  ///
  /// Prefer [Plain Old Data](https://dlang.org/spec/struct.html#POD) structs for Component data.
  void add(T)(T data = T.init, string name = fullyQualifiedName!T) if (isStruct!T) {
    add(data.component(name));
  }

  /// Detect whether this Entity has the given `Tag`.
  bool hasTag(const Tag tag) const {
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
  bool contains(T)(string name = "") const if (storableAsComponent!T) {
    import std.algorithm.iteration : filter, map;
    import std.algorithm.searching : canFind;
    import std.array : array;

    // For unnamed `Component` derivations
    static if (!isStruct!T && inheritsComponent!T && !isNamedComponent!T) {
      static assert(name == "", "Cannot filter for named components given an unnamed Component type.");
      return components_.filter!(c => c.classname == typeid(T)).array.length;
    }

    alias FilterFunc = bool function(inout Component);
    FilterFunc isStructureOrNamed;

    static if (isStruct!T) {
      isStructureOrNamed = &Component.isStructure!T;
    } else static if (isNamedComponent!T) {
      isStructureOrNamed = &Component.isNamed;
    }

    auto namedComponents = components.filter!(isStructureOrNamed)
      .map!(c => c.to!(const NamedComponent).name).array;
    return name == "" ? !!namedComponents.length : namedComponents.canFind(name);
  }

  /// Get Component data given its type and optionally its name.
  immutable(T[]) get(T)(string name = "") const if (storableAsComponent!T) {
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
  T[] getMut(T)(string name = "") const if (storableAsComponent!T) {
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

  /// Replace a Component given new value.
  ///
  /// Prefer [Plain Old Data](https://dlang.org/spec/struct.html#POD) structs for Component data.
  void replace(Component component) {
    assert(contains(component), "A Component must first be added before replacement.");
    components_[key(component)] = component;
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
enum bool inheritsComponent(T) = inheritsFrom!(T, Component);

private enum bool isRawComponent(T) = __traits(isSame, T, Component);

/// Detect whether `T` is a `Component`.
template isComponent(T) {
  alias isRawOrInherited = templateOr!(isRawComponent || inheritsComponent);
  enum bool isComponent = isRawOrInherited!T;
}

/// Detect whether `T` may be stored as Component data.
template storableAsComponent(T) {
  alias isStructOrComponent = templateOr!(isStruct, inheritsComponent, isRawComponent);
  enum bool storableAsComponent = isStructOrComponent!T;
}

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

/// Initialize a new `Component`, optionally given default data and a custom name.
Component component(T)(T data = T.init, const string name = "") if (isStruct!T) {
  return new Structure!T(data, name);
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

/// Derive this class to encapsulate a game system that operates on Resources and Components in the world.
abstract class System {
  private string name_;
  private const World world;

  /// Initialize a system given the ECS `World` and, optionally, a name.
  this(const World world, const string name = "") {
    this.name_ = name.length ? name : this.classinfo.name;
    this.world = world;
  }

  private alias SystemGenerator = System function(World world);
  /// Dynamically construct a new `System` instance given a function with parameters expecting
  /// specific resource and Component types.
  static SystemGenerator from(alias Func)() if (isCallableAsSystem!Func) {
    alias FuncSystem = GeneratedSystem!Func;
    return (World world) => new FuncSystem(world);
  }

  /// The name of this system.
  string name() const @property {
    return name_;
  }

  /// Operate this system on resources and `Component`s in the world.
  abstract void run() const;

  /// Query the world for entities containing a component of the given type.
  Entity[] query(ComponentT...)() {
    static if (ComponentT.length == 0) return world.entities;
  }
}

unittest {
  class Foo : System {
    this(World world) { super(world); }
    override void run() const {
      assert(world.entities.length == 0);
    }
  }
  const foo = new Foo(new World());

  import std.traits : fullyQualifiedName;
  assert(foo.name == fullyQualifiedName!Foo);

  foo.run();
}

import std.traits : isCallable, ReturnType;
/// Detect whether `T` is callable as a `System`, which can be mapped to a `System` with `System.from`.
template isCallableAsSystem(T...) if (T.length == 1 && isCallable!T && is (ReturnType!T == void)) {
  import std.traits : Parameters;
  alias TParams = Parameters!T;
  static if (!TParams.length)
    enum bool isCallableAsSystem = true;
  else {
    import std.traits : isBoolean, isNumeric, isSomeString;
    import std.meta : allSatisfy, templateOr;
    enum isResourceData(T) = isBoolean!T || isNumeric!T || isSomeString!T || isStruct!T;
    alias isComponentData(T) = storableAsComponent!T;
    enum bool isCallableAsSystem = allSatisfy!(templateOr!(
      isEntity,
      isResourceData,
      isComponentData
    ), TParams);
  }
}

@safe unittest {
  interface I { void run() const; }
  struct S { static void opCall(bool, int) {} }
  class C { void opCall(double, float, S, Number) {} }
  auto c = new C;

  static assert(isCallableAsSystem!c);
  static assert(isCallableAsSystem!(S));
  static assert(isCallableAsSystem!(I.run));
  static assert(isCallableAsSystem!(c.opCall));
  static assert(isCallableAsSystem!((Number _) {}));
}

private final class GeneratedSystem(alias Func) : System if (isCallableAsSystem!Func) {
  import std.traits : Parameters, ParameterIdentifierTuple, ParameterStorageClassTuple;
  import std.typecons : Tuple, tuple;

  enum GeneratedSystemName = __traits(identifier, Func);
  private static auto systemName = GeneratedSystemName;

  alias FuncParams = Parameters!Func;
  alias FuncParamNames = ParameterIdentifierTuple!Func;
  alias FuncParamStorage = ParameterStorageClassTuple!Func;
  private static auto paramNames = [FuncParamNames];

  this(World world) {
    super(world, "teraflop.ecs.GeneratedSystem:" ~ systemName);
  }

  override void run() const {
    import std.algorithm.iteration : each, joiner, map;
    import std.string : join;

    alias Replacements = Component[];
    Replacements[UUID] replacements;
    debug Diagnostic[] diagnostics;

    foreach (entity; world.entities) {
      const results = tryApplyFunc(entity);
      replacements[entity.id] ~= cast(Component[]) results.replacements;
      debug {
        auto messages = results.diagnostics.map!(d => d.message);
        if (messages.length)
          diagnostics ~= Diagnostic(messages.join("\n"), format!"Entity %s"(entity.id));
      }
    }

    debug {
      if (diagnostics.length) {
        auto message = diagnostics.map!(d => d.toString).join("\n\n");
        assert(0, format!"Ran system '%s':\n%s"(name, message));
      }
    }

    foreach (entityId; replacements.keys) {
      auto entity = cast(Entity) world.get(entityId);
      foreach (Component component; replacements[entityId])
        entity.replace(component);
    }
  }

  private struct Diagnostic {
    string message;
    string source = "Unknown";

    string toString() const @property {
      return format!"%s: %s"(source, message);
    }
  }

  private alias FuncApplicationResults = Tuple!(Component[], "replacements", Diagnostic[], "diagnostics");
  private FuncApplicationResults tryApplyFunc(const Entity entity) const {
    import std.algorithm.iteration : map;
    import std.array : array;
    import std.conv : text;
    import std.meta : staticIndexOf, staticMap;
    import std.traits : ConstOf, ImmutableOf, InoutOf, QualifierOf, ParameterStorageClass;

    string[] diagnosticMessages;

    // Try to get the dependent Entity, Component, and Resource instances for function arguments
    Tuple!(staticMap!(Unqual, FuncParams)) params;
    enum int indexOf(T) = staticIndexOf!(T, FuncParams);
    enum string ParamName(T) = FuncParamNames[indexOf!T];
    enum bool isParamConst(T) = __traits(isSame, QualifierOf!T, ConstOf!T);
    enum bool isParamImmutable(T) = __traits(isSame, QualifierOf!T, ImmutableOf!(Unqual!T));
    enum bool isImplicitlyConvertableFromMutable(T) =
        __traits(isSame, Unqual!T, T) ||
        __traits(isSame, QualifierOf!T, T) ||
        isParamConst!T;
    enum bool hasRefStorage(T) = (FuncParamStorage[indexOf!T] & ParameterStorageClass.ref_) ==
      ParameterStorageClass.ref_;
    enum bool hasScopeStorage(T) = (FuncParamStorage[indexOf!T] & ParameterStorageClass.scope_) ==
      ParameterStorageClass.scope_;
    enum string diagnosticNameOf(T) = "argument " ~ text(indexOf!T + 1) ~ " " ~ "'" ~ ParamName!T ~ "'" ~
      " of type " ~ typeid(Unqual!T).name;
    enum string diagnosticDlangFuncParams = "See https://dlang.org/spec/function.html#parameters";

    static foreach (Param; FuncParams) {
      // Guard against `ref Entity`, and `immutable ref` parameters
      static if (hasRefStorage!Param && isEntity!Param)
        static assert(0, "Reference qualifier on " ~ diagnosticNameOf!Param ~ " is not supported." ~
          "\n\tTeraflop considers overwriting an Entity at System runtime bad practice." ~
          "\n\t" ~ diagnosticDlangFuncParams);
      static if (hasRefStorage!Param && isParamImmutable!Param)
        static assert(0, "Reference qualifier on " ~ diagnosticNameOf!Param ~ " is not supported." ~
          "\n\t" ~ diagnosticDlangFuncParams);
      // Require the `scope` storage class on `Entity` parameters
      static if (!hasScopeStorage!Param && isEntity!Param)
        static assert(0, "Scoped storage class qualifier on " ~ diagnosticNameOf!Param ~ " is required." ~
          " i.e. Use \"`scope const Entity " ~ ParamName!Param ~ "`\" instead." ~
          "\n\tEntity references cannot escape a running System." ~
          "\n\t" ~ diagnosticDlangFuncParams);
      // TODO: Require the `const` storage class qualifier on `Entity` parameters
      // static if (!isParamConst!Param && isEntity!Param)
      //   static assert(0, "Constant qualifier on " ~ diagnosticNameOf!Param ~
      //    " is required. i.e. Use \"`const Entity " ~ ParamName!Param ~ "`\" instead." ~
      //    "\n\t" ~ diagnosticDlangFuncParams);

      static if (!isEntity!Param) {
        // Run the system function only if this entity contains instances of all the expected Component types
        if (!entity.contains!(Unqual!Param)(ParamName!Param)) {
          diagnosticMessages ~= format!("Could not apply %s to %s\n" ~
            "\tThere must exist a Component named '%s' in the World.")(
              diagnosticNameOf!Param,
              GeneratedSystemName,
              ParamName!Param);
          goto L_continue; // Hack to workaround lack of `continue` support in `static foreach` 😒️
        }
      }
      // TODO: Use `T.init` for `out` parameters
      // Otherwise, get the Entity, Resource, or Component data
      static if (isEntity!Param) {
        params[indexOf!Param] = cast(Unqual!Param) entity;
      } else static if (isParamImmutable!Param) {
        params[indexOf!Param] = entity.get!Param(ParamName!Param)[0];
      } else static if (isImplicitlyConvertableFromMutable!Param) {
        params[indexOf!Param] = entity.getMut!(Unqual!Param)(ParamName!Param)[0];
      } else {
        static assert(0,
          "Could not apply " ~ diagnosticNameOf!Param ~ " to " ~ GeneratedSystemName);
      }
      // Only define this label once
      static if (indexOf!Param == 0) {
L_continue:
      }
    }

    FuncApplicationResults results;
    results.diagnostics = diagnosticMessages.map!(msg => Diagnostic(msg)).array;

    if (diagnosticMessages.length) {
      results.replacements = new Component[0];
      return results;
    }

    // Run the system, applying dependent `Component` instance arguments
    Func(params.expand);

    Component[] replacements;
    static foreach (Param; FuncParams) {
      static if (hasRefStorage!Param) {
        static if (isStruct!(Unqual!Param))
          replacements ~= new Structure!(Unqual!Param)(params[indexOf!Param], ParamName!Param);
        else static if (!isComponent!(Unqual!Param))
          replacements ~= params[indexOf!Param];
      }
    }

    results.replacements = replacements;
    return results;
  }
}

unittest {
  auto world = new World();

  world.spawn(Number(0).component("number"));
  assert(world.entities.length == 1);

  auto counterSystem = System.from!counter;
  counterSystem(world).run();
  const number = world.entities[0].get!Number[0];
  assert(number.value == 1);
}

version(unittest) {
  struct Number {
    int value;
  }

  // TODO: Add an attribute to params to remap expected Component name binding?
  void counter(scope const Entity _, scope ref Number number) {
    number.value += 1;
  }
}
