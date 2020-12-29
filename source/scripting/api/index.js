const fs = require('fs')
const path = require('path')
const loader = require('@assemblyscript/loader')

const lib = require('./lib')

const registry = {}

function registrarFor(moduleGetter) {
  return (namePtr, version) => {
    try {
      const name = moduleGetter().exports.__getString(namePtr)

      registry[name] = {
        name,
        version: lib.unpackVersion(version)
      }
      console.log(`Registering plugin '${name}' v${registry[name].version.major}.${registry[name].version.minor}.${registry[name].version.patch}-${registry[name].version.meta}`)
      return version > 0
    } catch {
      return false
    }
  }
}

const imports = {
  plugin: {
    register: registrarFor(() => wasmModule)
  }
}
const wasmModule = loader.instantiateSync(fs.readFileSync(path.join(__dirname, 'build/optimized.wasm')), imports)
module.exports = wasmModule.exports
module.exports.plugin.unpackVersion = lib.unpackVersion
module.exports.registry = {
  registrarFor
}
