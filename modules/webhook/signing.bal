import ballerina/crypto;
import ballerina/http;
import commons/service_commons;

# Signs a delivery: `sha256=` + hex HMAC-SHA256 of `<timestamp>.<body>`.
#
# + secret - Shared secret
# + timestamp - Send time in epoch seconds, as sent in `x-commons-timestamp`
# + body - Request body
# + return - The signature header value, or an error
public isolated function sign(string secret, string timestamp, byte[] body) returns string|error {
    byte[] signed = [...timestamp.toBytes(), ...".".toBytes(), ...body];
    byte[] mac = check crypto:hmacSha256(signed, secret.toBytes());
    return "sha256=" + mac.toBase16();
}

# Verifies a received delivery and returns its event. Use it in the receiving service.
#
# + req - The webhook request
# + secret - Shared secret
# + toleranceSeconds - Largest accepted clock difference, which bounds replays
# + return - The event, or an error if the signature or timestamp is invalid
public isolated function verify(http:Request req, string secret, int toleranceSeconds = 300) returns WebhookEvent|error {
    string signature = check req.getHeader(HEADER_SIGNATURE);
    string timestamp = check req.getHeader(HEADER_TIMESTAMP);
    int sentAt = check int:fromString(timestamp);
    if (service_commons:nowMillis() / 1000 - sentAt).abs() > toleranceSeconds {
        return error("Webhook timestamp is outside the tolerance");
    }
    byte[] body = check req.getBinaryPayload();
    if !constantTimeEquals(check sign(secret, timestamp, body), signature) {
        return error("Webhook signature does not match");
    }
    return (check string:fromBytes(body)).fromJsonStringWithType();
}

isolated function constantTimeEquals(string expected, string actual) returns boolean {
    byte[] a = expected.toBytes();
    byte[] b = actual.toBytes();
    int diff = a.length() ^ b.length();
    foreach int i in 0 ..< int:min(a.length(), b.length()) {
        diff = diff | (a[i] ^ b[i]);
    }
    return diff == 0;
}
