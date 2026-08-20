Check the Astrid iOS to-do list and autonomously work every open task to completion. Designed to be safe to re-run on a schedule.

## Goal

**Drive the iOS list to empty.** Unlike `/fixstuff`, this does not ask which task to work on —
it takes them in priority order and keeps going until nothing is left. It stops on its own when
the list is clear, so a scheduled re-run that finds an empty list is a no-op, not busywork.

## The workflow itself is shared

**Read [`../astrid-web/docs/FIXALL_WORKFLOW.md`](../../../astrid-web/docs/FIXALL_WORKFLOW.md)
— it is the canonical description** of the queue (board ∩ Ready ∩ assignee ∩ due date), the
board etiquette (`Doing` / `Waiting` / handing back), the per-task loop (strategy comment →
branch → RED-GREEN TDD → gates → report), filing the other repo's half, and re-checking after
every task.

It lives in astrid-web because this loop already depends on that checkout — every queue and
board command is a script in it — and because it is one workflow, not two. The two command
files had drifted by 440 lines before they were consolidated, which is what a rule written
twice does.

Pull the queue with:

```bash
cd ../astrid-web && npx tsx scripts/ready-tasks.ts ios --harness claude-code
```

(The board argument is required here — it defaults to `web`. The harness never defaults;
guessing would claim another agent's work.)

## What is different here

- **DO NOT PUSH unless Jon asks for a build** (Jon, 2026-08-18). Work locally: branch, commit,
  merge into `iosdev`, keep the gates green — and stop there. Push `iosdev`, `macdev` or `main`
  only when he asks to build or test.

  The reason is concrete rather than cautious: **it burned through the Xcode Cloud usage
  allotment.** Every ship pushed three branches and started FOUR runs — `iosdev`, `macdev`,
  plus iOS Release and Mac Release on `main` — so one fix cost four runs, and shipping several
  fixes an hour apart exhausted the month. Once it is gone, every run is created and cancelled
  before it starts (`startedDate: null`, `cancelReason: null`) and `POST /v1/ciBuildRuns`
  returns 500, which looks exactly like an Apple outage and cost hours to diagnose. See
  [[xcode-cloud-runs-canceled]].

- **A task is DONE when it is merged into `iosdev` with the gates green.** Say in the
  completion report that it is merged and waiting to be built, rather than claiming it shipped.

- **Gates:** `npm run predeploy`, plus the Mac suite for anything touching `Core/` or Mac:
  ```bash
  xcodebuild test -scheme "Astrid Mac" -destination "platform=macOS" \
    -only-testing:"Astrid MacTests" -quiet
  ```
  Re-run them on the MERGED tree, not just the branch — a merge can break what neither side
  broke alone.

- **No `CURRENT_PROJECT_VERSION` bump per fix.** It does not name the TestFlight build:
  measured 2026-08-18, TestFlight's numbers are the Xcode Cloud RUN numbers (877, 878, 882…)
  while the repo said 254. Tell Jon the build number or the commit, not the bump.

- **An App Store submission, deleting files, or a significant architecture change still needs
  asking.**

## When Jon asks for a build

Push all three so they cannot drift — the `Core/` tree is shared — and expect one build to
carry several tasks. That is the trade for not burning the allotment: a build no longer maps to
a single change, so the completion reports have to carry the detail instead.

```bash
git push origin iosdev
git checkout macdev && git merge --ff-only iosdev && git push origin macdev
git checkout main   && git merge --no-ff iosdev -m "Merge iosdev: <what>"
git push origin main && git checkout iosdev
```

- Xcode Cloud picks the push up by webhook, which has lagged 0 to ~36 minutes. That is normal —
  do not retrigger on a hunch. A manual `POST /v1/ciBuildRuns` **must** carry
  `relationships.sourceBranchOrTag` (an `scmGitReferences` id) or it defaults to `main` and 409s.
- **If runs are created and cancelled with `startedDate: null`, the allotment is gone.** Say so
  and stop; pushing again only makes more cancelled runs.

**Xcode Cloud is not the only way out.** A build can be archived locally and uploaded straight
to App Store Connect — TestFlight included — with the ASC API key already in `.env.local`:
`xcodebuild archive` → `-exportArchive` with `method: app-store-connect` → `xcrun altool
--upload-app`, all three passing `-allowProvisioningUpdates` and the `-authenticationKey*`
flags so automatic signing can mint a distribution certificate. That is how builds 900–909
shipped while the allotment was out. See [[xcode-cloud-runs-canceled]].

See [ASTRID.md](../../ASTRID.md) for architecture and the full coding workflow, and `/fixstuff`
for the interactive, pick-one-task-at-a-time version.
