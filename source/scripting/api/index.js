const fs = require("fs");
const loader = require("@assemblyscript/loader");

const registry = {}

const imports = {
  plugin: {
    register: (name, version) => registry[name] = version
  }
};
const wasmModule = loader.instantiateSync(fs.readFileSync(__dirname + "/build/optimized.wasm"), imports);
module.exports = wasmModule.exports;
module.registry = registry;
