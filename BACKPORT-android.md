# Backport hosts/android

Work order. Everything below describes what is missing from this repository; nothing here has been applied yet.

Changes move one way, from `https://github.com/paritytech/polkadot-android-community` into `hosts/android`. Nothing in this repository is sent back the other way.

| | |
| --- | --- |
| source | https://github.com/paritytech/polkadot-android-community (`truapi-dev`) |
| from | `4f92ff6c1a8a7364a6bdf4923e77b2460fae6136` |
| to | `7fe8214b769e5cf5ece0b9f8538647c624794650` |
| commits | 25 |

## Pull requests in the range

Taken from the commit subjects, so a commit that landed without a number is not listed here. The full list is below it.

- [#169](https://github.com/paritytech/polkadot-android-community/pull/169)
- [#170](https://github.com/paritytech/polkadot-android-community/pull/170)
- [#172](https://github.com/paritytech/polkadot-android-community/pull/172)
- [#182](https://github.com/paritytech/polkadot-android-community/pull/182)
- [#183](https://github.com/paritytech/polkadot-android-community/pull/183)
- [#184](https://github.com/paritytech/polkadot-android-community/pull/184)
- [#185](https://github.com/paritytech/polkadot-android-community/pull/185)
- [#186](https://github.com/paritytech/polkadot-android-community/pull/186)
- [#188](https://github.com/paritytech/polkadot-android-community/pull/188)
- [#189](https://github.com/paritytech/polkadot-android-community/pull/189)
- [#197](https://github.com/paritytech/polkadot-android-community/pull/197)
- [#200](https://github.com/paritytech/polkadot-android-community/pull/200)
- [#210](https://github.com/paritytech/polkadot-android-community/pull/210)

<details>
<summary>All 25 commits</summary>

```
c9c452495	Remote logo & name fetch
90ee66888	add logo to message
31990f50c	pre merge
f00b2b78a	Merge branch 'main' into feature/Fetching-Payment-Asset-Logo-and-Name-from-Remote-source-
42eeae067	Fix
8b85c5f08	Fix
98f6f45d8	Release uncommitted coinage handoffs once per process (#185)
b65920363	Reject a handoff of an already handed-off asset (#184)
1de969f10	Keep resuming top-ups when one cannot be picked back up (#183)
f64d4163e	Start coinage durability regardless of remote config sync (#182)
8f0843dbd	smoothener (#170)
e10ee9f00	Merge pull request #172 from paritytech/feature/Fetching-Payment-Asset-Logo-and-Name-from-Remote-source-
19603cc11	Typo fix (#189)
bb57b2e37	Socket state detector (#169)
2af3fc678	Settle payments made of coins recovered from backup (#186)
79a047670	Fix: restart chat after app reinstall
34908f68e	Stop bottom sheets from padding the nav bar twice (#197)
c10f43c59	new search
ae3325563	Add a statement store indicator to the chain health bar (#188)
684d5b0c8	fix
f91aabf16	Merge pull request #200 from paritytech/feature/balance-display
07e1e98df	Let the expanded card fold away so the product can fill the screen
fa3f186c8	Merge main into truapi-dev
a30fc3e3d	Merge remote-tracking branch 'origin/truapi-dev' into feat/fold-expanded-pocket-card
7fe8214b7	Merge pull request #210 from paritytech/feat/fold-expanded-pocket-card
```

</details>

## How to finish this

You are completing this pull request. Work on its branch and push to it.

1. Run the refresh. Do not merge the trees by hand:

   ```bash
   scripts/refresh-host-import.sh refresh android
   ```

   It replaces `hosts/android` with the source's tree, re-applies this repository's adaptations as a three-way patch, and compares every path against the source by blob hash in both directions. That comparison is the point: it is what catches upstream work silently dropped and adaptations that no longer apply. A hand-merge produces a plausible tree and none of those checks.

2. Read what it reports before committing.

   - A conflict is left unmerged on purpose, so git refuses to commit it. Resolve each one, keeping this repository's adaptation unless the source has clearly superseded it.
   - `adaptation left no difference` means either the source adopted that change or it did not apply. Check which, and say so in the pull request.
   - If the script refuses the result outright, do not force it. Recover with `git reset --hard HEAD` and say what happened.

3. Build what the change touches. An upstream change that adds a requirement to a protocol will not show up as a conflict, because the comparison reads content and not types; it shows up as a conformer in this repository that no longer compiles.

4. Delete this file. It is the work order, not part of the tree:

   ```bash
   git rm BACKPORT-android.md
   ```

5. Commit the refreshed tree, `hosts/imports.json` with its new ref, and the deletion together, then push. That push is what starts CI on this pull request.
