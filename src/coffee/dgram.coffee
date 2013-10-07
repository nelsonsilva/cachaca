dgram = require('dgram')
events = require('events')
util = require('util')

ChromeSocket = chrome.socket # || chrome.experimental.socket

class Socket extends events.EventEmitter
    constructor: ->
        super

    bind: (port, address, cb) ->

        if typeof(address) is "function" 
            cb = address
            address = "0.0.0.0"

        ChromeSocket.create 'udp', (socket) =>
            @socketId = socket.socketId;

            console.log "Binding UDP socket #{@socketId} to #{address}:#{port}"
            ChromeSocket.bind @socketId, address, port, (result) =>
                console.log "result = #{result}"
                if (result != 0)
                    ChromeSocket.destroy @socketId
                    @handleError "Error on bind():", result
                else
                    @emit "listening"
                    cb()

    send: (buf, offset, length, port, address, cb) ->
        cb ||= ->
        # TODO - make it work without strings
        msg = buf.toString()
        #console.log "UDP sending to #{address}:#{port}: \n #{msg}"
        buffer = new ArrayBuffer(msg.length)
        bufferView = new Uint8Array(buffer);
        for i in [0..msg.length]
            bufferView[i] = msg.charCodeAt(i)
        ChromeSocket.sendTo @socketId, buffer, address, port, cb

    setMulticastTTL: (ttl) -> 
        ChromeSocket.setMulticastTimeToLive @socketId, ttl, ->

    setMulticastLoopback: (b) ->
        ChromeSocket.setMulticastLoopbackMode @socketId, b, ->

    setBroadcast: (b) ->

    addMembership: (multicastAddress, multicastInterface) ->
        console.log "addMembership #{multicastAddress}"
        ChromeSocket.joinGroup @socketId, multicastAddress, (result) =>
            if result isnt 0
              ChromeSocket.destroy @socketId
              @handleError "Error on joinGroup(): ", result
            else
              @_poll();
              @emit "connected"

    _poll: ->
        return unless @socketId?
        ChromeSocket.recvFrom @socketId, (result) =>
          if result.resultCode >= 0
            #console.debug "UDP Got data from #{result.address}" #, result
            if result.data?
                msg = String.fromCharCode.apply(null, new Uint8Array(result.data))
                #console.log "Got #{msg} from #{result.address}"
                @emit "message", msg, {address: result.address, port: result.port}
            @_poll()
          else
            @handleError "Error: ", result.resultCode
            @disconnect()

    handleError: (msg, alt) ->
        err = chrome.runtime.lastError
        err = err && err.message || alt;
        error = msg + err
        console.error "Error: #{error}"
        @emit "error", error

    disconnect: ->
        ChromeSocket.disconnect @socketId
        ChromeSocket.destroy @socketId
        @emit "close"

dgram.createSocket = (type) -> new Socket()