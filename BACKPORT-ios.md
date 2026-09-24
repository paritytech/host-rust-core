# Backport hosts/ios

Work order. Everything below describes what is missing from this repository; nothing here has been applied yet.

Changes move one way, from `https://github.com/paritytech/polkadot-ios-community` into `hosts/ios`. Nothing in this repository is sent back the other way.

| | |
| --- | --- |
| source | https://github.com/paritytech/polkadot-ios-community (`develop`) |
| from | `958fb7eb4cbb5deb5c802f5d69622562d6983282` |
| to | `0a89796d9730cb91de43e058824b67434bc8f438` |
| commits | 24 |

## Pull requests in the range

Taken from the commit subjects, so a commit that landed without a number is not listed here. The full list is below it.

- [#142](https://github.com/paritytech/polkadot-ios-community/pull/142)
- [#196](https://github.com/paritytech/polkadot-ios-community/pull/196)
- [#197](https://github.com/paritytech/polkadot-ios-community/pull/197)
- [#199](https://github.com/paritytech/polkadot-ios-community/pull/199)
- [#200](https://github.com/paritytech/polkadot-ios-community/pull/200)
- [#207](https://github.com/paritytech/polkadot-ios-community/pull/207)

<details>
<summary>All 24 commits</summary>

```
72bd241d5	Time out username lookup after cloud restore and stop spinner on rejected auth
b1b45a9fc	Show authentication failed label on cloud restore when auth is rejected
2922ca500	fix: show ready and total balance while funds are pending
647b329b9	fix audit issue
8cc7bce96	fix docs
fe0f1bbd8	fix unexpressible denomination
51831fb42	fix comments
da3641312	fix review
832d2f163	Merge branch 'develop' into fix/coinage-durability-audit
a9aadcbe5	Merge pull request #200 from paritytech/fix/coinage-durability-audit
ac1b17109	fix: settle payments made of coins recovered from backup
6db51eb1c	Merge pull request #197 from paritytech/issue-195
7c4085175	Startup configuration improvements (#142)
a152e5808	Merge pull request #196 from paritytech/fix/cloud-recovery
ce359bdb5	Merge branch 'develop' into fix/minter-after-backup
8cea7d1b4	Merge pull request #199 from paritytech/chore/runner
5581fc492	fix comments
96585236f	make installation reader shared
d0e131445	improve docs
def7eb8ba	refactoring
9754cfab2	simplify tests
a7a070ce2	Merge branch 'develop' into fix/minter-after-backup
ddd92c838	fix limits
0a89796d9	Merge pull request #207 from paritytech/fix/minter-after-backup
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
