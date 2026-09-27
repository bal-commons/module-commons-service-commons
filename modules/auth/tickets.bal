import ballerina/uuid;
import commons/service_commons;

# Single-use, short-lived tickets that let `EventSource` authenticate an SSE stream through the URL.
public isolated class TicketStore {
    private final int ttlMillis;
    private final map<[CallerIdentity, int]> tickets = {};

    # Creates a ticket store.
    #
    # + ttlSeconds - How long an unredeemed ticket stays valid
    public isolated function init(int ttlSeconds = 60) {
        self.ttlMillis = ttlSeconds * 1000;
    }

    # Issues a ticket for a caller.
    #
    # + caller - The authenticated caller the ticket stands for
    # + return - The ticket
    public isolated function issue(CallerIdentity caller) returns string {
        string ticket = uuid:createType4AsString();
        int now = service_commons:nowMillis();
        lock {
            foreach [string, [CallerIdentity, int]] [key, [_, expiry]] in self.tickets.entries() {
                if expiry < now {
                    _ = self.tickets.remove(key);
                }
            }
            self.tickets[ticket] = [caller.clone(), now + self.ttlMillis];
        }
        return ticket;
    }

    # Redeems a ticket; a ticket works once.
    #
    # + ticket - The ticket
    # + return - The caller it was issued for, or `()` if it is unknown, used or expired
    public isolated function redeem(string ticket) returns CallerIdentity? {
        lock {
            [CallerIdentity, int]? entry = self.tickets.removeIfHasKey(ticket);
            if entry is () || entry[1] <= service_commons:nowMillis() {
                return ();
            }
            return entry[0].clone();
        }
    }

    # Ticket lifetime in seconds.
    #
    # + return - The lifetime
    public isolated function ttlSeconds() returns int => self.ttlMillis / 1000;
}
