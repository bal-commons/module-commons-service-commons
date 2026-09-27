import ballerina/http;
import ballerina/jwt;

# Resolves the caller of a request from a bearer JWT, an API key or trusted headers.
public isolated class Authenticator {
    private final AuthConfig & readonly config;
    private final http:ListenerJwtAuthHandler? jwtHandler;

    # Creates an authenticator.
    #
    # + config - Auth settings
    # + return - An error if JWT auth is enabled without a JWKS URL or certificate
    public isolated function init(AuthConfig config) returns error? {
        self.config = config.cloneReadOnly();
        if !config.enableJwtAuth {
            self.jwtHandler = ();
            return;
        }
        jwt:ValidatorSignatureConfig signature;
        if config.jwtCertFile != "" {
            signature = {certFile: config.jwtCertFile};
        } else if config.jwksUrl != "" {
            signature = {jwksConfig: {url: config.jwksUrl,
                clientConfig: {secureSocket: config.jwksVerifyTls ? () : {disable: true}}}};
        } else {
            return error("enableJwtAuth requires jwksUrl or jwtCertFile");
        }
        http:JwtValidatorConfig validator = {signatureConfig: signature};
        if config.jwtIssuer != "" {
            validator.issuer = config.jwtIssuer;
        }
        if config.jwtAudience != "" {
            validator.audience = config.jwtAudience;
        }
        self.jwtHandler = new (validator);
    }

    # Resolves the caller.
    #
    # + req - The request
    # + return - The caller, or `401` when no enabled scheme accepts the credentials
    public isolated function authenticate(http:Request req) returns CallerIdentity|http:Unauthorized {
        AuthConfig config = self.config;
        if config.enableApiKey {
            string|http:HeaderNotFoundError key = req.getHeader(config.apiKeyHeader);
            if key is string && key == config.apiKeyValue {
                return headerIdentity(req, "service", [ALL_SCOPES]);
            }
        }
        http:ListenerJwtAuthHandler? handler = self.jwtHandler;
        if handler is http:ListenerJwtAuthHandler {
            string|http:HeaderNotFoundError authorization = req.getHeader("Authorization");
            if authorization is string && authorization.startsWith("Bearer ") {
                jwt:Payload|http:Unauthorized payload = handler.authenticate(authorization);
                return payload is jwt:Payload ? claimsIdentity(payload, config) : unauthorized();
            }
        }
        if !config.enableApiKey && !config.enableJwtAuth {
            return headerIdentity(req, "anonymous", ());
        }
        return unauthorized();
    }

    # Checks that the caller holds a scope. Passes when `enforceScopes` is off.
    #
    # + caller - The caller
    # + scope - The required scope
    # + return - `true` if the caller may proceed
    public isolated function hasScope(CallerIdentity caller, string scope) returns boolean {
        return !self.config.enforceScopes || holdsScope(caller, scope);
    }
}

# Checks that the caller holds a scope whether or not `enforceScopes` is on. Use it for privileged overrides such
# as reading another user's data or acting as an agent.
#
# + caller - The caller
# + scope - The scope
# + return - `true` if the caller's scopes include it or `*`
public isolated function holdsScope(CallerIdentity caller, string scope) returns boolean =>
    caller.scopes.indexOf(ALL_SCOPES) != () || caller.scopes.indexOf(scope) != ();

isolated function headerIdentity(http:Request req, string defaultUser, string[]? grantedScopes) returns CallerIdentity {
    string|http:HeaderNotFoundError userId = req.getHeader(HEADER_USER_ID);
    string|http:HeaderNotFoundError roles = req.getHeader(HEADER_USER_ROLES);
    string|http:HeaderNotFoundError scopes = req.getHeader(HEADER_USER_SCOPES);
    return {
        userId: userId is string && userId.trim() != "" ? userId.trim() : defaultUser,
        roles: roles is string ? splitList(roles, ",") : [],
        scopes: grantedScopes ?: (scopes is string ? splitList(scopes, " ") : [])
    };
}

isolated function claimsIdentity(jwt:Payload payload, AuthConfig config) returns CallerIdentity|http:Unauthorized {
    map<json> claims = <map<json>>payload.toJson();
    json userId = claimAt(claims, config.userIdClaim);
    if userId !is string || userId == "" {
        return unauthorized();
    }
    json scopeClaim = claims.hasKey("scope") ? claims["scope"] : claims["scp"];
    return {
        userId,
        roles: toList(claimAt(claims, config.rolesClaim), ","),
        scopes: toList(scopeClaim, " ")
    };
}

isolated function claimAt(map<json> claims, string path) returns json {
    json current = claims;
    foreach string part in re `\.`.split(path) {
        if current !is map<json> {
            return ();
        }
        current = current[part];
    }
    return current;
}

isolated function toList(json value, string separator) returns string[] {
    if value is string {
        return splitList(value, separator);
    }
    if value is json[] {
        return from json item in value where item is string select item;
    }
    return [];
}

isolated function splitList(string value, string separator) returns string[] {
    return from string item in re `${separator}`.split(value)
        let string trimmed = item.trim()
        where trimmed != ""
        select trimmed;
}

isolated function unauthorized() returns http:Unauthorized =>
    {body: {code: "UNAUTHORIZED", message: "Missing or invalid credentials"}};
