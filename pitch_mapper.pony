use "collections"
use "debug"
use "time"

actor PitchMapper
  var _player: AudioPlayer tag
  let _leds: LEDs tag
  let _timers: Timers tag
  let _active_notes: Array[U32] ref
  var _clip_record_head: (None | ClipRecordHead tag)
  let _num_clips: USize = 4
  let _clips: Array[(None | List[TimedGridEvent] val)]
  var _selected_clips: Set[USize] val

  // The X axis plays major-scale notes.
  let x_steps: Array[USize] = [0, 2, 4, 5, 7, 9, 11, 12]

  new create(player: AudioPlayer tag, leds: LEDs tag, timers: Timers tag) =>
    _player = player
    _leds = leds
    _timers = timers
    _active_notes = Array[U32](64)
    for i in Range(0, 64) do
      _active_notes.push(0)
    end
    _clip_record_head = None
    _clips = Array[(None | List[TimedGridEvent] val)](_num_clips)
    for i in Range(0, _num_clips) do
      _clips.push(None)
    end
    _selected_clips = recover val Set[USize] end

  be on_grid_event(event: ImmediateGridEvent val, source: EventSource) =>
    match source
    | FromUser =>
      if _selected_clips.size() > 0 then
        play_clips(event)
      else
        play_note(event)
      end
    | FromClipPlayHead =>
      play_note(event)
    end

  fun ref play_note(event: ImmediateGridEvent val) =>
    match event
    | (let xy: GridXY val, NoteOn) =>
      let pitch: U8 = make_pitch(xy)
      _player.on_note_event((pitch, xy, NoteOn))
      try
        let index: USize = (xy._1 + (xy._2 * 8))
        let new_val: U32 = _active_notes(index) + 1
        _active_notes.update(index, new_val)
      end
      _leds.set_led(xy._1, xy._2, 1)
    | (let xy: GridXY val, NoteOff) =>
      let pitch: U8 = make_pitch(xy)
      _player.on_note_event((pitch, xy, NoteOff))
    end

    // If we're recording, send all grid events to the record head.
    match _clip_record_head
    | (let h: ClipRecordHead tag) =>
      h.on_grid_event(event)
    end

  fun ref play_clips(event: ImmediateGridEvent val) =>
    match event
    | (let xy: GridXY, NoteOn) =>
      for clip_index in _selected_clips.values() do
        try
          let clip = _clips(clip_index)
          ClipPlayHead(
            clip as List[TimedGridEvent] val,
            xy._1.i32(),
            xy._2.i32(),
            this,
            _timers)
        else
          Debug.out("play_clips failed: " + clip_index.string())
        end
      end
    end

  be note_done(xy: GridXY val) =>
    try
      let index: USize = (xy._1 + (xy._2 * 8)).usize()
      let new_val: U32 = _active_notes(index) - 1
      _active_notes.update(index, new_val)
      if new_val == 0 then
        _leds.set_led(xy._1, xy._2, 0)
      end
    end

  fun ref make_pitch(xy: GridXY val): Pitch =>
    (let x: USize, let y: USize) = xy
    try
      ((y * 12) + x_steps(x)).u8() + 24
    else
      36
    end

  be start_record(clip_index: USize) =>
    _clip_record_head = ClipRecordHead(this, clip_index)

  be stop_record() =>
    match _clip_record_head
    | (let h: ClipRecordHead tag) =>
      h.on_done()
      _clip_record_head = None
    end

  be on_clip_recorded(clip_index: USize, events: List[TimedGridEvent] val) =>
    try
      _clips.update(clip_index, events)
    end

  be set_selected_clips(selected_clips: Set[USize] val) =>
    _selected_clips = selected_clips
