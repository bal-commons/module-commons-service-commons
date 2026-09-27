import ballerina/http;
import ballerina/lang.'float;
import ballerina/log;
import ballerina/sql;
import ballerina/task;
import ballerina/uuid;
import ballerinax/java.jdbc;
import commons/service_commons;
import commons/service_commons.db as sdb;

const BATCH_SIZE = 50;
const CLAIM_MILLIS = 60000;

type SubscriptionRow record {|
    string id;
    string participant_id;
    string url;
    string events;
    int created_at;
|};

type DueRow record {|
    string id;
    string event_id;
    string event;
    string payload;
    int attempts;
    string url;
    string secret;
|};

type DeliveryRow record {|
    string id;
    string event_id;
    string event;
    string status;
    int attempts;
    int created_at;
    int next_attempt_at;
    int? delivered_at;
    string? last_error;
|};

# Webhook subscriptions per participant, with a transactional outbox and signed, retried delivery.
# Tables are `<prefix>subscription` and `<prefix>outbox`.
public isolated class Webhooks {
    private final jdbc:Client db;
    private final sdb:DbType dbType;
    private final string ns;
    private final string prefix;
    private final string subscriptionTable;
    private final string outboxTable;
    private final DispatcherConfig & readonly config;

    # Creates the registry and dispatcher.
    #
    # + db - Database client; pass the service's own client so `enqueue` joins its transactions
    # + dbType - Dialect
    # + ns - Namespace
    # + prefix - Table prefix, e.g. `chat_webhook_`
    # + config - Delivery tuning
    # + return - An error if the prefix is invalid
    public isolated function init(jdbc:Client db, sdb:DbType dbType, string ns, string prefix,
            DispatcherConfig config = {}) returns error? {
        check sdb:validatePrefix(prefix);
        self.db = db;
        self.dbType = dbType;
        self.ns = ns;
        self.prefix = prefix;
        self.subscriptionTable = prefix + "subscription";
        self.outboxTable = prefix + "outbox";
        self.config = config.cloneReadOnly();
    }

    # Creates or upgrades the webhook tables.
    #
    # + return - An error if a migration fails
    public isolated function migrate() returns error? {
        return sdb:migrate(self.db, self.dbType, self.prefix, migrations);
    }

    # Registers a webhook for a participant.
    #
    # + input - The webhook
    # + return - The subscription with its secret, or an error
    public isolated function register(NewSubscription input) returns CreatedSubscription|error {
        string id = service_commons:newId();
        string secret = input?.secret ?: newSecret();
        int now = service_commons:nowMillis();
        _ = check self.db->execute(sql:queryConcat(`INSERT INTO `, sdb:ident(self.subscriptionTable),
            ` (id, ns, participant_id, url, events, secret, created_at) VALUES (${id}, ${self.ns},
            ${input.participantId}, ${input.url}, ${joinEvents(input.events)}, ${secret}, ${now})`));
        return {
            id,
            participantId: input.participantId,
            url: input.url,
            events: input.events,
            createdAt: service_commons:toIso(now),
            secret
        };
    }

    # Registers a configured webhook, or updates the one with the same participant and URL.
    #
    # + config - The webhook
    # + return - The subscription, or an error
    public isolated function upsert(WebhookConfig config) returns Subscription|error {
        SubscriptionRow[] existing = check self.fetch(sql:queryConcat(self.selectSubscriptions(),
            ` AND participant_id = ${config.participantId} AND url = ${config.url}`));
        if existing.length() == 0 {
            CreatedSubscription created = check self.register({...config});
            return {
                id: created.id,
                participantId: created.participantId,
                url: created.url,
                events: created.events,
                createdAt: created.createdAt
            };
        }
        _ = check self.db->execute(sql:queryConcat(`UPDATE `, sdb:ident(self.subscriptionTable),
            ` SET events = ${joinEvents(config.events)}, secret = ${config.secret} WHERE id = ${existing[0].id}`));
        SubscriptionRow updated = existing[0].clone();
        updated.events = joinEvents(config.events);
        return toSubscription(updated);
    }

    # Lists webhooks.
    #
    # + participantId - Only this participant's
    # + return - The subscriptions, or an error
    public isolated function list(string? participantId = ()) returns Subscription[]|error {
        sql:ParameterizedQuery query = self.selectSubscriptions();
        if participantId is string {
            query = sql:queryConcat(query, ` AND participant_id = ${participantId}`);
        }
        SubscriptionRow[] rows = check self.fetch(sql:queryConcat(query, ` ORDER BY id`));
        return rows.map(toSubscription);
    }

    # Gets a webhook.
    #
    # + id - Subscription ID
    # + return - The subscription, `()` if unknown, or an error
    public isolated function get(string id) returns Subscription?|error {
        SubscriptionRow[] rows = check self.fetch(sql:queryConcat(self.selectSubscriptions(), ` AND id = ${id}`));
        return rows.length() == 0 ? () : toSubscription(rows[0]);
    }

    # Removes a webhook and its pending deliveries.
    #
    # + id - Subscription ID
    # + return - `true` if it existed, or an error
    public isolated function remove(string id) returns boolean|error {
        _ = check self.db->execute(sql:queryConcat(`DELETE FROM `, sdb:ident(self.outboxTable),
            ` WHERE subscription_id = ${id}`));
        sql:ExecutionResult result = check self.db->execute(sql:queryConcat(`DELETE FROM `,
            sdb:ident(self.subscriptionTable), ` WHERE ns = ${self.ns} AND id = ${id}`));
        return (result.affectedRowCount ?: 0) > 0;
    }

    # Queues an event for every webhook of the recipients that accepts it. Call it inside the transaction that
    # makes the change, so the event is queued exactly when the change commits; then call `dispatch`.
    #
    # + event - Event name
    # + recipients - Participants to notify
    # + data - Event payload
    # + correlationId - Correlation ID of the conversation or case
    # + return - Deliveries queued, or an error
    public isolated function enqueue(string event, string[] recipients, json data, string? correlationId = ())
            returns int|error {
        if recipients.length() == 0 {
            return 0;
        }
        SubscriptionRow[] rows = check self.fetch(sql:queryConcat(self.selectSubscriptions(),
            ` AND participant_id IN (`, sql:arrayFlattenQuery(recipients), `)`));
        string eventId = service_commons:newId();
        int now = service_commons:nowMillis();
        int queued = 0;
        foreach SubscriptionRow row in rows {
            string[] events = splitEvents(row.events);
            if events.length() > 0 && events.indexOf(event) is () {
                continue;
            }
            WebhookEvent envelope = {
                eventId,
                event,
                ns: self.ns,
                recipientId: row.participant_id,
                occurredAt: service_commons:toIso(now),
                data
            };
            if correlationId is string {
                envelope.correlationId = correlationId;
            }
            _ = check self.db->execute(sql:queryConcat(`INSERT INTO `, sdb:ident(self.outboxTable),
                ` (id, ns, subscription_id, event_id, event, payload, status, attempts, next_attempt_at, created_at)
                VALUES (${service_commons:newId()}, ${self.ns}, ${row.id}, ${eventId}, ${event},
                ${envelope.toJsonString()}, ${PENDING}, 0, ${now}, ${now})`));
            queued += 1;
        }
        return queued;
    }

    # Delivers due events in the background. Call it after the transaction that queued them commits.
    public isolated function dispatch() {
        _ = start self.deliverAndLog();
    }

    # Delivers due events now, oldest first.
    #
    # + return - Deliveries attempted, or an error
    public isolated function deliverDue() returns int|error {
        int attempted = 0;
        while true {
            int now = service_commons:nowMillis();
            stream<DueRow, sql:Error?> due = self.db->query(sql:queryConcat(`SELECT o.id, o.event_id, o.event,
                o.payload, o.attempts, s.url, s.secret FROM `, sdb:ident(self.outboxTable), ` o JOIN `,
                sdb:ident(self.subscriptionTable), ` s ON s.id = o.subscription_id WHERE o.ns = ${self.ns}
                AND o.status = ${PENDING} AND o.next_attempt_at <= ${now}
                AND (o.locked_until IS NULL OR o.locked_until < ${now}) ORDER BY o.id LIMIT ${BATCH_SIZE}`));
            DueRow[] batch = check from DueRow row in due select row;
            foreach DueRow row in batch {
                if check self.claim(row.id, now) {
                    check self.attempt(row);
                    attempted += 1;
                }
            }
            if batch.length() < BATCH_SIZE {
                return attempted;
            }
        }
    }

    # Lists a webhook's most recent deliveries.
    #
    # + subscriptionId - Subscription ID
    # + 'limit - Most deliveries returned
    # + return - Deliveries, newest first, or an error
    public isolated function deliveries(string subscriptionId, int 'limit = 50) returns Delivery[]|error {
        stream<DeliveryRow, sql:Error?> rows = self.db->query(sql:queryConcat(`SELECT id, event_id, event, status,
            attempts, created_at, next_attempt_at, delivered_at, last_error FROM `, sdb:ident(self.outboxTable),
            ` WHERE subscription_id = ${subscriptionId} ORDER BY id DESC LIMIT ${'limit}`));
        return from DeliveryRow row in rows select check toDelivery(row);
    }

    # Schedules the retry job, which also prunes old delivered rows.
    #
    # + return - An error if the job cannot be scheduled
    public isolated function startRetries() returns error? {
        _ = check task:scheduleJobRecurByFrequency(new RetryJob(self), self.config.retryInterval);
    }

    isolated function pruneDelivered() returns error? {
        int cutoff = service_commons:nowMillis() - self.config.keepDeliveredHours * 3600000;
        _ = check self.db->execute(sql:queryConcat(`DELETE FROM `, sdb:ident(self.outboxTable),
            ` WHERE ns = ${self.ns} AND status = ${DELIVERED} AND delivered_at < ${cutoff}`));
    }

    isolated function deliverAndLog() {
        int|error result = self.deliverDue();
        if result is error {
            log:printError("Webhook delivery failed", result);
        }
    }

    // Claims a row for this node so concurrent dispatchers never send it twice.
    isolated function claim(string id, int now) returns boolean|error {
        sql:ExecutionResult result = check self.db->execute(sql:queryConcat(`UPDATE `, sdb:ident(self.outboxTable),
            ` SET locked_until = ${now + CLAIM_MILLIS} WHERE id = ${id} AND status = ${PENDING}
            AND (locked_until IS NULL OR locked_until < ${now})`));
        return result.affectedRowCount == 1;
    }

    isolated function attempt(DueRow row) returns error? {
        error? sent = self.send(row);
        int now = service_commons:nowMillis();
        int attempts = row.attempts + 1;
        if sent is () {
            _ = check self.db->execute(sql:queryConcat(`UPDATE `, sdb:ident(self.outboxTable),
                ` SET status = ${DELIVERED}, attempts = ${attempts}, delivered_at = ${now}, locked_until = NULL,
                last_error = NULL WHERE id = ${row.id}`));
            return;
        }
        string lastError = sent.message().length() > 1000 ? sent.message().substring(0, 1000) : sent.message();
        string status = attempts >= self.config.maxAttempts ? FAILED : PENDING;
        if status == FAILED {
            log:printWarn(string `Webhook delivery ${row.id} (${row.event}) failed after ${attempts} attempts`,
                'error = sent);
        }
        _ = check self.db->execute(sql:queryConcat(`UPDATE `, sdb:ident(self.outboxTable),
            ` SET status = ${status}, attempts = ${attempts}, next_attempt_at = ${now + self.backoffMillis(attempts)},
            locked_until = NULL, last_error = ${lastError} WHERE id = ${row.id}`));
    }

    isolated function send(DueRow row) returns error? {
        http:Client target = check new (row.url, {timeout: self.config.timeout});
        string timestamp = (service_commons:nowMillis() / 1000).toString();
        byte[] body = row.payload.toBytes();
        http:Request req = new;
        req.setBinaryPayload(body, "application/json");
        req.setHeader(HEADER_SIGNATURE, check sign(row.secret, timestamp, body));
        req.setHeader(HEADER_TIMESTAMP, timestamp);
        req.setHeader(HEADER_EVENT, row.event);
        req.setHeader(HEADER_EVENT_ID, row.event_id);
        http:Response response = check target->post("", req);
        if response.statusCode < 200 || response.statusCode >= 300 {
            return error(string `Receiver answered HTTP ${response.statusCode}`);
        }
    }

    isolated function backoffMillis(int attempts) returns int {
        float seconds = <float>self.config.initialBackoff * float:pow(2, <float>(attempts - 1));
        return <int>(float:min(seconds, <float>self.config.maxBackoff) * 1000);
    }

    isolated function selectSubscriptions() returns sql:ParameterizedQuery {
        return sql:queryConcat(`SELECT id, participant_id, url, events, created_at FROM `,
            sdb:ident(self.subscriptionTable), ` WHERE ns = ${self.ns}`);
    }

    isolated function fetch(sql:ParameterizedQuery query) returns SubscriptionRow[]|error {
        stream<SubscriptionRow, sql:Error?> rows = self.db->query(query);
        return from SubscriptionRow row in rows select row;
    }
}

isolated class RetryJob {
    *task:Job;
    private final Webhooks webhooks;
    private int runs = 0;

    isolated function init(Webhooks webhooks) {
        self.webhooks = webhooks;
    }

    public isolated function execute() {
        self.webhooks.deliverAndLog();
        boolean prune;
        lock {
            self.runs += 1;
            prune = self.runs % 720 == 1;
        }
        if prune {
            error? pruned = self.webhooks.pruneDelivered();
            if pruned is error {
                log:printError("Pruning delivered webhooks failed", pruned);
            }
        }
    }
}

isolated function toSubscription(SubscriptionRow row) returns Subscription => {
    id: row.id,
    participantId: row.participant_id,
    url: row.url,
    events: splitEvents(row.events),
    createdAt: service_commons:toIso(row.created_at)
};

isolated function toDelivery(DeliveryRow row) returns Delivery|error {
    Delivery delivery = {
        id: row.id,
        eventId: row.event_id,
        event: row.event,
        status: check row.status.ensureType(),
        attempts: row.attempts,
        createdAt: service_commons:toIso(row.created_at)
    };
    if delivery.status == PENDING {
        delivery.nextAttemptAt = service_commons:toIso(row.next_attempt_at);
    }
    int? deliveredAt = row.delivered_at;
    if deliveredAt is int {
        delivery.deliveredAt = service_commons:toIso(deliveredAt);
    }
    string? lastError = row.last_error;
    if lastError is string {
        delivery.lastError = lastError;
    }
    return delivery;
}

isolated function joinEvents(string[] events) returns string => string:'join(",", ...events);

isolated function splitEvents(string events) returns string[] =>
    from string event in re `,`.split(events) where event != "" select event;

isolated function newSecret() returns string =>
    re `-`.replaceAll(uuid:createType4AsString() + uuid:createType4AsString(), "");
