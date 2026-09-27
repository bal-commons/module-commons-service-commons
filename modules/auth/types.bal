# Listener auth settings, mirroring the workflow module's management.rest configurables.
# With neither JWT nor API key enabled, the service trusts the `x-user-*` headers (development only).
public type AuthConfig record {|
    # Validates bearer JWTs
    boolean enableJwtAuth = false;
    # Expected `iss` claim; empty skips the check
    string jwtIssuer = "";
    # Expected `aud` claim; empty skips the check
    string jwtAudience = "";
    # JWKS endpoint of the IdP
    string jwksUrl = "";
    # Verifies the JWKS endpoint's TLS certificate; turn off only for a self-signed demo IdP
    boolean jwksVerifyTls = true;
    # PEM certificate to validate signatures with instead of `jwksUrl`
    string jwtCertFile = "";
    # Claim holding the user ID; dotted paths address nested claims
    string userIdClaim = "sub";
    # Claim holding the roles, e.g. `groups` or `realm_access.roles`
    string rolesClaim = "groups";
    # Requires the operation's scope in the `scope`/`scp` claim
    boolean enforceScopes = false;
    # Accepts a static API key for service accounts; the caller then acts with every scope
    boolean enableApiKey = false;
    # Header carrying the API key
    string apiKeyHeader = "x-api-key";
    # Expected API key value
    string apiKeyValue = "";
|};

# The caller resolved from a request's credentials.
public type CallerIdentity record {|
    # User ID from `userIdClaim`
    string userId;
    # Roles from `rolesClaim`
    string[] roles = [];
    # Granted OAuth scopes; `*` grants all (API-key callers)
    string[] scopes = [];
|};

# Header carrying the user ID in trusted-header mode and for API-key callers.
public const HEADER_USER_ID = "x-user-id";
# Header carrying comma-separated roles in trusted-header mode and for API-key callers.
public const HEADER_USER_ROLES = "x-user-roles";
# Header carrying space-separated scopes in trusted-header mode; absent grants none.
public const HEADER_USER_SCOPES = "x-user-scopes";
# Query parameter carrying an SSE stream ticket.
public const TICKET_PARAM = "ticket";
# Scope that grants every operation.
public const ALL_SCOPES = "*";
