use "collections"
use "debug"
use "pony-opensoundcontrol"
use "promises"
use "random"

use "lib:portaudio_sink"
use "lib:portaudio"

actor AudioPlayer
  """Streams audio, turning notes on and off as directed via events."""

  let _random: Random
  let _buffer_count: USize
  let _frame_count: USize
  var _preroll: USize
  let _buffers: Array[OutBuffer]
  let _mixer: Mixer
  let _pitch_map: Map[Pitch, List[EnvVCA ref]]
  let _channels: MapIs[MixerChannel tag, MixerChannel ref]
  let _channel_xy: MapIs[MixerChannel tag, GridXY val]
  var _index: USize
  var _router: (None | OSCRouter tag)

  new create() =>
    _random = MT
    _buffer_count = 4
    _frame_count = 256
    _preroll = 0 // Will be filled in by preroll().
    _buffers = recover Array[OutBuffer] end
    _index = 0
    _router = None

    // Set up audio mixer.
    _mixer = Mixer(_frame_count)
    _pitch_map = Map[Pitch, List[EnvVCA ref]]
    _channels = MapIs[MixerChannel tag, MixerChannel ref]
    _channel_xy = MapIs[MixerChannel tag, GridXY val]

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

  be set_router(router: OSCRouter tag) =>
    _router = router

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

  fun pitch_to_freq(pitch: Pitch): F64 =>
    F64(440.0) * @pow[F64](F64(2), (pitch.f64() - 69.0) / 12.0)

  be on_note_event(event: ImmediateNoteEvent val) =>
    match event
    | (let pitch: Pitch, let xy: GridXY val, NoteOn) =>
      start_note(pitch, xy)
    | (let pitch: Pitch, _, NoteOff) =>
      stop_note(pitch)
    end

  fun ref start_note(pitch: Pitch, xy: GridXY val) =>
    // Debug.out("start_note: " + pitch.string())
    try
      // make the note
      let base_freq = pitch_to_freq(pitch)

      // Randomly perturb frequency.
      let freq: F64 = base_freq + ((_random.real() * 2.4) - 1.2)
      // Debug.out("freq: " + freq.string())

      // Build osc -> VCA chain and add to mixer.
      let osc = Oscillator(freq)
      let env_done: Promise[None] = Promise[None]
      let env_vca: EnvVCA ref = EnvVCA(osc, 0.001, 0.333, env_done)
      let channel: MixerChannel ref = MixerChannel(env_vca)
      let channel_tag: MixerChannel tag = channel

      // On notification that this envelope has completed its cycle,
      // tear down the channel.
      let this': AudioPlayer tag = recover this end
      env_done.next[None](
        recover
          lambda(x: None val)(this', channel_tag) =>
            this'.remove_channel(channel_tag)
          end
        end)

      // Add to pitch map. We'll trigger the release phase on note-off.
      push_note(pitch, env_vca)

      // Add to channel map, for channel teardown.
      _channels.insert(channel_tag, channel)

      // Add to channel->note info map, to display note-off.
      _channel_xy.insert(channel_tag, xy)

      // Start!
      _mixer.add_channel(channel)
    end

  fun ref stop_note(pitch: Pitch) =>
    try
      let env: EnvVCA ref = pop_note(pitch)
      env.release()
    else
      Debug.out("stop_note blew up")
    end

  fun ref push_note(pitch: U8, env_vca: EnvVCA ref) =>
    try
      _pitch_map(pitch).push(env_vca)
    else
      let list = List[EnvVCA]
      list.push(env_vca)
      _pitch_map.update(pitch, list)
    end

  fun ref pop_note(pitch: U8): EnvVCA ? =>
    _pitch_map(pitch).pop()

  be remove_channel(channel_tag: MixerChannel tag) =>
    try
      let channel: MixerChannel ref = _channels.remove(channel_tag)._2
      _mixer.remove_channel(channel)

      let xy: GridXY val = _channel_xy.remove(channel_tag)._2
      match _router
      | (let r: OSCRouter tag) =>
        r.note_done(xy)
      end
    end
