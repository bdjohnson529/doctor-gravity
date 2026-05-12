# Product Requirements Document (PRD): Doctor Gravity (AI-Powered Workout Tracker)
 
## 1. Project Overview
A native iPhone app where users generate reusable workout templates from natural language prompts using an LLM, then execute and log individual sessions against those templates. Progression is tracked by versioning target reps/duration over time via snapshots — the template structure stays stable while strength capacity evolves.
 
All data is stored locally. No backend required for MVP.
 
---
 
## 2. Target Platform & Stack
| Concern | Choice |
|---|---|
| Platform | Native iOS (iPhone), iOS 17+ |
| Language | Swift 5.9+ |
| UI Framework | SwiftUI |
| Persistence | SwiftData |
| AI Integration | LLM API (OpenAI or Anthropic) via direct HTTP — returns structured JSON |
| Architecture | MVVM — `@Observable` ViewModels, protocol-backed services |
 
---
 
## 3. Data Schema
 
### 3.1 WorkoutTemplate
The reusable blueprint created by the LLM. Defines structure only — exercises and sets. Never mutated after the first session is completed.
 
| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Auto-generated |
| `title` | String | LLM-generated, e.g. "Full Body Strength" |
| `createdAt` | Date | Set on save |
| `hasBeenCompleted` | Bool | False until the first session's `completedAt` is set. Controls first-run edit behaviour (see Section 6.3) |
| `sets` | [WorkoutSet] | Ordered relationship |
 
### 3.2 WorkoutSet
A group of one or more exercises within the template (single exercise or superset).
 
| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Auto-generated |
| `order` | Int | 0-indexed position in the template |
| `restSeconds` | Int | Default rest after this set (default: 60) |
| `exercises` | [WorkoutExercise] | Ordered relationship |
 
### 3.3 WorkoutExercise
The structural definition of an exercise. Holds identity and type only — **no target fields**. Targets live in `ExerciseTarget` (see 3.5).
 
| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Auto-generated |
| `name` | String | e.g. "Push-ups" |
| `order` | Int | 0-indexed position within the set |
| `isTimed` | Bool | True = timed exercise; false = rep-based |
| `notes` | String? | LLM-generated form cues, e.g. "Keep core tight" |
 
### 3.4 WorkoutSnapshot
A versioned set of targets for a template. Created once at template generation, then a new snapshot is created each time the user wants to progress (e.g. increase reps). Sessions always reference a specific snapshot.
 
| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Auto-generated |
| `templateId` | UUID | FK → WorkoutTemplate |
| `createdAt` | Date | Set on creation |
| `isActive` | Bool | True for the snapshot currently used when starting new sessions. Only one snapshot per template may be active at a time |
| `targets` | [ExerciseTarget] | One per WorkoutExercise |
 
### 3.5 ExerciseTarget
The target load for one exercise within a specific progression snapshot.
 
| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Auto-generated |
| `snapshotId` | UUID | FK → WorkoutSnapshot |
| `workoutExerciseId` | UUID | FK → WorkoutExercise |
| `targetReps` | Int? | Required if `WorkoutExercise.isTimed == false` |
| `targetDurationSeconds` | Int? | Required if `WorkoutExercise.isTimed == true` |
 
**Invariant:** For each `ExerciseTarget`, exactly one of `targetReps` or `targetDurationSeconds` must be non-nil, matching the parent `WorkoutExercise.isTimed` value. The JSON parser must reject targets that violate this.
 
### 3.6 WorkoutSession
A single logged execution of a template at a specific snapshot. Created when the user starts a workout; completed when they finish.
 
| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Auto-generated |
| `templateId` | UUID | FK → WorkoutTemplate |
| `snapshotId` | UUID | FK → WorkoutSnapshot used for this session |
| `startedAt` | Date | Set when execution begins |
| `completedAt` | Date? | Nil until the user finishes the session |
| `isCompleted` | Bool | True when `completedAt` is set |
| `sets` | [SessionSet] | Ordered relationship |
 
### 3.7 SessionSet
The logged instance of one `WorkoutSet` within a session.
 
| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Auto-generated |
| `order` | Int | Mirrors `WorkoutSet.order` |
| `exercises` | [SessionExercise] | Ordered relationship |
 
### 3.8 SessionExercise
The logged instance of one `WorkoutExercise` within a session. Holds only actuals — targets are read from the session's snapshot.
 
| Field | Type | Notes |
|---|---|---|
| `id` | UUID | Auto-generated |
| `workoutExerciseId` | UUID | FK → WorkoutExercise |
| `actualReps` | Int? | Logged by user; nil until completed |
| `actualDurationSeconds` | Int? | Logged on timed completion; nil until completed |
 
---
 
## 4. LLM Integration
 
### 4.1 Service Protocol
```swift
protocol LLMServiceProtocol {
    func generateTemplate(prompt: String) async throws -> WorkoutTemplate
}
```
Both `MockLLMService` (hardcoded JSON) and `LLMService` (real API) conform to this. Inject via SwiftUI environment. Views never reference a concrete type.
 
### 4.2 What the LLM Generates
The LLM returns a `WorkoutTemplate` with its `WorkoutSet` and `WorkoutExercise` children, plus an initial `WorkoutSnapshot` with one `ExerciseTarget` per exercise. This is saved atomically as a single transaction.
 
### 4.3 Prompt Contract
The system prompt must instruct the model to:
- Return **only valid JSON** — no preamble, no markdown fences, no explanation.
- Match the schema in Section 3 exactly (field names are the contract).
- Populate `notes` on exercises where form cues are relevant.
- Set `restSeconds` on every `WorkoutSet`.
- Include one `ExerciseTarget` per exercise in an initial `WorkoutSnapshot`.
Store the prompt template in `Prompts.swift` as a static string constant.
 
### 4.4 JSON Parsing Rules
- Decode in `JSONParser.swift` using `JSONDecoder`.
- On any decode failure: log the raw string, throw a typed `LLMParseError`, surface a user-readable message. Never crash.
- Validate the `isTimed` / target invariant (Section 3.5) after decoding; reject the template if violated.
- API keys read from `Config.xcconfig` only — never hard-coded or committed.
---
 
## 5. Functional Requirements
 
### 5.1 View: AI Template Generator (`TemplateGeneratorView`)
**States:** `.idle` → `.loading` → `.preview(WorkoutTemplate)` → `.error(String)`
 
| Element | Behaviour |
|---|---|
| Prompt text field | Multi-line, 300-char limit, placeholder with example |
| Generate button | Disabled while `.loading`; shows spinner |
| Template preview | List of sets and exercises with target reps/duration from the initial snapshot; read-only |
| Save button | Appears in `.preview` state; persists template + initial snapshot atomically; navigates to template list |
| Error banner | Shown in `.error` state with message and Retry option |
 
### 5.2 View: Template List & Detail (`TemplateListView` / `TemplateDetailView`)
 
| Element | Behaviour |
|---|---|
| Template list | All saved templates; shows title and last-used date |
| Detail view | Shows current active snapshot's targets per exercise |
| Start Workout button | Creates a new `WorkoutSession` referencing the active snapshot; enters execution view |
| Increase Progression button | Creates a new `WorkoutSnapshot` by copying the active snapshot's `ExerciseTarget` rows; sets new snapshot as active; opens an edit view to adjust targets |
 
### 5.3 View: Workout Execution (`WorkoutExecutionView`)
Entry point: user taps "Start Workout" on a template. A new `WorkoutSession` is instantiated immediately.
 
**States:** `.exercise(current: SessionExercise)` → `.rest(secondsRemaining: Int)` → `.complete`
 
Targets for display are read from `session.snapshotId → ExerciseTarget` for each exercise.
 
| Element | Behaviour |
|---|---|
| Progress indicator | "Set X of Y / Exercise Z of N" |
| Rep-based exercise | Shows `targetReps` from snapshot; stepper or number input for `actualReps` |
| Timed exercise | Countdown from `targetDurationSeconds`; auto-advances on completion; logs `actualDurationSeconds` |
| Rest screen | Countdown from `WorkoutSet.restSeconds`; Skip button |
| Next button | Advances state machine; disabled until reps logged (rep-based) |
| Completion screen | Summary of sets done and total reps; marks session complete (`completedAt = now`); triggers first-run logic (Section 5.3.1) |
 
**State persistence:** `WorkoutManager` holds full session state and flushes to SwiftData on every exercise transition and on `scenePhase → .background`.
 
#### 5.3.1 First-Run Edit Behaviour
During execution, if `template.hasBeenCompleted == false`, the user may edit exercises on the fly. Edits in this state **write through to the template and active snapshot**, because the user is still authoring their canonical plan.
 
Editable fields during first-run execution:
- **Swap exercise:** replace `WorkoutExercise.name` and reset `ExerciseTarget` values
- **Adjust targets:** update `ExerciseTarget.targetReps` or `targetDurationSeconds`
When the first session completes:
1. Set `template.hasBeenCompleted = true`
2. Set `session.completedAt = now`
For all subsequent sessions (`hasBeenCompleted == true`), edits during execution are **session-local only** — they update the `SessionExercise` being logged but do not touch the template or snapshot.
 
### 5.4 View: History (`HistoryView` / `HistoryDetailView`)
 
| Element | Behaviour |
|---|---|
| Completed sessions | All sessions where `isCompleted == true`, sorted by `completedAt` descending |
| Session row | Template title, date, total reps logged |
| Detail view | All exercises with `actualReps` / `actualDurationSeconds` and the snapshot's `targetReps` / `targetDurationSeconds` side-by-side |
| In-progress section | Sessions where `isCompleted == false`; tapping resumes execution |
| Analytics | Total reps across all history (sum of non-nil `actualReps`) |
 
---
 
## 6. Progression Flow
 
When the user wants to increase targets (e.g. after getting stronger):
 
1. User taps **"Increase Progression"** on `TemplateDetailView`
2. App creates a new `WorkoutSnapshot` for the template
3. All `ExerciseTarget` rows from the current active snapshot are copied to the new snapshot
4. New snapshot opens in an editable view — user adjusts any targets
5. On confirm: new snapshot's `isActive = true`; previous snapshot's `isActive = false`
6. All future sessions use the new snapshot; all historical sessions retain their original `snapshotId` and are unaffected
**Invariant:** Exactly one `WorkoutSnapshot` per template has `isActive == true` at any time. Enforce this in `WorkoutManager`, not in the view.
 
---
 
## 7. Technical Constraints
- **Offline-first:** SwiftData is the only persistence layer. Network calls for LLM API only.
- **Background safety:** `WorkoutManager` persists in-progress session state to SwiftData on every exercise transition and on `scenePhase → .background`.
- **Atomic saves:** Template + initial snapshot must be saved in a single SwiftData transaction. Session creation (template → session instantiation) is also atomic.
- **No UIKit:** SwiftUI only. Note any hard blockers if encountered.
- **Async/await only:** No Combine, no callbacks.
- **`@Observable` over `ObservableObject`:** Use Swift 5.9 `@Observable` macro throughout.
---
 
## 8. Implementation Phases
Build and manually verify each phase before starting the next.
 
| Phase | Deliverable | Done when… |
|---|---|---|
| 1 | SwiftData models | All models and relationships defined; container initialises; invariants enforced |
| 2 | `TemplateGeneratorView` + `MockLLMService` + `JSONParser` | Can generate, preview, and save a template + initial snapshot using mock data |
| 3 | `TemplateListView` + `TemplateDetailView` | Templates list correctly; detail shows active snapshot targets; Start Workout and Increase Progression buttons present |
| 4 | `WorkoutExecutionView` + `WorkoutManager` | Can execute a session end-to-end; first-run edit writes through to template; repeat-run edits are session-local; state survives backgrounding |
| 5 | `HistoryView` + `HistoryDetailView` | Completed sessions appear; in-progress sessions resumable; targets vs actuals shown side-by-side |
| 6 | Real `LLMService` | Full flow works with live API; keys loaded from config |