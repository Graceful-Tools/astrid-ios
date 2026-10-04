// built-task-closer.mjs — the decisions behind scripts/close-built-tasks.mjs, kept free of
// network and git so scripts/test-close-built-tasks.mjs can pin them.
//
// A /fixall task stays in Doing until a TestFlight build carries its commit (Jon, 2026-09-21).
// Closing it used to be a step inside a session, and the scheduled loop only starts a session
// when the queue has work — so on a quiet board nothing ever came back to close them, and Doing
// filled up until a person noticed (Jon, 2026-09-27: "Make sure the fixall script resolves the
// doing tasks"). The loop now does it on every tick, without a session, from these rules.

/** The line a session ends its "merged and pushed" comment with. The sha is the fix commit. */
export const AWAITING_BUILD = /\*\*Awaiting build:\*\*\s*`([0-9a-f]{7,40})`/i;

/**
 * The fix commit this task is waiting on, or null when it should be left alone.
 *
 * Only the NEWEST marker counts, and only when it is newer than the task's last completion: a
 * reopened task still carries the marker for the fix that missed, and closing it on that build
 * would undo the reopen before anyone had worked it.
 *
 * Any author's marker counts unless `authorId` is given. Interactive sessions post through the
 * astrid MCP or the OAuth comment script, and both write as Jon, so an agent-only rule left
 * their tasks in Doing after the build was VALID (AITD-454/458/459, 2026-10-04).
 */
export function awaitingSha(comments, authorId) {
  const at = c => Date.parse(c.createdAt) || 0;
  const lastCompleted = Math.max(0, ...comments
    .filter(c => c.systemEventType === 'COMPLETED')
    .map(at));
  const markers = comments
    .filter(c => (authorId == null || c.authorId === authorId) && AWAITING_BUILD.test(c.content ?? ''))
    .sort((a, b) => at(b) - at(a));
  const newest = markers[0];
  if (!newest || at(newest) <= lastCompleted) return null;
  return newest.content.match(AWAITING_BUILD)[1].toLowerCase();
}

/**
 * The lowest-numbered VALID build that contains `sha`, or null.
 *
 * `builds` is [{ number, state, sha }]: the sha comes from the Xcode Cloud run of the same
 * number (a build number IS its run number). `contains(fix, runSha)` is
 * `git merge-base --is-ancestor` — never a subject-line match, since one build carries several
 * tasks and its own message usually names a different one.
 */
export function buildCarrying(sha, builds, contains) {
  return builds
    .filter(b => b.state === 'VALID' && b.sha)
    .sort((a, b) => Number(a.number) - Number(b.number))
    .find(b => contains(sha, b.sha)) ?? null;
}

/** The completion comment — names the build, never says it shipped. */
export function closingComment({ sha, ios, mac }) {
  const builds = [ios && `iOS build **${ios.number}**`, mac && `Mac build **${mac.number}**`]
    .filter(Boolean).join(' and ');
  return `## In TestFlight: ${builds} (scheduled /fixall)\n\n` +
    `${builds} ${ios && mac ? 'are' : 'is'} **VALID** and contain${ios && mac ? '' : 's'} ` +
    `\`${sha.slice(0, 7)}\` (checked with \`git merge-base --is-ancestor\`). Closing.\n\n` +
    `If it doesn't look right in the build, reopen this and say what you saw.`;
}
