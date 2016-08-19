use "collections"
use "debug"
use "net"
use "time"

use "pony-opensoundcontrol"

actor OSCRouter is ButtonEventSink
  let _timers: Timers tag
  let _player: AudioPlayer tag
  var _pitch_mapper: (None | PitchMapper tag)
  var _our_port: I32
  var _osc_sink: (None |
                  (UDPSocket tag, AmbientAuth) |
                  (UDPSocket tag, AmbientAuth, String val, IPAddress val))

  let _buttons: Array[(None | Pushable tag | (Pushable tag & Chooseable tag))]
  var _leds: (None | LEDs tag)
  var _armed_clip: (None | USize)
  let _selected_clips: Set[USize]

  new create(timers: Timers tag, player: AudioPlayer tag, our_port: I32) =>
    _timers = timers
    _player = player
    _pitch_mapper = None
    _our_port = our_port
    _osc_sink = None

    _buttons = Array[(None | Pushable tag | (Pushable tag & Chooseable tag))].init(None, 8)
    _leds = None
    _armed_clip = None
    _selected_clips = Set[USize]

    for i in Range(0, 4) do
      add_button(i, ClipButton(this, i, i, 7))
    end

    add_button(7, ToggleButton(this, "record", 7, 7))

  be on_button_event(event: ButtonEvent val) =>
    match event
    | (TogglePress, "record", 0) =>
      // Debug.out("choose!")
      for i in Range(0, 4) do
        try (_buttons(i) as Chooseable tag).begin_choose() end
      end
    | (ClipArm, let index: USize) =>
      // Debug.out("choose ok!")
      for i in Range(0, 4) do
        try
          let c: Chooseable tag = _buttons(i) as Chooseable tag
          if i == index then
            c.start_record()
          else
            c.cancel_choose()
          end
        end
      end
      _armed_clip = index
    | (ToggleRelease, "record", 1) =>
      match _armed_clip
      | None =>
        // Debug.out("no clip chosen -- cancel record")
        for i in Range(0, 4) do
          try (_buttons(i) as Chooseable tag).cancel_choose() end
        end
        try (_buttons(7) as ToggleButton tag).set_state(0) end
      | let clip_index: USize =>
        // Debug.out("record clip " + clip_index.string() + "!")
        match _pitch_mapper
        | (let p: PitchMapper tag) =>
          p.start_record(clip_index)
        end
      end
    | (ToggleRelease, "record", 0) =>
      match _armed_clip
      | let clip_index: USize =>
        // Debug.out("record clip " + clip_index.string() + "... stop!")
        try (_buttons(clip_index) as Chooseable tag).stop_record() end
        match _pitch_mapper
        | let p: PitchMapper tag =>
          p.stop_record()
        end
      end
    | (ClipSelect, let index: USize) =>
      // Debug.out("select clip " + index.string())
      _selected_clips.set(index)
      push_selected_clips()
    | (ClipDeselect, let index: USize) =>
      // Debug.out("deselect clip " + index.string())
      _selected_clips.unset(index)
      push_selected_clips()
    end

  fun ref push_selected_clips() =>
    match _pitch_mapper
    | let p: PitchMapper tag =>
      let selected = recover Set[USize] end
      for c in _selected_clips.values() do
        selected.set(c)
      end
      p.set_selected_clips(consume selected)
    end

  be add_button(x: USize, b: Pushable tag) =>
    try
      _buttons(x) = b
    end

  fun ref set_leds(leds: LEDs tag) =>
    _leds = leds
    for b in _buttons.values() do
      match b
      | let pushable: Pushable tag =>
        pushable.set_leds(leds)
      end
    end
    match leds
    | (let leds': LEDs) =>
      leds'.clear()
    end

  be set_sink(sock: UDPSocket tag, auth: AmbientAuth) =>
    _osc_sink = (sock, auth)
    request_device_list(sock, auth, _our_port)

  be note_done(xy: GridXY val) =>
    match _pitch_mapper
    | (let p: PitchMapper tag) =>
      p.note_done(xy)
    end

  fun request_device_list(
    sock: UDPSocket tag, auth: AmbientAuth, our_port: I32) =>
    try
      // Request device list.
      let serialosc_addr = recover val DNS.ip4(auth, "localhost", "12002")(0) end
      let address: OSCAddress = OSCAddress("serialosc/list")
      let args = recover val
        let a = recover Array[OSCData] end
        a.push("localhost")
        a.push(our_port)
        consume a
      end
      let message: OSCMessage = OSCMessage(address, args)
      let packet = recover val message.binary() end
      let flat = recover val Util.flatten(packet) end
      sock.write(flat, serialosc_addr)
    else
      Debug.out("request_device_list failed miserably")
    end

  be handle_message(message: OSCMessage) =>
    Debug.out("OSCRouter got message " + message.string())

    // +++ TODO route map, rather than a bunch of string compares
    if message.address.string() == "sys/connect" then
      match _osc_sink
      | (let sock: UDPSocket tag, let auth: AmbientAuth) =>
        request_device_list(sock, auth, _our_port)
      end
      return
    end

    if message.address.string() == "sys/disconnect" then
      match _osc_sink
      | (let sock: UDPSocket tag,
         let auth: AmbientAuth,
         let device: String,
         let addr: IPAddress val) =>
        Debug.out("Device \"" + device + "\" has been removed.")
        _osc_sink = (sock, auth)
      end
      return
    end

    if message.address.string() == "serialosc/device" then
      match _osc_sink
      | (let sock: UDPSocket tag, let auth: AmbientAuth) =>
        try
          var device: String
          match message.args(0)
          | let d: String =>
            device = d
            Debug.out("got device: " + device)
          else
            error
          end
          match message.args(2)
          | let port: I32 =>
            let addr: IPAddress val = recover
              DNS.ip4(auth, "localhost", port.string())(0)
            end
            Debug.out("got sink!")
            _osc_sink = (sock, auth, device, addr)
            let leds: LEDs tag = LEDs(sock, device, addr)
            _pitch_mapper = PitchMapper(_player, leds, _timers)
            set_leds(leds)
          else
            error
          end
        else
          Debug.out("handle_message got hot nonsense from serialosc")
        end
      end
      return
    end

    // +++ TODO move into another function
    // Basic address check. Assumes monome touch event structure.
    match _osc_sink
    | (let sock: UDPSocket tag,
       let auth: AmbientAuth,
       let device: String,
       let addr: IPAddress val) =>
      if message.address.string() != (device + "/grid/key") then
        Debug.out("ignoring message for someone else")
        return
      end
    end

    var x: USize = 0
    var y: USize = 0
    var z: USize = 0
    try
      match message.args(0)
      | let i32_val: I32 =>
        x = i32_val.usize()
      else
        error
      end
      match message.args(1)
      | let i32_val: I32 =>
        y = i32_val.usize()
      else
        error
      end
      match message.args(2)
      | let i32_val: I32 =>
        z = i32_val.usize()
      else
        error
      end
    else
      return
    end

    if y < 7 then
      match _pitch_mapper
      | (let m: PitchMapper tag) =>
        if z != 0 then
          m.on_grid_event(((x, y), NoteOn), FromUser)
        else
          m.on_grid_event(((x, y), NoteOff), FromUser)
        end
      end
    else
      try
        match _buttons(x.usize())
        | let push: Pushable tag =>
          if z != 0 then
            push.press()
          else
            push.release()
          end
        end
      end
    end

  fun set_led(x: USize, y: USize, z: USize) =>
    match _leds
    | let l: LEDs tag =>
      l.set_led(x, y, z)
    end
