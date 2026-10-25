import SwiftUI

struct FoodView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showAdd = false

    private struct MealGroup: Identifiable {
        let id: String
        let meals: [Meal]
        var calories: Int { meals.reduce(0) { $0 + $1.calories } }
    }

    private var groups: [MealGroup] {
        let calendar = Calendar.current
        func bucket(_ meal: Meal) -> String {
            switch calendar.component(.hour, from: meal.date) {
            case ..<11: return "Breakfast"
            case 11..<16: return "Lunch"
            case 16..<19: return "Snacks"
            default: return "Dinner"
            }
        }
        let grouped = Dictionary(grouping: store.todaysMeals, by: bucket)
        return ["Breakfast", "Lunch", "Snacks", "Dinner"].compactMap { name in
            grouped[name].map { MealGroup(id: name, meals: $0) }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    HStack(alignment: .bottom) {
                        ScreenHeader(eyebrow: Date().formatted(.dateTime.weekday(.wide).day().month(.wide)), title: "Food diary")
                        Text("\(store.caloriesToday) kcal").font(.subheadline.weight(.heavy)).foregroundColor(Pulse.fuel)
                    }
                    if groups.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Nothing logged yet").font(.headline.weight(.heavy))
                                Text("Tap the mic and say what you ate, or add it by hand.")
                                    .font(.subheadline).foregroundColor(Pulse.muted)
                            }
                        }
                    }
                    ForEach(groups) { group in
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(group.id).font(.subheadline.weight(.heavy))
                                    Spacer()
                                    Text("\(group.calories) kcal").font(.subheadline.weight(.heavy)).foregroundColor(Pulse.fuel)
                                }
                                ForEach(group.meals) { meal in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 0) {
                                            Text(meal.name).font(.subheadline)
                                            Text(meal.date.formatted(date: .omitted, time: .shortened))
                                                .font(.caption).foregroundColor(Pulse.muted)
                                        }
                                        Spacer()
                                        Text("\(meal.calories)").font(.subheadline).foregroundColor(Pulse.muted)
                                    }
                                    .contextMenu {
                                        Button("Delete", role: .destructive) { store.deleteMeal(meal.id) }
                                    }
                                    .accessibilityElement(children: .combine)
                                }
                            }
                        }
                    }
                    Text("Calories are estimates from a food database. Amounts vary with portion and preparation.")
                        .font(.caption).foregroundColor(Pulse.muted).frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }
            .screenBackground()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add food")
                }
            }
            .sheet(isPresented: $showAdd) { AddFoodSheet() }
        }
    }
}

/// Type "2 rotis and a bowl of dal" and see the estimate before saving.
struct AddFoodSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    private var items: [FoodEstimate] { text.isEmpty ? [] : FoodDatabase.shared.parse(text) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                TextField("e.g. 2 rotis and a bowl of dal", text: $text, axis: .vertical)
                    .padding(14)
                    .background(Pulse.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                ForEach(items, id: \.self) { item in
                    HStack {
                        Text("\(item.quantity.formatted()) × \(item.name.capitalized)")
                        if !item.confident { Text("not found").font(.caption).foregroundColor(Pulse.power) }
                        Spacer()
                        Text("\(item.calories) kcal").foregroundColor(Pulse.fuel).fontWeight(.heavy)
                    }
                }
                Spacer()
                PrimaryButton(title: "Add \(items.filter(\.confident).reduce(0) { $0 + $1.calories }) kcal",
                              isEnabled: items.contains(where: \.confident)) {
                    store.addMeals(items.filter(\.confident).map { $0.asMeal(source: .manual) })
                    dismiss()
                }
            }
            .padding(20)
            .screenBackground()
            .navigationTitle("Add food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
