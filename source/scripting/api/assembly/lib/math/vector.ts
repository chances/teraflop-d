@unmanaged export class Vector2 {
  x: f64
  y: f64

  constructor(x: f64, y: f64) {
    this.x = x
    this.y = y
  }
}

@unmanaged export class Vector3 extends Vector2 {
  z: f64

  constructor(x: f64, y: f64, z: f64) {
    super(x, y)
    this.z = z
  }
}

@unmanaged export class Vector4 extends Vector3 {
  w: f64

  constructor(x: f64, y: f64, z: f64, w: f64) {
    super(x, y, z)
    this.w = w
  }
}

@unmanaged export class Color extends Vector4 {
  constructor(r: f64, g: f64, b: f64, a: f64 = 1.0) {
    super(r, g, b, a)
  }

  get r(): f64 {
    return this.x
  }
  set r(v: f64) {
    this.x = v
  }
  get g(): f64 {
    return this.y
  }
  set g(v: f64) {
    this.y = v
  }
  get b(): f64 {
    return this.z
  }
  set b(v: f64) {
    this.z = v
  }
  get a(): f64 {
    return this.w
  }
  set a(v: f64) {
    this.w = v
  }

  /** Construct a color given its hexadecimal representation, i.e. `0xRRGGBBAA`. */
  static from(v: u8): Color {
    return new Color(
      f64((v & 0xFF000000) >> 6) / 255.0,
      f64((v & 0x00FF0000) >> 4) / 255.0,
      f64((v & 0x0000FF00) >> 2) / 255.0,
      f64(v & 0x000000FF) / 255.0
    )
  }

  /** Construct a color given its red, green, and blue components, values between 0 and 255. */
  static rgb(r: u8, g: u8, b: u8): Color {
    assert(r <= 255, 'Red color component is out of bounds')
    assert(g <= 255, 'Green color component is out of bounds')
    assert(b <= 255, 'Blue color component is out of bounds')
    return new Color(f64(r) / 255.0, f64(g) / 255.0, f64(b) / 255.0)
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
    return new Color(f64(r) / 255.0, f64(g) / 255.0, f64(b) / 255.0, a)
  }
}
