import ballerina/http;
import ballerina/test;

function nextData(stream<http:SseEvent, error?> events) returns http:SseEvent|error {
    while true {
        record {|http:SseEvent value;|}? next = check events.next();
        if next is () {
            return error("stream ended");
        }
        if next.value.comment != "connected" {
            return next.value;
        }
    }
}

@test:Config
function publishReachesMatchingStreamsOnly() returns error? {
    Hub hub = new ({heartbeatInterval: 5});
    stream<http:SseEvent, error?> tara = hub.open(["user:tara", "role:Tenant"]);
    stream<http:SseEvent, error?> carlos = hub.open(["user:carlos"]);
    hub.publish({id: "1", event: "notification.created", data: {title: "hi"}}, ["role:Tenant"]);
    hub.publish({id: "2", event: "notification.created", data: {title: "yo"}}, ["user:carlos"]);
    test:assertEquals(check nextData(tara), {id: "1", event: "notification.created", data: "{\"title\":\"hi\"}"});
    test:assertEquals((check nextData(carlos)).id, "2");
    check tara.close();
    check carlos.close();
}

@test:Config
function backlogFirstAndNotRepeated() returns error? {
    Hub hub = new ({heartbeatInterval: 5});
    stream<http:SseEvent, error?> events = hub.open(["user:tara"], [{id: "1", event: "e", data: 1}]);
    hub.publish({id: "1", event: "e", data: 1}, ["user:tara"]);
    hub.publish({id: "2", event: "e", data: 2}, ["user:tara"]);
    test:assertEquals((check nextData(events)).id, "1");
    test:assertEquals((check nextData(events)).id, "2");
    check events.close();
}

@test:Config
function idleStreamSendsHeartbeat() returns error? {
    Hub hub = new ({heartbeatInterval: 0.3, pollInterval: 0.1});
    stream<http:SseEvent, error?> events = hub.open(["user:tara"]);
    test:assertEquals(check nextData(events), {comment: "keepalive"});
    check events.close();
}

@test:Config
function closedStreamsArePruned() returns error? {
    Hub hub = new;
    stream<http:SseEvent, error?> events = hub.open(["user:tara"]);
    test:assertEquals(hub.size(), 1);
    check events.close();
    hub.publish({id: "1", event: "e", data: ()}, ["user:tara"]);
    test:assertEquals(hub.size(), 0);
}
