import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct CreateGameResponse: Codable { let game_id: String }
struct GuessRequest: Codable { let game_id: String; let guess: String }
struct GuessResponse: Codable { let black: Int; let white: Int }
struct ErrorResponse: Codable, Error { let error: String }

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

final class MastermindAPI {
    private let base = URL(string: "https://mastermind.darkube.app")!
    private let session: URLSession = {
        #if canImport(FoundationNetworking)
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
        #else
        return URLSession.shared
        #endif
    }()

    func createGame() async throws -> String {
        var req = URLRequest(url: base.appendingPathComponent("game"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "accept")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.badStatus(-1, "No response") }
        if (200..<300).contains(http.statusCode) {
            let obj = try JSONDecoder().decode(CreateGameResponse.self, from: data)
            return obj.game_id
        } else {
            if let err = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw APIError.badStatus(http.statusCode, err.error)
            }
            throw APIError.badStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    func guess(gameID: String, guess: String) async throws -> GuessResponse {
        var req = URLRequest(url: base.appendingPathComponent("guess"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "accept")
        let body = GuessRequest(game_id: gameID, guess: guess)
        req.httpBody = try JSONEncoder().encode(body)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.badStatus(-1, "No response") }
        if (200..<300).contains(http.statusCode) {
            return try JSONDecoder().decode(GuessResponse.self, from: data)
        } else {
            if let err = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw APIError.badStatus(http.statusCode, err.error)
            }
            throw APIError.badStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    func deleteGame(id: String) async {
        var req = URLRequest(url: base.appendingPathComponent("game").appendingPathComponent(id))
        req.httpMethod = "DELETE"
        _ = try? await session.data(for: req)
    }
}

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
