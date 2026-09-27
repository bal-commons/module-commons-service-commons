import ballerina/http;
import ballerina/test;
import ballerinax/h2.driver as _;
import ballerinax/java.jdbc;
import commons/service_commons.db as sdb;

const SECRET = "s3cret";
const RECEIVER = "http://localhost:19301/hook";

isolated WebhookEvent[] received = [];

service /hook on new http:Listener(19301) {
    resource function post ok(http:Request req) returns http:Accepted|http:Unauthorized {
        WebhookEvent|error event = verify(req, SECRET);
        if event is error {
            return http:UNAUTHORIZED;
        }
        lock {
            received.push(event.clone());
        }
        return http:ACCEPTED;
    }

    resource function post broken() returns http:InternalServerError => http:INTERNAL_SERVER_ERROR;
}

function receivedEvents() returns WebhookEvent[] {
    lock {
        WebhookEvent[] & readonly events = received.cloneReadOnly();
        received.removeAll();
        return events;
    }
}

function newWebhooks(string name, DispatcherConfig config = {}) returns [Webhooks, jdbc:Client]|error {
    jdbc:Client db = check sdb:connect({url: string `jdbc:h2:mem:${name};DB_CLOSE_DELAY=-1`});
    Webhooks webhooks = check new (db, sdb:H2, "test", "w_", config);
    check webhooks.migrate();
    return [webhooks, db];
}

@test:Config
function registerListUpsertRemove() returns error? {
    [Webhooks, jdbc:Client] [webhooks, _] = check newWebhooks("registry");
    CreatedSubscription created = check webhooks.register({participantId: "agent:a", url: RECEIVER + "/ok"});
    test:assertEquals(created.secret.length(), 64);
    Subscription configured = check webhooks.upsert({participantId: "agent:b", url: RECEIVER + "/ok", secret: SECRET});
    Subscription again = check webhooks.upsert({participantId: "agent:b", url: RECEIVER + "/ok", secret: SECRET,
        events: ["message.created"]});
    test:assertEquals(again.id, configured.id);
    test:assertEquals(again.events, ["message.created"]);
    test:assertEquals((check webhooks.list()).length(), 2);
    test:assertEquals((check webhooks.list("agent:b")).map(s => s.id), [configured.id]);
    test:assertTrue(check webhooks.remove(created.id));
    test:assertEquals(check webhooks.get(created.id), ());
}

@test:Config
function deliversSignedEventsToMatchingSubscriptions() returns error? {
    _ = receivedEvents();
    [Webhooks, jdbc:Client] [webhooks, _] = check newWebhooks("deliver");
    Subscription agent = check webhooks.upsert({participantId: "agent:triage", url: RECEIVER + "/ok", secret: SECRET,
        events: ["message.created"]});
    _ = check webhooks.upsert({participantId: "agent:other", url: RECEIVER + "/ok", secret: SECRET});

    test:assertEquals(check webhooks.enqueue("message.created", ["agent:triage", "tara"], {seq: 1}, "case-1"), 1);
    test:assertEquals(check webhooks.enqueue("conversation.closed", ["agent:triage"], {}), 0, "event not subscribed");
    test:assertEquals(check webhooks.deliverDue(), 1);

    WebhookEvent[] events = receivedEvents();
    test:assertEquals(events.length(), 1);
    test:assertEquals(events[0].event, "message.created");
    test:assertEquals(events[0].recipientId, "agent:triage");
    test:assertEquals(events[0]?.correlationId, "case-1");
    test:assertEquals(events[0].data, {seq: 1});
    Delivery[] deliveries = check webhooks.deliveries(agent.id);
    test:assertEquals(deliveries[0].status, DELIVERED);
    test:assertEquals(check webhooks.deliverDue(), 0, "delivered events are not sent again");
}

@test:Config
function failedDeliveriesRetryThenFail() returns error? {
    [Webhooks, jdbc:Client] [webhooks, _] = check newWebhooks("retry", {maxAttempts: 2, initialBackoff: 0});
    Subscription broken = check webhooks.upsert({participantId: "agent:x", url: RECEIVER + "/broken", secret: SECRET});
    _ = check webhooks.enqueue("message.created", ["agent:x"], {});
    _ = check webhooks.deliverDue();
    Delivery first = (check webhooks.deliveries(broken.id))[0];
    test:assertEquals(first.status, PENDING);
    test:assertEquals(first.attempts, 1);
    test:assertEquals(first?.lastError, "Receiver answered HTTP 500");
    _ = check webhooks.deliverDue();
    Delivery last = (check webhooks.deliveries(broken.id))[0];
    test:assertEquals(last.status, FAILED);
    test:assertEquals(last.attempts, 2);
}

@test:Config
function enqueueJoinsTheCallersTransaction() returns error? {
    [Webhooks, jdbc:Client] [webhooks, db] = check newWebhooks("tx");
    Subscription agent = check webhooks.upsert({participantId: "agent:t", url: RECEIVER + "/ok", secret: SECRET});
    do {
        transaction {
            _ = check webhooks.enqueue("message.created", ["agent:t"], {});
            boolean rejected = true;
            if rejected {
                fail error("change rejected");
            }
            check commit;
        }
    } on fail {
    }
    test:assertEquals((check webhooks.deliveries(agent.id)).length(), 0);
    transaction {
        _ = check webhooks.enqueue("message.created", ["agent:t"], {});
        check commit;
    }
    test:assertEquals((check webhooks.deliveries(agent.id)).length(), 1);
    _ = db;
}

@test:Config
function verifyRejectsTamperingAndReplays() returns error? {
    byte[] body = "{}".toBytes();
    string now = (time() / 1000).toString();
    http:Request good = signed(body, now, check sign(SECRET, now, body));
    test:assertTrue(verify(good, SECRET) is error, "{} is not a WebhookEvent");

    http:Request tampered = signed("{\"x\":1}".toBytes(), now, check sign(SECRET, now, body));
    test:assertEquals((<error>verify(tampered, SECRET)).message(), "Webhook signature does not match");
    string old = (time() / 1000 - 3600).toString();
    http:Request replayed = signed(body, old, check sign(SECRET, old, body));
    test:assertEquals((<error>verify(replayed, SECRET)).message(), "Webhook timestamp is outside the tolerance");
}

function signed(byte[] body, string timestamp, string signature) returns http:Request {
    http:Request req = new;
    req.setBinaryPayload(body, "application/json");
    req.setHeader(HEADER_TIMESTAMP, timestamp);
    req.setHeader(HEADER_SIGNATURE, signature);
    return req;
}
