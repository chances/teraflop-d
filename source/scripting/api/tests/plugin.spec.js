const assert = require("assert")
const api = require("..")

assert.equal(api.plugin.makeVersion(0, 1, 0, 0), 8)
