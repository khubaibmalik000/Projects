# Algorithms

Deeper detail on the four non-trivial pieces of logic in this platform.
Source of truth is always the code (`src/aiops/`); this is a guide to it.

## EWMA / z-score detector

`aiops.anomaly.statistical.EwmaZScoreDetector`

Each series (`"{entity}:{metric}"`) is tracked independently:

1. **Warmup** (first `warmup_samples` points): mean/variance are computed
   with Welford's online algorithm -- numerically stable, no stored
   history.
2. **Steady state**: each new value is scored against the *current*
   baseline (`z = (value - mean) / std`) **before** the baseline is
   updated. This ordering matters -- scoring after updating would let a
   spike absorb itself into its own baseline.
3. **Damped update**: the baseline update uses a smaller effective alpha
   on anomalous points (`alpha * anomalous_update_damping`, default
   damping `0.1`). Without this, a sustained spike drags the EWMA mean up
   with it and the detector stops flagging the same ongoing anomaly a few
   samples later.

Thresholds (`warn_sigma=3.0`, `crit_sigma=5.0` by default) are on the
z-score, so they're comparable across metrics with wildly different
units and scales.

## Isolation Forest detector

`aiops.anomaly.ml.IsolationForestDetector`

Isolation Forest isolates points by recursive random splits; anomalies
are the points that take few splits to isolate (they're "easy to
separate" from the rest of the data). Because it has no online/partial-fit
mode:

1. Each entity keeps a bounded `deque(maxlen=window_size)` of recent
   feature vectors.
2. Once the buffer has `min_samples_to_fit` points, a model is fit
   against the *current window* and reused for the next
   `retrain_interval` observations before refitting.
3. On each observation, `predict()` gives an inlier/outlier call and
   `score_samples()` gives a continuous anomaly score (negated so higher
   = more anomalous).
4. On a flagged outlier, the top-3 contributing features are reported as
   the per-feature z-score against the current window's mean/std -- not
   because Isolation Forest is directly interpretable, but because a
   large marginal deviation on a specific feature is a decent proxy for
   "this is the dimension that made the point unusual."

**Why this catches things the z-score detector can't**: see
`aiops.generators.scenario.resource_pressure_scenario` and
`tests/test_ml_anomaly.py::test_flags_outlier_off_the_correlation_manifold`
-- a worker where CPU and queue depth are normally *anti-correlated*
(busier workers drain the queue faster) starts showing both rising
together. Each value alone stays inside its historical range the whole
time (no z-score fires), but the *joint* pattern is off the manifold the
model learned.

## Log template mining (Drain-inspired)

`aiops.logs.drain.LogTemplateMiner`

A simplified version of the Drain fixed-depth parse-tree algorithm
(He et al., 2017):

1. **Mask** (`aiops.logs.parser.mask_variables`): regex-replace UUIDs,
   IPv4 addresses, hex literals, and numbers with `<*>` before
   tokenizing, so `user 4471 logged in` and `user 9002 logged in` become
   the same token sequence.
2. **Bucket** by `(token_count, first_token)` -- an O(1)-ish first filter,
   since two log lines with a different number of tokens or a different
   first token are never the same template.
3. **Match**: within the bucket, compare the incoming token sequence to
   each existing cluster's template by positional similarity
   (`matches / len(tokens)`, where `<*>` in the template always counts as
   a match). The best match above `similarity_threshold` (default `0.5`)
   wins.
4. **Merge or create**: a match merges the line into that cluster (any
   position where tokens disagree becomes `<*>` in the template); no
   match creates a new cluster.

Each event carries `is_new_template` and `occurrence_count`. The pipeline
treats an `error`/`critical`-severity event as a notable signal only when
it's a brand-new template or has occurred `<= 3` times -- the volume
knob that turns "10,000 log lines/sec" into "a handful of signals."

## Correlation and root-cause ranking

`aiops.correlation.engine.CorrelationEngine`

- **Grouping**: an incoming signal joins the most recent open incident
  if (a) the incident was last updated within `correlation_window_seconds`
  (default 120s) *and* (b) either the signal's entity is already part of
  the incident, or it's within `related_max_hops` (default 2) of an
  existing incident entity in the service dependency graph
  (`aiops.correlation.dependency_graph.ServiceDependencyGraph`, a plain
  directed graph with bounded-hop BFS in both directions).
- **Root-cause ranking**: among the incident's affected entities, the one
  that is upstream (via the dependency graph) of the most *other*
  affected entities wins; ties break toward the entity whose earliest
  signal fired first. This is a heuristic, not a guarantee -- it assumes
  failures propagate upstream-to-downstream, which holds for the common
  "database is slow -> callers time out -> their callers time out" shape
  but not for every failure mode (e.g. a shared network partition
  affecting two unrelated services simultaneously).
- **Expiry**: incidents with no new signals for `close_after_seconds`
  (default 300s) are closed on the next `ingest()` call or an explicit
  `close_stale(now)` sweep.
