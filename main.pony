use "collections"
use "debug"
use "net"
use "pony-opensoundcontrol"
use "promises"
use "random"

use "lib:portaudio_sink"
use "lib:portaudio"

interface NotePlayable
  be start_note(pitch: U8)
  be stop_note(pitch: U8)

actor AudioPlayer is NotePlayable
  """Streams audio, turning notes on and off as directed via NotePlayable."""

  let _random: Random
  let _buffer_count: USize
  let _frame_count: USize
  var _preroll: USize
  let _buffers: Array[OutBuffer]
  let _mixer: Mixer
  let _pitch_map: Map[U8, EnvVCA ref]
  let _channels: MapIs[MixerChannel tag, MixerChannel ref]
  var _index: USize

  new create() =>
    _random = MT
    _buffer_count = 4
    _frame_count = 256
    _preroll = 0 // Will be filled in by preroll().
    _buffers = recover Array[OutBuffer] end
    _index = 0

    // Set up audio mixer.
    _mixer = Mixer(_frame_count)
    _pitch_map = Map[U8, EnvVCA ref]
    _channels = MapIs[MixerChannel tag, MixerChannel ref]

    // Set up audio stream.
    let open_result = @init_output_stream[I32](
      _frame_count,
      _buffer_count,
      addressof this.add_buffer,
      addressof this.preroll,
      addressof this.produce,
      this)
    Debug.out("got open_result: " + open_result.string())
    // The stream will be started by produce() when the preroll phase is done.

  be add_buffer(buf: Pointer[F32] iso, ready: Pointer[U8] iso) =>
    let frame_count = _frame_count
    let buf_array: OutBuffer iso = recover
      OutBuffer.from_cstring(consume buf, frame_count)
    end
    _buffers.push(consume buf_array)

  be preroll() =>
    _preroll = _buffers.size()
    // Debug.out("preroll out! " + _preroll.string() + " buffers.")

  be produce(timestamp: F64) =>
    try
      let buf = _buffers(_index)

      _mixer.produce(buf)

      // Advance buffer pointer.
      _index = _index + 1
      if _index == _buffers.size() then
        _index = 0
      end

      // If we're prerolling, see if it's time to start the stream.
      if _preroll > 0 then
        _preroll = _preroll - 1
        if _preroll == 0 then
          Debug.out("start...")
          let start_result = @start_output_stream[I32]()
          Debug.out("got start_result: " + start_result.string())
        end
      end

      // Pull synchronously.
      _mixer.pull()
    end

  be pull() =>
    _mixer.pull()

  fun pitch_to_freq(pitch: U8): F64 =>
    F64(440.0) * @pow[F64](F64(2), (pitch.f64() - 69.0) / 12.0)

  be start_note(pitch: U8) =>
    // Debug.out("start_note: " + pitch.string())
    try
      // make the note
      let base_freq = pitch_to_freq(pitch)

      // Randomly perturb frequency.
      let freq: F64 = base_freq + ((_random.real() * 3.0) - 1.5)
      // Debug.out("freq: " + freq.string())

      // Build osc -> VCA chain and add to mixer.
      let osc = Oscillator(freq)
      let env_done: Promise[None] = Promise[None]
      let env_vca: EnvVCA ref = EnvVCA(osc, 0.05, 5.0, env_done)
      let channel: MixerChannel ref = MixerChannel(env_vca)
      let channel_tag: MixerChannel tag = channel
      let me: AudioPlayer tag = recover this end

      // On notification that this envelope has completed its cycle,
      // tear down the channel.
      env_done.next[None](
        recover
          lambda(x: None val)(me, channel_tag) =>
            me.remove_channel(channel_tag)
          end
        end)

      // Add to pitch map. We'll trigger the release phase on note-off.
      _pitch_map.insert(pitch, env_vca)

      // Add to channel map, for channel teardown.
      _channels.insert(channel_tag, channel)

      // Start!
      _mixer.add_channel(channel)
    // else
    //   Debug.out("start_note blew up")
    end

  be stop_note(pitch: U8) =>
    // Debug.out("stop_note: " + pitch.string())
    try
      let env_vca: EnvVCA ref = _pitch_map.remove(pitch)._2
      env_vca.release()
    // else
    //   Debug.out("stop_note blew up")
    end

  be remove_channel(channel_tag: MixerChannel tag) =>
    try
      let channel: MixerChannel ref = _channels.remove(channel_tag)._2
      _mixer.remove_channel(channel)
    // else
    //   Debug.out("remove_channel blew up")
    end

actor OSCRouter
  let _player: NotePlayable tag

  // The X axis plays major-scale notes.
  let x_steps: Array[U8] = [0, 2, 4, 5, 7, 9, 11, 12]

  new create(player: NotePlayable tag) =>
    _player = player

  be handle_message(message: OSCMessage val) =>
    Debug.out("OSCRouter got message " + message.string())

    // Ignore the address altogether. Assume monome touch event structure.
    var x: I32 = 0
    var y: I32 = 0
    var z: I32 = 0
    try
      match message.args(0)
      | let i32_val: I32 =>
        x = i32_val
      else
        error
      end
      match message.args(1)
      | let i32_val: I32 =>
        y = i32_val
      else
        error
      end
      match message.args(2)
      | let i32_val: I32 =>
        z = i32_val
      else
        error
      end

      Debug.out("valid note event: (" + x.string() + "," + y.string() + ") -> " +
        z.string())
    else
      return
    end

    let pitch: U8 = make_pitch(x, y)
    if z != 0 then
      _player.start_note(pitch)
    else
      _player.stop_note(pitch)
    end

  fun make_pitch(x: I32, y: I32): U8 =>
    try
      ((y * 12) + x_steps(x.usize()).i32()).u8() + 24
    else
      36
    end

class OSCParser is UDPNotify
  let _router: OSCRouter tag

  new create(router: OSCRouter tag) =>
    _router = router

  fun ref listening(sock: UDPSocket ref) =>
    try
      Debug.out("listening at: " + sock.local_address().name()._1)
    end

  fun ref not_listening(sock: UDPSocket ref) =>
    Debug.out("not_listening")

  fun ref received(sock: UDPSocket ref, data: Array[U8] iso, from: IPAddress) =>
    let parse: OSCParseResult = OSC.parse(consume data)
    match parse
    | let message: OSCMessage =>
      Debug.out("OSCMessage " + message.string())
      _router.handle_message(message)
    | let parse_error: OSCParseError =>
      Debug.out("OSCParseError " + parse_error.description)
    end

actor Main
  new create(env: Env) =>
    let audio: AudioPlayer tag = AudioPlayer
    let router: OSCRouter tag = OSCRouter(audio)
    let parser: OSCParser iso = recover OSCParser(router) end
    try
      UDPSocket.ip4(env.root as AmbientAuth, consume parser, "", "12345")
    else
      Debug.out("FAIL")
    end
