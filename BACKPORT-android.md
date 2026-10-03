# Backport hosts/android

Work order. Everything below describes what is missing from this repository; nothing here has been applied yet.

Changes move one way, from `https://github.com/paritytech/polkadot-android-community` into `hosts/android`. Nothing in this repository is sent back the other way.

| | |
| --- | --- |
| source | https://github.com/paritytech/polkadot-android-community (`main`) |
| from | `7c239096b65b62b9d1de1b1cdef6ab4f7fba202e` |
| to | `edc2867a91cd427e1c225fb203b0b4ce18fb8174` |
| commits | 5 |

## Pull requests in the range

Taken from the commit subjects, so a commit that landed without a number is not listed here. The full list is below it.

- [#226](https://github.com/paritytech/polkadot-android-community/pull/226)

<details>
<summary>All 5 commits</summary>

```
a66140aba	chore(product-sample): regenerate package-lock.json from the npm registry
0e03f0465	chore(bindings): declare GPL-3.0-or-later in the Rust crate manifests
450ed32e6	docs(readme): surface the root README as the repo front page and add the DYOR clause
51299c0d3	docs(coinage): refer to the coinage reference implementation without naming the repo
edc2867a9	Merge pull request #226 from paritytech/chore/opensourcing-audit-fixes
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

4. Decide whether this backport is a breaking change. Read the pull requests listed above against `.claude/skills/semver-pr-title/SKILL.md`. If any of them makes a tester lose data or a session, reinstall, or find a feature gone, or makes a product change its code, retitle this pull request with `!`, for example `chore(hosts)!: backport 5 commits into hosts/android`, and name what breaks in its description. The nightly announcement lists `!` titles first.

5. Delete this file. It is the work order, not part of the tree:

   ```bash
   git rm BACKPORT-android.md
   ```

6. Commit the refreshed tree, `hosts/imports.json` with its new ref, and the deletion together, then push. That push is what starts CI on this pull request.
