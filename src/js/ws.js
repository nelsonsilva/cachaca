var http = require('./http.js');
var events = require('./events.js');

module.exports = function() {
/**
 * Constructs a server which is capable of accepting WebSocket connections.
 * @param {HttpServer} httpServer The Http Server to listen and handle
 *     WebSocket upgrade requests on.
 * @constructor
 */
function WebSocketServer(httpServer) {
  events.EventSource.apply(this);
  httpServer.addEventListener('upgrade', this.upgradeToWebSocket_.bind(this));
}

WebSocketServer.prototype = {
  __proto__: events.EventSource.prototype,

  upgradeToWebSocket_: function(request) {
    if (request.headers['Upgrade'] != 'websocket' ||
        !request.headers['Sec-WebSocket-Key']) {
      return false;
    }

    console.log("WebSocketServer Upgrade");

    if (this.dispatchEvent('request', new WebSocketRequest(request))) {
      if (request.socketId_)
        request.reject();
      return true;
    }

    return false;
  }
};

/**
 * Constructs a WebSocket request object from an Http request. This invalidates
 * the Http request's socket and offers accept and reject methods for accepting
 * and rejecting the WebSocket upgrade request.
 * @param {HttpRequest} httpRequest The HTTP request to upgrade.
 */
function WebSocketRequest(httpRequest) {
  // We'll assume control of the socket for this request.
  http.HttpRequest.apply(this, [httpRequest.headers, httpRequest.socketId_]);
  httpRequest.socketId_ = 0;
}

WebSocketRequest.prototype = {
  __proto__: http.HttpRequest.prototype,

  /**
   * Accepts the WebSocket request.
   * @return {WebSocketServerSocket} The websocket for the accepted request.
   */
  accept: function() {
    // Construct WebSocket response key.
    var clientKey = this.headers['Sec-WebSocket-Key'];
    var toArray = function(str) {
      var a = [];
      for (var i = 0; i < str.length; i++) {
        a.push(str.charCodeAt(i));
      }
      return a;
    }
    var toString = function(a) {
      var str = '';
      for (var i = 0; i < a.length; i++) {
        str += String.fromCharCode(a[i]);
      }
      return str;
    }

    // Magic string used for websocket connection key hashing:
    // http://en.wikipedia.org/wiki/WebSocket
    var magicStr = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

    // clientKey is base64 encoded key.
    clientKey += magicStr;
    var sha1 = new Sha1();
    sha1.reset();
    sha1.update(toArray(clientKey));
    var responseKey = btoa(toString(sha1.digest()));
    var responseHeader = {
      'Upgrade': 'websocket',
      'Connection': 'Upgrade',
      'Sec-WebSocket-Accept': responseKey};
    if (this.headers['Sec-WebSocket-Protocol'])
      responseHeader['Sec-WebSocket-Protocol'] = this.headers['Sec-WebSocket-Protocol'];
    this.writeHead(101, responseHeader);
    var socket = new WebSocketServerSocket(this.socketId_);
    // Detach the socket so that we don't use it anymore.
    this.socketId_ = 0;
    return socket;
  },

  /**
   * Rejects the WebSocket request, closing the connection.
   */
  reject: function() {
    this.close();
  }
}

/**
 * Constructs a WebSocketServerSocket using the given socketId. This should be
 * a socket which has already been upgraded from an Http request.
 * @param {number} socketId The socket id with an active websocket connection.
 */
function WebSocketServerSocket(socketId) {
  this.socketId_ = socketId;
  EventSource.apply(this);
  this.readFromSocket_();
}

WebSocketServerSocket.prototype = {
  __proto__: EventSource.prototype,

  /**
   * Send |data| on the WebSocket.
   * @param {string} data The data to send over the WebSocket.
   */
  send: function(data) {
    this.sendFrame_(1, data);
  },

  /**
   * Begin closing the WebSocket. Note that the WebSocket protocol uses a
   * handshake to close the connection, so this call will begin the closing
   * process.
   */
  close: function() {
    this.sendFrame_(8);
    this.readyState = 2;
  },

  readFromSocket_: function() {
    var t = this;
    var data = [];
    var message = '';
    var fragmentedOp = 0;
    var fragmentedMessage = '';

    var onDataRead = function(readInfo) {
      if (readInfo.resultCode <= 0) {
        t.close_();
        return;
      }
      if (!readInfo.data.byteLength) {
        socket.read(t.socketId_, onDataRead);
        return;
      }

      var a = new Uint8Array(readInfo.data);
      for (var i = 0; i < a.length; i++)
        data.push(a[i]);

      while (data.length) {
        var length_code = -1;
        var data_start = 6;
        var mask;
        var fin = (data[0] & 128) >> 7;
        var op = data[0] & 15;

        if (data.length > 1)
          length_code = data[1] & 127;
        if (length_code > 125) {
          if ((length_code == 126 && data.length > 7) ||
              (length_code == 127 && data.length > 14)) {
            if (length_code == 126) {
              length_code = data[2] * 256 + data[3];
              mask = data.slice(4, 8);
              data_start = 8;
            } else if (length_code == 127) {
              length_code = 0;
              for (var i = 0; i < 8; i++) {
                length_code = length_code * 256 + data[2 + i];
              }
              mask = data.slice(10, 14);
              data_start = 14;
            }
          } else {
            length_code = -1; // Insufficient data to compute length
          }
        } else {
          if (data.length > 5)
            mask = data.slice(2, 6);
        }

        if (length_code > -1 && data.length >= data_start + length_code) {
          var decoded = data.slice(data_start, data_start + length_code).map(function(byte, index) {
            return byte ^ mask[index % 4];
          });
          data = data.slice(data_start + length_code);
          if (fin && op > 0) {
            // Unfragmented message.
            if (!t.onFrame_(op, arrayBufferToString(decoded)))
              return;
          } else {
            // Fragmented message.
            fragmentedOp = fragmentedOp || op;
            fragmentedMessage += arrayBufferToString(decoded);
            if (fin) {
              if (!t.onFrame_(fragmentedOp, fragmentedMessage))
                return;
              fragmentedOp = 0;
              fragmentedMessage = '';
            }
          }
        } else {
          break; // Insufficient data, wait for more.
        }
      }
      socket.read(t.socketId_, onDataRead);
    };
    socket.read(this.socketId_, onDataRead);
  },

  onFrame_: function(op, data) {
    if (op == 1) {
      this.dispatchEvent('message', {'data': data});
    } else if (op == 8) {
      // A close message must be confirmed before the websocket is closed.
      if (this.readyState == 1) {
        this.sendFrame_(8);
      } else {
        this.close_();
        return false;
      }
    }
    return true;
  },

  sendFrame_: function(op, data) {
    var t = this;
    var WebsocketFrameString = function(op, str) {
      var length = str.length;
      if (str.length > 65535)
        length += 10;
      else if (str.length > 125)
        length += 4;
      else
        length += 2;
      var lengthBytes = 0;
      var buffer = new ArrayBuffer(length);
      var bv = new Uint8Array(buffer);
      bv[0] = 128 | (op & 15); // Fin and type text.
      bv[1] = str.length > 65535 ? 127 :
              (str.length > 125 ? 126 : str.length);
      if (str.length > 65535)
        lengthBytes = 8;
      else if (str.length > 125)
        lengthBytes = 2;
      var len = str.length;
      for (var i = lengthBytes - 1; i >= 0; i--) {
        bv[2 + i] = len & 255;
        len = len >> 8;
      }
      var dataStart = lengthBytes + 2;
      for (var i = 0; i < str.length; i++) {
        bv[dataStart + i] = str.charCodeAt(i);
      }
      return buffer;
    }

    var array = WebsocketFrameString(op, data || '');
    socket.write(this.socketId_, array, function(writeInfo) {
      if (writeInfo.resultCode < 0 ||
          writeInfo.bytesWritten !== array.byteLength) {
        t.close_();
      }
    });
  },

  close_: function() {
    chrome.socket.disconnect(this.socketId_);
    chrome.socket.destroy(this.socketId_);
    this.readyState = 3;
    this.dispatchEvent('close');
  }
};

return {
  'Server': WebSocketServer,
};
}();