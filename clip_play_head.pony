use "collections"
use "debug"
use "time"

actor ClipPlayHead
  let _it: Iterator[TimedGridEvent]
  var _state: (NoteOn | NoteOff)
  var _note: TimedGridEvent
  let _x_offset: I32
  let _y_offset: I32
  let _origin_time: U64
  let _start_time: U64
  let _pitch_mapper: PitchMapper
  let _timers: Timers
  let eof: TimedGridEvent val = ((0, 0), (0, 0), Note)

  new create(events: List[TimedGridEvent] val,
             x_offset: I32,
             y_offset: I32,
             pitch_mapper: PitchMapper,
             timers: Timers) =>
    _it = events.values()
    _state = NoteOn
    _start_time = Time.nanos()
    _pitch_mapper = pitch_mapper
    _timers = timers
    _note = try
      _it.next()
    else
      eof
    end

    _x_offset = x_offset - _note._2._1.i32()
    _y_offset = y_offset - _note._2._2.i32()
    _origin_time = _note._1._1
    if _note._1._1 > 0 then
      schedule(_start_time)
    end

  fun ref schedule(next_time: U64) =>
    let now = Time.nanos()
    let this': ClipPlayHead tag = this
    let notify: TimerNotify iso = recover object is TimerNotify
      let head: ClipPlayHead tag = this'
      fun ref apply(timer: Timer, count: U64): Bool =>
        head.tick()
        true
    end end
    let timer = Timer(consume notify, next_time - now)
    _timers(consume timer)

  fun ref offset_xy(xy: GridXY val): GridXY val =>
    ((xy._1.i32() + _x_offset).usize(),
     (xy._2.i32() + _y_offset).usize())

  fun ref offset_time(time: U64): U64 =>
    (time - _origin_time) + _start_time

  be tick() =>
    let xy = offset_xy(_note._2)
    var next_time: U64 = 0
    match _state
    | NoteOn =>
      _pitch_mapper.on_grid_event((xy, NoteOn), FromClipPlayHead)
      _state = NoteOff
      next_time = offset_time(_note._1._2)
    | NoteOff =>
      _pitch_mapper.on_grid_event((xy, NoteOff), FromClipPlayHead)
      try
        _note = _it.next()
        next_time = offset_time(_note._1._1)
      else
        _note = eof
        next_time = 0
      end
      _state = NoteOn
    end

    if next_time > 0 then
      schedule(next_time)
    end
