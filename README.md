# Reactor

Swift client for Reactor. Auth, a query builder, file storage, and functions for iOS 17 and macOS 14.

```swift
.package(url: "https://github.com/reactor-cloud/reactor-swift", exact: "1.26.09-beta.2")
```

[reactor.cloud](https://www.reactor.cloud) · [docs](https://github.com/reactor-cloud/reactor/blob/v1.26.09-beta.2/docs/clients/swift.md)

```swift
import Reactor

let reactor = ReactorClient(
  url: "https://<ref>.example.com",
  anonKey: anonKey,
  sessionStore: KeychainSessionStore()
)

let session = try await reactor.auth.signInWithPassword(email: email, password: password)

let rows = try await reactor.from("todos")
  .select()
  .eq("user_id", session.user.id)
  .order("created_at", ascending: false)
  .execute()

try await reactor.storage.from("files").upload(path: path, data: data, contentType: "text/plain")
let result = try await reactor.functions.invoke("ping", body: .object(["hello": .string("world")]))
```

| Surface | Call |
| --- | --- |
| Auth | `reactor.auth` — sign up, password, session, sign out |
| Data | `reactor.from(table)` — select, insert, update, delete |
| Storage | `reactor.storage.from(bucket)` — upload and download |
| Functions | `reactor.functions.invoke(name)` |

`sessionStore` defaults to memory. `KeychainSessionStore` keeps the session under `lab.reactor.session`. The query builder covers the calls a first app needs. Use HTTP for the rest of PostgREST. `signInWithOAuth(provider:redirectTo:)` returns the authorize URL. `signUp` returns `AuthOutcome`.

The product name is `Reactor`. Tag `v1.26.09-beta.2`.

## License

You can use Reactor as the backend for as many personal or commercial projects as you want. The license only restricts offering it as a competing hosted service.

Business Source License 1.1. Copyright 2026 AtomicoLabs SL and Claudio del Conde. See [LICENSE](LICENSE).
