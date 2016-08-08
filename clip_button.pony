use "debug"

actor ClipButton is (Pushable & Chooseable)
  let _sink: ButtonEventSink tag
  let _index: USize
  var _state: ClipButtonState val
  var _leds: (None | LEDs tag)
  let _position: (USize, USize)

  new create(sink: ButtonEventSink tag, clip_index: USize, x: USize, y: USize) =>
    _sink = sink
    _index = clip_index
    _state = Empty
    _leds = None
    _position = (x, y)

  be set_leds(leds: LEDs tag) =>
    _leds = leds
    show()

  be begin_choose() =>
    _state = match _state
    | Empty => (Choose, Empty)
    | Ready => (Choose, Ready)
    else
      (Choose, Empty)
    end
    show()

  be cancel_choose() =>
    _state = match _state
    | (Choose, Empty) => Empty
    | (Choose, Ready) => Ready
    else
      Empty
    end
    show()

  be start_record() =>
    _state = match _state
    | (Choose, _)=> Record
    else
      _state
    end
    show()

  be stop_record() =>
    _state = match _state
    | Record => Ready
    else
      _state
    end
    show()

  be press() =>
    match _state
    | Empty =>
      None
    | (Choose, _) =>
      _sink.on_button_event((ClipArm, _index))
    | Record =>
      None
    | Ready =>
      _sink.on_button_event((ClipSelect, _index))
    end

  be release() =>
    match _state
    | Ready =>
      _sink.on_button_event((ClipDeselect, _index))
    end

  fun show() =>
    let z: USize = match _state
    | Empty =>
      Debug.out("clip " + _index.string() + " Empty")
      0
    | (Choose, _) =>
      Debug.out("clip " + _index.string() + " Choose")
      1
    | Record =>
      Debug.out("clip " + _index.string() + " Record")
      1
    | Ready =>
      Debug.out("clip " + _index.string() + " Ready")
      0
    else
      0
    end
    match _leds
    | let leds: LEDs =>
      leds.set_led(_position._1, _position._2, z)
    end
