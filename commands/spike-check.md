---
description: Emit the stand-in spike checklist BEFORE a spike, so it's designed to hit the real binary + auth/lifecycle/fixed-port path (change-the-odds #3c).
---

# /session-continuity:spike-check $ARGUMENTS

You are responding to the `/session-continuity:spike-check` slash command.

**Your job: before any spike code is written, force the spike to be designed against the real load-bearing path** — not a stand-in that passes cleanly and proves nothing. This is the proactive complement to the `proven-gate` hook, which catches a stand-in only later, at claim-time.

If `$ARGUMENTS` is non-empty, treat it as the one-line description of the spike being planned and frame each question against it.

Present the following checklist and require an explicit answer to each item **before** the spike is built. Do not let the spike proceed on a hand-wave.

## The stand-in spike checklist

1. **What is the load-bearing behavior?** Name the one thing that, if it breaks in the real smoke later, means this spike's conclusion was wrong. (Example: for an egress proxy, that is `Proxy-Authorization` + the helper start/stop/reap lifecycle — NOT "bytes flow through a proxy".)

2. **Real binary?** Does the spike run the actual production binary / code path, or a hand-rolled stand-in? If it uses a stand-in, does that stand-in replace the load-bearing behavior from question 1? If yes, the spike **cannot** prove the claim — redesign it to exercise the real path.

3. **Real auth / lifecycle / fixed-port path?** Does the spike exercise the real authentication, the real start/stop/reap lifecycle, and the real fixed-port contention — or does it shortcut them (no-auth, always-fresh, free-port)? Each dimension you skip is a hole the real smoke will find. List which of the three are exercised for real and which are shortcut.

4. **Hermetic vs real-egress trade-off named?** If the spike needs the network, DNS, or a corp-locked box, state that dependency and confirm it matches the target environment. A "fast-fail" stand-in that actually hangs on the real path is the LEARNINGS #152 class — name the failure mode you are assuming away.

5. **What will the real smoke still have to prove that this spike does NOT?** Name it explicitly. This list is the spike's honest residual risk.

## Closing

Remind the user/agent:

> If any answer reveals the spike stands in for the load-bearing behavior, the spike is **not conclusive** no matter how cleanly it runs — redesign before claiming. When you later write up the result in a spec or plan, the `proven-gate` hook will require `Real path:` and `Stubbed:` fields — your answers to questions 2 and 5 here ARE those fields. Write them down now while the design is fresh.
