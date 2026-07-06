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

**From command line:**
```bash
xcodebuild test \
  -project "Astrid App.xcodeproj" \
  -scheme "Astrid App" \
  -destination "platform=iOS Simulator,name=iPhone 17"
```

### Test File Locations

| Test Type | Location |
|-----------|----------|
| Unit tests | `Astrid AppTests/Tests/UnitTests/` |
| Integration tests | `Astrid AppTests/Tests/IntegrationTests/` |
| Test helpers | `Astrid AppTests/Tests/Mocks/` |
| UI tests | `Astrid AppUITests/` |

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

### Core Test Classes

These tests run in CI (fast, no network required):

- `TaskModelTests` - Task model behavior
- `UserModelTests` - User model behavior
- `TaskListModelTests` - List model behavior
- `RepeatingTaskCalculatorTests` - Recurring task logic
- `UserImageCacheTests` - Image caching
- `PasskeyErrorTests` - Passkey error handling
- `EmailValidationTests` - Email format validation
- `EmptyStateMessageTests` - Empty state UI
- `ReviewPromptFeedbackTests` - App review prompts
- `TaskPresenterTests` - Task presentation logic
- `LocalizationManagerTests` - Localization

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
    let response = try await apiClient.request(.tasks)
    return try JSONDecoder().decode([Task].self, from: response)
}
```

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

The iOS app communicates with the Astrid backend API. When making changes:

1. **Reference the API contract**: See [docs/API_CONTRACT.md](./docs/API_CONTRACT.md)
2. **Don't assume API changes**: Coordinate with backend team
3. **Handle API versioning**: Use the `X-API-Version` header
4. **Maintain backward compatibility**: Support older API versions where possible

### API Endpoints Used

All endpoints are defined in `Astrid App/Core/Networking/APIEndpoint.swift`. Key endpoints:

- Authentication: `/api/auth/mobile-*`, `/api/auth/apple`, `/api/auth/google`
- Tasks: `/api/v1/tasks`, `/api/v1/tasks/{id}`
- Lists: `/api/lists`, `/api/lists/{id}`
- Comments: `/api/v1/tasks/{id}/comments`
- Real-time: `/api/v1/sse`

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

Add logging to `APIClient.swift`:
```swift
print("🌐 Request: \(endpoint.path)")
print("📦 Response: \(String(data: data, encoding: .utf8) ?? "")")
```

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
