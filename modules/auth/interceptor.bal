import ballerina/http;

const CALLER_KEY = "commons.auth.caller";

# Request interceptor that resolves the caller and stores it in the request context.
# A `ticket` query parameter authenticates as the caller the ticket was issued to.
public isolated service class AuthInterceptor {
    *http:RequestInterceptor;

    private final Authenticator authenticator;
    private final TicketStore tickets;

    # Creates the interceptor.
    #
    # + authenticator - Resolves callers from credentials
    # + tickets - Redeems SSE stream tickets
    public isolated function init(Authenticator authenticator, TicketStore tickets) {
        self.authenticator = authenticator;
        self.tickets = tickets;
    }

    isolated resource function 'default [string... path](http:RequestContext ctx, http:Request req)
            returns http:NextService|http:Unauthorized|error? {
        if req.method == http:OPTIONS {
            return ctx.next();
        }
        string? ticket = req.getQueryParamValue(TICKET_PARAM);
        CallerIdentity|http:Unauthorized caller;
        if ticket is string {
            CallerIdentity? redeemed = self.tickets.redeem(ticket);
            caller = redeemed ?: <http:Unauthorized>{body: {code: "UNAUTHORIZED", message: "Unknown or expired ticket"}};
        } else {
            caller = self.authenticator.authenticate(req);
        }
        if caller is http:Unauthorized {
            return caller;
        }
        ctx.set(CALLER_KEY, caller.cloneReadOnly());
        return ctx.next();
    }
}

# Returns the caller resolved by `AuthInterceptor`.
#
# + ctx - The request context
# + return - The caller, or an error if the interceptor did not run
public isolated function callerOf(http:RequestContext ctx) returns CallerIdentity|error {
    return ctx.getWithType(CALLER_KEY);
}
