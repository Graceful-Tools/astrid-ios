Pull tasks from the Astrid iOS to-do list and help the user work through them.

## Steps

1. **Ensure environment is set up** — copy `.env.local` from astrid-web if not present:
   ```bash
   cp ../astrid-web/.env.local .env.local 2>/dev/null || true
   ```

2. **Pull iOS tasks**:
   ```bash
   cd ../astrid-web && npx tsx scripts/get-astrid-tasks.ts ios
   ```

3. **Present the tasks** to the user and ask which one(s) to work on.

4. **For each task**, follow the coding workflow:
   - Analyze the issue
   - Implement the fix
   - Run `npm run predeploy` to verify
   - Fix any regressions
   - Add regression tests if applicable

5. **After all fixes**, ask the user if they're ready to ship.
