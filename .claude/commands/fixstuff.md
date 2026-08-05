Pull tasks from the Astrid iOS to-do list and work through them until the list is empty.

## Steps

1. **Ensure environment is set up** — copy `.env.local` from astrid-web if not present:
   ```bash
   cp ../astrid-web/.env.local .env.local 2>/dev/null || true
   ```

2. **Pull iOS tasks**:
   ```bash
   cd ../astrid-web && npx tsx scripts/get-astrid-tasks.ts ios
   ```
   Direct-DB alternative when the OAuth script is flaky:
   `DATABASE_URL="$DATABASE_URL_PROD" npx tsx scripts/ios-tasks-direct.ts`

3. **Present the tasks** to the user and ask which one(s) to work on.

4. **For each task**, follow the coding workflow:
   - Analyze the issue — read the description AND its comments/attachments. A
     screenshot attached to the task is usually the fastest route to the real cause.
   - RED regression test naming the task id → implement → green
   - Run `npm run predeploy` (plus the Mac suites for Mac tasks)
   - Fix any regressions
   - Post a completion report on the task and mark it complete

5. **RE-CHECK THE LIST AFTER EVERY TASK — never work from the opening snapshot.**
   New tasks arrive while work is in progress, and a REOPENED task looks exactly
   like one that was never done. After each completion:
   ```bash
   cd ../astrid-web && DATABASE_URL="$DATABASE_URL_PROD" npx tsx scripts/ios-tasks-direct.ts
   ```
   Work anything new or reopened before declaring the list clear. A reopened task
   means the previous fix missed — re-read it and find a different cause rather
   than re-closing it on the same reasoning.

6. **When the list is empty**, say so and ask whether to ship. Shipping means
   pushing to `iosdev` (or `macdev` for Mac work), which builds to TestFlight.
   `main` is the App Store branch — pushing there starts a release build, so
   that always waits for an explicit go-ahead.
