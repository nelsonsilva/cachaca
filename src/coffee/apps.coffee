querystring = require 'querystring'
connect = require 'connect'
events = require 'events'
templates = require './templates.coffee'

class App extends events.EventEmitter
    constructor: (@addr, name, url, protocols) ->
        super
        @config =
            name: name
            state: "stopped"
            link: ""
            connectionSvcURL: ""
            app_url: ""
            url: url
            protocols: protocols

        @receivers = []
        @remotes = []
        @messageQueue = []

    getName: -> @config.name

    registerSession: (connection) ->
        connection.on 'message', (message)  =>

            if @receivers.length == 0
                console.log("buffering msg for receiver");
                @messageQueue << message.data
            else
                console.log("relaying msg to receiver");
                @receivers[0].send(message.data)

            if message.data.indexOf('ping') == -1 and message.data.indexOf('pong') == -1
                console.log("-->to receiver: "+ message.data)

        connection.on 'close', (closeReason, description) =>
            i = @remotes.indexOf(connection)    
            @remotes.splice(i,1)
            console.log("Closed SessionChannel")

        console.log("Opened SessionChannel")
        @remotes << connection

    registerReceiver: (connection) ->

        connection.on 'message', (message) =>
            if @remotes.length > 0
                @remotes[0].send(message.data)

            if message.data.indexOf('ping') == -1 && message.data.indexOf('pong') == -1
                console.log("-->to remote: #{message.data}")        

        connection.on 'close', (closeReason, description) =>
            i = @receivers.indexOf(connection)  
            @receivers.splice(i,1);
            console.log("Closed ReceiverChannel");

        console.log("Opened ReceiverChannel")
        @receivers << connection

        while @messageQueue.length > 0
            connection.send @messageQueue.shift()

    getProtocols: ->
        return [] unless @config.state is "running"
        @config.protocols

    getRouter: -> 

        connect.router (app) =>

            app.get "", (req, res) =>
                
                data = templates['app.xml'](
                    name: @config.name
                    connectionSvcURL: @config.connectionSvcURL
                    protocols: @getProtocols()
                    state: @config.state
                    link: @config.link)

                res.putHeader 'Content-Type', 'text/xml'
                #res.putHeader 'Content-Length', data.byteLength
                
                res.putHeader "Access-Control-Allow-Method", "GET, POST, DELETE, OPTIONS"
                res.putHeader "Access-Control-Expose-Headers", "Location"
                res.putHeader "Cache-control", "no-cache, must-revalidate, no-store"
                res.end data
            
            app.delete "", (req, res) =>
                @config.state = "stopped";
                @config.link = "";
                @config.connectionSvcURL = "";

                data = templates['app.xml'](
                    name: @config.name
                    connectionSvcURL: @config.connectionSvcURL
                    protocols: @getProtocols()
                    state: @config.state
                    link: @config.link)


                @emit "close", {app: @config.name}

                res.putHeader 'Content-Type', 'text/xml'
                res.putHeader "Access-Control-Allow-Method", "GET, POST, DELETE, OPTIONS"
                res.putHeader "Access-Control-Expose-Headers", "Location"
                res.putHeader "Cache-control", "no-cache, must-revalidate, no-store"
                res.end data

            app.post "", (req, res) =>
                @config.state = "running";
                @config.link = "<link rel='run' href='web-1'/>";
                @config.connectionSvcURL = "http://#{@addr}:8008/connection/#{@config.name}"

                @emit "show", {app: @config.name, url: @config.url(req.body) }

                res.putHeader "Location", "http://#{@addr}:8008/apps/#{@config.name}/web-1"
                res.statusCode = 201
                res.end('\n\n')

class Apps
    
    constructor: ->
        @registered = {}

    setup: (server, addr) ->
        
        registerApp = (name, url) =>
            protocols = ["ramp"]
            app = new App addr, name, url, protocols
            @registered[name] = app
            server.use "/apps/#{name}", app.getRouter()
            console.log "Registered App: #{name}"

        registerApp "ChromeCast", (v) -> "https://www.gstatic.com/cv/receiver.html?#{v}"
        registerApp "YouTube", (v) -> "https://www.youtube.com/tv?#{v}"
        registerApp "PlayMovies", (v) -> "https://play.google.com/video/avi/eureka?#{v}"
        registerApp "GoogleMusic", -> "https://jmt17.google.com/sjdev/cast/player"
        registerApp "GoogleCastSampleApp", -> "http://anzymrcvr.appspot.com/receiver/anzymrcvr.html"
        registerApp "GoogleCastPlayer", -> "https://www.gstatic.com/eureka/html/gcp.html"
        registerApp "Fling", (v) -> "#{v}"
        registerApp "TicTacToe", -> "http://www.gstatic.com/eureka/sample/tictactoe/tictactoe.html"

module.exports = new Apps()