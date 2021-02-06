/// Authors: Chance Snow
/// Copyright: Copyright © 2020 Chance Snow. All rights reserved.
/// License: 3-Clause BSD License
module teraflop.traits;

/// Detect whether `T` is a struct type.
package enum bool isStruct(T) = is (T == struct);
/// Detect whether `T` is an interface type.
package enum bool isInterface(T) = is (T == interface);
/// Detect whether `T` is a class type.
package enum bool isClass(T) = is (T == class);
/// Detect whether `T` is an interface or class type.
package enum bool isHeritable(T) = isInterface!T || isClass!T;

/// Detect whether `T` inherits from `U`.
package template inheritsFrom(T, U) if (isClass!T && isClass!U) {
  import std.meta : anySatisfy;
  import std.traits : BaseClassesTuple, fullyQualifiedName;
  enum bool isBaseClassOfU(T) = __traits(isSame, fullyQualifiedName!T, fullyQualifiedName!U);
  enum bool inheritsFrom = anySatisfy!(isBaseClassOfU, BaseClassesTuple!T);
}
