/// <reference path="node_modules/assemblyscript/std/portable/index.d.ts" />

import * as fs from 'fs'
import * as path from 'path'
import * as loader from '@assemblyscript/loader'
import { ASUtil } from '@assemblyscript/loader'

import * as lib from './lib'
export * as plugin from './lib'

const plugins: Record<string,lib.Plugin> = {}

export namespace registry {
  /**
   * Retrieve a plugin registrar for testing purposes.
   * @param moduleGetter A function that returns an instantiation of a plugin's WebAssembly module
   */
  export function registrarFor(moduleGetter: () => { exports: ASUtil }) {
    return (namePtr: number, version: number) => {
      try {
        const name = moduleGetter().exports.__getString(namePtr)

        plugins[name] = {
          name,
          version: lib.unpackVersion(version)
        }
        console.log(`Registering plugin '${name}' v${plugins[name].version.major}.${plugins[name].version.minor}.${plugins[name].version.patch}-${plugins[name].version.meta}`)
        return version > 0
      } catch {
        return false
      }
    }
  }
}

const imports: loader.Imports = {
  plugin: {
    register: registry.registrarFor(() => wasmModule)
  }
}
const wasmModule = loader.instantiateSync(fs.readFileSync(path.join(__dirname, 'build/optimized.wasm')), imports)
module.exports = wasmModule.exports
module.exports.plugin.unpackVersion = lib.unpackVersion
module.exports.registry = registry
