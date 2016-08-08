use "debug"
use "net"
use "pony-opensoundcontrol"

actor LEDs
  let _sock: UDPSocket tag
  let _device: String val
  let _addr: IPAddress val

  new create(sock: UDPSocket tag, device: String val, addr: IPAddress val) =>
    _sock = sock
    _device = device
    _addr = addr

  be clear() =>
    try
      let address: OSCAddress = OSCAddress(_device + "/grid/led/all")
      let args: Array[OSCData] val = recover
        let a: Array[OSCData] iso = recover iso Array[OSCData] end
        let value: I32 = 0
        a.push(value)
        consume a
      end
      let message: OSCMessage = OSCMessage(address, args)
      let packet: Array[ByteSeq] val = recover message.binary() end
      let flat: Array[U8] val = recover Util.flatten(packet) end
      _sock.write(flat, _addr)
    else
      Debug.out("failed to build OSC message")
    end


  be set_led(x: USize, y: USize, z: USize) =>
    try
      let address: OSCAddress = OSCAddress(_device + "/grid/led/set")
      let args: Array[OSCData] val = recover
        let a: Array[OSCData] iso = recover iso Array[OSCData] end
        a.push(x.i32())
        a.push(y.i32())
        a.push(z.i32())
        consume a
      end
      let message: OSCMessage = OSCMessage(address, args)
      let packet: Array[ByteSeq] val = recover message.binary() end
      let flat: Array[U8] val = recover Util.flatten(packet) end
      _sock.write(flat, _addr)
    else
      Debug.out("failed to build OSC message")
    end
