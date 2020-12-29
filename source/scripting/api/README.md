# Teraflop Scripting API

[![Teraflop Scripting API CI](https://github.com/chances/teraflop-d/workflows/Teraflop%20Scripting%20API%20CI/badge.svg)](https://github.com/chances/teraflop-d/actions)
[![npm version](https://badge.fury.io/js/%40teraflop%2Fapi.svg)](https://www.npmjs.com/package/@teraflop/api)
<!-- [![dependencies Status](https://david-dm.org/chances/streaming-metadata/status.svg)](https://david-dm.org/chances/streaming-metadata) -->
<!-- [![devDependencies Status](https://david-dm.org/chances/streaming-metadata/dev-status.svg)](https://david-dm.org/chances/streaming-metadata?type=dev) -->

[Teraflop](https://github.com/chances/teraflop-d) game engine WebAssembly scripting API on a [Wasmer](https://wasmer.io/) and [AssemblyScript](https://www.assemblyscript.org/) foundation.

## Usage

## Creating a Plugin

The preferred method of creating a new plugin is to use the [plugin generator](https://github.com/chances/generator-teraflop#readme).

### From Scratch

1. Ensure [Node.js](https://nodejs.org) is installed.
2. `npm init`
    - When asked for keywords, add `teraflop-plugin`
3. `npm install @assemblyscript/loader@^0.17.12 @teraflop/api --save`
4. `npm install assemblyscript@^0.17.12 --save-dev`
5. `npx asinit .`
6. Edit `assembly/index.ts`:

    ```typescript
    import { plugin } from '@teraflop/api'

    const VERSION = plugin.makeVersion(1, 0, 0)

    // The entry point of your plugin.
    export function main(): boolean {
      return plugin.register('plugin-name', VERSION)
    }
    ```

## Development

<!-- TODO: Dev docs

Serve the widget locally, run `npm start`.

The URL of the widget will be copied to your clipboard. -->

## License

[MIT License](http://opensource.org/licenses/MIT)

Copyright &copy; 2020 Chance Snow. All rights reserved.
