// Must be the very first import in each service's entry point —
// before Express, before GraphQL, before anything else initializes.
// Loading dd-trace after other modules means those modules' internals
// are already bound and can't be auto-instrumented.
import tracer from 'dd-trace';

tracer.init({
  logInjection: true, // stitches trace_id/span_id into log lines automatically
});

export default tracer;
