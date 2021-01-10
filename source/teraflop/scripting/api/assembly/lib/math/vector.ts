import {
  Decoder,
  Writer,
  Encoder,
  Sizer,
  Codec,
  toArrayBuffer,
  Value,
} from "@wapc/as-msgpack"
import * as interop from '../interop'

function decodeVector<T>(size: u8, decoder: Decoder): T[] {
  const sizeError = `Expected \`${nameof<T>()}\` array of length ${size}`
  assert(!decoder.isNextNil(), sizeError)
  const observedSize = assert(decoder.readArraySize(), sizeError)
  assert(observedSize == 2, sizeError)
  let vector = new Array<T>(size);
  for (let i: u32 = 0; i < size; i++) {
    if (isSigned<T>() && isInteger<T>()) vector[i] = (<unknown>decoder.readInt32()) as T
    else if (isSigned<T>() && isFloat<T>()) vector[i] = (<unknown>decoder.readFloat32()) as T
    else assert(0,
      `Could not decode \`${nameof<T>()}\` vector element at index ${i}\n\t` +
      'Only `i32` and `f32` vectors are supported'
    )
  }
  return vector;
}

function encodeVector<T>(vector: T[], encoder: Writer): void {
  encoder.writeArraySize(vector.length)
  for (let i: i32 = 0; i < vector.length; i++) {
    if (isSigned<T>() && isInteger<T>()) encoder.writeInt32((<unknown>vector[i]) as i32)
    else if (isSigned<T>() && isFloat<T>()) encoder.writeFloat32((<unknown>vector[i]) as f32)
    else assert(0,
      `Could not encode \`${nameof<T>()}\` vector element at index ${i}\n\t` +
      'Only `i32` and `f32` vectors are supported'
    )
  }
}

export class Vector2<T> implements Codec {
  x: T
  y: T

  constructor(x: T, y: T) {
    this.x = x
    this.y = y
  }

  // TODO: static decode<T>(decoder: Decoder): Vector2<T>;
  decode(decoder: Decoder): void {
    const vector = decodeVector<T>(2, decoder)
    this.x = vector[0]
    this.y = vector[1]
  }
  encode(encoder: Writer): void {
    encodeVector<T>([this.x, this.y], encoder)
  }
}

export class Vector3<T> extends Vector2<T> {
  z: T

  constructor(x: T, y: T, z: T) {
    super(x, y)
    this.z = z
  }

  decode(decoder: Decoder): void {
    const vector = decodeVector<T>(3, decoder)
    this.x = vector[0]
    this.y = vector[1]
    this.z = vector[2]
  }
  encode(encoder: Writer): void {
    encodeVector<T>([this.x, this.y, this.z], encoder)
  }
}

export class Vector4<T> extends Vector3<T> {
  w: T

  constructor(x: T, y: T, z: T, w: T) {
    super(x, y, z)
    this.w = w
  }

  decode(decoder: Decoder): void {
    const vector = decodeVector<T>(4, decoder)
    this.x = vector[0]
    this.y = vector[1]
    this.z = vector[2]
    this.w = vector[3]
  }
  encode(encoder: Writer): void {
    encodeVector<T>([this.x, this.y, this.z, this.w], encoder)
  }
}

export class Color extends Vector4<interop.float> {
  constructor(r: f32, g: f32, b: f32, a: f32 = 1.0) {
    super(r, g, b, a)
  }

  get r(): f32 {
    return this.x
  }
  set r(v: f32) {
    this.x = v
  }
  get g(): f32 {
    return this.y
  }
  set g(v: f32) {
    this.y = v
  }
  get b(): f32 {
    return this.z
  }
  set b(v: f32) {
    this.z = v
  }
  get a(): f32 {
    return this.w
  }
  set a(v: f32) {
    this.w = v
  }

  /** Construct a color given its hexadecimal representation, i.e. `0xRRGGBBAA`. */
  static from(v: u8): Color {
    return new Color(
      f32((v & 0xFF000000) >> 6) / 255.0,
      f32((v & 0x00FF0000) >> 4) / 255.0,
      f32((v & 0x0000FF00) >> 2) / 255.0,
      f32(v & 0x000000FF) / 255.0
    )
  }

  /** Construct a color given its red, green, and blue components, values between 0 and 255. */
  static rgb(r: u8, g: u8, b: u8): Color {
    assert(r <= 255, 'Red color component is out of bounds')
    assert(g <= 255, 'Green color component is out of bounds')
    assert(b <= 255, 'Blue color component is out of bounds')
    return new Color(f32(r) / 255.0, f32(g) / 255.0, f32(b) / 255.0)
  }

  /**
   * Construct a color given its red, green, and blue components, values between 0 and 255,
   * and its alpha component, `0.0 <= alpha <= 1.0`.
   */
  static rgba(r: u8, g: u8, b: u8, a: f32): Color {
    assert(r <= 255, 'Red color component is out of bounds')
    assert(g <= 255, 'Green color component is out of bounds')
    assert(b <= 255, 'Blue color component is out of bounds')
    assert(a >= 0.0 && a <= 1.0, 'Alpha color component is out of bounds')
    return new Color(f32(r) / 255.0, f32(g) / 255.0, f32(b) / 255.0, a)
  }
}
