import ballerina/http;
import ballerina/lang.runtime;
import commons/service_commons;

# An event on a service's SSE stream.
public type StreamEvent record {|
    # Replay point, sent back by the client as `Last-Event-ID`
    string id;
    # SSE event name, e.g. `notification.created`
    string event;
    # Event payload
    json data;
|};

# Tuning for a hub's streams.
public type HubConfig record {|
    # How often an idle stream checks for events, in seconds
    decimal pollInterval = 0.2;
    # Comment sent on an idle stream to keep proxies from closing it, in seconds
    decimal heartbeatInterval = 15;
    # A stream not polled for this long is treated as disconnected, in seconds
    decimal staleAfter = 60;
    # Events buffered per stream; the oldest are dropped beyond this
    int maxQueued = 1000;
|};

# In-process fan-out of events to open SSE streams. Events and streams are matched by target keys,
# e.g. `user:alice` or `role:Finance`: a stream receives an event when they share a key.
# Streams on other nodes see nothing; clients recover missed events through replay.
public isolated class Hub {
    private final HubConfig & readonly config;
    private final map<Subscription> subscriptions = {};

    # Creates a hub.
    #
    # + config - Stream tuning
    public isolated function init(HubConfig config = {}) {
        self.config = config.cloneReadOnly();
    }

    # Opens a stream for a set of target keys.
    #
    # + targets - Keys the stream listens on
    # + backlog - Events to send first, e.g. those replayed after `Last-Event-ID`
    # + return - The stream, to return from an HTTP resource
    public isolated function open(string[] targets, StreamEvent[] backlog = []) returns stream<http:SseEvent, error?> {
        Subscription subscription = new (service_commons:newId(), targets, self.config);
        lock {
            self.subscriptions[subscription.id] = subscription;
        }
        EventIterator iterator = new (subscription, backlog, self.config);
        return new (iterator);
    }

    # Sends an event to every open stream that shares one of its target keys.
    #
    # + event - The event
    # + targets - Keys the event is addressed to
    public isolated function publish(StreamEvent event, string[] targets) {
        StreamEvent & readonly frozen = event.cloneReadOnly();
        string[] & readonly keys = targets.cloneReadOnly();
        lock {
            string[] stale = [];
            foreach Subscription subscription in self.subscriptions {
                if subscription.isStale() {
                    stale.push(subscription.id);
                } else if subscription.matches(keys) {
                    subscription.enqueue(frozen);
                }
            }
            foreach string id in stale {
                _ = self.subscriptions.remove(id);
            }
        }
    }

    # Number of open streams.
    #
    # + return - The count
    public isolated function size() returns int {
        lock {
            return self.subscriptions.length();
        }
    }
}

isolated class Subscription {
    final string id;
    private final string[] & readonly targets;
    private final HubConfig & readonly config;
    private final StreamEvent[] queue = [];
    private int lastPolled;
    private boolean closed = false;

    isolated function init(string id, string[] targets, HubConfig & readonly config) {
        self.id = id;
        self.targets = targets.cloneReadOnly();
        self.config = config;
        self.lastPolled = service_commons:nowMillis();
    }

    isolated function matches(readonly & string[] keys) returns boolean {
        foreach string key in keys {
            if self.targets.indexOf(key) != () {
                return true;
            }
        }
        return false;
    }

    isolated function enqueue(StreamEvent & readonly event) {
        lock {
            if self.queue.length() >= self.config.maxQueued {
                _ = self.queue.shift();
            }
            self.queue.push(event);
        }
    }

    isolated function poll() returns (StreamEvent & readonly)? {
        lock {
            self.lastPolled = service_commons:nowMillis();
            if self.queue.length() == 0 {
                return ();
            }
            return self.queue.shift().cloneReadOnly();
        }
    }

    isolated function close() {
        lock {
            self.closed = true;
        }
    }

    isolated function isClosed() returns boolean {
        lock {
            return self.closed;
        }
    }

    isolated function isStale() returns boolean {
        lock {
            return self.closed || service_commons:nowMillis() - self.lastPolled > <int>(self.config.staleAfter * 1000);
        }
    }
}

isolated class EventIterator {
    private final Subscription subscription;
    private final HubConfig & readonly config;
    private final StreamEvent[] backlog;
    private final map<boolean> sent = {};
    private boolean opened = false;

    isolated function init(Subscription subscription, StreamEvent[] backlog, HubConfig & readonly config) {
        self.subscription = subscription;
        self.config = config;
        self.backlog = backlog.clone();
    }

    public isolated function next() returns record {|http:SseEvent value;|}|error? {
        lock {
            // The response headers go out with the first event, so one is sent at once.
            if !self.opened {
                self.opened = true;
                return {value: {comment: "connected"}};
            }
            if self.backlog.length() > 0 {
                StreamEvent event = self.backlog.shift();
                self.sent[event.id] = true;
                return {value: toSse(event).cloneReadOnly()};
            }
        }
        int idleMillis = 0;
        int heartbeatMillis = <int>(self.config.heartbeatInterval * 1000);
        while !self.subscription.isClosed() {
            (StreamEvent & readonly)? event = self.subscription.poll();
            if event is StreamEvent & readonly {
                lock {
                    // Skips live events already sent as backlog.
                    if self.sent.removeIfHasKey(event.id) is boolean {
                        continue;
                    }
                }
                return {value: toSse(event)};
            }
            if idleMillis >= heartbeatMillis {
                return {value: {comment: "keepalive"}};
            }
            runtime:sleep(self.config.pollInterval);
            idleMillis += <int>(self.config.pollInterval * 1000);
        }
        return ();
    }

    public isolated function close() returns error? {
        self.subscription.close();
    }
}

isolated function toSse(StreamEvent event) returns http:SseEvent =>
    {id: event.id, event: event.event, data: event.data.toJsonString()};
