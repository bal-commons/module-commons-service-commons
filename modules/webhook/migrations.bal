import commons/service_commons.db as sdb;

final sdb:Migration[] & readonly migrations = [
    {
        version: 1,
        description: "webhook subscriptions and delivery outbox",
        statements: [
            string `CREATE TABLE {prefix}subscription (
                id VARCHAR(26) NOT NULL PRIMARY KEY,
                ns VARCHAR(64) NOT NULL,
                participant_id VARCHAR(255) NOT NULL,
                url VARCHAR(2000) NOT NULL,
                events VARCHAR(2000) NOT NULL,
                secret VARCHAR(255) NOT NULL,
                created_at BIGINT NOT NULL)`,
            "CREATE INDEX {prefix}subscription_participant ON {prefix}subscription (ns, participant_id)",
            string `CREATE TABLE {prefix}outbox (
                id VARCHAR(26) NOT NULL PRIMARY KEY,
                ns VARCHAR(64) NOT NULL,
                subscription_id VARCHAR(26) NOT NULL,
                event_id VARCHAR(26) NOT NULL,
                event VARCHAR(128) NOT NULL,
                payload TEXT NOT NULL,
                status VARCHAR(16) NOT NULL,
                attempts INT NOT NULL,
                next_attempt_at BIGINT NOT NULL,
                locked_until BIGINT,
                last_error VARCHAR(1000),
                created_at BIGINT NOT NULL,
                delivered_at BIGINT)`,
            "CREATE INDEX {prefix}outbox_due ON {prefix}outbox (ns, status, next_attempt_at)",
            "CREATE INDEX {prefix}outbox_subscription ON {prefix}outbox (subscription_id, id)"
        ]
    }
];
