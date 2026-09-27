# Databases every commons service supports.
public enum DbType {
    H2,
    MYSQL,
    POSTGRESQL
}

# JDBC connection settings for a commons service.
public type DbConfig record {|
    # Database dialect; selects the migration scripts
    DbType dbType = H2;
    # JDBC URL
    string url = "jdbc:h2:mem:commons;DB_CLOSE_DELAY=-1";
    # Database user
    string user = "sa";
    # Database password
    string password = "";
    # Connection pool size
    int maxOpenConnections = 10;
    # Runs the versioned migration scripts on startup
    boolean initSchema = true;
|};

# One schema version of a service. Statements use `{prefix}` for the service's table prefix.
public type Migration record {|
    # Version number; migrations run in ascending order, each once
    int version;
    # What this version changes
    string description;
    # Statements for every dialect without an entry in `dialectStatements`
    string[] statements;
    # Dialect-specific statements, keyed by `DbType`
    map<string[]> dialectStatements = {};
|};
