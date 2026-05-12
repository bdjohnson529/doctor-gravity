# CLAUDE.md — Doctor Gravity (AI-Powered Workout Tracker)

## Project Overview
A native iPhone app where users generate reusable workout templates from natural language prompts using an LLM, then execute and log individual sessions against those templates. Progression is tracked by versioning targets over time via snapshots — the template structure stays stable while strength capacity evolves. All data is stored locally.

## Reference Documents
Before starting any task, read the relevant docs:
- `PRD.md` — Full product requirements, data schema, view specifications, and progression flow (source of truth for what to build)

---

## Tech Stack
- **Language:** Swift 5.9+
- **UI:** SwiftUI
- **Persistence:** SwiftData
- **AI Integration:** LLM API (OpenAI or Anthropic) via direct HTTP — returns structured JSON
- **Target:** iOS 17+, iPhone only, MVP scope

---

## Project Structure
```
DoctorGravity/
├── Models/
│   ├── Template/        # WorkoutTemplate, WorkoutSet, WorkoutExercise
│   ├── Snapshot/        # WorkoutSnapshot, ExerciseTarget
│   └── Session/         # WorkoutSession, SessionSet, SessionExercise
├── Views/
│   ├── Generator/       # TemplateGeneratorView + subviews
│   ├── Templates/       # TemplateListView, TemplateDetailView
│   ├── Execution/       # WorkoutExecutionView + timer subviews
│   └── History/         # HistoryView, HistoryDetailView
├── ViewModels/          # WorkoutManager and per-view ViewModels
├── Services/
│   ├── LLMService.swift        # Real API integration
│   └── MockLLMService.swift    # Hardcoded JSON for local testing
├── Utilities/
│   └── JSONParser.swift        # LLM string → Swift model conversion
├── Resources/
│   └── Prompts.swift           # LLM prompt templates as static string constants
├── Config.xcconfig             # API keys — never commit
└── PRD.md
```

---

## Data Models
All models live in `Models/` grouped by layer. Never change field names without updating `JSONParser.swift` and `Prompts.swift` simultaneously.

**Template layer** (reusable structure, created by LLM, never mutated after first session completes):
```
WorkoutTemplate  → has many WorkoutSet
WorkoutSet       → has many WorkoutExercise (supports supersets)
WorkoutExercise  → structural definition only; no target fields
```

**Snapshot layer** (versioned targets; one active snapshot per template at all times):
```
WorkoutSnapshot  → belongs to WorkoutTemplate; has many ExerciseTarget
ExerciseTarget   → belongs to WorkoutSnapshot + WorkoutExercise; holds targetReps or targetDurationSeconds
```

**Session layer** (logged instances; each session references a specific snapshot):
```
WorkoutSession   → belongs to WorkoutTemplate + WorkoutSnapshot; has many SessionSet
SessionSet       → has many SessionExercise
SessionExercise  → belongs to WorkoutExercise; holds actualReps or actualDurationSeconds
```

See `PRD.md` Section 3 for the full schema including all fields, types, and FK relationships.

---

## Build & Run Commands
```bash
# Open in Xcode
open DoctorGravity.xcodeproj

# Build from CLI (simulator)
xcodebuild -scheme DoctorGravity -destination 'platform=iOS Simulator,name=iPhone 15' build

# Run tests
xcodebuild -scheme DoctorGravity -destination 'platform=iOS Simulator,name=iPhone 15' test
```

---

## Architecture Rules
1. **MVVM strictly.** Views own no business logic. All state lives in ViewModels or `WorkoutManager`.
2. **`WorkoutManager` is the single source of truth** for active session state. Responsibilities:
   - Instantiating a `WorkoutSession` (and child `SessionSet`/`SessionExercise` rows) from a template + active snapshot
   - Resolving targets for display by joining `session.snapshotId → ExerciseTarget`
   - Enforcing the active-snapshot invariant: exactly one `WorkoutSnapshot` per template has `isActive == true` at any time
   - Enforcing first-run edit write-through (see Rule #5)
   - Flushing session state to SwiftData on every exercise transition and on `scenePhase → .background`
3. **Services are protocol-backed.** `LLMService` and `MockLLMService` both conform to `LLMServiceProtocol`. Inject via SwiftUI environment. Views never reference a concrete type.
4. **No logic in SwiftData models.** Models are pure data. Computed properties are fine; methods that mutate state are not.
5. **First-run edit rule.** During execution, check `template.hasBeenCompleted`:
   - `false` → edits write through to `WorkoutExercise` and `ExerciseTarget` (user is still authoring the canonical plan)
   - `true` → edits are session-local only, updating `SessionExercise` without touching the template or snapshot
   - On first session completion: set `template.hasBeenCompleted = true` and `session.completedAt = now` atomically
6. **Offline-first.** SwiftData is the only persistence layer. Network calls for LLM API only.

---

## Coding Conventions
- Use `async/await` for all async work — no Combine or callbacks.
- Prefer `@Observable` (Swift 5.9+) over `ObservableObject`/`@Published`.
- Use `enum` with associated values for view states, e.g. `.idle`, `.loading`, `.preview(WorkoutTemplate)`, `.error(String)`.
- Name ViewModels `<ViewName>ViewModel` (e.g. `TemplateGeneratorViewModel`).
- Group related SwiftUI views in the same file if under ~150 lines; split into subviews otherwise.
- All LLM prompt strings go in `Prompts.swift` as static string constants — never inline.

---

## LLM Integration
- The LLM returns a `WorkoutTemplate` with `WorkoutSet` and `WorkoutExercise` children, plus an initial `WorkoutSnapshot` with one `ExerciseTarget` per exercise — saved atomically as a single SwiftData transaction.
- The system prompt must instruct the model to return **only valid JSON** — no preamble, no markdown fences. Field names in the JSON are the contract; they must match the schema exactly.
- `JSONParser.swift` handles all decoding. On any failure: log the raw string, throw a typed `LLMParseError`, surface a user-readable message. Never crash.
- Validate the `isTimed` invariant after decoding: each `ExerciseTarget` must have exactly one of `targetReps` or `targetDurationSeconds` non-nil, matching the parent `WorkoutExercise.isTimed`. Reject the response if violated.
- During development, always use `MockLLMService` (hardcoded valid JSON). Only swap to `LLMService` in Phase 6 once all prior phases are verified.
- API keys read from `Config.xcconfig` only — never hard-coded or committed.

---

## Implementation Phases
Work in this order. Do not proceed to the next phase without completing and manually verifying the current one.

**Phase 1 — Models & Persistence**
- Define all 8 SwiftData models per PRD Section 3
- Verify SwiftData container initialises and all relationships resolve
- Enforce the `isTimed` invariant in `JSONParser.swift`

**Phase 2 — Template Generator (Mock)**
- Build `TemplateGeneratorView` with prompt input and template preview
- Wire to `MockLLMService` returning hardcoded valid JSON
- Implement `JSONParser` to decode response into models
- Save template + initial snapshot atomically to SwiftData

**Phase 3 — Template List & Detail**
- Build `TemplateListView` and `TemplateDetailView`
- Detail view reads targets from the active `WorkoutSnapshot`
- Implement "Start Workout" button (creates `WorkoutSession`, enters execution)
- Implement "Increase Progression" button (creates new `WorkoutSnapshot`, copies targets, opens edit view, swaps active)

**Phase 4 — Workout Execution**
- Build `WorkoutExecutionView` with state-driven exercise progression
- Implement countdown timer for `isTimed` exercises
- Implement `actualReps` / `actualDurationSeconds` logging
- Implement first-run edit write-through vs session-local logic in `WorkoutManager`
- Mark session complete and persist on finish; set `hasBeenCompleted` on first completion

**Phase 5 — History**
- Build `HistoryView` (completed sessions, sorted by `completedAt` desc) and `HistoryDetailView`
- Show targets vs actuals side-by-side in detail view
- Show in-progress sessions as resumable
- Add total reps analytics

**Phase 6 — Real LLM Integration**
- Swap `MockLLMService` for `LLMService` with real API calls
- End-to-end test: prompt → JSON → parse → save → execute → history

---

## What Not To Do
- Do not use UIKit unless SwiftUI has a hard blocker (note it in a comment if so).
- Do not add any backend, sync, or cloud storage in MVP scope.
- Do not hard-code API keys.
- Do not skip the mock service phase — build and verify all UI before touching real network calls.
- Do not silently swallow errors from `JSONParser`; always surface them to the user.
- Do not enforce the active-snapshot invariant in views — it belongs in `WorkoutManager`.
- Do not put target fields (`targetReps`, `targetDurationSeconds`) on `WorkoutExercise` — they live in `ExerciseTarget` only.