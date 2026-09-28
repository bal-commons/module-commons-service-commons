// How a component authenticates to a commons service. The app supplies it once; components ask it for headers.
export interface AuthAdapter {
  headers(): Record<string, string> | Promise<Record<string, string>>;
  // Called when a service answers 401, e.g. to send the user to sign in again.
  onUnauthorized?(): void;
}

// Bearer tokens from the app's own OIDC client.
export function bearer(getToken: () => string | undefined | null | Promise<string | undefined | null>,
    onUnauthorized?: () => void): AuthAdapter {
  return {
    async headers(): Promise<Record<string, string>> {
      const token = await getToken();
      return token ? {Authorization: `Bearer ${token}`} : {};
    },
    onUnauthorized
  };
}

// Trusted identity headers, for services running without an identity provider (development only).
export function devUser(userId: string, roles: string[] = [], scopes: string[] = []): AuthAdapter {
  return {
    headers: () => ({
      "x-user-id": userId,
      "x-user-roles": roles.join(","),
      ...(scopes.length ? {"x-user-scopes": scopes.join(" ")} : {})
    })
  };
}

const NO_AUTH: AuthAdapter = {headers: () => ({})};

// Shared on globalThis so every bal-commons package on the page sees the same default, even if bundled twice.
const registry = globalThis as {__balCommonsAuth?: AuthAdapter};

// Sets the adapter every component uses unless it is given its own `auth` property.
export function configureAuth(auth: AuthAdapter): void {
  registry.__balCommonsAuth = auth;
}

export function defaultAuth(): AuthAdapter {
  return registry.__balCommonsAuth ?? NO_AUTH;
}
