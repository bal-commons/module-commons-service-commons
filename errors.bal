import ballerina/http;
import ballerina/log;

# Error body returned by every commons service.
public type ErrorBody record {|
    # Stable, machine-readable error code
    string code;
    # Human-readable description
    string message;
|};

# Builds a `400 Bad Request` with an error body.
#
# + message - What was wrong with the request
# + return - The response
public isolated function badRequest(string message) returns http:BadRequest =>
    {body: <ErrorBody>{code: "BAD_REQUEST", message}};

# Builds a `403 Forbidden` with an error body.
#
# + message - Why the caller may not do this
# + return - The response
public isolated function forbidden(string message) returns http:Forbidden =>
    {body: <ErrorBody>{code: "FORBIDDEN", message}};

# Builds a `404 Not Found` with an error body.
#
# + message - What was not found
# + return - The response
public isolated function notFound(string message) returns http:NotFound =>
    {body: <ErrorBody>{code: "NOT_FOUND", message}};

# Builds a `409 Conflict` with an error body.
#
# + message - What conflicted
# + return - The response
public isolated function alreadyExists(string message) returns http:Conflict =>
    {body: <ErrorBody>{code: "CONFLICT", message}};

# Maps errors returned by resources and request binding to `ErrorBody` responses.
public isolated service class ErrorInterceptor {
    *http:ResponseErrorInterceptor;

    isolated remote function interceptResponseError(error err) returns http:BadRequest|http:NotFound|http:InternalServerError {
        if err is http:PayloadBindingError|http:HeaderBindingError|http:QueryParameterBindingError
                |http:PathParameterBindingError {
            return badRequest(err.message());
        }
        if err is http:RequestDispatchingError {
            return notFound(err.message());
        }
        log:printError("Request failed", err);
        http:InternalServerError response = {body: <ErrorBody>{code: "INTERNAL_ERROR", message: err.message()}};
        return response;
    }
}
