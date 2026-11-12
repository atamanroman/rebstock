# MCP OAuth setup

MCP is disabled when `mcp` is absent or `null`.
Its bearer authentication is independent of the web application's single-user and forward-auth modes.
The following settings prepare the public resource `https://rebstock.neonforest.org/mcp` for the pre-registered public client `rebstock-codex`.
Public discovery at `https://id.neonforest.org/.well-known/openid-configuration` was checked on 2026-11-08 and advertised the issuer and JWKS URI below.
The deployed provider did not yet advertise `rebstock:mcp`.

Add this object to the Rebstock JSON configuration:

```json
{
  "mcp": {
    "resource": "https://rebstock.neonforest.org/mcp",
    "issuer": "https://id.neonforest.org",
    "jwks_uri": "https://id.neonforest.org/jwks.json",
    "client_id": "rebstock-codex",
    "scope": "rebstock:mcp",
    "username_claim": "preferred_username"
  }
}
```

The equivalent NixOS service option is:

```nix
services.rebstock.mcp = {
  resource = "https://rebstock.neonforest.org/mcp";
  issuer = "https://id.neonforest.org";
  jwksUri = "https://id.neonforest.org/jwks.json";
  clientId = "rebstock-codex";
  scope = "rebstock:mcp";
  usernameClaim = "preferred_username";
};
```

Register the client and scope in Authelia before enabling this configuration.
Use the existing issuer signing key and the existing `private_two_factor` authorization policy where those are already configured.
Merge these entries into the existing `identity_providers.oidc` configuration:

```yaml
identity_providers:
  oidc:
    scopes:
      'rebstock:mcp':
        claims:
          - 'preferred_username'
    claims_policies:
      rebstock_mcp:
        access_token:
          - 'preferred_username'
    clients:
      - client_id: 'rebstock-codex'
        client_name: 'Rebstock MCP for Codex'
        public: true
        authorization_policy: 'private_two_factor'
        require_pkce: true
        pkce_challenge_method: 'S256'
        redirect_uris:
          - 'http://127.0.0.1:17933/callback'
        audience:
          - 'https://rebstock.neonforest.org/mcp'
        requested_audience_mode: 'explicit'
        scopes:
          - 'openid'
          - 'offline_access'
          - 'rebstock:mcp'
        claims_policy: 'rebstock_mcp'
        response_types:
          - 'code'
        grant_types:
          - 'authorization_code'
          - 'refresh_token'
        consent_mode: 'explicit'
        access_token_signed_response_alg: 'RS256'
        token_endpoint_auth_method: 'none'
```

The matching Codex configuration below fixes both the callback URI and listener port.
Authelia's public discovery was checked on 2026-11-09 and advertises `authorization_response_iss_parameter_supported: true`, which allows Codex to reuse this explicit callback for a pre-registered client.
If using a different issuer or callback, register the exact URI selected by Codex and keep the listener port consistent.
Leave the client secret unset for this public client.
Authelia supports custom scopes, copying granted claims into access tokens, explicit resource audiences, and signed JWT access tokens through its [provider options](https://www.authelia.com/configuration/identity-providers/openid-connect/provider/) and [client options](https://www.authelia.com/configuration/identity-providers/openid-connect/clients/).
Verify that the minted access token has `typ: at+jwt`, `alg: RS256`, the expected `iss`, an `aud` containing the MCP resource, `client_id: rebstock-codex`, the granted `rebstock:mcp` scope (`scope` string or Authelia's `scp` array), a future integer `exp`, and a nonempty `preferred_username` matching the intended Rebstock username.
ID tokens and opaque access tokens do not satisfy this boundary.

After registration and deployment, add the following server to the configuration source that supplies your Codex `config.toml`, following the [official OAuth connection guidance](https://learn.chatgpt.com/docs/extend/mcp#oauth-client-registration-and-callbacks).
The client ID is public and this configuration contains no client secret.

```toml
[mcp_servers.rebstock]
url = "https://rebstock.neonforest.org/mcp"
oauth_resource = "https://rebstock.neonforest.org/mcp"
scopes = ["rebstock:mcp", "openid", "offline_access"]
tool_timeout_sec = 240

[mcp_servers.rebstock.oauth]
client_id = "rebstock-codex"
callback_url = "http://127.0.0.1:17933/callback"
callback_port = 17933
```

Request the published scope when logging in:

```sh
codex mcp login rebstock
```

Configure the reverse proxy to pass `/mcp` and `/.well-known/oauth-protected-resource/mcp` to Rebstock without web forward-auth redirects.
Keep the remaining web routes under their existing authentication policy.
The protected-resource metadata publishes the configured resource, issuer, and scope.
Bearer challenges identify that metadata endpoint.
A missing or invalid token receives `401`, a valid token without the required scope receives `403`, and unavailable signing keys receive `503` with `Retry-After`.

The verifier fetches only the configured JWKS URI, verifies TLS certificates and hostnames, disables redirects, bounds streamed JWKS bodies to 256 KiB, and uses a two-second deadline.
On Erlang 28, the native HTTP client buffers unsuccessful HTTP response bodies internally before returning them; those responses are rejected, but their transient buffering is limited by the deadline rather than the streamed-body size check.
Erlang 29 additionally enforces the body limit inside the HTTP client.
Plain HTTP is accepted only for explicitly configured `127.0.0.1` or `::1` fixtures.
The in-memory cache holds up to eight JWKS endpoints for five minutes and refreshes on an unknown key ID, with five seconds between repeated unknown-key refreshes.
Failed fetches are cached for five seconds, and a failed refresh preserves still-valid cached keys.
Removing a signing key takes effect when its cached set expires.
JWT validation does not check immediate access-token revocation, so configure a suitably short access-token lifespan at the provider.
Origin headers must equal the public resource's origin exactly; requests without Origin are supported for native clients.

Local signed-token tests cover the resource-server checks.
A deployed browser login, consent, callback, refresh, and end-to-end Codex tool call still need live verification after the provider and reverse-proxy configuration is applied.
