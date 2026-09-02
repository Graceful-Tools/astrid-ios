# iOS Share Extension Setup Guide

This guide walks through the Xcode configuration steps required to enable the Share Extension for photos and files.

## Overview

The Share Extension allows users to create Astrid tasks directly from the iOS system share sheet when sharing photos or files from other apps (Photos, Files, Safari, etc.).

**Architecture:** Share Extension → App Group → Main App → Backend API

## Prerequisites

- Xcode 15.0 or later
- Apple Developer Account (for App Groups)
- Astrid iOS app project already configured

## Manual Xcode Setup Steps

### Step 1: Create Share Extension Target

1. **Open Xcode project:**
   ```bash
   open "Astrid App.xcodeproj"
   ```

2. **Add new target:**
   - Click on the project in Project Navigator
   - Click **+** button at the bottom of the Targets list
   - Choose **Share Extension** from the iOS templates
   - Click **Next**

3. **Configure target:**
   - **Product Name:** `ShareExtension`
   - **Team:** Select your development team
   - **Language:** Swift
   - **Bundle Identifier:** `Graceful-Tools-Inc.Astrid-App.ShareExtension`
   - Click **Finish**
   - When asked about Xcode Scheme, click **Activate**

### Step 2: Replace Generated Files

Xcode will generate default Share Extension files. Replace them with our custom implementation:

1. **Delete generated files** (keep the target, just delete these files):
   - `ShareViewController.swift` (Xcode's default version)
   - `MainInterface.storyboard` (if created)

2. **Add our implementation files to the ShareExtension target:**
   - Select these files in Project Navigator:
     - `ShareExtension/ShareViewController.swift`
     - `ShareExtension/TaskQuickCreateView.swift`
     - `ShareExtension/Info.plist`
   - In File Inspector (right panel), check **ShareExtension** under "Target Membership"

3. **Add shared files to ShareExtension target:**
   These files need to be accessible by both main app and extension:
   - `Astrid App/Core/Models/SharedTaskData.swift`
   - `Astrid App/Core/Services/ShareDataManager.swift`
   - `Astrid App/Utilities/Constants.swift`
   - `Astrid App/Utilities/Theme.swift`

   For each file: Select it → File Inspector → Check **ShareExtension** under "Target Membership"

### Step 3: Configure Info.plist

1. **Select ShareExtension target** in project settings
2. **Go to Info tab**
3. **Verify/Update these keys:**
   - `NSExtension` → `NSExtensionPointIdentifier`: `com.apple.share-services`
   - `NSExtension` → `NSExtensionMainStoryboard`: `MainInterface`
   - Do not also set `NSExtensionPrincipalClass`; App Store Connect rejects extensions that declare both entry points.
   - `NSExtensionActivationSupportsImageWithMaxCount`: `1`
   - `NSExtensionActivationSupportsFileWithMaxCount`: `1`

4. **Add Privacy Description:**
   - Key: `NSPhotoLibraryUsageDescription`
   - Value: `Astrid needs access to your photos to create tasks with attachments.`

### Step 4: Configure App Groups

App Groups allow the Share Extension and main app to share data.

#### In Apple Developer Portal:

1. Go to [Apple Developer Portal](https://developer.apple.com)
2. Navigate to **Certificates, Identifiers & Profiles** → **Identifiers**
3. Select your main app identifier: `Graceful-Tools-Inc.Astrid-App`
4. Enable **App Groups** capability
5. Click **Configure** → Create new App Group: `group.cc.astrid.app`
6. Save changes
7. Repeat for Share Extension identifier: `Graceful-Tools-Inc.Astrid-App.ShareExtension`

#### In Xcode:

1. **Select Astrid App target** → **Signing & Capabilities**
2. Click **+ Capability** → Add **App Groups**
3. Check `group.cc.astrid.app`

4. **Select ShareExtension target** → **Signing & Capabilities**
5. Click **+ Capability** → Add **App Groups**
6. Check `group.cc.astrid.app`

### Step 5: Configure Entitlements

Entitlements files have been created for you:
- `Astrid App/Astrid App.entitlements` (updated with App Group)
- `ShareExtension/ShareExtension.entitlements` (new)

**Verify in Xcode:**

1. **Astrid App target:**
   - Go to **Build Settings** → Search for "Entitlements"
   - **Code Signing Entitlements** should be: `Astrid App/Astrid App.entitlements`

2. **ShareExtension target:**
   - Go to **Build Settings** → Search for "Entitlements"
   - **Code Signing Entitlements** should be: `ShareExtension/ShareExtension.entitlements`

### Step 6: Configure Signing

1. **Select Astrid App target** → **Signing & Capabilities**
   - **Team:** Select your team
   - **Signing Certificate:** Development or Distribution
   - Enable **Automatically manage signing** (recommended)

2. **Select ShareExtension target** → **Signing & Capabilities**
   - **Team:** Same team as main app
   - **Signing Certificate:** Same as main app
   - Enable **Automatically manage signing** (recommended)

### Step 7: Build Settings

Verify these build settings for **ShareExtension target**:

1. **Deployment Info:**
   - iOS Deployment Target: 16.0 or higher (match main app)

2. **Swift Compiler:**
   - Swift Language Version: Swift 5

3. **Linking:**
   - No special frameworks needed (SwiftUI is built-in)

## Testing the Share Extension

### Build and Run

1. **Select ShareExtension scheme** in Xcode
2. **Run** (⌘R) on a physical device or simulator
3. Xcode will ask: "Choose an app to run"
4. Select **Photos** or **Files** app

### Test Flow

1. **From Photos app:**
   - Open a photo
   - Tap Share button
   - Scroll to find **Astrid** in share sheet
   - Tap Astrid icon
   - Enter task details
   - Tap **Save**
   - Photo should be saved to Astrid

2. **From Files app:**
   - Select a document (PDF, text file, etc.)
   - Tap Share button
   - Select **Astrid**
   - Create task with file attachment

3. **From Safari:**
   - Tap Share button on any image
   - Select **Astrid** to save image as task

### Verify in Main App

1. **Open main Astrid app**
2. Check console logs: Should see "Processing shared task..."
3. Navigate to tasks list
4. Verify new task appears with attachment

## Troubleshooting

### Share Extension not appearing in share sheet

**Issue:** Astrid doesn't show up in iOS share sheet

**Solutions:**
- Verify App Groups are configured correctly (same group ID in both targets)
- Check Info.plist activation rules (NSExtensionActivation...)
- Restart device/simulator
- Delete and reinstall app

### "App Group not configured" error

**Issue:** Console shows "App Group not configured"

**Solutions:**
- Verify App Group exists in Apple Developer Portal
- Check both main app and extension have App Groups capability enabled
- Ensure group ID matches exactly: `group.cc.astrid.app`
- Regenerate provisioning profiles

### Files not uploading

**Issue:** Tasks created but files missing

**Solutions:**
- Check network connectivity
- Verify user is authenticated in main app
- Check console logs for upload errors
- Verify file size isn't too large (25MB limit)

### Extension crashes on launch

**Issue:** Share Extension crashes when opened

**Solutions:**
- Verify all shared files have ShareExtension target membership
- Check for missing imports (SwiftUI, UniformTypeIdentifiers)
- Build and clean (⌘⇧K) then rebuild

## File Structure

```
astrid-ios/
├── Astrid App/
│   ├── Core/
│   │   ├── Models/
│   │   │   └── SharedTaskData.swift          ← Shared with extension
│   │   └── Services/
│   │       ├── ShareDataManager.swift        ← Shared with extension
│   │       └── AttachmentService.swift       ← Main app only
│   ├── Utilities/
│   │   ├── Constants.swift                   ← Shared with extension
│   │   └── Theme.swift                       ← Shared with extension
│   └── Astrid App.entitlements               ← Updated with App Group
├── ShareExtension/
│   ├── ShareViewController.swift             ← Extension entry point
│   ├── TaskQuickCreateView.swift             ← Extension UI
│   ├── Info.plist                            ← Extension config
│   └── ShareExtension.entitlements           ← Extension permissions
└── AstridApp.swift                           ← Updated to process shared tasks
```

## App Group Data Flow

1. **User shares photo from Photos app**
2. **Share Extension** receives photo via iOS
3. **ShareViewController** extracts photo data
4. **TaskQuickCreateView** shows task creation UI
5. **ShareDataManager** saves task + photo to App Group container
6. **Extension closes**, returns to Photos app
7. **Main app launches** (or comes to foreground)
8. **AstridApp** detects pending shared tasks
9. **TaskServiceMCP** creates task on backend
10. **AttachmentService** uploads photo from shared container
11. **ShareDataManager** marks task as completed and cleans up

## Security Notes

- App Groups are sandboxed - only accessible by apps with same group ID
- Share Extension runs in isolated process with limited memory
- Shared files are automatically cleaned up after 7 days
- Authentication state is NOT shared (by design)
- Extension cannot access main app's keychain directly

## Next Steps

After completing setup:

1. Test with various file types (images, PDFs, text files)
2. Test on different iOS versions (16.0+)
3. Test with large files (check memory limits)
4. Add analytics/logging if needed
5. Consider adding list picker in extension UI
6. Add due date/priority pickers for enhanced functionality

## Additional Resources

- [Apple Share Extension Programming Guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Share.html)
- [App Groups Documentation](https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_application-groups)
- [UniformTypeIdentifiers Framework](https://developer.apple.com/documentation/uniformtypeidentifiers)

---

**Implementation completed:** All Swift files and configurations are ready.

**Manual steps required:** Follow Steps 1-7 above to configure Xcode project.

**Questions?** Check console logs for detailed debugging information.
