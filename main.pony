use "collections"
use "debug"
use "net"
use "pony-opensoundcontrol"
use "promises"
use "time"

class OSCParser is UDPNotify
  let _router: OSCRouter tag

  new create(router: OSCRouter tag) =>
    _router = router

  fun ref listening(sock: UDPSocket ref) =>
    try
      Debug.out("listening at: " + sock.local_address().name()._1)
    end

  fun ref not_listening(sock: UDPSocket ref) =>
    Debug.out("not_listening")

  fun ref received(sock: UDPSocket ref, data: Array[U8] iso, from: IPAddress) =>
    let parse: OSCParseResult = OSC.parse(consume data)
    match parse
    | let message: OSCMessage =>
      _router.handle_message(message)
    | let parse_error: OSCParseError =>
      Debug.out("OSCParseError " + parse_error.description)
    end

actor Main
  new create(env: Env) =>
    try
      let auth: AmbientAuth = env.root as AmbientAuth
      let audio: AudioPlayer tag = AudioPlayer
      let our_port: I32 = 12345
      let timers: Timers tag = Timers
      let router: OSCRouter tag = OSCRouter(timers, audio, our_port)
      audio.set_router(router)
      let parser: OSCParser iso = recover OSCParser(router) end
      let sock = UDPSocket.ip4(auth, consume parser, "", our_port.string())
      router.set_sink(sock, auth)
    else
      Debug.out("FAIL")
    end
