use "collections"
use "debug"
use "promises"
use "random"
use "time"
use "lib:portaudio_sink"
use "lib:portaudio"

// External sample format: 32-bit float.
type OutBuffer is Array[F32]

// Internal sample format: 64-bit float.
type Buffer is Array[F64]

primitive Clipper
  fun clip(value: F64): F64 =>
    if value < -1.0 then
      -1.0
    elseif value > 1.0 then
      1.0
    else
      value
    end

interface Producer
  fun ref produce(buf: Buffer)

primitive EnvAttack
primitive EnvRelease
primitive EnvDone
type EnvStage is (EnvAttack | EnvRelease | EnvDone)

class EnvVCA is Producer
  let _attack_delta: F64
  let _release_delta: F64
  var _gain: F64
  var _stage: EnvStage
  let _producer: Producer
  let _done: Promise[None]

  new create(producer: Producer,
             attack_time: F64,
             release_time: F64,
             done: Promise[None]) =>
    _attack_delta = 1.0 / (attack_time * 44100.0)
    _release_delta = 1.0 / (release_time * 44100.0)
    _gain = 0.0
    _stage = EnvAttack
    _producer = producer
    _done = done

  fun ref release() =>
    match _stage
    | EnvAttack =>
      _stage = EnvRelease
    end

  fun ref produce(buf: Buffer) =>
    // Pull buffer from input.
    _producer.produce(buf)

    // Apply envelope in place.
    try
      for i in Range[USize](0, buf.size()) do
        buf.update(i, buf(i) * _gain)
        match _stage
        | EnvAttack =>
          _gain = _gain + _attack_delta
          if _gain >= 1.0 then
            _gain = 1.0
          end
        | EnvRelease =>
          _gain = _gain - _release_delta
          if _gain <= 0.0 then
            _gain = 0.0
            _stage = EnvDone
            _done(None)
          end
        end
      end
    end

class Oscillator is Producer
  var _phasor: F64
  var _phasor_inc: F64

  new create(freq: F64) =>
    _phasor = 0
    _phasor_inc = freq / 44100.0

  fun ref produce(buf: Buffer) =>
    for i in Range[USize](0, buf.size()) do
      try
        buf.update(i, _phasor)
      end
      _phasor = _phasor + _phasor_inc
      if _phasor >= 0.5 then
        _phasor = _phasor - 1.0
      end
    end

class MixerChannel
  let _buffers: Array[Buffer]
  var _read_index: USize
  var _write_index: USize
  var _producer: Producer

  new create(producer: Producer) =>
    _buffers = recover Array[Buffer] end
    _read_index = 0
    _write_index = 0
    _producer = producer

  fun ref adopt(frame_count: USize) =>
    for i in Range[USize](0, 2) do
      _buffers.push(recover Buffer(frame_count).init(0.0, frame_count) end)
    end
    try
      pull()
      pull()
    end

  fun ref next(): (None | Buffer) ? =>
    if _read_index == _write_index then
      None
    else
      let result =_buffers(_read_index)
      _read_index = _read_index + 1
      if _read_index == _buffers.size() then
        _read_index = 0
      end
      result
    end

  fun ref pull(): Bool ? =>
    // Figure out what the next buffer is, or if we're full.
    var next_write_index: USize = _write_index + 1
    if next_write_index == _buffers.size() then
      next_write_index = 0
    end
    if next_write_index == _read_index then
      return false
    end
    // Fill the next buffer.
    _producer.produce(_buffers(_write_index))
    _write_index = next_write_index
    true

class Mixer
  """A very basic pull-model audio mixer."""
  let _frame_count: USize
  let _channels: Array[MixerChannel]
  let _mixbuf: Buffer
  var _channel_gain: F64

  new create(frame_count: USize) =>
    _frame_count = frame_count
    _channels = Array[MixerChannel]
    _mixbuf = Buffer.init(0.0, _frame_count)
    _channel_gain = 1.0 / 16

  fun ref add_channel(channel: MixerChannel) =>
    channel.adopt(_frame_count)
    _channels.push(channel)

  fun ref remove_channel(channel: MixerChannel) ? =>
    let i = _channels.find(channel)
    _channels.remove(i, 1)

  fun ref produce(buf: OutBuffer) =>
    try
      for i in Range[USize](0, _frame_count) do
        _mixbuf.update(i, 0.0)
      end
      for c in _channels.values() do
        match c.next()
        | let ch_buf: Buffer =>
          for i in Range[USize](0, _frame_count) do
            _mixbuf.update(i, _mixbuf(i) + ch_buf(i))
          end
        end
      end
      for i in Range[USize](0, _frame_count) do
        buf.update(i, Clipper.clip(_mixbuf(i) * _channel_gain).f32())
      end
    end

  fun ref pull() =>
    for c in _channels.values() do
      try
        let result = c.pull()
      end
    end
