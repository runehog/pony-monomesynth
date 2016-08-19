primitive Util
  fun flatten(packet: Array[ByteSeq] val): Array[U8] iso^ =>
    let result = recover Array[U8] end
    for a in packet.values() do
      match a
      | let str: String val =>
        result.append(str)
      | let blob: Array[U8] val =>
        result.append(blob)
      end
    end
    consume result
