class val TimedGridEvent is Comparable[TimedGridEvent box]
  let _v: TimedGridEventData

  new create(v: TimedGridEventData) =>
    _v = v

  fun apply(): TimedGridEventData => _v

  fun eq(that: TimedGridEvent box): Bool =>
    _v._1._1 == that._v._1._1

  fun lt(that: TimedGridEvent box): Bool =>
    _v._1._1 < that._v._1._1
