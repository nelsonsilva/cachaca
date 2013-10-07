ws = require '../js/ws.js'
dgram = require "dgram" # load our custom dgram version
ssdp = require "peer-ssdp"
querystring = require 'querystring'
uuid = require 'node-uuid'
templates = require './templates.coffee'

# PUT YOUR EXTERNAL IP HERE
ADDRESS = '192.168.1.1'

# override some "os" methods
require("os").networkInterfaces = -> [[{family: 'IPv4', address: ADDRESS}]]


peer = ssdp.createPeer()
myUuid = uuid.v4()

# Listen for HTTP connections.
connect = require 'connect'
app = connect()

wsServer = new ws.Server(app.server)

# A list of connected websockets.
connectedSockets = []
wsServer.addEventListener "request", (req) =>
    console.log "Client connected"

    sessionRegex = new RegExp('^/session/.*$')

    if req.url is'/stage'
        global.stageConnection = req.accept()

        global.stageConnection.send(JSON.stringify({
            cmd: "idle"
        }));
    
    else if req.url is '/system/control'
        socket = req.accept()
        console.log("system/control")
        # ...
    else if req.url is '/connection'

        sockect = req.accept()

        socket.addEventListener "message", (e) ->
            cmd = JSON.parse(e.data)
            if cmd.type is "REGISTER"
                name = cmd.name;
                connection.send(JSON.stringify({
                    type: "CHANNELREQUEST",
                    "senderId": 1,
                    "requestId": 1
                }))

                wsServer.addEventListener "request", (req) ->
                    if req.url is "/receiver/#{cmd.name}"
                        receiverConnection = request.accept()    
                        appName = request.resourceURL.pathname.replace('/receiver/','').replace('Dev','')
                        Apps.registered[appName].registerReceiver(receiverConnection)
                

            else if cmd.type is "CHANNELRESPONSE"
                connection.send(JSON.stringify({
                    type: "NEWCHANNEL",
                    "senderId": 1,
                    "requestId": 1,
                    "URL": "ws://localhost:8008/receiver/#{name}"
                }))

    if sessionRegex.matches req.url
        sessionConn = req.accept()   
        console.log("Session up")

        appName = request.resourceURL.pathname.replace('/session/','');
        sessionId = request.resourceURL.search.replace('?','');

        targetApp = Apps.registered[appName];

        targetApp.registerSession(sessionConn) if targetApp?
            

Apps = require('./apps.coffee');

setupRouter = -> app.use connect.router (app) ->
    app.get "/ssdp/device-desc.xml", (req, res) ->
        console.log "/ssdp/device-desc.xml"

        data = templates['device-desc.xml'](uuid: myUuid, base: "http://#{req.headers.Host}:8008")

        res.putHeader 'Content-Type', 'text/xml'
        res.putHeader 'Content-Length', data.byteLength
        res.putHeader "Access-Control-Allow-Method", "GET, POST, DELETE, OPTIONS"
        res.putHeader "Access-Control-Allow-Method", "GET, POST, DELETE, OPTIONS"
        res.putHeader "Access-Control-Expose-Headers", "Location"
        res.putHeader "Application-Url", "http://#{req.headers.Host}:8008/apps"
        res.end data

    app.post "/connection/:app", (req, res) ->
        console.log("Connecting App "+ req.params.app);

        res.putHeader "Access-Control-Allow-Method", "POST, OPTIONS"
        res.putHeader "Access-Control-Allow-Headers", "Content-Type"

        json = JSON.stringify({
            URL: "ws://#{req.headers.Host}:8008/session/#{req.params.app}?1",
            pingInterval: 3
        })

        res.putHeader 'Content-Type', 'application/json'
        res.putHeader 'Content-Length', json.byteLength

        res.end(json)

    app.get '/apps', (req, res) ->
        for key, app of Apps.registered
            if app.config.state is "running"
                console.log "Redirecting to #{key}"
                res.statusCode = 303
                res.putHeader "Location", "http://#{req.headers.Host}:8008/apps/#{key}"
                res.end()
                return;

        res.putHeader("Access-Control-Allow-Method", "GET, POST, DELETE, OPTIONS");
        res.putHeader("Access-Control-Expose-Headers", "Location");
        res.putHeader("Content-Length", "0");
        res.putHeader("Content-Type", "text/html; charset=UTF-8");
        res.statusCode = 204

        res.end()


setupSSDP = (addr) ->
    peer.on "ready", -> console.log("ready")

    peer.on "error", -> console.log("SSDP error:" + e)

    peer.on "notify", (headers, address) -> console.log("notify")

    peer.on "search", (headers, address) ->

        console.debug "search from", address

        if headers.ST.indexOf("dial-multiscreen-org:service:dial:1") != -1
            peer.reply({
                LOCATION: "http://#{addr}:8008/ssdp/device-desc.xml",
                ST: "urn:dial-multiscreen-org:service:dial:1",
                "CONFIGID.UPNP.ORG": 7337,
                "BOOTID.UPNP.ORG": 7337,
                USN: "uuid:#{myUuid}"
            }, address)

    console.log "Starting peer-ssdp"
    peer.start()

module.exports = {

    run: ->

        Apps.setup app, ADDRESS

        setupRouter()
        setupSSDP(ADDRESS)

        app.listen 8008, ADDRESS

    apps: ->
        Apps.registered
}