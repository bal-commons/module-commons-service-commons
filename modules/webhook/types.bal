# A webhook registered from configuration, e.g. an agent's endpoint known at deploy time.
public type WebhookConfig record {|
    # Participant whose events are delivered, e.g. `agent:maintenance-triage`
    string participantId;
    # Delivery endpoint
    string url;
    # HMAC signing secret shared with the receiver
    string secret;
    # Event names to deliver; empty delivers all
    string[] events = [];
|};

# A webhook to register through the API.
public type NewSubscription record {|
    # Participant whose events are delivered
    string participantId;
    # Delivery endpoint
    string url;
    # Event names to deliver; empty delivers all
    string[] events = [];
    # HMAC signing secret; generated when absent
    string secret?;
|};

# A registered webhook.
public type Subscription record {|
    # Subscription ID
    string id;
    # Participant whose events are delivered
    string participantId;
    # Delivery endpoint
    string url;
    # Event names delivered; empty means all
    string[] events;
    # RFC 3339 registration time
    string createdAt;
|};

# A newly registered webhook, with its secret. The secret is not returned again.
public type CreatedSubscription record {|
    *Subscription;
    # HMAC signing secret
    string secret;
|};

# Body of every webhook delivery.
public type WebhookEvent record {|
    # Unique per event; the receiver's idempotency key
    string eventId;
    # Event name, e.g. `message.created`
    string event;
    # Namespace the event belongs to
    string ns;
    # Participant this delivery is for
    string recipientId;
    # RFC 3339 time the event happened
    string occurredAt;
    # Correlation ID of the conversation or case
    string correlationId?;
    # Event payload
    json data;
|};

# State of one delivery.
public enum DeliveryStatus {
    PENDING,
    DELIVERED,
    FAILED
}

# One delivery of an event to a subscription.
public type Delivery record {|
    # Delivery ID
    string id;
    # Event ID
    string eventId;
    # Event name
    string event;
    # Delivery state
    DeliveryStatus status;
    # Attempts made
    int attempts;
    # RFC 3339 time the event was queued
    string createdAt;
    # RFC 3339 time of the next attempt, while pending
    string nextAttemptAt?;
    # RFC 3339 time it was delivered
    string deliveredAt?;
    # Error of the last failed attempt
    string lastError?;
|};

# Delivery tuning.
public type DispatcherConfig record {|
    # Attempts before a delivery is marked FAILED
    int maxAttempts = 8;
    # Delay before the first retry, in seconds; doubles each attempt
    decimal initialBackoff = 1;
    # Longest delay between retries, in seconds
    decimal maxBackoff = 300;
    # Request timeout, in seconds
    decimal timeout = 10;
    # How often pending deliveries are retried, in seconds
    decimal retryInterval = 5;
    # Delivered rows are kept this long, in hours
    int keepDeliveredHours = 24;
|};

# Header carrying `sha256=<hex HMAC of "<timestamp>.<body>">`.
public const HEADER_SIGNATURE = "x-commons-signature";
# Header carrying the send time in epoch seconds.
public const HEADER_TIMESTAMP = "x-commons-timestamp";
# Header carrying the event name.
public const HEADER_EVENT = "x-commons-event";
# Header carrying the event ID.
public const HEADER_EVENT_ID = "x-commons-event-id";
