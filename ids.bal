import ballerina/random;
import ballerina/time;

const CROCKFORD = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

# Returns a new ULID: 26 Crockford base32 characters that sort by creation time.
#
# + return - The new ID
public isolated function newId() returns string {
    int ms = nowMillis();
    string[] chars = [];
    foreach int _ in 0 ..< 10 {
        chars.unshift(CROCKFORD[ms % 32]);
        ms = ms / 32;
    }
    foreach int _ in 0 ..< 16 {
        chars.push(CROCKFORD[checkpanic random:createIntInRange(0, 32)]);
    }
    return string:'join("", ...chars);
}

# Returns the current time as epoch milliseconds, the timestamp format of every commons table.
#
# + return - Milliseconds since the Unix epoch
public isolated function nowMillis() returns int {
    [int, decimal] [seconds, fraction] = time:utcNow();
    return seconds * 1000 + <int>(fraction * 1000).floor();
}

# Formats epoch milliseconds as an RFC 3339 UTC timestamp.
#
# + millis - Milliseconds since the Unix epoch
# + return - The timestamp, e.g. `2026-09-25T10:15:30.120Z`
public isolated function toIso(int millis) returns string {
    return time:utcToString([millis / 1000, <decimal>(millis % 1000) / 1000]);
}

# Parses an RFC 3339 timestamp into epoch milliseconds.
#
# + timestamp - The timestamp
# + return - Milliseconds since the Unix epoch, or an error if it is not a valid timestamp
public isolated function fromIso(string timestamp) returns int|error {
    [int, decimal] [seconds, fraction] = check time:utcFromString(timestamp);
    return seconds * 1000 + <int>(fraction * 1000).floor();
}
