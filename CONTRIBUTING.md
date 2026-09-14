# Contributing to Astrid iOS

Thank you for your interest in contributing to the Astrid iOS app! This document provides guidelines and instructions for contributing.

## Code of Conduct

This project adheres to the [Contributor Covenant Code of Conduct](./CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

## Prerequisites

Before you begin, ensure you have:

- **Xcode 26.0+** (download from Mac App Store)
- **iOS 18.6+** deployment target
- **Apple Developer account** (free account works for simulator testing)
- **Git** for version control

## Getting Started

### 1. Fork and Clone

```bash
# Fork the repository on GitHub, then clone your fork
git clone https://github.com/YOUR_USERNAME/astrid-ios.git
cd astrid-ios
```

### 2. Open in Xcode

```bash
open "Astrid App.xcodeproj"
```

### 3. Configure Signing

1. In Xcode, select the project in the navigator
2. Select "Astrid App" target
3. Under "Signing & Capabilities":
   - Select your Team (or Personal Team)
   - Change Bundle Identifier if needed (e.g., `com.yourname.astrid`)

### 4. Build and Run

- Select an iPhone simulator (e.g., iPhone 17)
- Press **Cmd+R** to build and run
- The app should launch in the simulator

## Development Workflow

### Branch Naming

Use descriptive branch names with prefixes:

- `feature/` - New features (e.g., `feature/dark-mode`)
- `fix/` - Bug fixes (e.g., `fix/sync-error`)
- `refactor/` - Code refactoring (e.g., `refactor/task-service`)
- `test/` - Test additions (e.g., `test/auth-tests`)

### Commit Convention

We follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <description>
```

**Types:**
- `feat` - New feature
- `fix` - Bug fix
- `refactor` - Code restructuring
- `test` - Adding/updating tests
- `docs` - Documentation
- `chore` - Maintenance

**Examples:**
```bash
feat(tasks): add swipe to complete
fix(auth): handle expired sessions
refactor(sync): simplify SSE reconnection logic
```

## Testing

### Running Tests

**In Xcode:**
- Press **Cmd+U** to run all tests
- Use the Test Navigator (Cmd+6) to run specific tests

**From command line:** `npm run test` (unit), `npm run test:ui`, `npm run test:mac`. The
full command table and the test-file locations are in [CLAUDE.md](./CLAUDE.md) §Quality Gates.

### Writing Tests

Follow the AAA pattern (Arrange-Act-Assert):

```swift
@MainActor
func testTaskCompletion() {
    // Arrange
    let task = TestHelpers.createTestTask(completed: false)

    // Act
    task.markAsCompleted()

    // Assert
    XCTAssertTrue(task.completed)
    XCTAssertNotNil(task.completedAt)
}
```

Bug fixes are test-driven: a RED regression test naming the task id, then the fix
(ASTRID.md §0 rule 7). Fixtures come from `TestHelpers` and the repo-root walk from
`RepositoryLocator`; do not hand-roll either.

## Code Style

### SwiftUI Guidelines

- Use SwiftUI for all new views
- Prefer `@State` and `@Binding` for local state
- Use `@StateObject` for view-owned observable objects
- Use `@EnvironmentObject` for shared state

```swift
struct TaskRowView: View {
    let task: Task
    @Binding var isSelected: Bool

    var body: some View {
        HStack {
            // ...
        }
    }
}
```

### Async/Await

Use async/await for asynchronous operations:

```swift
func fetchTasks() async throws -> [Task] {
    try await AstridAPIClient.shared.getTasks()
}
```

Views never call `AstridAPIClient` directly; writes go through the service layer
(ASTRID.md §0 rule 1).

### Architecture

The app follows an MVVM-like architecture:

```
Views/          # SwiftUI views
Models/         # Data models
Core/
  Services/     # Business logic (TaskService, ListService)
  Networking/   # API client
  Persistence/  # Core Data
```

### No External Dependencies

The app uses only system frameworks. Do not add external packages unless absolutely necessary.

## API Compatibility

- Every path is versioned `/api/v1/...` in the path; there is no version header.
- New endpoints go in `AstridAPIClient` (ASTRID.md §2a); the `APIEndpoint` enum is legacy
  and closed to additions.
- The list of paths the app calls is [docs/API_ENDPOINTS.md](./docs/API_ENDPOINTS.md)
  (test-gated); wire shapes are in [docs/API_CONTRACT.md](./docs/API_CONTRACT.md).
- Make the web API change first, deploy it, then consume it here. For breaking changes add
  a new version and keep the old one working.

## Pull Request Process

### Before Submitting

1. **Build succeeds**: Cmd+B with no errors
2. **Tests pass**: Cmd+U runs all tests successfully
3. **No SwiftLint warnings** (if available)
4. **Test on multiple simulators**: iPhone and iPad

### PR Template

Your PR description should include:

```markdown
## Summary
Brief description of changes

## Changes
- List of specific changes

## Test Plan
- How to test manually
- [ ] Unit tests added/updated
- [ ] Tested on iPhone simulator
- [ ] Tested on iPad simulator

## Screenshots
(If UI changes, include before/after screenshots)
```

### Review Process

1. PRs require at least one approval
2. All CI checks must pass
3. Test coverage should not decrease
4. Follow up on review comments promptly

## Debugging Tips

### View API Requests

Use `PrivacyLogger.request` / `.response` (DEBUG-only, redacts secrets) rather than `print`.

### Debug Server Configuration

In DEBUG builds, you can change the server:
1. Build and run the app
2. Go to Settings tab
3. Scroll to "Developer" section
4. Select server (localhost, local network, production)

### Core Data Debugging

Add launch arguments in Xcode:
- `-com.apple.CoreData.SQLDebug 1` - SQL logging
- `-com.apple.CoreData.ConcurrencyDebug 1` - Thread safety checks

## Getting Help

- **Questions**: Open a [Discussion](https://github.com/Graceful-Tools/astrid-ios/discussions)
- **Bug reports**: Open an issue on GitHub
- **Feature requests**: Open an issue on GitHub

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
