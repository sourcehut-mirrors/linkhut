# Overview

The linkhut API is a way to interact programmatically with your bookmarks, notes and other linkhut data.

Wherever possible the linkhut API uses the same syntax and method names as the [Pinboard API](https://www.pinboard.in/api/).

All API methods are GET requests, even when good REST habits suggest they should use a different verb.

Methods return data in XML format or JSON format based on the value of the `Accept` header or from the value of the 
`_format` request parameter.

## Authentication

There are various ways of authenticating with the linkhut API.

### Personal Access Tokens

The easiest and fastest way to authenticate with linkhut is to [create a personal
access token](https://ln.ht/_/oauth/personal-token). This token will have
unrestricted access to all linkhut APIs and can be used like a normal access token
to authenticate API requests (see [Authenticating API requests](#authenticating-api-requests)).

**Warning**: do not give your personal access tokens to third parties. Any third
party which encourages you to give them a personal access token should instead
develop an OAuth application as described in the next section.

## OAuth Applications

Personal access tokens are suitable for authenticating yourself, but if you
intend to provide software that other sr.ht users can log into, you should
[create an OAuth application](https://ln.ht/_/oauth/register) instead. The OAuth
flow allows end-users to grant your application only the privileges it requires to
execute its duties and to revoke this access at any time. This is accomplished
through an **OAuth exchange**:

1. Direct the user (in a web browser) to a special page on `ln.ht` where we
   present them with the permissions you're asking for, and they can provide consent.
2. The user is redirected back to your application's **base redirect URI**. We
   will add an **exchange token** to the query string.
3. Your application sends an HTTP request directly to `ln.ht` using this
   exchange token and your application credentials to obtain an access token.

To this end, you need to have an HTTP server running somewhere that the user can be
redirected to upon consenting to the permissions you requested. Decide on a URL we can
redirect the user to in your application, and fill out the base redirect URI accordingly.

Upon submitting the form, your **application ID** and **application secret** will be shown
to you. **Record your application secret now**. It will not be shown to you again.

### The OAuth consent page

To start the exchange, direct the user to the following URL:

```none
https://ln.ht/_/oauth/authorize?client_id=<CLIENT_ID>&scopes=<SCOPES>&redirect_uri=<REDIRECT_URI>
```

Provide the following parameters in the query string:

- `client_id`: The application ID assigned to you in the previous step.
- `scopes`: A list of scopes you're requesting — see next section.   
- `redirect_uri`: Your application URI for redirect the user to.

### OAuth scopes

The linkhut API methods require valid tokens for a specific **scope**. A scope is written as: `context:access`. 
Where **context** is the API method (e.g., `posts`, `tags`) and **access** is either `read` or `write` 
depending on whether the operation is merely fetching data, or enabling callers to transform data (e.g., add or edit links).

Scopes enable you to request access only for the minimum access level you require.

### The application redirect

Once the user consents, they will be redirected to your `redirect_uri` updated with
some additional query string parameters you can use for the next steps:

- `code`: An exchange token you can use to obtain an access token in the next step.
- `error`: If present, indicates that an error occurred in the process — see notes.
- `error_description`: If present, a human friendly error string, if that human is an engineer.

Possible values for `error`:

- `invalid_grant`
- `invalid_redirect`
- `invalid_scope`
- `user_declined`

**Important**: the user is able to **edit** the scopes you've requested before
consenting. You must handle the case where the scopes returned in the redirect
do not match the scopes you requested.

### Obtaining an access token

Once your application retrieves the exchange token from the redirect, you can
submit an HTTP POST request to `https://api.ln.ht/v1/oauth/token` with the following parameters:

- `grant_type`: Set to: `authorization_code` 
- `client_id`: The application ID assigned to you when you registered the application.
- `client_secret`: The application secret assigned to you when you registered the application.
- `code`: The exchange token issued in the previous step.

You will receive a response like this:

```json
{
  "token_type": "bearer",
  "access_token": "your access token",
  "created_at": "%Y-%m-%dT%H:%M:%S",
  "expires_in": 31536000,
  "refresh_token": "your refresh token",
  "scope": "list of OAuth scopes the user consented to"
}
```

You can now use this token for [Authenticating API requests](#authenticating-api-requests).

### Authenticating API requests

Authenticating your API request is simple once you have an access token. 
You just need to set the `Authorization` header to `Bearer <your-access-token>`.

For example:

```shell
$ curl \
-H Authorization:'Bearer <your-access-token>' \
https://api.ln.ht/v1/posts/get
```

Alternatively, you can also include the token as the query parameter `auth_token`.

For example:

```shell
$ curl 'https://api.ln.ht/v1/posts/get?auth_token=<your-access-token>'
```
### Refreshing access tokens

There's no mechanism to extend the expiration time of an access token, instead you can request a new access token by 
using the `refresh_token` provided when obtaining the original access token.

To request a new access token send another POST request to `https://api.ln.ht/v1/oauth/token` with the following parameters:

- `grant_type`: Set to: `refresh_token`
- `client_id`: The application ID assigned to you when you registered the application.
- `client_secret`: The application secret assigned to you when you registered the application.
- `refresh_token`: The refresh token issued in the previous step.

**Note**: Requesting a new access token will automatically revoke the previous one, regardless of its original expiration time.

## Etiquette

* Please wait **at least one second** between HTTP queries, or you are likely to get automatically throttled. If you are
  releasing a library to access the API, you **must** do this.
* Please watch for 500 or 999 errors and back-off appropriately. It means that you have been throttled.
* Please set your User-Agent to something identifiable. The default identifiers (e.g.: `Java/1.8.0_191`, `lwp-perl`) 
  tend to get banned from time to time.
* If you are releasing software, or a service for other people to use, your software or service **must not** add any 
  links without a user’s explicit direction. Likewise, you **must not** modify any urls except under the user’s explicit 
  direction.

## Methods

* [Posts](posts.md)
* [Tags](tags.md)
