# What to ask before drafting

Open with the questions whose answers the draft cannot be written without, and stop asking once the notes have answered them. Batches of 5–8, numbered, grouped by area. Quote the note you are asking about, so the user can see what you already understood.

Two rules make the difference between an interview and an interrogation:

- **Ask about mechanism, never about mood.** "What happens when the host holds no key for that product?" is answerable. "Can you tell me more about the design?" makes the user do your job.
- **Confirm what you inferred.** Anything you deduced but the notes never said becomes a question with your inference in it: "I read this as the host resolving the alias, not the product — correct?"

## Areas

**Problem.** What breaks today, for whom, and how often? Is there an incident, a bug, a tracking issue, or a product that hit it? What is the cost of not doing this? A Motivation section with no concrete failure reads as a preference.

**Mechanism.** Step through the change end to end. Who calls what, with which arguments, in which order? What does the host do that it did not do before? Where does state live, and who owns it? What is the exact type of every new field?

**Surface.** Which trait, method, request id, error variant, SCALE type, or config key changes? Names and shapes, not paraphrases — every repo RFC of consequence carries the literal signature (`0022-account-derivations.md` has 16 fenced blocks, `0017-coinage-payment.md` 12).

**Boundaries.** What is deliberately not in scope? Which adjacent problem does this refuse to solve, and why? When scope is contested, this becomes a `## Non-goals` section rather than a sentence buried in Motivation.

**Rejected designs.** What else was considered, and what killed each one? An Alternatives section that lists only strawmen tells a reviewer the design space was never explored. The strongest rejected option is the one worth writing down.

**Failure and edges.** What happens on a malformed request, a missing key, a concurrent call, a host that does not implement the new method, a version skew between product and host? Which errors are new and what does a product do with each?

**Compatibility.** Does this break an existing wire format, method, or type? Which versions interoperate? What does a host or product have to do to migrate, and can old and new coexist during the rollout?

**Verification.** How does an implementer prove they got it right? Which existing test surface covers it, and what has to be added? For anything cryptographic or consensus-adjacent, what is the oracle — a reference implementation, a round-trip, a known-answer vector?

**Security and privacy.** What can a hostile product or host do with this that it could not before? What new data crosses the trust boundary, and who can see it?

**Prior work.** Which RFC does this amend, supersede, or depend on? Which RFC number, so the draft can link it? Has it been discussed anywhere — an issue, a PR thread, a call? Who has already pushed back, and on what?

**Genuinely open.** What is the author actually unsure about? These become `## Unresolved Questions`. False modesty ("perhaps the naming could be improved") wastes a reviewer's attention; a real fork in the design earns it.

## When to stop

Stop when you can write the Detailed Design without the word "somehow", every new name has a type, and every failure path has a defined outcome. If a question stays unanswered because the user genuinely does not know yet, that is not a blocker — it is an Unresolved Question, and it goes in the draft as one.
