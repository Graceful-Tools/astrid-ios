# Google OAuth Setup for iOS

This guide explains how to configure Google OAuth for the Astrid iOS app.

## Prerequisites

- Google Cloud Console access
- Xcode project set up with the Astrid app target

## Step 1: Create Google OAuth Client ID for iOS

1. Go to [Google Cloud Console](https://console.cloud.google.com/apis/credentials)
2. Select your Astrid project (or create one if needed)
3. Click **"Create Credentials" > "OAuth 2.0 Client ID"**
4. Choose **"iOS"** as the application type
5. Configure the client:
   - **Name**: `Astrid iOS App`
   - **Bundle ID**: `Graceful-Tools-Inc.Astrid-App` (or the exact bundle ID for the target/environment you are configuring)
6. Click **"Create"**
7. **Save the Client ID** - it will look like: `123456789-abcdefg.apps.googleusercontent.com`

## Step 2: Get the Reversed Client ID

The reversed client ID is used for the redirect URI:

```
Original: 123456789-abcdefg.apps.googleusercontent.com
Reversed: com.googleusercontent.apps.123456789-abcdefg
```

## Step 3: Verify the public iOS client configuration

Open `Astrid App/Core/Authentication/GoogleSignInManager.swift` and verify the public iOS client ID and redirect URI:

```swift
private let clientID = "<ios-client-id>.apps.googleusercontent.com"
private let redirectURI = "com.googleusercontent.apps.<reversed-client-id>:/oauth2redirect/google"
```

The iOS OAuth client ID is public configuration, but never commit OAuth client
secrets, refresh tokens, access tokens, API keys, or private credentials to the
iOS repository. Runtime secrets belong in Keychain or server-side configuration,
not in source files.

## Step 4: Configure Xcode URL Scheme

1. Open your Xcode project
2. Select the **AstridApp** target
3. Go to the **"Info"** tab
4. Expand **"URL Types"**
5. Click the **"+"** button to add a new URL type
6. Configure:
   - **Identifier**: `com.googleusercontent.apps`
   - **URL Schemes**: `com.googleusercontent.apps.123456789-abcdefg` (your reversed client ID)
   - **Role**: Editor

## Step 5: Enable Google OAuth API

In Google Cloud Console:

1. Go to **"APIs & Services" > "Library"**
2. Search for **"People API"**
3. Click **"Enable"**

## Step 6: Add Required Scopes

The app requests these scopes:
- `openid` - Required for OAuth
- `email` - User's email address
- `profile` - User's name and picture

These are already configured in `GoogleSignInManager.swift`.

## Step 7: Test Google Sign In

1. Build and run the app in Xcode
2. Tap **"Continue with Google"** on the login screen
3. You should see the Google sign-in web page
4. Sign in with your Google account
5. Grant permissions
6. You'll be redirected back to the app

## Troubleshooting

### Error: "Invalid client ID"
- Verify the client ID is correct in `GoogleSignInManager.swift`
- Make sure you created an **iOS** client ID, not a web client ID

### Error: "Redirect URI mismatch"
- Check that the URL scheme in Xcode matches your reversed client ID exactly
- Make sure there are no typos

### Error: "Sign in cancelled"
- This is normal if the user cancels the web authentication
- No action needed

### Error: "Not configured"
- You haven't replaced the placeholder values in `GoogleSignInManager.swift`
- Follow Step 3 above

## Security Notes

### Production Deployment

**IMPORTANT**: The current implementation uses PKCE (Proof Key for Code Exchange) for security, but you should also:

1. **Verify ID tokens on the backend** - Currently using Google's tokeninfo endpoint, but consider using a JWT library for offline verification
2. **Implement proper session management** - The current implementation creates simple session tokens; consider using JWT or NextAuth sessions
3. **Add rate limiting** - Protect the `/api/auth/google` endpoint from abuse

### Apple Sign In Requirement

Per App Store guidelines, if you offer third-party sign-in (Google), you must also offer Sign in with Apple. This is already implemented in the app.

## Related Files

- iOS Client: `Astrid App/Core/Authentication/GoogleSignInManager.swift`
- Backend Endpoint: `app/api/v1/auth/google/route.ts` (in astrid-web)
- Login UI: `Astrid App/Views/Authentication/LoginView.swift`

## Support

If you encounter issues:
1. Check the Xcode console for error messages
2. Verify all configuration steps above
3. Ensure your Google Cloud project has OAuth consent screen configured
