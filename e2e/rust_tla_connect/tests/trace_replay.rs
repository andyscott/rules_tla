use rust_tla_connect_demo::BoundedCounter;
use rules_tla_trace_corpus_support::load_trace_corpus_from_env;
use std::error::Error;
use tla_connect::replay_traces;

#[test]
fn apalache_generated_traces_replay_against_rust_driver() -> Result<(), Box<dyn Error>> {
    let traces = load_trace_corpus_from_env("TLA_TRACE_CORPUS")?;
    assert!(!traces.is_empty(), "expected at least one Apalache-generated trace");

    let stats = replay_traces(BoundedCounter::new, &traces)?;
    assert_eq!(stats.traces_replayed, traces.len());
    assert!(stats.total_states >= stats.traces_replayed);

    Ok(())
}
