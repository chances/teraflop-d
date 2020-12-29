const assert = require("assert")
const api = require("..")

assert.strictEqual(api.plugin.makeVersion(0, 1, 0, 0), 65536)

const versionNum = api.plugin.makeVersion(0, 1, 0)
const version = {
  raw: versionNum,
  major: (versionNum & 0xFF000000) >> 24,
  minor: (versionNum & 0x00FF0000) >> 16,
  patch: (versionNum & 0x0000FF00) >> 8,
  meta: versionNum & 0x000000FF
}
console.log(version)
assert.strictEqual(version.major, 0)
assert.strictEqual(version.minor, 1)
assert.strictEqual(version.patch, 0)
assert.strictEqual(version.meta, 0)
