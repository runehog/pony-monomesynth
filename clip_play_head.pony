use "collections"
use "debug"
use "time"

actor ClipPlayHead
  let _x_offset: I32
  let _y_offset: I32
  let _origin_time: U64
  let _start_time: U64
  let _pitch_mapper: PitchMapper
  let _timers: Timers
  let eof: TimedGridEvent = recover val TimedGridEvent(((0, 0), (0, 0), Note)) end

  new create(events: Array[TimedGridEvent] val,
             x_offset: I32,
             y_offset: I32,
             pitch_mapper: PitchMapper,
             timers: Timers) =>
    _start_time = Time.nanos()
    _pitch_mapper = pitch_mapper
    _timers = timers

    let first_note = try
      events(0)
    else
      eof
    end

    _x_offset = x_offset - first_note()._2._1.i32()
    _y_offset = y_offset - first_note()._2._2.i32()
    _origin_time = first_note()._1._1

    // TODO: don't just dump everything into 'timers' -- this makes it
    // impossible to stop the sequence under user control. Instead,
    // spawn upcoming events in batches, and cancel pending events when
    // told to stop.
    for note in events.values() do
      schedule_note_on(note)
    end

  fun ref offset_xy(xy: GridXY val): GridXY val =>
    ((xy._1.i32() + _x_offset).usize(),
     (xy._2.i32() + _y_offset).usize())

  fun ref offset_time(time: U64): U64 =>
    (time - _origin_time) + _start_time

  fun ref schedule_note_on(note: TimedGridEvent val) =>
    let now = Time.nanos()
    let when = offset_time(note()._1._1) // NoteOn time.
    let this': ClipPlayHead tag = this
    let notify: TimerNotify iso = recover object is TimerNotify
      let head: ClipPlayHead tag = this'
      let note: TimedGridEvent val = note
      fun ref apply(timer: Timer, count: U64): Bool =>
        head.start_note(note)
        true
    end end
    let timer = Timer(consume notify, when - now)
    _timers(consume timer)

  fun ref schedule_note_off(note: TimedGridEvent val) =>
    let now = Time.nanos()
    let when = offset_time(note()._1._2) // NoteOff time.
    let this': ClipPlayHead tag = this
    let notify = recover object is TimerNotify
      let head: ClipPlayHead tag = this'
      let note: TimedGridEvent val = note
      fun ref apply(timer: Timer, count: U64): Bool =>
        head.end_note(note)
        true
    end end
    let timer = Timer(consume notify, when - now)
    _timers(consume timer)

  be start_note(note: TimedGridEvent val) =>
    let xy = offset_xy(note()._2)
    _pitch_mapper.on_grid_event((xy, NoteOn), FromClipPlayHead)
    schedule_note_off(note)

  be end_note(note: TimedGridEvent val) =>
    let xy = offset_xy(note()._2)
    _pitch_mapper.on_grid_event((xy, NoteOff), FromClipPlayHead)
