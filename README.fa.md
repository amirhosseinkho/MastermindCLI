> English version: [README.md](README.md)


# گزارش پروژه — Mastermind (Swift / CLI / Ubuntu WSL)

## امیرحسین خوشبخت

## شماره دانشجویی: 99105429

## مشخصات محیط اجرا

* **Platform:** Ubuntu (WSL) روی ویندوز
* **Swift:** `Swift version 6.1.2 (swift-6.1.2-RELEASE)` — Target: `x86_64-unknown-linux-gnu`
* **Networking prerequisites (در صورت نیاز):**

  ```bash
  sudo apt-get update
  sudo apt-get install -y ca-certificates libcurl4-openssl-dev
  sudo update-ca-certificates
  ```

---

## بخش اول: پیاده‌سازی بازی Mastermind در ترمینال

### 1) ایجاد پروژه و ساخت

```bash
# ساخت پوشه و ایجاد پکیج اجرایی Swift
mkdir MastermindCLI && cd MastermindCLI
swift package init --type executable
```

### 2) قرار دادن کد (همه پیام‌ها و رشته‌ها انگلیسی)

فایل `main.swift` را جایگزین کنید. اگر پروژه‌تان `Sources/main.swift` دارد همان را بنویسید؛ اگر زیر `Sources/<TargetName>/main.swift` است، همان را جایگزین کنید.

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

### 3) اجرا

```bash
# حالت توسعه
swift run

# حالت انتشار (سریع‌تر)
swift build -c release
# نام باینری معمولاً نام پکیج است:
./.build/release/MastermindCLI
```

### 4) خروجی نمونه (ثبت‌شده در اجرای شما)

(نمونهٔ واقعی شما)

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

### 5) توضیح کد (خلاصه و دقیق)

* **Networking روی لینوکس:** روی Linux/WSL باید `FoundationNetworking` را ایمپورت کنیم تا `URLSession/URLRequest` قابل استفاده باشند؛ به همین دلیل از `#if canImport(FoundationNetworking)` استفاده شده است.
* **ساختار کد:**

  * **Models:** مطابق مستندات، چهار مدل ساده برای درخواست/پاسخ (`CreateGameResponse`, `GuessRequest`, `GuessResponse`, `ErrorResponse`).
  * **MastermindAPI:** یک کلاینت HTTP کوچک با `URLSession` (تایم‌اوت ۱۵ثانیه)، سه متد:

    * `createGame()` → `POST /game` و دریافت `game_id`
    * `guess(gameID, guess)` → `POST /guess` با بدنهٔ JSON و خواندن `black/white`
    * `deleteGame(id)` → `DELETE /game/{id}` برای پاکسازی (best-effort)
  * **Error handling:** اگر وضعیت HTTP خارج از 2xx باشد، تلاش می‌کنیم `ErrorResponse` را دیکد کنیم و پیام معنادار برگردانیم؛ در غیر این‌صورت متن خام را نشان می‌دهیم.
  * **CLI Loop:** برنامه پس از ساخت بازی، در یک حلقهٔ ورودی-خروجی ساده:

    * ورودی را با `prompt` می‌گیرد.
    * دستور `exit` هر لحظه برنامه را با حذف بازی می‌بندد.
    * با `validateGuess` اجبار می‌کند حدس دقیقاً ۴ رقم و هر رقم بین ۱ تا ۶ باشد.
    * با دریافت پاسخ، نتیجه را به شکل `xB yW` چاپ می‌کند و با `black == 4` خاتمه می‌دهد.
* **I/O ساده و واضح:** پیام‌ها و خطاها انگلیسی‌اند تا پروژه روی محیط انگلیسی استاندارد شفاف باشد.
* **Clean-up:** قبل از خروج (نرمال یا خطایی) در صورت داشتن `gameID` فراخوانی `DELETE` انجام می‌شود.

### 6) نکات عیب‌یابی

* اگر خطاهای `URLSession`/`URLRequest` داشتید: **حتماً** `FoundationNetworking` را ایمپورت کنید (همین‌طور که در کد انجام شده است).
* اگر خطای TLS/CURL دارید: نصب `ca-certificates` و `libcurl4-openssl-dev` در بالا.
* اگر `swift run` همچنان نسخهٔ قدیمی را اجرا می‌کند: پوشهٔ درست `main.swift` را بررسی کنید (`Sources/main.swift` یا `Sources/<Target>/main.swift`).

---

## بخش دوم: تحلیل API (حداکثر سه پاراگراف)

**تحلیل وضعیت فعلی.** API فعلی ساده و قابل‌درک است: `POST /game` بازی جدید می‌سازد و `game_id` می‌دهد، `POST /guess` با `{game_id, guess}` تعداد **B**‌(black) و **W**‌(white) را برمی‌گرداند و `DELETE /game/{gameID}` برای حذف است. در مستندات، نمونهٔ cURL اشتباه دوبل‌شدن scheme دارد (`https://https://...`) و حتی در خود UI خطای CORS دیده می‌شود؛ این‌ها باعث می‌شود نمونه‌های “Try it” در Swagger کار نکنند. همچنین قیود ورودی (الگوی دقیق حدس، سیاست ارقام تکراری) صریح بیان نشده و پاسخ حدس وضعیت بازی را مشخص نمی‌کند (آیا تمام شده؟ چند تلاش مصرف شده؟ تاریخچه؟).

**پیشنهادهای بهبود.** مستندات OpenAPI 3 را اصلاح کرده و نمونه‌های عملی ارائه شود؛ CORS صحیح و endpoint سلامت (`/health`) افزوده گردد. `POST /game` بهتر است `201 Created` با هدر `Location: /games/{id}` بدهد. برای بدنهٔ `guess` قید `pattern: "^[1-6]{4}$"` گذاشته شود و پاسخ علاوه‌بر `black/white` شامل `status: ongoing|won|lost`، `attempts_used/remaining` و در صورت پایان `finished_at` باشد. خطاها با الگوی یکنواخت `{ code, message, details, request_id }` بازگردند و از کدهای HTTP دقیق (`400` JSON بدفرم، `404` بازی ناموجود، `422` حدس نامعتبر، `429` نرخ زیاد) استفاده شود. روی شناسه‌ها از UUIDv4 و روی بازی‌های رها‌شده TTL تعریف شود.

**طراحی پیشنهادی از نو.** نسخه‌دار و منبع‌محور: `POST /v1/games` (با گزینه‌های دشواری/طول/الفبا)، `GET /v1/games/{id}` برای وضعیت زنده، `POST /v1/games/{id}/guesses` برای ثبت حدس (با هدر `Idempotency-Key`)، و `GET /v1/games/{id}/guesses` برای تاریخچه صفحه‌بندی‌شده؛ `DELETE /v1/games/{id}` برای انصراف. پس از `won|lost`، حدس جدید با `409 Conflict` رد شود. افزودن ردیابی (`X-Request-ID`)، محدودسازی نرخ، و نمونه‌کدهای کلاینت (cURL/Swift/JS) مستندسازی را کامل و مصرف API را برای وب/CLI/موبایل پایدارتر می‌کند.

