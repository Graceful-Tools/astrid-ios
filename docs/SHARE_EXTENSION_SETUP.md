# Share Extension

The `Astrid` target (source in `Astrid/`) is the iOS Share Extension. It lets users create
tasks from the system share sheet — photos, files, URLs and text from Photos, Files, Safari
and other apps.

**Architecture:** Share Extension → App Group container → main app → backend.

## Layout

| Path | Role |
|---|---|
| `Astrid/ShareViewController.swift` | Extension entry point (storyboard `Astrid/Base.lproj/MainInterface.storyboard`) |
| `Astrid/TaskQuickCreateView.swift` | SwiftUI task-creation sheet |
| `Astrid/Info.plist` | `NSExtension` activation rules (image, file, web URL, text, movie) |
| `Astrid/Astrid.entitlements` | App Group entitlement |
| `Shared/SharedTaskData.swift`, `Shared/ShareDataManager.swift`, `Shared/AppLog.swift` | Compiled into both the app and the extension |
| `AstridApp.swift` (`processSharedTasks`) | Main app drains the container on launch / foreground |

Target membership is managed by the pbxproj exception sets for the `Astrid` target; files
outside `Shared/` and `Astrid/` are not visible to the extension unless listed there.

## App Group

The group identifier is `group.gracefultools.astrid`, defined once in
`ShareDataManager.appGroupIdentifier` and in both entitlements files (`Astrid App/Astrid
App.entitlements`, `Astrid/Astrid.entitlements`). It must be enabled on both App IDs in the
Apple Developer portal and checked under **Signing & Capabilities → App Groups** on both
targets. `ShareDataManager.validateAppGroupAccess()` logs a clear error at launch when the
container is unreachable.

## Info.plist rules

Set `NSExtensionMainStoryboard` **or** `NSExtensionPrincipalClass`, never both — App Store
Connect rejects an extension that declares two entry points. This target uses the storyboard.

## Data flow

1. The extension receives the shared item and shows `TaskQuickCreateView`.
2. `ShareDataManager` writes the task and any file into the App Group container.
3. The extension closes. Authentication state is not shared with the extension by design.
4. On next launch or foreground, `AstridApp.processSharedTasks()` loads the pending tasks,
   creates them through `TaskService`, uploads files through `AttachmentService`, then
   removes the completed entries.

## Troubleshooting

- **Extension missing from the share sheet:** the activation rule in `Astrid/Info.plist`
  does not match the item type, or the extension scheme was never run once on the device.
- **"App Group not configured":** the group is missing from one of the two entitlements
  files or from one App ID in the portal. Both must match `ShareDataManager.appGroupIdentifier`.
- **Shared files never upload:** check the main app's log for `processSharedTasks`; the
  extension only stages, the app does the network work.
