# Backport hosts/ios

Work order. Everything below describes what is missing from this repository; nothing here has been applied yet.

Changes move one way, from `https://github.com/paritytech/polkadot-ios-community` into `hosts/ios`. Nothing in this repository is sent back the other way.

| | |
| --- | --- |
| source | https://github.com/paritytech/polkadot-ios-community (`develop`) |
| from | `7e65dd87459d78ae1c282b82f4324301571003d8` |
| to | `17cbe5e1dc19912ee18be151c2886754ba141141` |
| commits | 56 |

## Pull requests in the range

Taken from the commit subjects, so a commit that landed without a number is not listed here. The full list is below it.

- [#217](https://github.com/paritytech/polkadot-ios-community/pull/217)
- [#224](https://github.com/paritytech/polkadot-ios-community/pull/224)
- [#233](https://github.com/paritytech/polkadot-ios-community/pull/233)
- [#238](https://github.com/paritytech/polkadot-ios-community/pull/238)
- [#239](https://github.com/paritytech/polkadot-ios-community/pull/239)
- [#242](https://github.com/paritytech/polkadot-ios-community/pull/242)
- [#246](https://github.com/paritytech/polkadot-ios-community/pull/246)
- [#247](https://github.com/paritytech/polkadot-ios-community/pull/247)
- [#248](https://github.com/paritytech/polkadot-ios-community/pull/248)

<details>
<summary>All 56 commits</summary>

```
a9e23e703	feat: show fiat sign and asset symbol on the balance card and breakdown
871897ee1	Merge branch 'develop' into issue-214
071b2499e	feat: add new font
744cc700a	Exclude Sentry from Release builds
1dd288e78	Skip Sentry debug files upload for Release
d1b3a478c	Rename IssueMonitoringServicing to IssueMonitoringServiceProtocol
8ea95b6a2	Scan every Mach-O in the Release archive for Sentry
bc42b6da5	Pass empty Sentry DSN for Release builds
4b7a6e00d	Document Sentry link opt-in and IssueMonitoring package
ee7bc5b39	Merge branch 'develop' into feature/remove-sentry-release
228292613	Restore IssueMonitoring package dropped by the develop merge
9fe49d43d	Draw coinage holdings as coins
e5ff7f799	Rebuild the coin depiction in Metal
9c6a7a071	Wear the coins by what has happened to them
5d9e51352	Light the coins from the phone's own tilt
4f4e650b6	Roll the light around the coin's face, and recentre it only at rest
ef7a29a8d	Load the coin assets once, off the main thread
c93de0b1c	Order the coins as the stakeholder asked, and finish the depiction
034a0b4d7	Replace the composition bar with rules under the runs, and clear out the rest
4adc3a96a	Raise the tab bar chrome above the keyboard only while it is on screen
05f39dfb2	Remove the status depictions the coins replaced
dd6ddcab2	Record how the coin assets were generated
4126deb5a	Ignore the keyboard replayed while the tab bar returns from a screen
ccd04bb7e	Ship only what the coins actually use
76c3f7ced	Store the vendored assets as binary, and the vectors one row per line
bf295c1be	Draw nothing when there is nothing held, and time the right thing
7149e6249	Move the tab bar chrome for its own search focus and nothing else
4f59e70fa	Rule the runs with an outlined bar, and slide the clearing one
a0d6431f1	Stop resizing the coins while the card is animating
1b60875bf	Set the total as one amount, everywhere it is shown
c6106bcbc	Put the fiat symbol on the run marker amounts too
90655f399	resolve chain block time from chain model instead of hardcoded values
eed39d1a5	Hand the coins their renderer and their sensor
ade77a080	Give the drawable back once the coins have settled
35b80267b	Set the card's Ready figure like every other one
30ff31522	Read gravity from one place
64787a5df	feat: currency symbol and asset in chat transfer bubbles
633254e85	feat: currency symbol and asset in the payment amount row
9fc40c310	Merge pull request #239 from paritytech/feature/coinage-details-fungibility
941a522c7	Merge branch 'develop' into feature/remove-sentry-release
ab12b2332	Merge branch 'develop' into issue-214
54b07ee92	Merge pull request #247 from paritytech/issue-244
877941de6	Merge pull request #217 from paritytech/issue-214
744729553	Merge pull request #238 from paritytech/fix/input-camera-animation
f340f46a0	Show a grabber at the top of the scan panel
794f8b764	Pull the scan panel down by its grabber to close it
898345627	Dismiss the search when the scan panel is pulled down
e3ec24ca4	Clip the panel content while a drag shrinks it
251bdd1d4	Extend the grabber touch target to 44pt
c51ab374c	Lift the drag start into its own step
923687c3e	Move the SPA hosting into its own file
71a7344b6	Merge pull request #224 from paritytech/feature/remove-sentry-release
46103e8c0	Merge pull request #242 from paritytech/fix/chainstatus-blocktime
4568c9af8	Merge pull request #246 from paritytech/issue-145
bf859d85f	Merge pull request #248 from paritytech/feature/dismiss-input
17cbe5e1d	Merge pull request #233 from paritytech/fix/search-loader-text
```

</details>

## How to finish this

You are completing this pull request. Work on its branch and push to it.

1. Run the refresh. Do not merge the trees by hand:

   ```bash
   scripts/refresh-host-import.sh refresh ios
   ```

   It replaces `hosts/ios` with the source's tree, re-applies this repository's adaptations as a three-way patch, and compares every path against the source by blob hash in both directions. That comparison is the point: it is what catches upstream work silently dropped and adaptations that no longer apply. A hand-merge produces a plausible tree and none of those checks.

2. Read what it reports before committing.

   - A conflict is left unmerged on purpose, so git refuses to commit it. Resolve each one, keeping this repository's adaptation unless the source has clearly superseded it.
   - `adaptation left no difference` means either the source adopted that change or it did not apply. Check which, and say so in the pull request.
   - If the script refuses the result outright, do not force it. Recover with `git reset --hard HEAD` and say what happened.

3. Build what the change touches. An upstream change that adds a requirement to a protocol will not show up as a conflict, because the comparison reads content and not types; it shows up as a conformer in this repository that no longer compiles.

4. Decide whether this backport is a breaking change. Read the pull requests listed above against `.claude/skills/semver-pr-title/SKILL.md`. If any of them makes a tester lose data or a session, reinstall, or find a feature gone, or makes a product change its code, retitle this pull request with `!`, for example `chore(hosts)!: backport 56 commits into hosts/ios`, and name what breaks in its description. The nightly announcement lists `!` titles first.

5. Delete this file. It is the work order, not part of the tree:

   ```bash
   git rm BACKPORT-ios.md
   ```

6. Commit the refreshed tree, `hosts/imports.json` with its new ref, and the deletion together, then push. That push is what starts CI on this pull request.
