// Plugin interface

// Host-defined interface
// https://www.assemblyscript.org/exports-and-imports.html#imports
export declare function register(name: string, version: i32): bool

export enum VersionMeta {
  Release = 0,
  ReleaseCandidate = 1,
  PreRelease = 2,
  Beta = 3,
  Alpha = 4,
  PreAlpha = 5,
  MAX = u8.MAX_VALUE
}

/**
 * Pack a Semantic Version into a 32-bit bitfield.
 * @param major Incompatible API changes
 * @param minor Added functionality in a backwards compatible manner
 * @param patch Backwards compatible bug fixes
 * @param meta Additional label for pre-release and build metadata
 *
 * **Bitfield**
 *
 * |    major    |    minor    |    patch    |    meta     |
 * | ----------- | ----------- | ----------- | ----------- |
 * | `0000 0000` | `0000 0000` | `0000 0000` | `0000 0000` |
 *
 * @see https://semver.org
 */
export function makeVersion(major: u8, minor: u8, patch: u8, meta: i32 = VersionMeta.Release): i32 {
  assert(major <= u8.MAX_VALUE, "Major version component is out of bounds")
  assert(minor <= u8.MAX_VALUE, "Minor version component is out of bounds")
  assert(patch <= u8.MAX_VALUE, "Patch version component is out of bounds")
  assert(meta <= VersionMeta.MAX, "Version metadata is out of bounds")

  return ((major as i32) << 24) | ((minor as i32) << 16) | ((patch as i32) << 8) | (meta as i32)
}
