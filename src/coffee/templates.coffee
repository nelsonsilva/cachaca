module.exports =
    'device-desc.xml': ({base, uuid}) ->
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>
        <root xmlns=\"urn:schemas-upnp-org:device-1-0\" xmlns:r=\"urn:restful-tv-org:schemas:upnp-dd\">
            <specVersion>
            <major>1</major>
            <minor>0</minor>
            </specVersion>
            <URLBase>#{base}</URLBase>
            <device>
                <deviceType>urn:schemas-upnp-org:device:dail:1</deviceType>
                <friendlyName>CAChaCa</friendlyName>
                <manufacturer>Google Inc.</manufacturer>
                <modelName>Eureka Dongle</modelName>
                <UDN>uuid:#{uuid}</UDN>
                <serviceList>
                    <service>
                        <serviceType>urn:schemas-upnp-org:service:dail:1</serviceType>
                        <serviceId>urn:upnp-org:serviceId:dail</serviceId>
                        <controlURL>/ssdp/notfound</controlURL>
                        <eventSubURL>/ssdp/notfound</eventSubURL>
                        <SCPDURL>/ssdp/notfound</SCPDURL>
                    </service>
                </serviceList>
            </device>
        </root>"

    'app.xml': ({name, connectionSvcURL, protocols, state, link}) ->
        res = "<?xml version='1.0' encoding='UTF-8'?>
        <service xmlns='urn:dial-multiscreen-org:schemas:dial'>
            <name>#{name}</name>
            <options allowStop='true'/>
            <state>#{state}</state>
            #{link}"
            
        if state is "running"
            res += "<servicedata xmlns='urn:chrome.google.com:cast'>
                <connectionSvcURL>#{connectionSvcURL}</connectionSvcURL>
                <protocols>#{"<protocol>#{p}</protocol>" for p in protocols}</protocols>
            </servicedata>
            <activity-status xmlns='urn:chrome.google.com:cast'>
                <description>#{name} Receiver</description>
            </activity-status>"
            
            
        res + "</service>"
