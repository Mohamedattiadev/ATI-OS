# SQL

Describing the answer you want, and letting the database work out how to get
it. That inversion is the whole thing.

## Why a job asks for it

It is the most portable skill on this page. Interviews ask for it directly,
it survives every framework change, and the difference between a query that
returns in 3ms and one that returns in 30s is usually one index and one
person who understood why.

## The order to learn it in

1. **SELECT / WHERE / ORDER BY / LIMIT** — enough to answer real questions.
2. **JOINs** — inner, left, and why a left join with a `WHERE` on the right
   table silently becomes an inner join. Draw them; the Venn diagrams help
   less than a two-row example.
3. **GROUP BY and aggregates** — and the rule that decides what may appear
   in a SELECT alongside an aggregate. `HAVING` filters groups, `WHERE`
   filters rows, and mixing them up is the classic mistake.
4. **Indexes** — what one is (a sorted structure), when it is used, and when
   your `WHERE` accidentally prevents it (a function on the column).
5. **`EXPLAIN`** — read the plan. This is where SQL stops being a language
   you write and becomes one you reason about.
6. **Transactions** — atomicity, and what an isolation level actually
   changes. Enough to know why "it worked in testing" is not evidence.

## Milestones — you are done with a step when you can do this

- [ ] Write a query with two joins and a group-by without trial and error
- [ ] Explain why a left join turned into an inner join
- [ ] Read an `EXPLAIN` and say whether an index was used
- [ ] Say what a covering index is and why it can remove a table lookup
- [ ] Explain what happens when two transactions update the same row

## Build these

- **Load a real dataset into SQLite.** It needs no server and it is on your
  machine already. Any public CSV will do. Ask it ten questions you actually
  want answered.
- **Make a query slow, then fast.** Enough rows to matter, then time it, add
  an index, time it again, and read the plan both times. Feeling that
  difference is worth more than reading about indexes.

## Read

- **Use The Index, Luke** (use-the-index-luke.com) — free, and the best
  explanation of indexes and query plans anywhere.
- **The SQLite documentation** — unusually well written, and the query
  planner pages are readable.

## Watch

Add the minute marks yourself as you watch — see README.md for why they
ship blank.

- **Any thorough "SQL joins explained" walkthrough** — pick one that shows
  the intermediate result set at each stage rather than only Venn diagrams.
  - `MM:SS` —

## The traps

- **`SELECT *` in anything you keep.** It breaks when a column is added and
  it stops an index from covering the query.
- **Learning an ORM before SQL.** Then you cannot read what it generated,
  which is exactly when you need to.
- **Assuming `NULL` behaves like a value.** `NULL = NULL` is not true. This
  will bite you in a `WHERE`, a `JOIN` and a `NOT IN`.
