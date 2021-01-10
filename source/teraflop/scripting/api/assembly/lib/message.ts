enum ErrorType {
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

interface ErrorMessage {
  /** @see `ErrorType` */
  code: u32,
  message: string
}

class Message<Msg> {
  error: ErrorMessage | null
  value: Msg | null

  constructor (error: ErrorMessage | null, value: Msg | null) {
    this.error = error;
    this.value = value;
  }

  static fromError<Msg>(error: ErrorMessage): Message<Msg> {
    return new Message<Msg>(error, null);
  }

  static makeError<Msg>(code: ErrorType | u32, message: string): Message<Msg> {
    return Message.fromError<Msg>({ code, message });
  }

  static fromValue<Msg>(value: Msg): Message<Msg> {
    return new Message<Msg>(null, value);
  }
}
