Run the standard predeploy checks for the iOS app.

Execute:
```bash
npm run predeploy
```

This validates:
1. All localizations are complete (12 languages)
2. Project builds successfully
3. Unit tests pass

Report the results clearly. If there are failures, summarize what failed and suggest fixes.

For a quicker check (build only, no tests): `npm run predeploy:quick`
For a full check including UI tests: `npm run predeploy:full`
