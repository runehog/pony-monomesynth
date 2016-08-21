use "collections"
use "debug"
use "pony-opensoundcontrol"
use "promises"
use "random"

use "pony-af"

use "lib:portaudio_sink"
use "lib:portaudio"

actor AudioPlayer
  """Streams audio, turning notes on and off as directed via events."""

  let _random: Random
  let _audio_settings: AudioSettings
  var _preroll: USize
  let _buffers: Array[OutBuffer]
  let _mixer: Mixer
  let _pitch_map: Map[Pitch, List[Array[EnvVCA ref]]]
  let _channels: MapIs[MixerChannel tag, MixerChannel ref]
  let _channel_xy: MapIs[MixerChannel tag, GridXY val]
  var _index: USize
  var _router: (None | OSCRouter tag)

  new create() =>
    _random = MT
    _audio_settings = AudioSettings(44100.0, 256, 4)
    _preroll = 0 // Will be filled in by preroll().
    _buffers = recover Array[OutBuffer] end
    _index = 0
    _router = None

    // Set up audio mixer.
    _mixer = Mixer(_audio_settings)
    _pitch_map = Map[Pitch, List[Array[EnvVCA ref]]]
    _channels = MapIs[MixerChannel tag, MixerChannel ref]
    _channel_xy = MapIs[MixerChannel tag, GridXY val]

    // Set up audio stream.
    let open_result = @init_output_stream[I32](
      _audio_settings.frames_per_buffer,
      _audio_settings.buffer_count,
      addressof this.add_buffer,
      addressof this.preroll,
      addressof this.produce,
      this)
    Debug.out("got open_result: " + open_result.string())
    // The stream will be started by produce() when the preroll phase is done.

  be set_router(router: OSCRouter tag) =>
    _router = router

  be add_buffer(buf: Pointer[F32] iso, ready: Pointer[U8] iso) =>
    let buf_array = recover
      OutBuffer.from_cstring(consume buf, _audio_settings.frames_per_buffer)
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
      // let freq_lfo_rate_env = EnvVCA(
      //   _audio_settings, ConstantValue(1.0), freq, 3.0, freq * 2.0, 0.01, freq * 2.0, 15.0, base_freq * 16, None)
      let freq_lfo_rate_env = EnvVCA(
        _audio_settings, ConstantValue(1.0), freq * 1.888, 8.0, freq * 2.01, 2.0, freq * 1.98, 10.0, freq * 2.222, None)
      let freq_lfo = SineOsc(_audio_settings, 0.000001
        where scale = freq / 2.0, freq_mod = freq_lfo_rate_env)
      let osc = SineOsc(_audio_settings, freq
        where freq_mod = freq_lfo)
      let env_done: Promise[None] = Promise[None]
      let amp_env = EnvVCA(
        _audio_settings, osc, 0.0, 8.0, 1.0, 0.05, 1.0, 15.0, 0.0, env_done)
      // let amp_env = EnvVCA(
      //   _audio_settings, osc, 0.0, 0.001, 1.0, 0.05, 0.2, 1.5, 0.0, env_done)
      let channel: MixerChannel ref = MixerChannel(amp_env)
      let channel_tag: MixerChannel tag = channel

      // On notification that this envelope has completed its cycle,
      // tear down the channel.
      let this' = recover tag this end
      env_done.next[None](
        recover
          lambda(x: None val)(this', channel_tag) =>
            this'.remove_channel(channel_tag)
          end
        end)

      // Add to pitch map. We'll trigger the release phase for all of the
      // listed envelopes on note-off.
      push_note(pitch, [amp_env, freq_lfo_rate_env])

      // Add to channel map, for channel teardown.
      _channels.insert(channel_tag, channel)

      // Add to channel->note info map, to display note-off.
      _channel_xy.insert(channel_tag, xy)

      // Start!
      _mixer.add_channel(channel)
    end

  fun ref stop_note(pitch: Pitch) =>
    try
      let envs: Array[EnvVCA ref] = pop_note(pitch)
      for env in envs.values() do
        env.release()
      end
    else
      Debug.out("stop_note blew up")
    end

  fun ref push_note(pitch: U8, env_vcas: Array[EnvVCA ref]) =>
    try
      _pitch_map(pitch).push(env_vcas)
    else
      let list = List[Array[EnvVCA ref]]
      list.push(env_vcas)
      _pitch_map.update(pitch, list)
    end

  fun ref pop_note(pitch: U8): Array[EnvVCA ref] ? =>
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
