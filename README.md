# Teraflop

[![DUB Package](https://img.shields.io/dub/v/teraflop.svg)](https://code.dlang.org/packages/teraflop)
[![Teraflop CI](https://github.com/chances/teraflop-d/workflows/Teraflop%20CI/badge.svg?branch=master)](https://github.com/chances/teraflop-d/actions)
[![codecov](https://codecov.io/gh/chances/teraflop-d/branch/master/graph/badge.svg?token=5YN3BU7KR3)](https://codecov.io/gh/chances/teraflop-d/)

An ECS game engine on a [Vulkan](https://github.com/rtbo/gfx-d#readme) foundation.

Ported from its original [C# implementation](https://github.com/chances/teraflop).

## Usage

```json
"dependencies": {
    "teraflop": "0.7.1"
}
```

[API Reference](https://chances.github.io/teraflop-d)

## Examples

- [`dub run teraflop:triangle`](https://github.com/chances/teraflop-d/blob/master/examples/triangle/source/app.d)
- [`dub run teraflop:cube`](https://github.com/chances/teraflop-d/blob/master/examples/cube/source/app.d)

## License

Teraflop's [ECS](https://en.wikipedia.org/wiki/Entity_component_system) implementation was inspired by [Bevy ECS](https://bevyengine.org/learn/book/getting-started/ecs) and [entt](https://github.com/skypjack/entt).

[3-Clause BSD License](https://opensource.org/licenses/BSD-3-Clause)

Copyright &copy; 2020 Chance Snow. All rights reserved.
