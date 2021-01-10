import { Codec, Decoder, Writer } from '@wapc/as-msgpack'

export enum ErrorType {
  ///
  unknown = 0,
  ///
  exception,
  ///
  msgpack,
  ///
  commandNotFound,
  ///
  actionNotFound
}

export interface ErrorMessage {
  /** @see {@link ErrorType} */
  code: u32,
  message: string
}

export class Message implements Codec {
  error: ErrorMessage | null
  /** Body of this message encoded in the [MessagePack](https://msgpack.org) format. */
  value: ArrayBuffer | null

  constructor (error: ErrorMessage | null = null, value: ArrayBuffer | null = null) {
    this.error = error;
    this.value = value;
  }

  static fromError(error: ErrorMessage): Message {
    return new Message(error, null);
  }

  static makeError(code: u32, message: string): Message {
    return Message.fromError({ code, message });
  }

  static fromValue(value: ArrayBuffer): Message {
    return new Message(null, value);
  }

  static decode(buffer: ArrayBuffer): Message {
    const decoder = new Decoder(buffer)
    let result = new Message()
    result.decode(decoder)
    return result
  }
  decode(decoder: Decoder): void {
    this.error = null
    if (!decoder.isNextNil()) {
      this.error = {
        code: decoder.readUInt32(),
        message: decoder.readString()
      }
    }
    if (!decoder.isNextNil()) this.value = decoder.readByteArray()
  }
  encode(encoder: Writer): void {
    if (this.error === null) encoder.writeNil()
    else {
      encoder.writeUInt32(this.error.code)
      encoder.writeString(this.error.message)
    }
    if (this.value === null) encoder.writeNil()
    else encoder.writeByteArray(this.value)
  }
}
