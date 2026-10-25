import Foundation

/// Mirrors backend/app/foods.py so logging also works offline (for example on the Watch).
/// The numbers come from shared/foods.json, never from an AI model.
struct FoodEstimate: Hashable, Codable {
    var name: String
    var quantity: Double
    var unit: String
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double
    var confident: Bool

    func asMeal(source: Meal.Source = .voice) -> Meal {
        Meal(name: name.capitalized, quantity: quantity, unit: unit, calories: calories,
             protein: protein, carbs: carbs, fat: fat, source: source)
    }
}

final class FoodDatabase {
    static let shared = FoodDatabase()

    struct Food: Decodable {
        let id: String
        let names: [String]
        let unit: String
        let kcal: Double
        let protein: Double
        let carbs: Double
        let fat: Double
    }
    private struct File: Decodable { let foods: [Food] }

    let foods: [Food]

    init(bundle: Bundle = .main) {
        if let url = bundle.url(forResource: "foods", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let file = try? JSONDecoder().decode(File.self, from: data) {
            foods = file.foods
        } else {
            foods = []
        }
    }

    init(foods: [Food]) { self.foods = foods }

    private static let numberWords: [String: Double] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "half": 0.5, "couple": 2,
    ]
    private static let units: Set<String> = ["piece", "slice", "bowl", "cup", "glass", "teaspoon", "tsp", "handful", "serving"]

    static func singular(_ word: String) -> String {
        let w = word.lowercased()
        if w.count > 3, w.hasSuffix("ies") { return String(w.dropLast(3)) + "y" }
        if w.count > 3, w.hasSuffix("es") {
            let stem = String(w.dropLast(2))
            if ["ch", "sh", "x", "s", "o"].contains(where: { stem.hasSuffix($0) }) { return stem }
        }
        if w.count > 2, w.hasSuffix("s"), !w.hasSuffix("ss") { return String(w.dropLast()) }
        return w
    }

    static func normalise(_ text: String) -> String {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map { singular(String($0)) }
            .joined(separator: " ")
    }

    func find(_ name: String) -> Food? {
        let phrase = " " + Self.normalise(name) + " "
        var best: (length: Int, food: Food)?
        for food in foods {
            for alias in food.names {
                let a = Self.normalise(alias)
                if phrase.contains(" " + a + " "), best == nil || a.count > best!.length {
                    best = (a.count, food)
                }
            }
        }
        return best?.food
    }

    func ground(_ name: String, quantity: Double = 1) -> FoodEstimate {
        guard let food = find(name) else {
            return FoodEstimate(name: name.trimmingCharacters(in: .whitespaces), quantity: quantity,
                                unit: "serving", calories: 0, protein: 0, carbs: 0, fat: 0, confident: false)
        }
        let q = quantity > 0 ? quantity : 1
        func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }
        return FoodEstimate(name: food.id, quantity: q, unit: food.unit,
                            calories: Int((food.kcal * q).rounded()),
                            protein: round1(food.protein * q), carbs: round1(food.carbs * q),
                            fat: round1(food.fat * q), confident: true)
    }

    /// "Log two rotis, one bowl of dal and a cup of curd" -> three estimates.
    func parse(_ text: String) -> [FoodEstimate] {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
        cleaned = cleaned.replacingOccurrences(
            of: #"^(please\s+)?(log|add|i had|i ate|i've had|ive had|i have had|had|ate)\s+"#,
            with: "", options: [.regularExpression, .caseInsensitive])
        for separator in [" and ", " plus ", " with "] {
            cleaned = cleaned.replacingOccurrences(of: separator, with: ",", options: .caseInsensitive)
        }

        var items: [FoodEstimate] = []
        for chunk in cleaned.split(separator: ",") {
            var tokens = chunk.split(separator: " ").map(String.init)
            guard !tokens.isEmpty else { continue }
            var quantity = 1.0
            if let first = tokens.first, let number = Double(first) {
                quantity = number
                tokens.removeFirst()
            } else if let first = tokens.first?.lowercased(), let number = Self.numberWords[first] {
                quantity = number
                tokens.removeFirst()
            }
            if let first = tokens.first, Self.units.contains(Self.singular(first)) { tokens.removeFirst() }
            if tokens.first?.lowercased() == "of" { tokens.removeFirst() }
            guard !tokens.isEmpty else { continue }
            items.append(ground(tokens.joined(separator: " "), quantity: quantity))
        }
        return items
    }
}
