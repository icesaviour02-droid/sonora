# Why the current YouTube login is different from Safari Google sign-in

Checked against the actual desktop implementation and official API documentation on 26 October 2026.

## Existing desktop behavior

`crates/music/src/youtube/mod.rs` registers `SignIn::Anonymous` and `SignIn::Secret`. Its browser
sign-in window loads the provider's page and extracts proof cookies. Account verification uses
`YtMusic::with_cookies`, account index/channel and YouTube's profile endpoint. It does not register
a Google OAuth application for each listener. “Guest” is the YouTube provider's anonymous mode.

The iPhone core currently uses that same pinned client's cookie authentication. An ephemeral
WKWebView can expose its own cookie store to the app, so it was used for desktop-style session
import. It does not share existing Safari logins, and Google may reject embedded login. That is
not equivalent to the commercial Google OAuth sign-in experience the user requests.

## Correct system authentication UI

ASWebAuthenticationSession is the system authentication sheet. A registered OAuth client starts
Google authorization with a redirect URI and PKCE, then receives an authorization callback and
exchanges the code for tokens. A non-ephemeral session can use browser sign-in state. This API
returns a callback URL, not Safari's YouTube session cookies. SFSafariViewController is also not
a mechanism for reading the user's private Safari cookie jar.

Simply replacing WKWebView with either Safari API would leave the current provider without the
cookies it expects. A Google Cloud project/client ID alone does not make the current cookie-only
YouTube Music client accept OAuth bearer tokens. Do not add a fake “connected” state or a Safari
button that cannot complete provider authentication.

## Current user's preference and next implementation requirement

The user has no Google Cloud project and does not want developer setup merely to listen.
Prioritize reliable anonymous/Guest playback and the existing local-file path now. Completing
commercial Safari account sign-in requires an OAuth-compatible provider adapter, a registered
Google OAuth client/redirect configuration, secure token refresh/storage and real-account testing.
No such registration or accepted OAuth adapter exists in this checkout. Do not claim this is fixed.
Do not ask the user to create a Cloud project as if that alone solved YouTube Music authentication.

## Official references

- https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession
- https://developers.google.com/youtube/v3/guides/auth/installed-apps
- https://developers.google.com/identity/protocols/oauth2/native-app

These documents describe system OAuth authentication. They do not promise access to all unofficial
YouTube Music cookie-authenticated endpoints or authorize extraction of Safari cookies.
