# CS101 — Solid Computer Science & Engineering Fundamentals

Language-agnostic guidance: correctness, testing, data structures, algorithms,
design patterns, regression hygiene, and performance reasoning.

---

## 1. Correctness First

### Invariants
- Every loop, struct, or module has **invariants** — conditions that must be true
  before and after every operation.  State them explicitly in comments.
- The question "what can *never* happen here?" is more powerful than
  "what should happen?"

### Edge Cases — The Canonical List
Always think through these:
1. **Zero** — empty input, zero-length string, null pointer, count=0
2. **One** — single element, exactly-one iteration, boundary at size=1
3. **Many** — large N, overflow, wraparound
4. **Negative** — signed underflow, negative indices if applicable
5. **Duplicate** — repeated keys, duplicate insertions
6. **Order** — sorted, reverse-sorted, random
7. **Absent** — missing key, file not found, lookup miss
8. **Concurrent** — (if applicable) interleaving, TOCTOU

### Off-by-One
- The most common bug class. Verify loop bounds with:
  - Start at 0 or 1?
  - `<` vs `<=`?
  - Last element included or excluded?
  - Null terminator accounted for?

### Memory Safety (Systems Languages)
- Every allocation must have a clear **owner**.
- Every pointer must have a **lifetime** that exceeds its last use.
- After free, null the pointer (use-after-free defense).
- Double-free is always a bug — track ownership.

---

## 2. Testing

### The Testing Pyramid
```
     /------\
    /  E2E   \       Few — slow, brittle, but validate full flow
   /----------\
  / Integration\      Some — verify modules talk correctly
 /--------------\
/    Unit         \   Many — fast, precise, isolate logic
-------------------
```

### Unit Test Principles
- **One thing per test.** If it has "and" in the name, split it.
- **Arrange, Act, Assert** — three clear sections.
- **Deterministic.** No wall-clock time, no random without seeded RNG.
- **No I/O.** Mock or stub filesystem, network, DB.
- **Test the behavior, not the implementation.** Refactoring shouldn't break
  tests unless the contract changes.

### Property-Based Testing
- Instead of hand-picking cases, specify **properties** that hold ∀ inputs:
  - "sorting a list twice equals sorting it once" (idempotence)
  - "reversing a list twice gives back the original" (involution)
  - "encoding then decoding is identity" (round-trip)
- Generate random inputs; the generator finds counterexamples.

### Regression Testing — The Rule
**Every bug gets a test before the fix.**
1. Write a test that **fails** because of the bug.
2. Apply the fix.
3. The test now passes — and will **forever** catch a recurrence.

### Test-Driven Development (TDD) — When to Use
- Best for: pure logic, parsers, serialization, algorithms
- Skip for: exploratory UI, throwaway prototypes, trivial plumbing
- Red → Green → Refactor cycle is the discipline.

---

## 3. Data Structures — Choosing Wisely

### Decision Table
| Need | Structure | O(lookup) | O(insert) | Notes |
|------|-----------|-----------|-----------|-------|
| Key→value, unordered | Hash Table | O(1) avg | O(1) avg | Great general-purpose |
| Key→value, sorted | Balanced Tree | O(log n) | O(log n) | Range queries, ordered walk |
| Fixed-size, index access | Array | O(1) | — | Cache-friendly, SIMD-friendly |
| Dynamic, index access | Dynamic Array | O(1) | O(1) amortized | append-heavy |
| FIFO | Queue (ring buf) | — | O(1) | Fixed or growing |
| LIFO | Stack (array) | — | O(1) | Recursion, backtracking |
| Priority | Heap | O(log n) pop | O(log n) | Top-K, Dijkstra, scheduling |
| Set membership | Hash Set | O(1) avg | O(1) avg | Dedup, visited tracking |
| Prefix matching | Trie | O(k) k=key len | O(k) | Autocomplete, routing |
| Disjoint sets | Union-Find | ~O(α(n)) | ~O(α(n)) | Connected components |

### When Not to Use a Hash Table
- Need ordering → tree or sorted array
- Tiny N (N < 20) → linear scan beats hashing overhead
- Memory-constrained → sorted array + binary search
- Predictable keys → perfect hashing or direct lookup array

### Cache Awareness
- Arrays beat linked lists in practice (contiguous memory, prefetchable).
- AoS (Array of Structs) vs SoA (Struct of Arrays): SoA is better when you
  iterate over one field across many elements.
- Cache lines are 64 bytes. Keep hot data together.

---

## 4. Algorithmic Reasoning

### Complexity Cheat Sheet
| N | log n | n log n | n² | 2ⁿ |
|---|-------|---------|-----|-----|
| 10 | 3 | 33 | 100 | 1024 |
| 100 | 7 | 664 | 10,000 | 1.27e30 |
| 10⁶ | 20 | 20×10⁶ | 10¹² | impossible |
| 10⁹ | 30 | 30×10⁹ | 10¹⁸ | impossible |

- **O(n)**: scan once — good.
- **O(n log n)**: sorting, divide-and-conquer — acceptable.
- **O(n²)**: nested loops — dangerous above N≈10,000.
- **O(2ⁿ)**: exponential — N>30 is impractical.

### When to Optimize
1. **Profile first.** Never optimize without data.
2. Find the **hot path** (the 5% of code that runs 95% of the time).
3. Optimize the hot path only.
4. Re-profile to confirm improvement.

### Common Algorithmic Patterns
- **Divide & Conquer**: merge sort, quicksort, binary search
- **Dynamic Programming**: overlapping subproblems (memoization / tabulation)
- **Greedy**: locally optimal → globally optimal (when problem has
  optimal substructure and the greedy choice property)
- **Two Pointers**: sorted array traversal, sliding window
- **BFS/DFS**: graph traversal, shortest unweighted path (BFS)

---

## 5. Design Patterns (Systems Style)

### Ownership Pattern
- Every resource (memory, file, socket, lock) has exactly **one owner**.
- Transfer ownership explicitly (move semantics, explicit handoff).
- RAII: acquisition is initialization; release in destructor/cleanup.

### Arena/Region Allocation
- Allocate many objects in a single arena.
- Free all at once (arena reset) — no individual frees.
- Perfect for: request processing, frame allocation, temporary work.
- Avoids: fragmentation, per-object free overhead, use-after-free (lifetimes
  are clear).

### State Machine
- Explicit states + explicit transitions.
- Every state handles every possible event (or rejects it).
- Avoids: "impossible state" bugs, spaghetti conditionals.
- Implementation: enum + switch, or table-driven.

### Reader-Writer
- Multiple concurrent readers OR one exclusive writer.
- Key: the transition between read and write (upgrade) is tricky.

### Producer-Consumer
- Ring buffer (lock-free SPSC) or mutex+condvar (MPMC).
- Always think about: what happens when the buffer is full? empty?

### Strategy / Polymorphism
- Function pointer table (vtable) for runtime dispatch.
- Avoid deep inheritance hierarchies; prefer composition.

---

## 6. Regression Hygiene

### Before Every Change
1. **Olympus snapshot** — save current state.
2. Run the existing test suite — ensure you start green.
3. Understand what the change touches.

### After Every Change
1. Run the test suite again — stay green.
2. If new behavior: add a test.
3. If bug fix: add a regression test first, then fix.
4. **Olympus snapshot** — checkpoint your progress.

### Bisect-Readiness
The commit history must be **small, atomic, and green**:
- One logical change per commit.
- Every commit builds and passes tests.
- This enables `git bisect` to find bugs in O(log n) steps.

---

## 7. Performance & Profiling

### The Cardinal Rule
**Measure, don't guess.** Intuition about performance is wrong ~80% of
the time.

### What to Measure
- **Wall-clock time** — what the user experiences.
- **CPU time** — actual work done (excludes I/O wait).
- **Allocations** — count and total bytes.
- **Cache misses** — the real bottleneck in most systems code.

### Benchmark Hygiene
- Warm up (JIT, cache) before measuring.
- Run multiple iterations; report median, not mean.
- Isolate from other system activity.
- Be aware of CPU frequency scaling.

---

## 8. Debugging

### Scientific Method
1. **Observe** the bug — can you reproduce it reliably?
2. **Hypothesize** — what could cause this?
3. **Experiment** — test the hypothesis (add logging, assertion, or fix).
4. **Confirm** — does the experiment prove or disprove the hypothesis?
5. **Fix** — only after you understand the root cause.

### Rubber-Duck Debugging
Explain the problem to an inanimate object (or a log file). The act of
articulating forces you to examine assumptions.

### Binary Search Debugging
- Narrow the search space by half each time.
- Comment out half the code. Bug still there? It's in the other half.
- Git bisect automates this across commits.

### The Most Common Root Causes (in order)
1. Off-by-one error (loop bounds, array indices)
2. Null / uninitialized value
3. Use-after-free / double-free
4. Incorrect ownership (who frees this?)
5. Concurrency: missing lock, deadlock, race
6. Integer overflow / underflow
7. Wrong assumption about input validity

---

## 9. Code Review Checklist

- Does it handle all 8 edge cases (zero, one, many, negative, duplicate,
  order, absent, concurrent)?
- Are there tests? Do they pass?
- Is every allocation paired with a deallocation?
- Are loop bounds correct?
- Is the algorithm the right complexity class for the expected input size?
- Are error paths tested?
- Is there dead code or unreachable branches?
- Can a future reader understand the intent?

---

## 10. Meta: When to Ask for Help

- Stuck for >30 minutes → explain the problem (rubber duck).
- Still stuck after 30 more minutes → escalate.
- Design decision with broad impact → discuss before implementing.
- Uncertain about algorithm choice → benchmark two approaches, don't debate.

---

*This skill is foundational. Apply it regardless of language or domain.*
