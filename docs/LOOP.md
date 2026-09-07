# How the improvement loop runs

Claude is in charge of planning and execution against docs/GOAL.md. Tim tests on the
device, answers taste questions, and does the few Apple/Firebase clicks that need a
human. Everything else is autonomous.

## One iteration

1. **Pick** the next task from the current plan in docs/superpowers/plans/ (highest
   value toward GOAL.md first). Write intent in STATE.md.
2. **Build** it: Claude, or a worker subagent for well-scoped pieces (a screen, a
   function, a test target). Tests first where the change is logic.
3. **Gates**: BeerKit tests, functions tests, emulator rules tests, cloud compile.
4. **Adversary**: an independent reviewer pass (`/code-review high` on the diff) whose
   findings are verified by separate agents; must-fix findings go back to step 2. For
   UI work, `/impeccable audit` (native) on screenshots from the UI-test run. For rules
   and functions, `/security-review`.
5. **Ship**: commit + push (compile runs automatically). At a milestone boundary,
   `ios-testflight`, then an ntfy push to Tim with what to try.
6. **Listen**: Tim's device feedback arrives by chat, ntfy reply, or TestFlight's
   built-in feedback (shake the phone, add a screenshot + note; Claude reads it via the
   App Store Connect API). Crash reports the same way. Feedback becomes tasks.

## Cadence

- While Tim is around: continuous, in this session.
- Otherwise: `/loop` self-paced wakeups keep working through the plan; a push at every
  milestone or blocker. Tim can stop it any time with Ctrl+C.
- Bigger fan-outs (e.g. redesign all six screens in parallel with per-screen reviewers)
  use the Workflow tool; Tim opts in per run because it burns more tokens.

## Roles

| Who | Does |
|---|---|
| Claude (this session) | plans, writes code and tests, runs gates, orchestrates subagents, ships, reports |
| Worker subagents | scoped implementation tasks with clear acceptance criteria |
| Reviewer / verifier agents | adversarial: try to break the change, verify each finding |
| Tim | device testing, taste decisions, Apple/Firebase clicks, budget and scope calls |

## Rules

- Never ship on red. Never touch production data. Never widen scope without saying so.
- Every TestFlight build has a changelog line in STATE.md and a push to Tim.
- STATE.md is the single source of truth for "where are we"; it is updated every iteration.
