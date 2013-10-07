{EventEmitter} = require('events')
http = require '../js/http.js'

class RouteMatcher
  
  constructor: ->
    @BINDINGS = {}
    @re = new RegExp(":([A-Za-z][A-Za-z0-9_]*)", "g")

  get: (pattern, handler) -> @addPattern pattern, handler, 'GET'
  post: (pattern, handler) -> @addPattern pattern, handler, 'POST'
  put: (pattern, handler) -> @addPattern pattern, handler, 'PUT'
  delete: (pattern, handler) -> @addPattern pattern, handler, 'DELETE'

  addPattern: (input, handler, method) ->
    # We need to search for any :<token name> tokens in the String and replace them with named capture groups
    console.log "Adding pattern #{method} #{input}"
    
    sb = input;
    groups = []
    while m = @re.exec(input)
      group = m[1]
      if groups.indexOf(group) != -1
        throw new IllegalArgumentException("Cannot use identifier " + group + " more than once in pattern string");
      
      # TODO - support groups with the same prefix!
      sb = sb.replace(":#{group}", "([^\\/]+)")
      groups.push group

    binding = {
      pattern: new RegExp(sb), 
      paramNames: groups,
      handler: handler
    }

    @BINDINGS[method] ||= []
    @BINDINGS[method].push binding

  noMatch: (@noMatchHandler) ->

  handle: (request) =>
    
    bindings = @BINDINGS[request.method] || []

    url = request.headers.url

    console.log ">>> #{request.method} #{url}"
    for binding in bindings
      m = binding.pattern.exec(url);

      if m?
        params = {};
        if binding.paramNames? 
          i = 1
          # Named param
          for param in binding.paramNames
            params[param] = m[i++]
          
        else
          # Un-named params
          for i in [0..m.length]
            params["param#{i}"] = m[i + 1]
  
        request.params = params
        binding.handler(request);
        return
    
    return noMatchHandler(request) if noMatchHandler?

    # Default 404
    request.response.statusCode = 404
    request.response.end()

class HttpResponse

  constructor: (@request) ->
    @statusCode = 200
    @headers = {}

  putHeader: (k, v) ->
    @headers[k] = v

  end: (data) ->
    @request.headers['Connection'] = null # unless data?
    if data?
      length = data.byteLength 
      length ||= 0
      #@putHeader 'Content-Length', length
    @request.writeHead(@statusCode, @headers)
    @request.end(data)

class App extends EventEmitter

  constructor: ->
    @stack = []
    @route = '/'

    @server = new http.Server()

    @routeMatcher = new RouteMatcher()

    @routeMatcher.noMatch @handle

    @server.addEventListener "request", (request) =>
      # setup the response object
      request.response = new HttpResponse(request)
      @routeMatcher.handle request
      # true

  use: (route, fn) ->

    pos = @stack.length - 1

    # default route to '/'
    if ('string' != typeof route)
      fn = route
      route = ''

    # Check for routes
    if fn.routes?
      base = route
      for route in fn.routes
        do =>
          {method, path, handler} = route
          # Add the route
          @routeMatcher[method] "#{base}#{path}",
            # Wrap the handler
            (req) =>
              
              # Add the handler to the stack
              @stack.splice(pos,0, { route: req.headers.url, handler: handler})
              # setup the response object
              req.response = new HttpResponse(req)
              @handle(req)
              @stack.splice(pos,1) # Remove it from the stack

      return @

    # wrap sub-apps
    if ('function' == typeof fn.handle)
      server = fn
      fn.route = route
      fn = (req, res, next) ->
        server.handle(req, res, next)

    # normalize route to not trail with slash
    if ('/' == route[route.length - 1])
      route = route.substr(0, route.length - 1);

    @stack.push { route: route, handler: fn }
    @

  listen: (port, host = '0.0.0.0') ->
    @server.listen port, host

  handle: (req) =>
    stack = @stack
    removed = ''
    index = 0

    res = req.response

    next = (err) ->
      req.url = removed + req.headers.url
      req.originalUrl = req.originalUrl or req.url
      removed = ""
      layer = stack[index++]

      unless layer?
        if err
          msg = err.toString()
          res.statusCode = 500
          res.putHeader "Content-Type", "text/plain"
          res.end msg
        else
          res.statusCode = 404
          res.putHeader "Content-Type", "text/plain"
          res.end "Cannot " + req.method + " " + req.url

        console.log "No layer found to handle the request"
        return

      try
        path = req.url
        path = "/"  unless path?

        console.log "#{path} == #{layer.route}"
        return next(err)  unless 0 is path.indexOf(layer.route)

        c = path[layer.route.length]

        return next(err)  if c and "/" isnt c and "." isnt c
        removed = layer.route

        # Refactor to use url.parse
        req.url = {pathname: req.url.substr(removed.length)}
        req.url.pathname = "/" + req.url.pathname  unless "/" is req.url.pathname[0]

        res.writeHead = (@statusCode, headers) ->  @putAllHeaders headers

        layer.handler req, res, next

      catch e
          console.error "Exception #{e}"
          next e

    stack = @stack
    removed = ""
    index = 0
    next()

connect = ->
  #app(req, res) -> app.handle(req, res)
  app = new App
  app.use argument for argument in arguments
  app

connect.static = (path) ->
   (req, res, next) ->
      file = path
      if req.url.pathname is '/'
        file += '/index.html'
      else if (req.url.pathname.indexOf('..') == -1)
        file += req.url.pathname

      vertx.fileSystem.exists file, (err, res) ->
        return next() unless res
        req.response.sendFile(file)


connect.logger = (options) ->
  fmt =  (req, res) ->
    remoteAddr = ""
    httpVersion = "1.1"
    date = new Date
    method = req.method
    url = req.uri
    referer = req.headers()["Referer"] || ""
    userAgent = req.headers()["User-Agent"]  || ""
    status = res.statusCode
    contentLength = "--" #res.length()
    responseTime = date - req._startTime

    "#{remoteAddr} - [#{date}] '#{method} #{url} HTTP/#{httpVersion}' #{status} #{contentLength} - #{responseTime} ms '#{referer}' '#{userAgent}'"

  (req, res, next) ->
    req._startTime = new Date;

    # mount safety
    return next() if (req._logging)

    # flag as logging
    req._logging = true;

    # immediate
    end = res.end;
    res.end = (chunk, encoding) ->
        res.end = end;
        res.end(chunk, encoding);
        line = fmt(req, res);
        return unless line?
        console.log line + '\n'

    next();

connect.router = (fn) ->
    app =
      routes: []

    methods = ["get", "post", "delete", "put"]
    for method in methods
      do (method) ->
        app[method] = (path, handler) ->
          app.routes.push {method: method, path: path, handler: handler}

    fn app
    app


connect.favicon = (path, options) ->
  options ?= {}
  path ?=  __dirname + '/../public/favicon.ico'
  maxAge = options.maxAge || 86400000;

  (req, res, next) ->
    return next() if ('/favicon.ico' != req.url)
    vertx.fileSystem.exists path, (err, res) ->
      return next() unless res
      req.response.sendFile(path)


module.exports = connect