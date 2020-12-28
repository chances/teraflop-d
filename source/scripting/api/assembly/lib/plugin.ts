// Plugin interface

// Host-defined interface
// https://www.assemblyscript.org/exports-and-imports.html#imports
export declare function register(name: string, version: i32): bool

export namespace plugin {
  export enum VersionMeta {
    Release = 0,
    Alpha = 1,
    Beta = 2,
    PreRelease = 3,
    ReleaseCandidate = 4,
    MAX = u8.MAX_VALUE
  }

  export function makeVersion(major: u8, minor: u8, patch: u8, meta: i32 = VersionMeta.Release): i32 {
    assert(meta <= VersionMeta.MAX, "Version metadata is out of bounds")
    return (major << 4) + (minor << 3) + (patch << 2) + meta;
  }
}
