# Backport hosts/ios

Work order. Everything below describes what is missing from this repository; nothing here has been applied yet.

Changes move one way, from `https://github.com/paritytech/polkadot-ios-community` into `hosts/ios`. Nothing in this repository is sent back the other way.

| | |
| --- | --- |
| source | https://github.com/paritytech/polkadot-ios-community (`develop`) |
| from | `5963378daf939c7e93d7472e31f9048e59d4aeb0` |
| to | `01fb8c7fe4b637d11322c33eda9f5acf2f5d4f22` |
| commits | 13 |

## Pull requests in the range

Taken from the commit subjects, so a commit that landed without a number is not listed here. The full list is below it.

- [#198](https://github.com/paritytech/polkadot-ios-community/pull/198)
- [#209](https://github.com/paritytech/polkadot-ios-community/pull/209)
- [#219](https://github.com/paritytech/polkadot-ios-community/pull/219)

<details>
<summary>All 13 commits</summary>

```
e34654a5c	Add order attribute to chat message storage model
63ba35ee5	Add cross-process chat message order allocator
3f09d6c0d	Sort chat feed by allocated order instead of timestamp
f95a2dd1f	Warning fix
56a2c16e9	Allocate chat message order lazily from a backup-excluded counter
a4c463bd6	Inherit compacted message order for expanded messages
892bdcdaf	Detect synced backlog against the chat's latest timestamp
d22ff218d	Index chat messages by order and sort chat list by it
8e490362a	Pass inherited order per call instead of storing it on the mapper
b1e2f3fb0	Fix: Localizaton typo (#209)
76385212a	Merge branch 'develop' into fix/message-ordering
510f0be09	Merge pull request #219 from paritytech/issue-216
01fb8c7fe	Merge pull request #198 from paritytech/fix/message-ordering
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
