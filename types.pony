interface ButtonEventSink
  be on_button_event(m: ButtonEvent val)

interface Pushable
  be press()
  be release()
  be set_leds(led: LEDs tag)

interface Chooseable
  be begin_choose()
  be cancel_choose()
  be start_record()
  be stop_record()

// Recorded sequences consist of a GridXY in addition to start time (relative
// to the start of the sequence) and duration (relative to start of note).
type TimedEvent is (U64, U64)

// Rather than recording the pitches played, we record the positions on the
// grid, for easy transposition in-scale.
type GridXY is (USize, USize)

type Pitch is U8

// Used to tag an immediate event based on its origin (to avoid an infinite
// regress playing clips of clips of clips ...)
primitive FromUser
primitive FromClipPlayHead
type EventSource is (FromUser | FromClipPlayHead)

// Immediate command types.
primitive NoteOn
primitive NoteOff
type ImmediateCommand is (NoteOn | NoteOff)

// Immediate events: a GridXY plus an ImmediateCommand.
type ImmediateGridEvent is (GridXY val, ImmediateCommand)

type ImmediateNoteEvent is (Pitch, GridXY val, ImmediateCommand)

// Timed event types.
primitive Note
type TimedCommand is Note

// See timed_grid_event.pony.
type TimedGridEventData is (TimedEvent val, GridXY val, TimedCommand)

// Button events.
primitive ClipArm
primitive ClipSelect
primitive ClipDeselect

primitive TogglePress
primitive ToggleRelease
type ButtonEvent is
  ((ClipArm, USize) |
   (ClipSelect, USize) |
   (ClipDeselect, USize) |
   (TogglePress, String, USize) |
   (ToggleRelease, String, USize))

// Clip button states.
primitive Empty
primitive Choose
primitive Record
primitive Ready
type ClipButtonState is (Empty | (Choose, Empty | Ready) | Record | Ready)
