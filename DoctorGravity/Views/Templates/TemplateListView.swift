import SwiftUI
import SwiftData

struct TemplateListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.llmService) private var llmService

    @Query(sort: \WorkoutTemplate.createdAt, order: .reverse)
    private var templates: [WorkoutTemplate]

    @State private var isGeneratorPresented = false

    var body: some View {
        NavigationStack {
            Group {
                if templates.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Workouts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isGeneratorPresented = true
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isGeneratorPresented) {
                TemplateGeneratorView(
                    viewModel: TemplateGeneratorViewModel(
                        service: llmService,
                        modelContext: modelContext
                    )
                )
            }
        }
    }

    // MARK: - List

    private var list: some View {
        List {
            ForEach(templates) { template in
                NavigationLink(value: template) {
                    TemplateRow(template: template)
                }
            }
            .onDelete(perform: deleteTemplates)
        }
        .navigationDestination(for: WorkoutTemplate.self) { template in
            TemplateDetailView(template: template)
        }
    }

    private func deleteTemplates(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(templates[index])
        }
        try? modelContext.save()
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No workouts yet", systemImage: "figure.strengthtraining.traditional")
        } description: {
            Text("Tap the + button to generate your first workout template.")
        } actions: {
            Button {
                isGeneratorPresented = true
            } label: {
                Label("Generate workout", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Row

private struct TemplateRow: View {
    let template: WorkoutTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(template.title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        if let lastCompleted = template.sessions
            .compactMap(\.completedAt)
            .max() {
            return "Last: \(lastCompleted.formatted(.relative(presentation: .named)))"
        }
        return "Created \(template.createdAt.formatted(.relative(presentation: .named)))"
    }
}

#Preview {
    TemplateListView()
        .modelContainer(for: [
            WorkoutTemplate.self, WorkoutSet.self, WorkoutExercise.self,
            WorkoutSnapshot.self, ExerciseTarget.self,
            WorkoutSession.self, SessionSet.self, SessionExercise.self
        ], inMemory: true)
}
