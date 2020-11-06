/// Teraflop's Entity Component System primitives.
///
/// Inspired by <a href="https://bevyengine.org/learn/book/getting-started/ecs/">Bevy ECS</a> and <a href="https://github.com/skypjack/entt">entt</a>.
///
/// See_Also: <a href="https://en.wikipedia.org/wiki/Entity_component_system">Entity Component System</a> on Wikipedia
///
/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.ecs;

import std.conv : to;
import std.string : format;
import std.meta : templateOr;
import std.traits : fullyQualifiedName, Unqual;
import std.uuid : UUID;

import teraflop.traits : inheritsFrom, isInterface, isStruct;

/// Detect whether `T` is the `World` class.
enum bool isWorld(T) = __traits(isSame, T, World);

/// A collection of Entities, their `Component`s, and `Resource`s. `System`s operate on those
/// components and mutate the World.
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

/// Detect whether `T` is the `Resources` class.
enum bool isResources(T) = __traits(isSame, T, Resources);

import std.traits : isBoolean, isNumeric, isSomeString;
private alias isResourceData = templateOr!(isBoolean, isNumeric, isSomeString, isStruct);

import std.variant : Variant;
private alias ResourceId = size_t;
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
  const(T) get(T)() const {
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
  /// Prefer <a href="https://dlang.org/spec/struct.html#POD">Plain Old Data</a> structs constructed with `component` for Component data.
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
    return get!T(name).length > 0;
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

  /// Get a mutable reference to Component data given its interface type.
  T[] getMut(T)() const if (isInterface!T) {
    import std.algorithm.iteration : filter, map;
    import std.array : array;

    return cast(T[]) components
      .filter!(c => typeid(T).isBaseOf(c.classinfo))
      .map!(c => cast(T) c).array;
  }

  /// Get a mutable reference to Component data given its type and optionally its name.
  T[] getMut(T)(string name = "") const if (storableAsComponent!T) {
    import std.algorithm.iteration : filter, map;
    import std.algorithm.searching : canFind;
    import std.array : array;

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
      return cast(T[]) namedComponents.filter!(c => typeid(T).isBaseOf(c.classinfo))
        .map!(c => c.to!(const T)).array;
    }
  }

  /// Replace a Component given new value.
  ///
  /// Prefer <a href="https://dlang.org/spec/struct.html#POD">Plain Old Data</a> structs constructed with `component` for Component data.
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
    assert(entity.contains!NamedComponent);
    assert(entity.contains(entity.components[0]));

    import std.conv : to;
    const structures = entity.get!Number;
    assert(structures.length == 1);
    assert(structures == [seven].idup);
  }
}

/// Detect whether `T` inherits from `Component`.
enum bool inheritsComponent(T) = inheritsFrom!(T, Component);

private enum bool isRawComponent(T) = __traits(isSame, T, Component);

/// Detect whether `T` is the `Component` class or inherits from `Component`.
template isComponent(T) {
  alias isRawOrInherited = templateOr!(isRawComponent, inheritsComponent);
  enum bool isComponent = isRawOrInherited!T;
}

/// Detect whether `T` may be stored as Component data.
template storableAsComponent(T) {
  alias isStructOrComponent = templateOr!(isStruct, isComponent);
  alias isStructOrComponentAndNotInterface = templateAnd!(templateNot!isInterface, isStructOrComponent);
  enum bool storableAsComponent = isStructOrComponentAndNotInterface!T;
}

/// A container for specialized `Entity` data.
///
/// Prefer <a href="https://dlang.org/spec/struct.html#POD">Plain Old Data</a> structs constructed with `component` for Component data.
abstract class Component {
  private string type_;

  package string type() const @property {
    return this.classinfo.name;
  }

  package static bool isNamed(inout Component component) {
    return typeid(NamedComponent).isBaseOf(component.classinfo);
  }

  package static bool isStructure(T)(inout Component component) if (isStruct!T) {
    return typeid(Structure!T).isBaseOf(component.classinfo);
  }

  package static bool isTag(inout Component component) {
    return typeid(Tag).isBaseOf(component.classinfo);
  }
}

/// Detect whether `T` inherits from `NamedComponent`.
enum bool inheritsNamedComponent(T) = inheritsFrom!(T, NamedComponent);

private enum bool isRawNamedComponent(T) = __traits(isSame, T, NamedComponent);

/// Detect whether `T` is the `NamedComponent` class or inherits from `NamedComponent`.
template isNamedComponent(T) {
  alias isRawOrInherited = templateOr!(isRawNamedComponent, inheritsComponent);
  enum bool isNamedComponent = isRawOrInherited!T;
}

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

/// Initialize a new `Component` optionally with initial data and a custom name.
///
/// Params:
/// data = Initial data value.
/// name = A custom name. Defaults to `fullyQualifiedName!T`.
Component component(T)(T data = T.init, const string name = "") if (isStruct!T) {
  return new Structure!T(data, name);
}

/// A named, dataless Component used to flag Entities.
final class Tag : NamedComponent {
  /// Initialize a new Tag.
  this(string name) pure {
    super(name);
  }
  /// Make an immutable copy of this Tag.
  immutable(Tag) idup() const @property {
    return new immutable(Tag)(name);
  }
}

/// Create a new `Tag` given a name.
///
/// Params:
/// name = Desired name.
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

/// Whether *all* of an `Entity`'s GPU Resources have been initialized.
static const Initialized = tag("Initialized");
/// Whether *all* of an `Entity`'s `Asset` Components have been loaded.
static const Loaded = tag("Loaded");

unittest {
  assert(Initialized.name == Initialized.stringof);
  assert(Loaded.name == Loaded.stringof);
}

/// Detect whether `T` inherits from `System`.
enum bool inheritsSystem(T) = inheritsFrom!(T, System);

private enum bool isRawSystem(T) = __traits(isSame, T, System);

/// Detect whether `T` is the `System` class or inherits from `System`.
template isSystem(T) {
  alias isRawOrInherited = templateOr!(isRawSystem, inheritsSystem);
  enum bool isSystem = isRawOrInherited!T;
}

/// A function that initializes a new dynamically generated `System`.
///
/// Use `System.from` to construct a `SystemGenerator` given a function that satisfies `isCallableAsSystem`.
///
/// See_Also: `System.from`, `isCallableAsSystem`
alias SystemGenerator = System function(World world);

/// Derive this class to encapsulate a game System that operates on Resources and Components in the World.
abstract class System {
  private string name_;
  private const World world;

  /// Initialize a System given the ECS `World` and, optionally, a name.
  ///
  /// Params:
  /// world = The `World` the System will operate on.
  /// name = A name for this System. Defaults to the derived class' name.
  ///
  ///        Defaults to `fullyQualifiedName!System` or, in the case of a generated System,
  ///        "`fullyQualifiedName!System`:FuncName" where `FuncName` is the name of the function used to generate the System.
  ///
  /// See_Also: `World`, `System.name`
  this(const World world, const string name = "") {
    this.name_ = name.length ? name : this.classinfo.name;
    this.world = world;
  }

  /// Dynamically generate a new `System` instance given a function.
  ///
  /// When a generated System is run it will try to apply the World's Entities, Components, and Resources to the function's parameters.
  ///
  /// See <a href=isCallableAsSystem.html#Requirements><span class="pln">isCallableAsSystem</span> § Satisfaction Requirements</a> to understand the requirements of `isCallableAsSystem`.
  ///
  /// See <a href="#Parameter-Application">Parameter Application</a> to understand how parameters are applied at runtime.
  ///
  /// <strong>See Also</strong>: `isCallableAsSystem`
  /// <h2 id="Parameter-Application">Parameter Application</h2>
  /// When ran, a generated System will:
  /// $(OL
  ///   $(LI For each of the World's Entities, either:)
  ///     <ol type="a">
  ///       $(LI Apply a constant reference to the World for `World` parameters)
  ///       $(LI Apply a constant reference to the current Entity for `Entity` parameters)
  ///       $(LI Apply a constant reference to the World's Resources for `Resources` parameters)
  ///       $(LI Apply a constant reference to the generated System for `System` parameters)
  ///       $(LI Try to find a matching Entity Component to apply given a parameter's type and name:)
  ///         $(UL
  ///           $(LI `struct` and `Component` parameter names must match an Entity's Component name)
  ///         )
  ///       $(LI Try to find a matching World Resource to apply given the parameter's type is one of:)
  ///         $(UL
  ///           $(LI <a href="https://dlang.org/spec/type.html#basic-data-types" title="The D Language Website">Basic Data</a>)
  ///           $(LI arrays)
  ///           $(LI string)
  ///           $(LI `struct`)
  ///         )
  ///       $(LI Or, if a parameter could not be applied, continue to the next Entity)
  ///     </ol>
  ///   $(LI Call the user-provided function for Entities if and only if <i>all</i> parameters were be applied)
  ///   $(LI For all `struct` and `Component` parameters with the `ref` storage class, update the Component)
  /// )
  /// Returns: A newly instantiated `SystemGenerator`, a function that initializes a new generated `System` given a `World` reference.
  /// See_Also:
  /// $(UL
  ///   $(LI `isCallableAsSystem`)
  ///   $(LI `SystemGenerator`)
  ///   $(LI <a href="https://dlang.org/spec/function.html#param-storage" title="The D Language Website">Storage Classes</a>)
  ///   $(LI <a href="https://dlang.org/spec/type.html#basic-data-types" title="The D Language Website">Basic Data Types</a>)
  /// )
  static SystemGenerator from(alias Func)() if (isCallableAsSystem!Func) {
    alias FuncSystem = GeneratedSystem!Func;
    return (World world) => new FuncSystem(world);
  }

  /// The name of this System.
  ///
  /// The name is used in diagnostic messages.
  string name() const @property {
    return name_;
  }

  /// Operate this System on Resources and Components in the `World`.
  abstract void run() const;

  /// Query the `World` for Entities containing Components of the given types.
  const(Entity[]) query(ComponentT...)() const {
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

import std.meta : staticIndexOf, templateAnd, templateNot, templateOr;
import std.traits : ConstOf, ImmutableOf, Parameters, ParameterIdentifierTuple, ParameterStorageClass,
  ParameterStorageClassTuple, QualifierOf;

/// `isCallableAsSystem` parameter requirements helper templates
private enum bool hasConstStorage(T) = __traits(isSame, QualifierOf!T, ConstOf);
private enum bool hasImmutableStorage(T) = __traits(isSame, QualifierOf!T, ImmutableOf);
private enum bool hasRefStorage(alias T) = (T & ParameterStorageClass.ref_) == ParameterStorageClass.ref_;
private enum bool hasScopeStorage(alias T) = (T & ParameterStorageClass.scope_) == ParameterStorageClass.scope_;
private enum bool isImplicitlyConvertableFromMutable(T) =
    __traits(isSame, Unqual!T, T) ||
    __traits(isSame, QualifierOf!T, T) ||
    hasConstStorage!T;
private alias isIllegalReference = templateAnd!(
  templateOr!(isResources, templateNot!isResourceData),
  templateOr!(isStruct, templateNot!isComponent)
);
private alias mustNotBeMutable = templateOr!(isResources, isWorld, isEntity, isSystem);
private alias isIllegallyMutable = templateAnd!(
  templateOr!(isResources, templateNot!isResourceData),
  templateNot!hasConstStorage,
  mustNotBeMutable
);
private template illegallyEscapesScope(Param, alias ParamStorage) {
  alias escapesScope = templateAnd!(
    templateOr!(isResources, templateNot!isResourceData),
    templateOr!(isResources, isComponent, isWorld, isEntity, isSystem)
  );
  alias notHasScopeStorage = templateNot!(hasScopeStorage!ParamStorage);
  enum bool illegallyEscapesScope = notHasScopeStorage!ParamStorage && escapesScope!Param;
}

@safe unittest {
  alias PSCT = ParameterStorageClassTuple;

  alias Func = void function(Resources);
  static assert(!hasConstStorage!(Parameters!Func[0]));
  static assert(!hasImmutableStorage!(Parameters!Func[0]));
  static assert(!hasRefStorage!(PSCT!Func[0]));
  static assert(!hasScopeStorage!(PSCT!Func[0]));
  static assert( isIllegallyMutable!(Parameters!Func[0]));
  static assert( illegallyEscapesScope!(Parameters!Func[0], PSCT!Func[0]));

  alias Func_RefResources = void function(ref Resources);
  const Func_RefResources f_ref = (ref Resources) => {}();
  static assert(!hasConstStorage!(Parameters!f_ref[0]));
  static assert(!hasImmutableStorage!(Parameters!f_ref[0]));
  static assert( hasRefStorage!(PSCT!f_ref[0]));
  static assert(!hasScopeStorage!(PSCT!f_ref[0]));
  static assert( isIllegalReference!(Parameters!f_ref[0]));
  static assert( isIllegallyMutable!(Parameters!f_ref[0]));
  static assert( illegallyEscapesScope!(Parameters!f_ref[0], PSCT!f_ref[0]));

  alias Func_ScopeRef = void function(scope ref Resources);
  const Func_ScopeRef f_scopeRef = (ref Resources) => {}();
  static assert(!hasConstStorage!(Parameters!f_scopeRef[0]));
  static assert(!hasImmutableStorage!(Parameters!f_scopeRef[0]));
  static assert( hasRefStorage!(PSCT!f_scopeRef[0]));
  static assert( hasScopeStorage!(PSCT!f_scopeRef[0]));
  static assert( isIllegalReference!(Parameters!f_scopeRef[0]));
  static assert( isIllegallyMutable!(Parameters!f_scopeRef[0]));
  static assert(!illegallyEscapesScope!(Parameters!f_scopeRef[0], PSCT!f_scopeRef[0]));
}

import std.traits : isCallable, ReturnType;
/// Detect whether `T` is callable as a `System`.
///
/// If `T` is callable as a System, use `System.from` to construct a `SystemGenerator` from the function.
///
/// <h2 id="Requirements">Satisfaction Requirements</h2>
///
/// $(OL
///   $(LI `T` <b>MUST</b> satisfy <a href="https://dlang.org/library/std/traits/is_callable.html" title="The D Language Website">`isCallable`</a>.)
///   $(LI `T` <b>MUST</b> return `void`.)
///   $(LI <i>All</i> of `T`'s parameters <b>MUST</b> match one of:)
///     $(UL
///       $(LI Any <a href="https://dlang.org/spec/type.html#basic-data-types" title="The D Language Website">Basic Data Type</a>, e.g. `bool`, `int`, `uint`, `float`, `double`, `char`, etc.)
///       $(LI Any <a href="https://dlang.org/spec/type.html#derived-data-types" title="The D Language Website">array type</a> derived from a Basic Data Type, e.g. `int[]`, `float[]`, `string[]`, etc.)
///       $(LI Any <a href="https://dlang.org/spec/arrays.html#strings" title="The D Language Website">string type</a>, e.g. `string`, `char[]`, `wchar[]`, etc.)
///       $(LI A `struct` type)
///       $(LI `World`)
///       $(LI `Resources`)
///       $(LI `Entity`)
///       $(LI `Component` or any of its derivations)
///       $(LI `System`)
///     )
///   $(LI <i>All</i> of `T`'s parameters <b>MUST NOT</b> use the `immutable` <a href="https://dlang.org/spec/function.html#param-storage" title="The D Language Website">Storage Class</a>. <p>Use `const` instead.</p>)
///   $(LI <i>Certain</i> parameters <b>MUST</b> use specific Storage Classes:)
///     $(UL
///       $(LI `World`, `Resources`, `Entity`, `Component`, and `System` parameters <b>MUST</b> use the `scope` Storage Class)
///       $(LI `World`, `Resources`, `Entity`, and `System` parameters <b>MUST</b> use the `const` Storage Class)
///       $(LI The `ref` Storage Class <b>MUST NOT</b> be used with the `const` Storage Class)
///     )
///   $(LI `struct` and `Component` parameters <b>MAY</b> use the `ref` Storage Class)
/// )
/// See_Also:
/// $(UL
///   $(LI `System.from`)
///   $(LI <a href="https://dlang.org/library/std/traits/is_callable.html" title="The D Language Website">`isCallable`</a>)
///   $(LI <a href="https://dlang.org/spec/type.html#basic-data-types" title="The D Language Website">Basic Data Types</a>)
///   $(LI <a href="https://dlang.org/spec/type.html#derived-data-types" title="The D Language Website">Derived Data Types</a>)
///   $(LI <a href="https://dlang.org/spec/arrays.html#strings" title="The D Language Website">Strings</a>)
///   $(LI <a href="https://dlang.org/spec/function.html#param-storage" title="The D Language Website">Parameter Storage Classes</a>)
/// )
template isCallableAsSystem(T...) if (T.length == 1 && isCallable!T && is (ReturnType!T == void)) {
  import std.traits : Parameters;
  alias TParams = Parameters!T;
  static if (!TParams.length)
    enum bool isCallableAsSystem = true;
  else {
    import std.meta : allSatisfy;
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
    import std.meta : staticMap;

    FuncApplicationResults results;
    string[] diagnosticMessages;
    Component[] replacements;

    // Parameter helper templates
    enum int indexOf(T) = staticIndexOf!(T, FuncParams);
    enum string ParamName(T) = FuncParamNames[indexOf!T];
    alias notHasScopeStorage = templateNot!hasScopeStorage;

    // Diagnostic message generator helper templates
    template diagnosticNameOf(T) {
      static if (ParamName!T != "")
        enum string paramName = " '" ~ ParamName!T ~ "'";
      else
        enum string paramName = "";
      enum string diagnosticNameOf = "parameter " ~ text(indexOf!T + 1) ~ paramName ~
      " of type `" ~ fullyQualifiedName!(Unqual!T) ~ "`";
    }
    enum string diagnosticHintOf(T) = text(typeid(Unqual!T).name, ParamName!T) ~ "` parameter";
    enum string diagnosticBadPractice =
      "Teraflop considers it bad practice to modify the World, Resources, an Entity, or this System when it's running.";
    enum string diagnosticDlangFuncParams = "See https://dlang.org/spec/function.html#parameters";

    // Try to get the dependent Entity, Component, and Resource instances for function arguments
    Tuple!(staticMap!(Unqual, FuncParams)) params;
    auto isResource = false;
    auto componentExists = false;
    static foreach (Param; FuncParams) {
      // Guard against immutable parameters
      static if (hasImmutableStorage!Param)
        static assert(0, "Immutable qualifier on " ~ diagnosticNameOf!Param ~ " is not supported." ~
          "\n\t" ~ diagnosticDlangFuncParams ~
          "\n\n\tHint: Use `const` qualifier instead." ~
          "\n");
      // Guard against `ref World`, `ref Entity`, `ref Resources`, and `ref System` parameter
      static if (hasRefStorage!(FuncParamStorage[indexOf!Param]) && isIllegalReference!Param)
        static assert(0, "Reference qualifier on " ~ diagnosticNameOf!Param ~ " is not supported." ~
          "\n\t" ~ diagnosticBadPractice ~
          "\n\t" ~ diagnosticDlangFuncParams);
      // Guard against `const ref` parameters
      static if (hasRefStorage!(FuncParamStorage[indexOf!Param]) && hasConstStorage!Param)
        static assert(0, "Reference qualifier on " ~ diagnosticNameOf!Param ~ " is not supported." ~
          "\n\t" ~ diagnosticDlangFuncParams);
      // Require the `const` storage class qualifier on `World`, `Resources`, `Entity`, and `System` parameters
      static if (isIllegallyMutable!Param)
        static assert(0, "Constant qualifier on " ~ diagnosticNameOf!Param ~ " is required." ~
          "\n\t" ~ diagnosticBadPractice ~
          "\n\t" ~ diagnosticDlangFuncParams ~
          "\n\n\tHint: Add `const` qualifier to `" ~ diagnosticHintOf!Param ~ "." ~
          "\n");
      // Require the `scope` storage class qualifier on `World`, `Resources`, `Entity`, `Component`, and `System` parameters
      static if (illegallyEscapesScope!(Param, FuncParamStorage[indexOf!Param]))
        static assert(0, "Scoped storage class qualifier on " ~ diagnosticNameOf!Param ~ " is required." ~
          "\n\tWorld, Resources, Entity, Component, and System references cannot escape a running System." ~
          "\n\t" ~ diagnosticDlangFuncParams ~
          "\n\n\tHint: Add `scope` storage class to `" ~ diagnosticHintOf!Param ~ "." ~
          "\n");

      static if (!isWorld!Param && !isResources!Param && !isEntity!Param) {
        // Run the system function only if this entity contains instances of all the expected Resource and Component types
        componentExists = storableAsComponent!Param && entity.contains!(Unqual!Param)(ParamName!Param);
        if (!componentExists && (isResources!Param || isResourceData!Param)) {
          isResource = isResources!Param || world.resources.contains!(Unqual!Param);
        } else if (!isResource && !componentExists) {
          diagnosticMessages ~= format!("Could not apply %s to %s" ~
            "\n\tThere must exist a Resource of type `%s` or a Component named '%s' in the World.")(
              diagnosticNameOf!Param,
              GeneratedSystemName,
              fullyQualifiedName!(Unqual!Param),
              ParamName!Param);
          goto L_continueApplyingParams; // Hack to workaround lack of `continue` support in `static foreach` 😒️
        }
      }
      // TODO: Use `T.init` for `out` parameters
      // Otherwise, get the World, Resources, Entity, Resource, or Component data
      static if (isWorld!Param) {
        params[indexOf!Param] = world;
      } else static if (isResources!Param) {
        params[indexOf!Param] = world.resources;
      } else static if (isEntity!Param) {
        params[indexOf!Param] = cast(Entity) entity;
      } else static if (isResources!Param || isResourceData!Param || storableAsComponent!Param) {
        if (componentExists) {
          static if (hasConstStorage!Param) {
            params[indexOf!Param] = entity.get!(Unqual!Param)(ParamName!Param)[0];
          } else static if (isImplicitlyConvertableFromMutable!Param) {
            params[indexOf!Param] = entity.getMut!(Unqual!Param)(ParamName!Param)[0];
          } else {
            static assert(0, "Could not apply " ~ diagnosticNameOf!Param ~ " to " ~ GeneratedSystemName);
          }
        } else if (isIllegallyMutable!Param) {
          // Guard against illegally mutable Resources
          if (!isStruct!Param && hasRefStorage!(FuncParamStorage[indexOf!Param])) {
            diagnosticMessages ~= "Constant qualifier on " ~ diagnosticNameOf!Param ~ " is required." ~
              "\n\t" ~ diagnosticBadPractice ~
              "\n\t" ~ diagnosticDlangFuncParams ~
              "\n\n\tHint: Use `const` qualifier instead." ~
              "\n";
          } else if (!isStruct!Param) {
            diagnosticMessages ~= "Constant qualifier on " ~ diagnosticNameOf!Param ~ " is required." ~
              "\n\t" ~ diagnosticBadPractice ~
              "\n\t" ~ diagnosticDlangFuncParams ~
              "\n\n\tHint: Add `const` qualifier to `" ~ diagnosticHintOf!Param ~ "." ~
              "\n";
          }
          goto L_systemDoesNotApply;
        } else {
          // Otherwise carry on with Resource(s) parameter assignment
          static if (isResourceData!Param) {
            params[indexOf!Param] = world.resources.get!(Unqual!Param);
          } else {
            static assert(isResources!Param, "");
            params[indexOf!Param] = world.resources;
          }
        }
      } else {
        static assert(0, "Could not apply " ~ diagnosticNameOf!Param ~ " to " ~ GeneratedSystemName);
      }

      // Only define this label once
      static if (indexOf!Param == 0) {
L_continueApplyingParams:
      }

      isResource = false;
      componentExists = false;
    }

    results.diagnostics = diagnosticMessages.map!(msg => Diagnostic(msg)).array;

    // Run the system, applying dependent `Component` instance arguments
    Func(params.expand);

    static foreach (Param; FuncParams) {
      static if (hasRefStorage!(FuncParamStorage[indexOf!Param])) {
        static if (isStruct!(Unqual!Param)) {
          if (entity.contains!(Unqual!Param))
            replacements ~= new Structure!(Unqual!Param)(params[indexOf!Param], ParamName!Param);
        } else static if (!isComponent!(Unqual!Param))
          replacements ~= params[indexOf!Param];
      }
    }

L_systemDoesNotApply:

    results.replacements = replacements;
    return results;
  }
}

unittest {
  auto world = new World();

  // Counter system with a Resource
  world.resources.add(Number(0));
  assert(world.resources.get!Number.value == 0);
  world.spawn(Vector().component("position"));
  assert(world.entities.length == 1);

  auto resourceSystem = System.from!((scope const Resources resources, const Number number) => {
    assert(resources.get!Number.value == 0);
    assert(number.value == 0);
  }());
  resourceSystem(world).run();
  const numberResource = world.resources.get!Number;
  assert(numberResource.value == 0, "Systems MUST NOT mutate Resources when running.");
  // TODO: Add a `Commands` interface so that Systems can queue Entity spawns and Resource changes

  // Counter System with a Component
  world = new World();
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
  struct Vector {
    float x;
    float y;
    float z;
  }

  // TODO: Add an attribute to params to remap expected Component name binding?
  void counter(scope const Entity _, scope ref Number number) {
    number.value += 1;
  }
}
