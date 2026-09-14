Run the standard predeploy checks for the iOS app.

Execute:
```bash
npm run predeploy
```

The steps it runs are listed in CLAUDE.md §Quality Gates.

If the version check (step 1) fails, the fix is a dot bump of `MARKETING_VERSION` for the named target in
`Astrid App.xcodeproj/project.pbxproj` — ask the user which number, never pick one.

Report the results clearly. If there are failures, summarize what failed and suggest fixes.

For a quicker check (build only, no tests): `npm run predeploy:quick`
For a full check including UI tests: `npm run predeploy:full`
