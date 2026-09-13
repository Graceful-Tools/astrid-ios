Run the standard predeploy checks for the iOS app.

Execute:
```bash
npm run predeploy
```

This validates:
1. Neither target's `MARKETING_VERSION` is already released on the App Store (skips when offline)
2. All localizations are complete (12 languages)
3. Project builds successfully
4. Unit tests pass

If step 1 fails, the fix is a dot bump of `MARKETING_VERSION` for the named target in
`Astrid App.xcodeproj/project.pbxproj` — ask the user which number, never pick one.

Report the results clearly. If there are failures, summarize what failed and suggest fixes.

For a quicker check (build only, no tests): `npm run predeploy:quick`
For a full check including UI tests: `npm run predeploy:full`
