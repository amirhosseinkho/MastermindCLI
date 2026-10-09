> Persian version: [README.fa.md](README.fa.md)

# Project report: Mastermind (Swift / CLI / Ubuntu WSL)

**Amirhossein Khoshbakht** (student ID 99105429)

## Environment

* **Platform:** Ubuntu (WSL) on Windows
* **Swift:** `Swift version 6.1.2 (swift-6.1.2-RELEASE)`, target `x86_64-unknown-linux-gnu`
* **Networking prerequisites (if needed):**

  ```bash
  sudo apt-get update
  sudo apt-get install -y ca-certificates libcurl4-openssl-dev
  sudo update-ca-certificates
  ```

---

## Part 1: A terminal Mastermind game

### 1) Create and build the project

```bash
# Create the folder and an executable Swift package
mkdir MastermindCLI && cd MastermindCLI
swift package init --type executable
```

### 2) Add the code (all messages and strings are in English)

Replace `main.swift` with the code below. If your project has `Sources/main.swift`, put it there; if it uses `Sources/<TargetName>/main.swift`, replace that file instead.

```swift
// Sources/main.swift  (or Sources/<TargetName>/main.swift)

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// --- Models ---
struct CreateGameResponse: Codable { let game_id: String }
struct GuessRequest: Codable { let game_id: String; let guess: String }
struct GuessResponse: Codable { let black: Int; let white: Int }
struct ErrorResponse: Codable, Error { let error: String }

// --- Errors ---
enum APIError: Error, LocalizedError {
    case badStatus(Int, String)
    case invalidURL
    var errorDescription: String? {
        switch self {
        case .badStatus(let code, let msg): return "HTTP \(code): \(msg)"
        case .invalidURL: return "Invalid URL"
        }
    }
}

// --- HTTP Client ---
final class MastermindAPI {
    private let base = URL(string: "https://mastermind.darkube.app")!
    private let session: URLSession = {
        #if canImport(FoundationNetworking)
        // Linux/WSL path: use a configured session (timeouts)
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
        #else
        // Apple platforms: shared session is fine
        return URLSession.shared
        #endif
    }()

    func createGame() async throws -> String {
        var req = URLRequest(url: base.appendingPathComponent("game"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "accept")

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.badStatus(-1, "No response")
        }
        if (200..<300).contains(http.statusCode) {
            let obj = try JSONDecoder().decode(CreateGameResponse.self, from: data)
            return obj.game_id
        } else if let err = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
            throw APIError.badStatus(http.statusCode, err.error)
        } else {
            throw APIError.badStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    func guess(gameID: String, guess: String) async throws -> GuessResponse {
        var req = URLRequest(url: base.appendingPathComponent("guess"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "accept")
        req.httpBody = try JSONEncoder().encode(GuessRequest(game_id: gameID, guess: guess))

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.badStatus(-1, "No response")
        }
        if (200..<300).contains(http.statusCode) {
            return try JSONDecoder().decode(GuessResponse.self, from: data)
        } else if let err = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
            throw APIError.badStatus(http.statusCode, err.error)
        } else {
            throw APIError.badStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    func deleteGame(id: String) async {
        var req = URLRequest(url: base.appendingPathComponent("game").appendingPathComponent(id))
        req.httpMethod = "DELETE"
        _ = try? await session.data(for: req) // Best-effort cleanup
    }
}

// --- CLI App ---
@main
struct App {
    static func main() async {
        print("🎯 Mastermind (CLI) — type 'exit' at any time to quit")
        let api = MastermindAPI()
        var gameID = ""

        do {
            gameID = try await api.createGame()
            print("New game started. Game ID: \(gameID)")
            print("Rule: guess a 4-digit code, each digit 1–6. Example: 1234")

            var attempt = 1
            while true {
                guard let guess = prompt("Guess #\(attempt): ") else {
                    print("Input ended (EOF). Exiting…")
                    if !gameID.isEmpty { await api.deleteGame(id: gameID) }
                    return
                }

                if guess.lowercased() == "exit" {
                    print("Exiting…")
                    if !gameID.isEmpty { await api.deleteGame(id: gameID) }
                    return
                }

                guard validateGuess(guess) else {
                    print("Invalid input. Enter exactly 4 digits, each between 1 and 6 (e.g., 1234).")
                    continue
                }

                do {
                    let res = try await api.guess(gameID: gameID, guess: guess)
                    print("Result: \(res.black)B \(res.white)W")
                    if res.black == 4 {
                        print("🏆 Congrats! You cracked the code. Game over.")
                        if !gameID.isEmpty { await api.deleteGame(id: gameID) }
                        return
                    }
                    attempt += 1
                } catch {
                    print("❌ Guess failed: \(error.localizedDescription)")
                    print("You can try again or type 'exit' to quit.")
                }
            }
        } catch {
            print("❌ Failed to start a new game: \(error.localizedDescription)")
            print("Please check your internet/firewall and try again.")
        }
    }

    // Simple prompt/validate utilities
    static func prompt(_ message: String) -> String? {
        FileHandle.standardOutput.write(Data(message.utf8))
        return readLine(strippingNewline: true)
    }

    static func validateGuess(_ s: String) -> Bool {
        guard s.count == 4 else { return false }
        for ch in s {
            if ch < "1" || ch > "6" { return false }
        }
        return true
    }
}
```

### 3) Run

```bash
# Development build
swift run

# Release build (faster)
swift build -c release
# The binary is usually named after the package:
./.build/release/MastermindCLI
```

### 4) Sample output (from an actual run)

```
🎯 Mastermind (CLI) — type 'exit' at any time to quit
New game started. Game ID: dcrfovti6zus
Rule: guess a 4-digit code, each digit 1–6. Example: 1234
Guess #1: 1234
Result: 0B 2W
Guess #2: 4321
Result: 0B 2W
Guess #3: 3456
Result: 2B 1W
Guess #4: 3451
Result: 2B 0W
Guess #5: 3426
Result: 1B 2W
Guess #6: 6451
Result: 3B 0W
Guess #7: 6452
Result: 4B 0W
🏆 Congrats! You cracked the code. Game over.
```

### 5) How the code works

* **Networking on Linux:** on Linux/WSL, `FoundationNetworking` must be imported for `URLSession` and `URLRequest` to be available, which is why the code uses `#if canImport(FoundationNetworking)`.
* **Code structure:**

  * **Models:** four simple request/response models that follow the API documentation (`CreateGameResponse`, `GuessRequest`, `GuessResponse`, `ErrorResponse`).
  * **MastermindAPI:** a small HTTP client built on `URLSession` (15-second timeout) with three methods:

    * `createGame()` → `POST /game`, returns the `game_id`
    * `guess(gameID, guess)` → `POST /guess` with a JSON body, reads `black`/`white`
    * `deleteGame(id)` → `DELETE /game/{id}` for best-effort cleanup
  * **Error handling:** if the HTTP status is not 2xx, the client tries to decode an `ErrorResponse` and return a meaningful message; otherwise it shows the raw response text.
  * **CLI loop:** after creating a game, the program runs a simple input/output loop that:

    * reads input with `prompt`;
    * quits at any time on `exit`, deleting the game first;
    * uses `validateGuess` to require exactly 4 digits, each between 1 and 6;
    * prints each result as `xB yW` and stops when `black == 4`.
* **Plain, clear I/O:** messages and errors are in English so the program reads clearly in a standard English environment.
* **Cleanup:** before exiting, whether normally or after an error, the program calls `DELETE` if it has a `gameID`.

### 6) Troubleshooting

* If you get `URLSession`/`URLRequest` errors, make sure `FoundationNetworking` is imported (as the code above does).
* If you get TLS/curl errors, install `ca-certificates` and `libcurl4-openssl-dev` as shown above.
* If `swift run` still runs an old version, check that `main.swift` is in the right folder (`Sources/main.swift` or `Sources/<Target>/main.swift`).

---

## Part 2: API analysis (at most three paragraphs)

**Current state.** The current API is simple and easy to follow: `POST /game` creates a new game and returns a `game_id`, `POST /guess` with `{game_id, guess}` returns the number of **B** (black) and **W** (white) pegs, and `DELETE /game/{gameID}` deletes a game. The cURL example in the documentation has a doubled scheme (`https://https://...`), and the UI itself shows a CORS error, so the "Try it" examples in Swagger do not work. The input constraints (the exact guess pattern and the policy on repeated digits) are not stated, and the guess response does not report the game state (is the game over? how many attempts have been used? what is the history?).

**Suggested improvements.** Fix the OpenAPI 3 documentation and add working examples; configure CORS correctly and add a health endpoint (`/health`). `POST /game` should return `201 Created` with a `Location: /games/{id}` header. The `guess` body should carry the constraint `pattern: "^[1-6]{4}$"`, and the response should include, besides `black`/`white`, `status: ongoing|won|lost`, `attempts_used`/`attempts_remaining`, and `finished_at` once the game ends. Errors should follow one format, `{ code, message, details, request_id }`, with precise HTTP status codes (`400` malformed JSON, `404` unknown game, `422` invalid guess, `429` rate limit). Game IDs should be UUIDv4, and abandoned games should expire after a TTL.

**Redesign from scratch.** A versioned, resource-oriented API: `POST /v1/games` (with options for difficulty, code length and alphabet), `GET /v1/games/{id}` for live state, `POST /v1/games/{id}/guesses` to submit a guess (with an `Idempotency-Key` header), `GET /v1/games/{id}/guesses` for paginated history, and `DELETE /v1/games/{id}` to abandon a game. After `won` or `lost`, new guesses should be rejected with `409 Conflict`. Adding request tracing (`X-Request-ID`), rate limiting, and client examples (cURL/Swift/JS) would complete the documentation and make the API more dependable for web, CLI and mobile clients.
