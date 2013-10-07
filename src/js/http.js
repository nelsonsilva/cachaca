/**
 * Copyright (c) 2013 The Chromium Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 **/

events = require('./events.js')

module.exports = function() {

var socket = (chrome.experimental && chrome.experimental.socket) ||
    chrome.socket;

// If this does not have chrome.socket, then return an empty http namespace.
if (!socket)
  return {};

// Http response code strings.
var responseMap = {
  200: 'OK',
  201: 'Created',
  301: 'Moved Permanently',
  304: 'Not Modified',
  400: 'Bad Request',
  401: 'Unauthorized',
  403: 'Forbidden',
  404: 'Not Found',
  413: 'Request Entity Too Large',
  414: 'Request-URI Too Long',
  500: 'Internal Server Error'};

/**
 * Convert from an ArrayBuffer to a string.
 * @param {ArrayBuffer} buffer The array buffer to convert.
 * @return {string} The textual representation of the array.
 */
var arrayBufferToString = function(buffer) {
  return String.fromCharCode.apply(null, new Uint8Array(buffer));
};

/**
 * Convert a string to an ArrayBuffer.
 * @param {string} string The string to convert.
 * @return {ArrayBuffer} An array buffer whose bytes correspond to the string.
 */
var stringToArrayBuffer = function(string) {
  console.log("stringToArrayBuffer " + string);
  var buffer = new ArrayBuffer(string.length); // 2 bytes for each char
  var bufferView = new Uint8Array(buffer);
  for (var i = 0; i < string.length; i++) {
    bufferView[i] = string.charCodeAt(i);
  }
  return buffer;
};

/**
 * HttpServer provides a lightweight Http web server. Currently it only
 * supports GET requests and upgrading to other protocols (i.e. WebSockets).
 * @constructor
 */
function HttpServer() {
  events.EventSource.apply(this);
  this.readyState_ = 0;
}

HttpServer.prototype = {
  __proto__: events.EventSource.prototype,

  /**
   * Listen for connections on |port| using the interface |host|.
   * @param {number} port The port to listen for incoming connections on.
   * @param {string=} opt_host The host interface to listen for connections on.
   *     This will default to 0.0.0.0 if not specified which will listen on
   *     all interfaces.
   */
  listen: function(port, opt_host) {
    var t = this;
    socket.create('tcp', {}, function(socketInfo) {
      t.socketInfo_ = socketInfo;
      socket.listen(t.socketInfo_.socketId, opt_host || '0.0.0.0', port, 50,
                    function(result) {
        console.log("HttpServer listening on " + (opt_host || '0.0.0.0') + ":" + port);
        t.readyState_ = 1;
        t.acceptConnection_(t.socketInfo_.socketId);
      });
    });
  },

  acceptConnection_: function(socketId) {
    var t = this;
    socket.accept(this.socketInfo_.socketId, function(acceptInfo) {
      t.onConnection_(acceptInfo);
      t.acceptConnection_(socketId);
    });
  },

  onConnection_: function(acceptInfo) {
    this.readRequestFromSocket_(acceptInfo.socketId);
  },

  readRequestFromSocket_: function(socketId) {
    var t = this;
    var requestData = '';
    var endIndex = 0;
    var onDataRead = function(readInfo) {

      // Check if connection closed.
      if (readInfo.resultCode <= 0) {
        socket.disconnect(socketId);
        socket.destroy(socketId);
        return;
      }

      requestData += arrayBufferToString(readInfo.data).replace(/\r\n/g, '\n');

      // Check for end of request.
      endIndex = requestData.indexOf('\n\n', endIndex);
      if (endIndex == -1) {
        endIndex = requestData.length - 1;
        socket.read(socketId, onDataRead);
        return;
      }

      var headers = requestData.substring(0, endIndex).split('\n');
      var headerMap = {};
      // headers[0] should be the Request-Line
      var requestLine = headers[0].split(' ');
      headerMap['method'] = requestLine[0];
      headerMap['url'] = requestLine[1];
      headerMap['Http-Version'] = requestLine[2];
      for (var i = 1; i < headers.length; i++) {
        requestLine = headers[i].split(':', 2);
        if (requestLine.length == 2)
          headerMap[requestLine[0]] = requestLine[1].trim();
      }
      var body = requestData.substring(endIndex + 2); // skip over \n\n

      var request = new HttpRequest(headerMap, body, socketId);
      t.onRequest_(request);
    }
    console.log("socketId = " + socketId);
    socket.read(socketId, onDataRead);
  },

  onRequest_: function(request) {
    console.debug("onRequest", request);
    var type = request.headers['Upgrade'] ? 'upgrade' : 'request';
    var keepAlive = request.headers['Connection'] == 'keep-alive';
    console.log("onRequest " + type);
    if (!this.dispatchEvent(type, request)) {
      console.log("closing the socket");
      request.close();
    }
    else if (keepAlive)
      this.readRequestFromSocket_(request.socketId_);
  },
};

// MIME types for common extensions.
var extensionTypes = {
  'css': 'text/css',
  'html': 'text/html',
  'htm': 'text/html',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'js': 'text/javascript',
  'png': 'image/png',
  'svg': 'image/svg+xml',
  'txt': 'text/plain'};

/**
 * Constructs an HttpRequest object which tracks all of the request headers and
 * socket for an active Http request.
 * @param {Object} headers The HTTP request headers.
 * @param {number} socketId The socket Id to use for the response.
 * @constructor
 */
function HttpRequest(headers, body, socketId) {
  this.version = 'HTTP/1.1';
  this.headers = headers;
  this.body = body;
  this.responseHeaders_ = {};
  this.headersSent = false;
  this.socketId_ = socketId;
  this.writes_ = 0;
  this.bytesRemaining = 0;
  this.finished_ = false;
  this.readyState = 1;
  this.method = headers.method;
}

HttpRequest.prototype = {
  __proto__: EventSource.prototype,

  /**
   * Closes the Http request.
   */
  close: function() {

    // The socket for keep alive connections will be re-used by the server.
    // Just stop referencing or using the socket in this HttpRequest.
    if (this.headers['Connection'] != 'keep-alive') {
      socket.disconnect(this.socketId_);
      socket.destroy(this.socketId_);
    }
    this.socketId_ = 0;
    this.readyState = 3;
  },

  /**
   * Write the provided headers as a response to the request.
   * @param {int} responseCode The HTTP status code to respond with.
   * @param {Object} responseHeaders The response headers describing the
   *     response.
   */
  writeHead: function(responseCode, responseHeaders) {
    var headerString = this.version + ' ' + responseCode + ' ' +
        (responseMap[responseCode] || 'Unknown');
    this.responseHeaders_ = responseHeaders;
    if (this.headers['Connection'] == 'keep-alive')
      responseHeaders['Connection'] = 'keep-alive';
    if (!responseHeaders['Content-Length'] && responseHeaders['Connection'] == 'keep-alive')
      responseHeaders['Transfer-Encoding'] = 'chunked';
    for (var i in responseHeaders) {
      headerString += '\r\n' + i + ': ' + responseHeaders[i];
    }
    headerString += '\r\n\r\n';
    this.write_(stringToArrayBuffer(headerString));
  },

  /**
   * Writes data to the response stream.
   * @param {string|ArrayBuffer} data The data to write to the stream.
   */
  write: function(data) {
    if (this.responseHeaders_['Transfer-Encoding'] == 'chunked') {
      var newline = '\r\n';
      var byteLength = (data instanceof ArrayBuffer) ? data.byteLength : data.length;
      var chunkLength = byteLength.toString(16).toUpperCase() + newline;
      var buffer = new ArrayBuffer(chunkLength.length + byteLength + newline.length);
      var bufferView = new Uint8Array(buffer);
      for (var i = 0; i < chunkLength.length; i++)
        bufferView[i] = chunkLength.charCodeAt(i);
      if (data instanceof ArrayBuffer) {
        bufferView.set(new Uint8Array(data), chunkLength.length);
      } else {
        for (var i = 0; i < data.length; i++)
          bufferView[chunkLength.length + i] = data.charCodeAt(i);
      }
      for (var i = 0; i < newline.length; i++)
        bufferView[chunkLength.length + byteLength + i] = newline.charCodeAt(i);
      data = buffer;
    } else if (!(data instanceof ArrayBuffer)) {
      data = stringToArrayBuffer(data);
    }
    this.write_(data);
  },

  /**
   * Finishes the HTTP response writing |data| before closing.
   * @param {string|ArrayBuffer=} opt_data Optional data to write to the stream
   *     before closing it.
   */
  end: function(opt_data) {
    if (opt_data)
      this.write(opt_data);
    if (this.responseHeaders_['Transfer-Encoding'] == 'chunked')
      this.write('');
    this.finished_ = true;
    this.checkFinished_();
  },

  /**
   * Automatically serve the given |url| request.
   * @param {string} url The URL to fetch the file to be served from. This is
   *     retrieved via an XmlHttpRequest and served as the response to the
   *     request.
   */
  serveUrl: function(url) {
    var t = this;
    var xhr = new XMLHttpRequest();
    xhr.onloadend = function() {
      var type = 'text/plain';
      if (this.getResponseHeader('Content-Type')) {
        type = this.getResponseHeader('Content-Type');
      } else if (url.indexOf('.') != -1) {
        var extension = url.substr(url.indexOf('.') + 1);
        type = extensionTypes[extension] || type;
      }
      console.log('Served ' + url);
      var contentLength = this.getResponseHeader('Content-Length');
      if (xhr.status == 200)
        contentLength = (this.response && this.response.byteLength) || 0;
      t.writeHead(this.status, {
        'Content-Type': type,
        'Content-Length': contentLength});
      t.end(this.response);
    };
    xhr.open('GET', url, true);
    xhr.responseType = 'arraybuffer';
    xhr.send();
  },

  write_: function(array) {
    var t = this;
    this.bytesRemaining += array.byteLength;
    socket.write(this.socketId_, array, function(writeInfo) {
      if (writeInfo.bytesWritten < 0) {
        console.error('Error writing to socket, code '+writeInfo.bytesWritten);
        return;
      }

      t.bytesRemaining -= writeInfo.bytesWritten;
      t.checkFinished_();
    });
  },

  checkFinished_: function() {
    if (!this.finished_ || this.bytesRemaining > 0)
      return;
    this.close();
  }
};

return {
  'Server': HttpServer,
  'HttpRequest': HttpRequest
};
}();
