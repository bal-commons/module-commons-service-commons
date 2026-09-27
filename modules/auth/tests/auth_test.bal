import ballerina/http;
import ballerina/jwt;
import ballerina/test;

const CERT = "modules/auth/tests/resources/test-cert.pem";
const KEY = "modules/auth/tests/resources/test-key.pem";

function request(map<string> headers) returns http:Request {
    http:Request req = new;
    foreach [string, string] [name, value] in headers.entries() {
        req.setHeader(name, value);
    }
    return req;
}

function token(map<json> claims, string issuer = "thunder") returns string|error {
    return jwt:issue({
        issuer,
        audience: "tenant-app",
        customClaims: claims,
        signatureConfig: {config: {keyFile: KEY}}
    });
}

@test:Config
function trustedHeadersWhenNoAuthEnabled() returns error? {
    Authenticator authn = check new ({});
    CallerIdentity caller = check authn.authenticate(request({
        "x-user-id": "tara", "x-user-roles": "Tenant, Residents"
    })).ensureType();
    test:assertEquals(caller, {userId: "tara", roles: ["Tenant", "Residents"], scopes: []});
    test:assertTrue(authn.hasScope(caller, "a:read"), "scopes are not enforced");
    test:assertFalse(holdsScope(caller, "a:admin"), "privileged overrides still need the scope");
}

@test:Config
function trustedHeadersCarryScopes() returns error? {
    Authenticator authn = check new ({enforceScopes: true});
    CallerIdentity caller = check authn.authenticate(request({"x-user-id": "tara", "x-user-scopes": "a:read"})).ensureType();
    test:assertTrue(authn.hasScope(caller, "a:read"));
    test:assertFalse(authn.hasScope(caller, "a:write"));
}

@test:Config
function apiKeyGrantsAllScopes() returns error? {
    Authenticator authn = check new ({enableApiKey: true, apiKeyValue: "k", enforceScopes: true});
    CallerIdentity caller = check authn.authenticate(request({"x-api-key": "k", "x-user-id": "workflow"})).ensureType();
    test:assertEquals(caller.userId, "workflow");
    test:assertTrue(authn.hasScope(caller, "anything"));
    test:assertTrue(authn.authenticate(request({"x-api-key": "wrong"})) is http:Unauthorized);
    test:assertTrue(authn.authenticate(request({})) is http:Unauthorized);
}

@test:Config
function jwtClaimsBecomeIdentity() returns error? {
    Authenticator authn = check new ({enableJwtAuth: true, jwtCertFile: CERT, jwtIssuer: "thunder",
        jwtAudience: "tenant-app", enforceScopes: true});
    string jwt = check token({"sub": "priya", "groups": ["PropertyManager"], "scope": "notification:read notification:send"});
    CallerIdentity caller = check authn.authenticate(request({"Authorization": "Bearer " + jwt})).ensureType();
    test:assertEquals(caller, {userId: "priya", roles: ["PropertyManager"], scopes: ["notification:read", "notification:send"]});
    test:assertTrue(authn.hasScope(caller, "notification:send"));
    test:assertFalse(authn.hasScope(caller, "notification:admin"));
}

@test:Config
function jwtNestedClaimPaths() returns error? {
    Authenticator authn = check new ({enableJwtAuth: true, jwtCertFile: CERT, userIdClaim: "user.name",
        rolesClaim: "realm_access.roles"});
    string jwt = check token({"user": {"name": "carlos"}, "realm_access": {"roles": ["Contractor"]}, "scp": ["x"]});
    CallerIdentity caller = check authn.authenticate(request({"Authorization": "Bearer " + jwt})).ensureType();
    test:assertEquals(caller, {userId: "carlos", roles: ["Contractor"], scopes: ["x"]});
}

@test:Config
function jwtRejectsWrongIssuerAndHeaders() returns error? {
    Authenticator authn = check new ({enableJwtAuth: true, jwtCertFile: CERT, jwtIssuer: "thunder"});
    string jwt = check token({"sub": "mallory"}, "elsewhere");
    test:assertTrue(authn.authenticate(request({"Authorization": "Bearer " + jwt})) is http:Unauthorized);
    test:assertTrue(authn.authenticate(request({"x-user-id": "mallory"})) is http:Unauthorized);
}

@test:Config
function jwtAuthNeedsAKeySource() {
    Authenticator|error authn = new ({enableJwtAuth: true});
    test:assertTrue(authn is error);
}

@test:Config
function ticketsAreSingleUse() {
    TicketStore tickets = new;
    string ticket = tickets.issue({userId: "tara"});
    test:assertEquals(tickets.redeem(ticket), {userId: "tara", roles: [], scopes: []});
    test:assertEquals(tickets.redeem(ticket), ());
    test:assertEquals(tickets.redeem("unknown"), ());
}

@test:Config
function ticketsExpire() {
    TicketStore tickets = new (0);
    string ticket = tickets.issue({userId: "tara"});
    test:assertEquals(tickets.redeem(ticket) is (), true);
}
