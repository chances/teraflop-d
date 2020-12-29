import 'assemblyscript/std/portable'
export { register, makeVersion, VersionMeta } from '../assembly/lib/plugin'

export interface Plugin {
  name: string,
  version: Version
}

export interface Version {
  major: number,
  minor: number,
  patch: number,
  meta: number
}

/** Unpack a [Semantic Version](https://semver.org) from a 32-bit bitfield. */
export function unpackVersion(version: number): Version & { raw: number } {
  return {
    raw: version,
    major: (version & 0xFF000000) >> 24,
    minor: (version & 0x00FF0000) >> 16,
    patch: (version & 0x0000FF00) >> 8,
    meta: version & 0x000000FF
  }
}
