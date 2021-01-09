const assert = require("assert")
const api = require("..")

assert.strictEqual(api.plugin.makeVersion(0, 1, 0, 0), 65536)

const versionNum = api.plugin.makeVersion(0, 1, 0)

const version = api.plugin.unpackVersion(versionNum)
console.log(version)
assert.strictEqual(version.major, 0)
assert.strictEqual(version.minor, 1)
assert.strictEqual(version.patch, 0)
assert.strictEqual(version.meta, 0)

api.plugin.register(api.__newString('test-plugin'), versionNum)
