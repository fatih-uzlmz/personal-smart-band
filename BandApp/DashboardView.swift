import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    intro

                    if model.isSample {
                        Label("Preview data — no band connected", systemImage: "info.circle")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }

                    MetricCard(title: "Readiness", value: readinessText,
                               detail: readinessDetail,
                               symbol: "heart.fill")
                    MetricCard(title: "Activity Load", value: activityLoadText,
                               detail: "Day load \u{00B7} 0\u{2013}100 scale",
                               symbol: "bolt.fill")
                    MetricCard(title: "Steps", value: stepsText,
                               detail: "Daily count from the band",
                               symbol: "figure.walk")
                    MetricCard(title: "Sleep", value: sleepText,
                               detail: "Estimated time asleep",
                               symbol: "moon.stars")
                    MetricCard(title: "Calories", value: caloriesText,
                               detail: "Vendor estimate · definition to verify",
                               symbol: "flame")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Device")
                            .font(.headline)
                        #if targetEnvironment(simulator)
                        Text("Band sync needs a real iPhone \u{2014} the SDK only ships device builds. Run on your phone to sync, or preview below.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Load 7-day mock week") {
                            Task { await model.loadMockWeek() }
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 4)
                        Text("Deterministic mock band data \u{2014} no Bluetooth, same pipeline as the real sync. The orange banner marks it as preview.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        #else
                        if let status = model.syncStatus {
                            Text(status)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Connect your H7 band over Bluetooth and pull the latest steps, sleep, and calorie estimates.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Button("Sync band") {
                            Task { await model.syncBand() }
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 4)
                        #endif
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))

                    Text("Your records stay in this app on your phone. The prototype has no account or network features.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if let error = model.errorMessage {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
                .padding()
            }
            .navigationTitle("Today")
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Your day, in five numbers.")
                .font(.title2.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var readinessText: String {
        model.todayScores?.readiness.map { "\($0.value)%" } ?? "\u{2014}"
    }

    private var readinessDetail: String {
        guard let readiness = model.todayScores?.readiness else {
            return "Needs a night of sleep data"
        }
        return "Sleep-based \u{00B7} \(readiness.zone.rawValue)"
    }

    private var activityLoadText: String {
        guard let activityLoad = model.todayScores?.activityLoad else { return "\u{2014}" }
        return String(format: "%.1f", activityLoad.value)
    }

    private var stepsText: String {
        model.today?.steps?.formatted() ?? "—"
    }

    private var sleepText: String {
        guard let minutes = model.today?.sleepSessions.reduce(0, { $0 + $1.estimatedSleepMinutes }) else {
            return "—"
        }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    private var caloriesText: String {
        guard let calories = model.today?.vendorCaloriesKcal else { return "—" }
        return "\(calories.formatted(.number.precision(.fractionLength(0)))) kcal"
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .frame(width: 38, height: 38)
                .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(value).font(.largeTitle.bold()).contentTransition(.numericText())
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}
