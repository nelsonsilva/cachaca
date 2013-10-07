server = require("./server.coffee")

server.run()

console.debug server.apps()

for k, app of server.apps()
    
    app.on "show", ({app, url}) -> 
        console.log "[#{app}] show #{url}"
        $('#idle_container').fadeOut('slow')
        $('#cast').attr('src', url)

    app.on "close", ({app}) -> 
        $('#idle_container').fadeIn('slow')
        $('#cast').attr('src', '')

$(document).ready ->
    $('#idle_container').fadeIn('slow')