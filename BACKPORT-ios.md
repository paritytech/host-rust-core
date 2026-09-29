# Backport hosts/ios

Work order. Everything below describes what is missing from this repository; nothing here has been applied yet.

Changes move one way, from `https://github.com/paritytech/polkadot-ios-community` into `hosts/ios`. Nothing in this repository is sent back the other way.

| | |
| --- | --- |
| source | https://github.com/paritytech/polkadot-ios-community (`develop`) |
| from | `01fb8c7fe4b637d11322c33eda9f5acf2f5d4f22` |
| to | `e213ebea29b25ee2af6199af91957f7bf60725ed` |
| commits | 12 |

## Pull requests in the range

Taken from the commit subjects, so a commit that landed without a number is not listed here. The full list is below it.

- [#205](https://github.com/paritytech/polkadot-ios-community/pull/205)
- [#220](https://github.com/paritytech/polkadot-ios-community/pull/220)
- [#221](https://github.com/paritytech/polkadot-ios-community/pull/221)
- [#229](https://github.com/paritytech/polkadot-ios-community/pull/229)
- [#231](https://github.com/paritytech/polkadot-ios-community/pull/231)
- [#232](https://github.com/paritytech/polkadot-ios-community/pull/232)

<details>
<summary>All 12 commits</summary>

```
8ba137c47	feat: add statement store connection indicator
9124ee8e6	feat: polish the network status panel copy and spacing
625ce076f	fix: update tests
aac5c824b	feat: share a single invite message from the id card
42122aa73	Merge branch 'develop' into issue-123
8af2e514e	Remote config improvements (#221)
c70981225	Merge pull request #231 from paritytech/issue-228
92531b7b8	Merge pull request #205 from paritytech/issue-123
0fcd9a316	Remove Jailbreak gate and fix dependencies (#229)
69ce94ce7	Align chat input placeholder with typed text
63ffff873	Align chat input placeholder with typed text (#232)
e213ebea2	Merge pull request #220 from paritytech/fix/input-camera-animation
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

4. Delete this file. It is the work order, not part of the tree:

   ```bash
   git rm BACKPORT-ios.md
   ```

5. Commit the refreshed tree, `hosts/imports.json` with its new ref, and the deletion together, then push. That push is what starts CI on this pull request.
