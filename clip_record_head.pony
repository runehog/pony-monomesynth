use "collections"
use "debug"
use "sort"
use "time"

actor ClipRecordHead
  let _pitch_mapper: PitchMapper tag
  let _clip_index: USize

  // Timestamp of the most recent note-on event at a given linearized
  // grid position, or None.
  let _note_ons: Array[(None | U64)] ref

  // Events are added to this list as note-offs arrive that correspond
  // to entries in _note_ons.
  var _events: Array[TimedGridEvent] iso

  new create(pitch_mapper: PitchMapper tag, clip_index: USize) =>
    _pitch_mapper = pitch_mapper
    _clip_index = clip_index
    _note_ons = Array[(None | U64)]
    for i in Range(0, 64) do
      _note_ons.push(None)
    end
    _events = recover Array[TimedGridEvent] end

  fun ref linearize(xy: GridXY val): USize =>
    (xy._1 + (xy._2 * 8))

  be on_grid_event(event: ImmediateGridEvent val) =>
    let timestamp: U64 = Time.nanos()
    let i: USize = linearize(event._1)
    match event
    | (_, NoteOn) =>
      try
        // Add to _note_ons. NOTE: if we received two note-ons for a
        // given grid position without an intervening note-off, this
        // will result in the first being ignored.
        _note_ons.update(i, timestamp)
      else
        Debug.out("NoteOn a splode")
      end
    | (_, NoteOff) =>
      try
        // Get start time / remove from _note_ons.
        let start_time: U64 = match _note_ons.update(i, None)
        | (let start_time': U64) => start_time'
        else
          Debug.out("no start_time for " + i.string())
          return
        end
        // Build the event and add it to end of the array. The end result
        // is an array sorted by note-off time -- we will re-sort it by
        // note-on time in on_done().
        let event': TimedGridEvent val = recover
          TimedGridEvent(((start_time, timestamp), event._1, Note))
        end
        _events.push(event')
      else
        Debug.out("NoteOff a splode")
      end
    end

  fun ref dump_events(events: Array[TimedGridEvent] val) =>
    for entry in events.values() do
      match entry()
      | (let t: TimedEvent val, let xy: GridXY val, let c: TimedCommand val) =>
        let command: String val = match c
        | Note => "Note"
        else
          "???"
        end
        Debug.out("[" + t._1.string() + "+" + (t._2 - t._1).string() + "] @" +
          xy._1.string() + "," + xy._2.string() + " " + command)
      end
    end

  be on_done() =>
    let events: Array[TimedGridEvent] val = _events = recover Array[TimedGridEvent] end
    let sorted_events: Array[TimedGridEvent] val = recover
      let sorted_events' = Array[TimedGridEvent](events.size())
      for e in events.values() do
        sorted_events'.push(recover val TimedGridEvent(e()) end)
      end
      try
        QuickSort[TimedGridEvent](sorted_events')
      else
        Debug.out("sort fail")
        return
      end
      sorted_events'
    end

    // dump_events(sorted_events)

    // Send back to PitchMapper.
    _pitch_mapper.on_clip_recorded(_clip_index, sorted_events)
