actor ToggleButton is Pushable
  let _sink: ButtonEventSink tag
  let _name: String val
  var _state: USize
  var _leds: (None | LEDs tag)
  let _position: (USize, USize)

  new create(sink: ButtonEventSink tag, name: String val, x: USize, y: USize) =>
    _sink = sink
    _name = name
    _state = 0
    _leds = None
    _position = (x, y)

  be press() =>
    _sink.on_button_event((TogglePress, _name, _state))
    _state = _state xor 1
    show()

  be release() =>
    _sink.on_button_event((ToggleRelease, _name, _state))

  be set_state(state: USize) =>
    _state = state
    show()

  be set_leds(leds: LEDs tag) =>
    _leds = leds
    show()

  fun show() =>
    match _leds
    | let leds: LEDs =>
      leds.set_led(_position._1, _position._2, _state)
    end
