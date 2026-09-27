import ballerina/lang.runtime;
import ballerina/test;

@test:Config
function newIdIsUlidShaped() {
    string id = newId();
    test:assertEquals(id.length(), 26);
    test:assertTrue(re `[0-9A-HJKMNP-TV-Z]{26}`.isFullMatch(id));
}

@test:Config
function newIdSortsByTime() {
    string first = newId();
    runtime:sleep(0.01);
    test:assertTrue(newId() > first);
}

@test:Config
function isoRoundTrips() returns error? {
    int millis = 1790000000123;
    test:assertEquals(check fromIso(toIso(millis)), millis);
}
