import ballerina/log;
import ballerina/sql;
import ballerinax/java.jdbc;
import commons/service_commons;

# Opens a pooled JDBC client. The application supplies the driver, e.g. `import ballerinax/h2.driver as _;`.
#
# + config - Connection settings
# + return - The client, or an error if the connection cannot be opened
public isolated function connect(DbConfig config) returns jdbc:Client|sql:Error {
    return new (config.url, config.user, config.password,
        connectionPool = {maxOpenConnections: config.maxOpenConnections});
}

# Checks a table prefix so it can be spliced into SQL as an identifier.
#
# + prefix - The prefix, e.g. `notification_`
# + return - An error if it is not a letter followed by letters, digits or underscores
public isolated function validatePrefix(string prefix) returns error? {
    if !re `[A-Za-z][A-Za-z0-9_]{0,29}`.isFullMatch(prefix) {
        return error(string `Invalid table prefix '${prefix}': use letters, digits and underscores, starting with a letter`);
    }
}

# Returns a query fragment holding an SQL identifier, for table names built from a validated prefix.
#
# + name - The identifier; never pass user input
# + return - The fragment, to combine with `sql:queryConcat`
public isolated function ident(string name) returns sql:ParameterizedQuery {
    return raw(name);
}

# Returns a query holding a literal SQL string with no parameters.
#
# + statement - The SQL
# + return - The query
public isolated function raw(string statement) returns sql:ParameterizedQuery {
    sql:ParameterizedQuery query = ``;
    query.strings = [statement].cloneReadOnly();
    return query;
}

# Reports whether an error is a unique or primary key violation (SQL state class 23).
#
# + err - The error
# + return - `true` for an integrity constraint violation
public isolated function isDuplicateKey(error err) returns boolean {
    if err !is sql:DatabaseError {
        return false;
    }
    string? state = err.detail().sqlState;
    return state is string && state.startsWith("23");
}

# Applies the migrations newer than the recorded schema version, each in order, and records them.
#
# + db - The client
# + dbType - Dialect, selecting `dialectStatements`
# + prefix - The service's table prefix; the version table is `<prefix>schema_version`
# + migrations - All of the service's migrations
# + return - An error if a statement fails
public isolated function migrate(jdbc:Client db, DbType dbType, string prefix, Migration[] migrations) returns error? {
    check validatePrefix(prefix);
    sql:ParameterizedQuery versionTable = ident(prefix + "schema_version");
    _ = check db->execute(sql:queryConcat(`CREATE TABLE IF NOT EXISTS `, versionTable,
            ` (version INT PRIMARY KEY, description VARCHAR(255) NOT NULL, applied_at BIGINT NOT NULL)`));
    int? current = check db->queryRow(sql:queryConcat(`SELECT MAX(version) FROM `, versionTable));
    int applied = current ?: 0;
    Migration[] pending = from Migration m in migrations where m.version > applied order by m.version select m;
    foreach Migration m in pending {
        string[] statements = m.dialectStatements[dbType] ?: m.statements;
        foreach string statement in statements {
            _ = check db->execute(raw(re `\{prefix\}`.replaceAll(statement, prefix)));
        }
        _ = check db->execute(sql:queryConcat(`INSERT INTO `, versionTable,
                ` (version, description, applied_at) VALUES (${m.version}, ${m.description}, ${service_commons:nowMillis()})`));
        log:printInfo(string `Applied schema ${prefix}v${m.version}: ${m.description}`);
    }
}

# Runs `work` in a database transaction: committed when it returns a value, rolled back when it returns an error.
# Services use it instead of their own `transaction` blocks, because each package that contains one starts the
# transaction coordinator, and a second start in one program fails on the port.
#
# + work - The statements to run; clients it uses join the transaction
# + return - What `work` returned, or its error
public isolated function atomic(isolated function () returns anydata|error work) returns anydata|error {
    anydata result = ();
    transaction {
        result = check work();
        check commit;
    }
    return result;
}
