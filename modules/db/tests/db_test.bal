import ballerina/sql;
import ballerina/test;
import ballerinax/h2.driver as _;
import ballerinax/java.jdbc;

final Migration[] migrations = [
    {version: 1, description: "create items", statements: ["CREATE TABLE {prefix}item (id VARCHAR(26) PRIMARY KEY)"]},
    {
        version: 2,
        description: "add name",
        statements: ["ALTER TABLE {prefix}item ADD COLUMN name VARCHAR(64)"],
        dialectStatements: {[H2]: ["ALTER TABLE {prefix}item ADD COLUMN name VARCHAR(32)"]}
    }
];

@test:Config
function migrateAppliesOnceInOrder() returns error? {
    jdbc:Client db = check connect({url: "jdbc:h2:mem:migrate;DB_CLOSE_DELAY=-1"});
    check migrate(db, H2, "t_", migrations);
    check migrate(db, H2, "t_", migrations);
    int versions = check db->queryRow(`SELECT COUNT(*) FROM t_schema_version`);
    test:assertEquals(versions, 2);
    _ = check db->execute(`INSERT INTO t_item (id, name) VALUES ('a', 'first')`);
    string name = check db->queryRow(`SELECT name FROM t_item WHERE id = 'a'`);
    test:assertEquals(name, "first");
}

@test:Config
function duplicateKeyIsRecognised() returns error? {
    jdbc:Client db = check connect({url: "jdbc:h2:mem:dup;DB_CLOSE_DELAY=-1"});
    check migrate(db, H2, "d_", [migrations[0]]);
    _ = check db->execute(`INSERT INTO d_item (id) VALUES ('a')`);
    sql:ExecutionResult|sql:Error result = db->execute(`INSERT INTO d_item (id) VALUES ('a')`);
    test:assertTrue(result is sql:Error && isDuplicateKey(result));
    test:assertFalse(isDuplicateKey(error("other")));
}

@test:Config
function prefixMustBeAnIdentifier() {
    test:assertTrue(validatePrefix("notification_") is ());
    test:assertTrue(validatePrefix("x; DROP TABLE y") is error);
    test:assertTrue(validatePrefix("1abc") is error);
}

@test:Config
function atomicCommitsOrRollsBack() returns error? {
    final jdbc:Client db = check connect({url: "jdbc:h2:mem:atomic;DB_CLOSE_DELAY=-1"});
    check migrate(db, H2, "a_", [migrations[0]]);
    anydata committed = check atomic(isolated function () returns anydata|error {
        _ = check db->execute(`INSERT INTO a_item (id) VALUES ('kept')`);
        return 1;
    });
    test:assertEquals(committed, 1);
    anydata|error rolledBack = atomic(isolated function () returns anydata|error {
        _ = check db->execute(`INSERT INTO a_item (id) VALUES ('dropped')`);
        return error("rejected");
    });
    test:assertTrue(rolledBack is error);
    int count = check db->queryRow(`SELECT COUNT(*) FROM a_item`);
    test:assertEquals(count, 1);
}
