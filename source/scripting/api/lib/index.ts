/**
 * Unpack a Semantic Version from a 32-bit bitfield.
 * @param version
 * @see https://semver.org
 */
export function unpackVersion(version: number) {
  return {
    raw: version,
    major: (version & 0xFF000000) >> 24,
    minor: (version & 0x00FF0000) >> 16,
    patch: (version & 0x0000FF00) >> 8,
    meta: version & 0x000000FF
  }
}
