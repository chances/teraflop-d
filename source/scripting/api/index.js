const fs = require("fs")
const loader = require("@assemblyscript/loader")

const lib = require('./lib')

const registry = {}

const imports = {
  plugin: {
    register: (namePtr, version) => {
      const name = __getString(namePtr)

      registry[name] = {
        name,
        version: lib.unpackVersion(version)
      }
      console.log(`Registering plugin '${name}' v${registry[name].version.major}.${registry[name].version.minor}.${registry[name].version.patch}-${registry[name].version.meta}`)
      return version > 0
    }
  }
}
const wasmModule = loader.instantiateSync(fs.readFileSync(__dirname + "/build/optimized.wasm"), imports)
const { __getString } = wasmModule.exports
module.exports = wasmModule.exports
module.exports.plugin.unpackVersion = lib.unpackVersion
